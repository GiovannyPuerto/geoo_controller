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
from django.contrib.postgres.aggregates import StringAgg as GroupConcat
from django.db.models import F, Max, OuterRef, Q, Subquery, Sum
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
    """
    _ = date_from

    target_date = None
    if date_to:
        try:
            target_date = datetime.strptime(date_to, "%Y-%m-%d").date()
        except ValueError:
            target_date = None

    products_query = Product.objects.filter(inventory_name=inventory_name).only(
        "id",
        "code",
        "description",
        "group",
        "initial_balance",
        "initial_unit_cost",
    )

    if limit:
        try:
            limit_int = int(limit)
            products_query = products_query[:limit_int]
        except ValueError:
            pass

    if category_filter:
        products_query = products_query.filter(group__icontains=category_filter)

    if warehouse_filter:
        products_query = products_query.filter(
            warehousedetail__warehouse__icontains=warehouse_filter
        ).distinct()

    product_ids = list(products_query.values_list("id", flat=True))
    if not product_ids:
        return []

    latest_records_query = InventoryRecord.objects.filter(
        product_id=OuterRef("product_id"),
        warehouse=OuterRef("warehouse"),
    ).order_by("-date")
    if target_date:
        latest_records_query = latest_records_query.filter(date__lte=target_date)

    records_scope = InventoryRecord.objects.filter(product_id__in=product_ids)
    if target_date:
        records_scope = records_scope.filter(date__lte=target_date)

    last_records_per_warehouse = InventoryRecord.objects.filter(
        id__in=records_scope.values("product_id", "warehouse")
        .annotate(latest_id=Subquery(latest_records_query.values("id")[:1]))
        .values("latest_id")
    ).only("product_id", "date", "final_quantity", "unit_cost", "warehouse")

    last_records_dict = {}
    for record in last_records_per_warehouse:
        product_id = record.product_id
        if product_id not in last_records_dict:
            last_records_dict[product_id] = []
        last_records_dict[product_id].append(record)

    pre_year_query = InventoryRecord.objects.filter(product_id__in=product_ids)
    if target_date:
        pre_year_query = pre_year_query.filter(
            date__lt=target_date.replace(day=1, month=1)
        )
    else:
        pre_year_query = pre_year_query.filter(date__year__lt=datetime.now().year)

    pre_year_sums = pre_year_query.values("product_id").annotate(
        total_quantity=Sum("quantity")
    )
    pre_year_dict = {
        item["product_id"]: item["total_quantity"] or Decimal("0")
        for item in pre_year_sums
    }

    rotation_year = target_date.year if target_date else datetime.now().year
    monthly_movements = InventoryRecord.objects.filter(
        product_id__in=product_ids,
        date__year=rotation_year,
    )
    if target_date:
        monthly_movements = monthly_movements.filter(date__lte=target_date)

    monthly_movements = (
        monthly_movements.annotate(month=TruncMonth("date"))
        .values("product_id", "month")
        .annotate(monthly_total=Sum("quantity"))
        .order_by("product_id", "month")
    )

    monthly_dict = {}
    for movement in monthly_movements:
        product_id = movement["product_id"]
        if product_id not in monthly_dict:
            monthly_dict[product_id] = {}
        monthly_dict[product_id][movement["month"].month] = movement["monthly_total"]

    warehouse_details = WarehouseDetail.objects.filter(product_id__in=product_ids).values(
        "product_id"
    ).annotate(warehouses=GroupConcat("warehouse", delimiter=", ", distinct=True))
    warehouses_dict = {
        item["product_id"]: item["warehouses"] or "Todos" for item in warehouse_details
    }

    warehouse_detail_records = WarehouseDetail.objects.filter(
        product_id__in=product_ids
    ).select_related("product")
    warehouse_detail_dict = {}
    for wd in warehouse_detail_records:
        product_id = wd.product_id
        if product_id not in warehouse_detail_dict:
            warehouse_detail_dict[product_id] = {}
        warehouse_detail_dict[product_id][wd.warehouse] = wd

    analysis_data = []
    for product in products_query:
        try:
            last_records = last_records_dict.get(product.id, [])
            current_stock = Decimal("0")
            negative_stock_alert = False

            if last_records:
                for record in last_records:
                    final_qty = Decimal(record.final_quantity or 0)
                    current_stock += final_qty
                    if final_qty < 0:
                        negative_stock_alert = True
            else:
                for wd in warehouse_detail_dict.get(product.id, {}).values():
                    initial_qty = Decimal(wd.initial_quantity or 0)
                    current_stock += initial_qty
                    if initial_qty < 0:
                        negative_stock_alert = True

            if last_records:
                latest_record = max(last_records, key=lambda rec: rec.date)
                current_unit_cost = Decimal(
                    latest_record.unit_cost or product.initial_unit_cost or 0
                )
            else:
                current_unit_cost = Decimal(product.initial_unit_cost or 0)

            is_consumed = current_stock <= 0

            pre_year_sum = pre_year_dict.get(product.id, Decimal("0"))
            balance_pre_year = Decimal(product.initial_balance or 0) + pre_year_sum
            movements_by_month = monthly_dict.get(product.id, {})

            monthly_balances = []
            running_balance = balance_pre_year
            for month in range(1, 13):
                running_balance += movements_by_month.get(month, Decimal("0"))
                monthly_balances.append(running_balance)

            all_zero_balance = all(balance == 0 for balance in monthly_balances)
            unique_balances = set(monthly_balances)

            if all_zero_balance and balance_pre_year == 0:
                rotation = "Activo"
            elif all_zero_balance and balance_pre_year > 0:
                rotation = "Obsoleto"
            elif len(unique_balances) == 1 and monthly_balances[0] > 0:
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

            if rotation_filter and rotation != rotation_filter:
                continue
            if stagnant_filter:
                if stagnant_filter == "Sí" and not is_stagnant:
                    continue
                if stagnant_filter == "No" and is_stagnant:
                    continue
            if high_rotation_filter:
                if high_rotation_filter == "Sí" and high_rotation != "Sí":
                    continue
                if high_rotation_filter == "No" and high_rotation == "Sí":
                    continue
            if search_filter:
                search_lower = search_filter.lower()
                if not (
                    search_lower in product.code.lower()
                    or search_lower in product.description.lower()
                ):
                    continue

            analysis_data.append(
                {
                    "codigo": product.code,
                    "nombre_producto": product.description,
                    "grupo": product.group,
                    "cantidad_saldo_actual": float(current_stock),
                    "valor_saldo_actual": float(current_stock * current_unit_cost),
                    "costo_unitario": float(current_unit_cost),
                    "consumed": "Sí" if is_consumed else "No",
                    "estancado": "Sí" if is_stagnant else "No",
                    "rotacion": rotation,
                    "alta_rotacion": high_rotation,
                    "almacen": warehouses_dict.get(product.id, "Todos"),
                    "has_negative_stock_alert": negative_stock_alert,
                }
            )
        except Exception as exc:
            logger.error(
                f"Error processing product {product.code}: {str(exc)}", exc_info=True
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
