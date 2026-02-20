"""
Servicios analíticos de inventario.

Este módulo centraliza cálculos de:
- movimientos mensuales,
- análisis por producto,
- estado de inventario a una fecha objetivo.
"""

import logging
from datetime import datetime
from decimal import Decimal

from dateutil.relativedelta import relativedelta
from django.db.models import F, Max, Q, Sum
from django.db.models.functions import TruncMonth
from django.utils.timezone import now

from ..models import InventoryRecord, Product, WarehouseDetail

logger = logging.getLogger(__name__)


def get_monthly_movements_data(
    inventory_name="default",
    warehouse_filter="",
    category_filter="",
    search_filter="",
):
    """
    Calcula entradas, salidas y saldo de cierre para una ventana de 12 meses.
    """
    today = now().date()
    twelve_months_ago = today - relativedelta(months=11)
    start_of_period = twelve_months_ago.replace(day=1)

    base_queryset = InventoryRecord.objects.filter(
        product__inventory_name=inventory_name
    )

    if warehouse_filter:
        base_queryset = base_queryset.filter(warehouse__icontains=warehouse_filter)
    if category_filter:
        base_queryset = base_queryset.filter(category__icontains=category_filter)
    if search_filter:
        base_queryset = base_queryset.filter(
            Q(product__code__icontains=search_filter)
            | Q(product__description__icontains=search_filter)
        )

    if warehouse_filter:
        initial_stock_query = WarehouseDetail.objects.filter(
            product__inventory_name=inventory_name,
            warehouse__icontains=warehouse_filter,
        )
        if category_filter:
            initial_stock_query = initial_stock_query.filter(
                product__group__icontains=category_filter
            )
        initial_stock_value = (
            initial_stock_query.aggregate(total_initial_value=Sum("initial_value"))[
                "total_initial_value"
            ]
            or Decimal("0")
        )
    else:
        initial_stock_query = Product.objects.filter(inventory_name=inventory_name)
        if category_filter:
            initial_stock_query = initial_stock_query.filter(
                group__icontains=category_filter
            )
        initial_stock_value = (
            initial_stock_query.aggregate(
                total_initial_value=Sum(F("initial_balance") * F("initial_unit_cost"))
            )["total_initial_value"]
            or Decimal("0")
        )

    past_movements_value = (
        base_queryset.filter(date__lt=start_of_period).aggregate(total_value=Sum("total"))[
            "total_value"
        ]
        or Decimal("0")
    )

    starting_balance = initial_stock_value + past_movements_value

    monthly_movements = (
        base_queryset.filter(date__gte=start_of_period)
        .annotate(month=TruncMonth("date"))
        .values("month")
        .annotate(
            total_entries=Sum("total", filter=Q(quantity__gt=0)),
            total_exits=Sum("total", filter=Q(quantity__lt=0)),
        )
        .order_by("month")
    )

    monthly_data = {
        item["month"].strftime("%Y-%m"): {
            "entries": item["total_entries"] or Decimal("0"),
            "exits": abs(item["total_exits"] or Decimal("0")),
        }
        for item in monthly_movements
    }

    result_data = []
    current_balance = starting_balance
    for i in range(12):
        current_month_date = twelve_months_ago + relativedelta(months=i)
        month_key = current_month_date.strftime("%Y-%m")

        month_data = monthly_data.get(
            month_key, {"entries": Decimal("0"), "exits": Decimal("0")}
        )
        entries = month_data["entries"]
        exits = month_data["exits"]

        current_balance += entries - exits
        result_data.append(
            {
                "month": month_key,
                "total_entries": float(entries),
                "total_exits": float(exits),
                "closing_balance": float(current_balance),
            }
        )

    return result_data


def get_product_analysis_data(
    inventory_name="default",
    category_filter="",
    warehouse_filter="",
    rotation_filter="",
    stagnant_filter="",
    high_rotation_filter="",
    date_from="",  # Se mantiene por compatibilidad con la vista actual.
    date_to="",
    search_filter="",
    limit="",
):
    """
    Construye el análisis agregado por producto con filtros de negocio.
    Usa queries SQL masivas para evitar N+1 y loops lentos.
    """
    _ = date_from

    target_date = None
    if date_to:
        try:
            target_date = datetime.strptime(date_to, "%Y-%m-%d").date()
        except ValueError:
            target_date = None

    # ── 1. Productos base ────────────────────────────────────────────────────
    products_qs = Product.objects.filter(inventory_name=inventory_name).values(
        "id", "code", "description", "group", "initial_balance", "initial_unit_cost"
    )
    if category_filter:
        products_qs = products_qs.filter(group__icontains=category_filter)
    if warehouse_filter:
        products_qs = products_qs.filter(
            warehousedetail__warehouse__icontains=warehouse_filter
        ).distinct()
    if search_filter:
        sl = search_filter.lower()
        products_qs = products_qs.filter(
            Q(code__icontains=sl) | Q(description__icontains=sl)
        )
    if limit:
        try:
            products_qs = products_qs[: int(limit)]
        except ValueError:
            pass

    products_list = list(products_qs)
    if not products_list:
        return []

    product_ids = [p["id"] for p in products_list]

    # ── 2. Stock actual: último registro por (producto, almacén) ─────────────
    # Una sola query con MAX(id) agrupado — mucho más rápido que Subquery correlacionada.
    records_scope = InventoryRecord.objects.filter(product_id__in=product_ids)
    if target_date:
        records_scope = records_scope.filter(date__lte=target_date)

    latest_ids_qs = (
        records_scope.values("product_id", "warehouse")
        .annotate(latest_id=Max("id"))
        .values("latest_id")
    )
    latest_ids = [row["latest_id"] for row in latest_ids_qs if row["latest_id"]]

    # stock_dict[product_id] = (sum_final_qty, max_date, unit_cost, has_negative)
    stock_dict: dict[int, tuple] = {}
    if latest_ids:
        for rec in InventoryRecord.objects.filter(id__in=latest_ids).values(
            "product_id", "final_quantity", "unit_cost", "date"
        ):
            pid = rec["product_id"]
            fq = Decimal(rec["final_quantity"] or 0)
            if pid not in stock_dict:
                stock_dict[pid] = [Decimal("0"), rec["date"], Decimal(rec["unit_cost"] or 0), False]
            stock_dict[pid][0] += fq
            if fq < 0:
                stock_dict[pid][3] = True
            if rec["date"] > stock_dict[pid][1]:
                stock_dict[pid][1] = rec["date"]
                stock_dict[pid][2] = Decimal(rec["unit_cost"] or 0)

    # ── 3. Stock inicial por almacén (para productos sin movimientos) ─────────
    wd_initial: dict[int, tuple] = {}  # product_id -> (sum_qty, has_negative)
    for row in WarehouseDetail.objects.filter(product_id__in=product_ids).values(
        "product_id", "warehouse", "initial_quantity"
    ):
        pid = row["product_id"]
        qty = Decimal(row["initial_quantity"] or 0)
        if pid not in wd_initial:
            wd_initial[pid] = [Decimal("0"), False]
        wd_initial[pid][0] += qty
        if qty < 0:
            wd_initial[pid][1] = True

    # ── 4. Nombres de almacenes por producto ─────────────────────────────────
    warehouses_dict: dict[int, set] = {}
    for row in WarehouseDetail.objects.filter(product_id__in=product_ids).values(
        "product_id", "warehouse"
    ):
        warehouses_dict.setdefault(row["product_id"], set()).add(row["warehouse"])
    warehouses_str = {
        pid: ", ".join(sorted(ws)) or "Todos"
        for pid, ws in warehouses_dict.items()
    }

    # ── 5. Movimientos acumulados antes del año de rotación (balance_pre_year) ─
    rotation_year = target_date.year if target_date else datetime.now().year
    pre_year_filter = Q(product_id__in=product_ids)
    if target_date:
        pre_year_filter &= Q(date__lt=target_date.replace(day=1, month=1))
    else:
        pre_year_filter &= Q(date__year__lt=rotation_year)

    pre_year_dict: dict[int, Decimal] = {
        row["product_id"]: row["total"] or Decimal("0")
        for row in InventoryRecord.objects.filter(pre_year_filter)
        .values("product_id")
        .annotate(total=Sum("quantity"))
    }

    # ── 6. Movimientos mensuales del año de rotación ─────────────────────────
    monthly_filter = Q(product_id__in=product_ids, date__year=rotation_year)
    if target_date:
        monthly_filter &= Q(date__lte=target_date)

    monthly_dict: dict[int, dict[int, Decimal]] = {}
    for row in (
        InventoryRecord.objects.filter(monthly_filter)
        .annotate(month=TruncMonth("date"))
        .values("product_id", "month")
        .annotate(monthly_total=Sum("quantity"))
    ):
        pid = row["product_id"]
        monthly_dict.setdefault(pid, {})[row["month"].month] = row["monthly_total"] or Decimal("0")

    # ── 7. Construir resultado ────────────────────────────────────────────────
    analysis_data = []
    for product in products_list:
        try:
            pid = product["id"]

            # Stock actual
            if pid in stock_dict:
                sd = stock_dict[pid]
                current_stock = sd[0]
                current_unit_cost = sd[2] or Decimal(product["initial_unit_cost"] or 0)
                negative_stock_alert = sd[3]
            else:
                wi = wd_initial.get(pid, [Decimal("0"), False])
                current_stock = wi[0]
                current_unit_cost = Decimal(product["initial_unit_cost"] or 0)
                negative_stock_alert = wi[1]

            is_consumed = current_stock <= 0

            # Rotación
            pre_year_sum = pre_year_dict.get(pid, Decimal("0"))
            balance_pre_year = Decimal(product["initial_balance"] or 0) + pre_year_sum
            movements_by_month = monthly_dict.get(pid, {})

            monthly_balances = []
            running = balance_pre_year
            for month in range(1, 13):
                running += movements_by_month.get(month, Decimal("0"))
                monthly_balances.append(running)

            all_zero = all(b == 0 for b in monthly_balances)
            unique_b = set(monthly_balances)

            if all_zero and balance_pre_year == 0:
                rotation = "Activo"
            elif all_zero and balance_pre_year > 0:
                rotation = "Obsoleto"
            elif len(unique_b) == 1 and monthly_balances[0] > 0:
                rotation = "Obsoleto"
            elif (
                len(monthly_balances) >= 3
                and len(set(monthly_balances[-3:])) == 1
                and monthly_balances[-1] > 0
            ):
                rotation = "Estancado"
            else:
                rotation = "Activo"

            is_stagnant = rotation in ["Estancado", "Obsoleto"]
            consecutive_changes = sum(
                1
                for i in range(len(monthly_balances) - 1)
                if monthly_balances[i] != monthly_balances[i + 1]
            )
            high_rotation = "Sí" if consecutive_changes >= 2 else "No"

            # Filtros de negocio en Python (aplicados tras calcular)
            if rotation_filter and rotation != rotation_filter:
                continue
            if stagnant_filter == "Sí" and not is_stagnant:
                continue
            if stagnant_filter == "No" and is_stagnant:
                continue
            if high_rotation_filter == "Sí" and high_rotation != "Sí":
                continue
            if high_rotation_filter == "No" and high_rotation == "Sí":
                continue

            analysis_data.append(
                {
                    "codigo": product["code"],
                    "nombre_producto": product["description"],
                    "grupo": product["group"],
                    "cantidad_saldo_actual": float(current_stock),
                    "valor_saldo_actual": float(current_stock * current_unit_cost),
                    "costo_unitario": float(current_unit_cost),
                    "consumed": "Sí" if is_consumed else "No",
                    "estancado": "Sí" if is_stagnant else "No",
                    "rotacion": rotation,
                    "alta_rotacion": high_rotation,
                    "almacen": warehouses_str.get(pid, "Todos"),
                    "has_negative_stock_alert": negative_stock_alert,
                }
            )
        except Exception as exc:
            logger.error(
                "Error processing product %s: %s", product.get("code"), exc, exc_info=True
            )
            continue

    return analysis_data


def get_inventory_at_date_data(
    inventory_name="default",
    date_str="",
    target_date=None,
    warehouse_filter="",
    category_filter="",
):
    """
    Calcula el inventario (cantidad/valor) de cada producto para una fecha dada.
    """
    if target_date is None:
        raise ValueError("target_date es requerido para calcular inventario por fecha")

    products_query = Product.objects.filter(inventory_name=inventory_name)
    if category_filter:
        products_query = products_query.filter(group__icontains=category_filter)
    if warehouse_filter:
        products_query = products_query.filter(
            warehousedetail__warehouse__icontains=warehouse_filter
        ).distinct()

    product_ids = list(products_query.values_list("id", flat=True))
    if not product_ids:
        return {
            "date": date_str,
            "total_quantity": 0.0,
            "total_value": 0.0,
            "products": [],
        }

    warehouse_details = WarehouseDetail.objects.filter(product_id__in=product_ids).select_related(
        "product"
    )
    warehouse_detail_dict = {}
    for wd in warehouse_details:
        product_id = wd.product_id
        if product_id not in warehouse_detail_dict:
            warehouse_detail_dict[product_id] = {}
        warehouse_detail_dict[product_id][wd.warehouse] = wd

    movements_up_to_date = InventoryRecord.objects.filter(
        product_id__in=product_ids,
        date__lte=target_date,
    ).select_related("product")

    movements_dict = {}
    for record in movements_up_to_date:
        product_id = record.product_id
        warehouse = record.warehouse
        if product_id not in movements_dict:
            movements_dict[product_id] = {}
        if warehouse not in movements_dict[product_id]:
            movements_dict[product_id][warehouse] = []
        movements_dict[product_id][warehouse].append(record)

    latest_costs = InventoryRecord.objects.filter(
        product_id__in=product_ids,
        date__lte=target_date,
    ).values("product_id").annotate(latest_cost=Max("unit_cost"))
    latest_cost_dict = {
        item["product_id"]: item["latest_cost"] or Decimal("0") for item in latest_costs
    }

    total_quantity = Decimal("0")
    total_value = Decimal("0")
    products_data = []

    for product in products_query:
        product_quantity = Decimal("0")
        product_warehouses = warehouse_detail_dict.get(product.id, {})

        if warehouse_filter:
            product_warehouses = {
                name: detail
                for name, detail in product_warehouses.items()
                if warehouse_filter.lower() in name.lower()
            }

        for warehouse, wd in product_warehouses.items():
            warehouse_quantity = Decimal(wd.initial_quantity or 0)
            warehouse_movements = movements_dict.get(product.id, {}).get(warehouse, [])
            for record in warehouse_movements:
                warehouse_quantity += Decimal(record.quantity or 0)
            product_quantity += warehouse_quantity

        unit_cost = latest_cost_dict.get(product.id, Decimal(product.initial_unit_cost or 0))
        product_value = product_quantity * unit_cost

        total_quantity += product_quantity
        total_value += product_value

        products_data.append(
            {
                "codigo": product.code,
                "nombre_producto": product.description,
                "grupo": product.group,
                "cantidad": float(product_quantity),
                "valor": float(product_value),
                "costo_unitario": float(unit_cost),
            }
        )

    return {
        "date": date_str,
        "total_quantity": float(total_quantity),
        "total_value": float(total_value),
        "products": products_data,
    }
