"""
Servicios analíticos de inventario.

Este módulo centraliza cálculos de:
- movimientos mensuales,
- análisis por producto,
- estado de inventario a una fecha objetivo.
"""

import logging
import hashlib
import json
import re
from datetime import datetime, timedelta
from decimal import Decimal

from dateutil.relativedelta import relativedelta
from django.core.cache import cache
from django.db.models import (
    Case,
    Count,
    DecimalField,
    ExpressionWrapper,
    F,
    Max,
    Min,
    Q,
    Sum,
    Value,
    When,
)
from django.db.models.functions import TruncMonth
from django.utils.timezone import now

from ..models import InventoryRecord, Product, WarehouseDetail

logger = logging.getLogger(__name__)


def _search_q(search_filter: str, code_field: str = 'code', desc_field: str = 'description') -> Q:
    """
    Retorna un Q para filtrar por código o descripción.
    Si la búsqueda es solo dígitos → coincidencia exacta en código (evita
    que "320" coincida con "3200" o "1320").
    Si contiene letras → coincidencia parcial en código y descripción.
    """
    if re.match(r'^\d+$', search_filter):
        return Q(**{f'{code_field}__iexact': search_filter}) | Q(**{f'{desc_field}__icontains': search_filter})
    return Q(**{f'{code_field}__icontains': search_filter}) | Q(**{f'{desc_field}__icontains': search_filter})


def _resolve_target_month(target_month="", fallback_date=None):
    """
    Resuelve el mes objetivo en formato YYYY-MM.
    """
    if target_month:
        try:
            month_start = datetime.strptime(target_month, "%Y-%m").date().replace(day=1)
            return month_start, month_start.strftime("%Y-%m")
        except ValueError:
            pass

    if fallback_date is None:
        fallback_date = now().date()
    month_start = fallback_date.replace(day=1)
    return month_start, month_start.strftime("%Y-%m")


def _get_monthly_value_series(
    inventory_name="default",
    warehouse_filter="",
    category_filter="",
    search_filter="",
    months=12,
):
    """
    Construye la serie mensual de entradas/salidas valorizadas y saldo inicial.
    """
    try:
        months_count = int(months or 12)
    except (TypeError, ValueError):
        months_count = 12
    months_count = max(1, min(months_count, 36))
    today = now().date()
    start_month_date = (today - relativedelta(months=months_count - 1)).replace(day=1)

    base_queryset = InventoryRecord.objects.filter(
        product__inventory_name=inventory_name
    )
    if warehouse_filter:
        base_queryset = base_queryset.filter(warehouse__icontains=warehouse_filter)
    if category_filter:
        base_queryset = base_queryset.filter(category__icontains=category_filter)
    if search_filter:
        base_queryset = base_queryset.filter(
            _search_q(search_filter, 'product__code', 'product__description')
        )

    value_output = DecimalField(max_digits=28, decimal_places=6)

    # Usamos el campo `total` (ya almacenado con signo correcto desde el ERP)
    # en lugar de recalcular quantity × unit_cost.  Esto produce los mismos
    # valores que el ERP cuando usa costeo promedio ponderado, FIFO u otro
    # método donde unit_cost de salidas ≠ costo de compra.
    #
    # Convención del campo `total` en BD:
    #   total > 0  →  entrada  (valor añadido al inventario)
    #   total < 0  →  salida   (valor removido del inventario)
    #   total = 0  →  movimiento sin valor (no afecta saldo monetario)
    #
    # Para el saldo inicial y pasado también usamos total, que ya representa
    # el cambio neto de valor de cada movimiento.

    # ── Saldo inicial (inventario base) ─────────────────────────────────────
    if warehouse_filter:
        initial_stock_query = WarehouseDetail.objects.filter(
            product__inventory_name=inventory_name,
            warehouse__icontains=warehouse_filter,
        )
        if category_filter:
            initial_stock_query = initial_stock_query.filter(
                product__group__icontains=category_filter
            )
        if search_filter:
            initial_stock_query = initial_stock_query.filter(
                _search_q(search_filter, 'product__code', 'product__description')
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
        if search_filter:
            initial_stock_query = initial_stock_query.filter(
                _search_q(search_filter)
            )
        initial_stock_value = (
            initial_stock_query.aggregate(
                total_initial_value=Sum(F("initial_balance") * F("initial_unit_cost"))
            )["total_initial_value"]
            or Decimal("0")
        )

    past_movements_value = (
        base_queryset.filter(date__lt=start_month_date).aggregate(
            total_value=Sum("total")
        )["total_value"]
        or Decimal("0")
    )
    starting_balance = initial_stock_value + past_movements_value

    monthly_movements = (
        base_queryset.filter(date__gte=start_month_date)
        .annotate(month=TruncMonth("date"))
        .values("month")
        .annotate(
            total_entries=Sum(
                Case(
                    When(quantity__gt=0, then=F("total")),
                    default=Value(Decimal("0"), output_field=value_output),
                    output_field=value_output,
                )
            ),
            total_exits=Sum(
                Case(
                    # total es negativo para salidas; lo negamos para reportar
                    # el valor absoluto de lo que salió del inventario.
                    When(quantity__lt=0, then=ExpressionWrapper(
                        -1 * F("total"),
                        output_field=value_output,
                    )),
                    default=Value(Decimal("0"), output_field=value_output),
                    output_field=value_output,
                )
            ),
        )
        .order_by("month")
    )

    monthly_data = {
        item["month"].strftime("%Y-%m"): {
            "entries": item["total_entries"] or Decimal("0"),
            "exits": item["total_exits"] or Decimal("0"),
        }
        for item in monthly_movements
    }

    return start_month_date, months_count, starting_balance, monthly_data


def get_monthly_movements_data(
    inventory_name="default",
    warehouse_filter="",
    category_filter="",
    search_filter="",
):
    """
    Calcula entradas, salidas y saldo de cierre para una ventana de 12 meses.
    """
    (
        start_month_date,
        months_count,
        starting_balance,
        monthly_data,
    ) = _get_monthly_value_series(
        inventory_name=inventory_name,
        warehouse_filter=warehouse_filter,
        category_filter=category_filter,
        search_filter=search_filter,
        months=12,
    )

    result_data = []
    current_balance = starting_balance
    for i in range(months_count):
        current_month_date = start_month_date + relativedelta(months=i)
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


def get_monthly_cuts_data(
    inventory_name="default",
    warehouse_filter="",
    category_filter="",
    search_filter="",
    months=12,
):
    """
    Calcula cortes mensuales:
    - corte general (valorizado),
    - corte promedio por producto.
    """
    (
        start_month_date,
        months_count,
        starting_balance,
        monthly_data,
    ) = _get_monthly_value_series(
        inventory_name=inventory_name,
        warehouse_filter=warehouse_filter,
        category_filter=category_filter,
        search_filter=search_filter,
        months=months,
    )

    # Cantidad de productos considerados para el promedio por producto.
    products_qs = Product.objects.filter(inventory_name=inventory_name)
    if category_filter:
        products_qs = products_qs.filter(group__icontains=category_filter)
    if warehouse_filter:
        products_qs = products_qs.filter(
            Q(warehousedetail__warehouse__icontains=warehouse_filter)
            | Q(inventoryrecord__warehouse__icontains=warehouse_filter)
        ).distinct()
    if search_filter:
        products_qs = products_qs.filter(
            _search_q(search_filter)
        )
    products_count = products_qs.count()

    rows = []
    running_balance = starting_balance
    average_sum_general = Decimal("0")
    average_sum_per_product = Decimal("0")

    for i in range(months_count):
        current_month_date = start_month_date + relativedelta(months=i)
        month_key = current_month_date.strftime("%Y-%m")
        month_data = monthly_data.get(
            month_key, {"entries": Decimal("0"), "exits": Decimal("0")}
        )
        entries = month_data["entries"]
        exits = month_data["exits"]
        opening_balance = running_balance
        closing_balance = opening_balance + entries - exits
        average_balance_general = (opening_balance + closing_balance) / Decimal("2")
        if products_count > 0:
            average_balance_per_product = average_balance_general / Decimal(products_count)
        else:
            average_balance_per_product = Decimal("0")
        average_sum_general += average_balance_general
        average_sum_per_product += average_balance_per_product

        rows.append(
            {
                "month": month_key,
                "opening_balance": float(opening_balance),
                "total_entries": float(entries),
                "total_exits": float(exits),
                "closing_balance": float(closing_balance),
                # Compatibilidad: average_balance conserva el corte general.
                "average_balance": float(average_balance_general),
                "average_balance_general": float(average_balance_general),
                "average_balance_per_product": float(average_balance_per_product),
                "products_count": products_count,
            }
        )
        running_balance = closing_balance

    period_average_general = (
        average_sum_general / Decimal(months_count) if months_count else Decimal("0")
    )
    period_average_per_product = (
        average_sum_per_product / Decimal(months_count) if months_count else Decimal("0")
    )

    return {
        "months": rows,
        # El promedio principal solicitado es producto por producto.
        "period_average_cut": float(period_average_per_product),
        "period_average_general": float(period_average_general),
        "period_average_per_product": float(period_average_per_product),
        "products_count": products_count,
        "months_count": months_count,
    }


def get_monthly_product_cuts_data(
    inventory_name="default",
    target_month="",
    warehouse_filter="",
    category_filter="",
    search_filter="",
    limit="",
    offset="",
    page_size="",
):
    """
    Retorna el corte mensual por producto usando promedio diario real.

    Para cada producto calcula:
    - cantidad de apertura del mes,
    - cantidad de cierre del mes,
    - cantidad promedio diaria del mes (promedio de cortes diarios),
    y sus valores con costo unitario.
    """
    records_base = InventoryRecord.objects.filter(product__inventory_name=inventory_name)
    if warehouse_filter:
        records_base = records_base.filter(warehouse__icontains=warehouse_filter)
    if category_filter:
        records_base = records_base.filter(category__icontains=category_filter)
    if search_filter:
        records_base = records_base.filter(
            _search_q(search_filter, 'product__code', 'product__description')
        )

    max_record_date = records_base.aggregate(max_d=Max("date"))["max_d"]
    month_start, month_key = _resolve_target_month(
        target_month=target_month,
        fallback_date=max_record_date,
    )
    month_end = (month_start + relativedelta(months=1)) - relativedelta(days=1)
    month_days = []
    day_cursor = month_start
    while day_cursor <= month_end:
        month_days.append(day_cursor)
        day_cursor += timedelta(days=1)
    days_count = len(month_days)

    products_qs = Product.objects.filter(inventory_name=inventory_name)
    if category_filter:
        products_qs = products_qs.filter(group__icontains=category_filter)
    if warehouse_filter:
        products_qs = products_qs.filter(
            Q(warehousedetail__warehouse__icontains=warehouse_filter)
            | Q(inventoryrecord__warehouse__icontains=warehouse_filter)
        ).distinct()
    if search_filter:
        products_qs = products_qs.filter(
            _search_q(search_filter)
        )

    try:
        limit_value = int(limit) if str(limit).strip() else 0
    except (TypeError, ValueError):
        limit_value = 0
    if limit_value < 0:
        limit_value = 0
    try:
        offset_value = int(offset) if str(offset).strip() else 0
    except (TypeError, ValueError):
        offset_value = 0
    if offset_value < 0:
        offset_value = 0
    try:
        page_size_value = int(page_size) if str(page_size).strip() else 0
    except (TypeError, ValueError):
        page_size_value = 0
    if page_size_value < 0:
        page_size_value = 0

    products_meta = list(
        products_qs.values(
            "id",
            "code",
            "description",
            "group",
            "initial_balance",
            "initial_unit_cost",
        )
    )
    product_ids = [p["id"] for p in products_meta]
    if not product_ids:
        return {
            "month": month_key,
            "month_start": month_start.isoformat(),
            "month_end": month_end.isoformat(),
            "products": [],
            "products_count": 0,
            "totals": {
                "opening_quantity": 0.0,
                "closing_quantity": 0.0,
                "average_quantity": 0.0,
                "opening_value": 0.0,
                "closing_value": 0.0,
                "average_value": 0.0,
            },
            "truncated": False,
            "limit": limit_value,
            "offset": offset_value,
            "page_size": page_size_value,
            "has_next_page": False,
        }

    records_scope = InventoryRecord.objects.filter(product_id__in=product_ids)
    if warehouse_filter:
        records_scope = records_scope.filter(warehouse__icontains=warehouse_filter)

    warehouse_query = WarehouseDetail.objects.filter(product_id__in=product_ids)
    if warehouse_filter:
        warehouse_query = warehouse_query.filter(warehouse__icontains=warehouse_filter)

    initial_qty_by_warehouse: dict[tuple[int, str], Decimal] = {
        (row["product_id"], row["warehouse"]): Decimal(row["initial_quantity"] or 0)
        for row in warehouse_query.values("product_id", "warehouse", "initial_quantity")
    }

    movement_before_start_by_warehouse: dict[tuple[int, str], Decimal] = {
        (row["product_id"], row["warehouse"]): row["qty"] or Decimal("0")
        for row in records_scope.filter(date__lt=month_start)
        .values("product_id", "warehouse")
        .annotate(qty=Sum("quantity"))
    }
    movement_by_day_by_warehouse: dict[tuple[int, str, datetime], Decimal] = {
        (row["product_id"], row["warehouse"], row["date"]): row["qty"] or Decimal("0")
        for row in records_scope.filter(date__gte=month_start, date__lte=month_end)
        .values("product_id", "warehouse", "date")
        .annotate(qty=Sum("quantity"))
    }

    opening_final_ids = [
        row["latest_id"]
        for row in records_scope.filter(
            final_quantity__isnull=False,
            date__lt=month_start,
        )
        .values("product_id", "warehouse")
        .annotate(latest_id=Max("id"))
        if row["latest_id"]
    ]
    opening_final_by_warehouse: dict[tuple[int, str], Decimal] = {
        (row["product_id"], row["warehouse"]): Decimal(row["final_quantity"] or 0)
        for row in InventoryRecord.objects.filter(id__in=opening_final_ids).values(
            "product_id", "warehouse", "final_quantity"
        )
    }
    daily_final_ids = [
        row["latest_id"]
        for row in records_scope.filter(
            final_quantity__isnull=False,
            date__gte=month_start,
            date__lte=month_end,
        )
        .values("product_id", "warehouse", "date")
        .annotate(latest_id=Max("id"))
        if row["latest_id"]
    ]
    daily_final_by_warehouse: dict[tuple[int, str, datetime], Decimal] = {
        (row["product_id"], row["warehouse"], row["date"]): Decimal(
            row["final_quantity"] or 0
        )
        for row in InventoryRecord.objects.filter(id__in=daily_final_ids).values(
            "product_id", "warehouse", "date", "final_quantity"
        )
    }

    latest_cost_ids = [
        row["latest_id"]
        for row in records_scope.filter(date__lte=month_end)
        .values("product_id")
        .annotate(latest_id=Max("id"))
        if row["latest_id"]
    ]
    latest_cost_by_product: dict[int, Decimal] = {
        row["product_id"]: Decimal(row["unit_cost"] or 0)
        for row in InventoryRecord.objects.filter(id__in=latest_cost_ids).values(
            "product_id", "unit_cost"
        )
    }

    warehouses_by_product: dict[int, set[str]] = {}
    for row in warehouse_query.values("product_id", "warehouse"):
        warehouses_by_product.setdefault(row["product_id"], set()).add(row["warehouse"])
    for row in records_scope.values("product_id", "warehouse").distinct():
        warehouses_by_product.setdefault(row["product_id"], set()).add(row["warehouse"])

    movement_before_start_by_product: dict[int, Decimal] = {
        row["product_id"]: row["qty"] or Decimal("0")
        for row in records_scope.filter(date__lt=month_start)
        .values("product_id")
        .annotate(qty=Sum("quantity"))
    }
    movement_by_day_by_product: dict[tuple[int, datetime], Decimal] = {
        (row["product_id"], row["date"]): row["qty"] or Decimal("0")
        for row in records_scope.filter(date__gte=month_start, date__lte=month_end)
        .values("product_id", "date")
        .annotate(qty=Sum("quantity"))
    }
    daily_final_product_ids = [
        item["latest_id"]
        for item in records_scope.filter(
            final_quantity__isnull=False,
            date__gte=month_start,
            date__lte=month_end,
        )
        .values("product_id", "date")
        .annotate(latest_id=Max("id"))
        if item["latest_id"]
    ]
    daily_final_by_product: dict[tuple[int, datetime], Decimal] = {
        (row["product_id"], row["date"]): Decimal(row["final_quantity"] or 0)
        for row in InventoryRecord.objects.filter(id__in=daily_final_product_ids).values(
            "product_id", "date", "final_quantity"
        )
    }

    rows = []
    total_opening_qty = Decimal("0")
    total_closing_qty = Decimal("0")
    total_average_qty = Decimal("0")
    total_opening_value = Decimal("0")
    total_closing_value = Decimal("0")
    total_average_value = Decimal("0")

    for product in products_meta:
        pid = product["id"]
        product_warehouses = warehouses_by_product.get(pid, set())
        opening_qty = Decimal("0")
        closing_qty = Decimal("0")
        sum_daily_qty = Decimal("0")

        if product_warehouses:
            for warehouse in product_warehouses:
                key = (pid, warehouse)

                opening_wh_qty = opening_final_by_warehouse.get(key)
                if opening_wh_qty is None:
                    opening_wh_qty = (
                        initial_qty_by_warehouse.get(key, Decimal("0"))
                        + movement_before_start_by_warehouse.get(key, Decimal("0"))
                    )

                running_wh_qty = opening_wh_qty
                sum_daily_wh_qty = Decimal("0")
                for day in month_days:
                    day_final_qty = daily_final_by_warehouse.get((pid, warehouse, day))
                    if day_final_qty is not None:
                        running_wh_qty = day_final_qty
                    else:
                        running_wh_qty += movement_by_day_by_warehouse.get(
                            (pid, warehouse, day), Decimal("0")
                        )
                    sum_daily_wh_qty += running_wh_qty

                opening_qty += opening_wh_qty
                closing_qty += running_wh_qty
                sum_daily_qty += sum_daily_wh_qty
        else:
            base_initial = Decimal(product["initial_balance"] or 0)
            opening_qty = base_initial + movement_before_start_by_product.get(
                pid, Decimal("0")
            )
            running_qty = opening_qty
            for day in month_days:
                day_final_qty = daily_final_by_product.get((pid, day))
                if day_final_qty is not None:
                    running_qty = day_final_qty
                else:
                    running_qty += movement_by_day_by_product.get((pid, day), Decimal("0"))
                sum_daily_qty += running_qty
            closing_qty = running_qty

        average_qty = (
            sum_daily_qty / Decimal(days_count) if days_count > 0 else closing_qty
        )
        unit_cost = latest_cost_by_product.get(
            pid, Decimal(product["initial_unit_cost"] or 0)
        )

        opening_value = opening_qty * unit_cost
        closing_value = closing_qty * unit_cost
        average_value = average_qty * unit_cost

        total_opening_qty += opening_qty
        total_closing_qty += closing_qty
        total_average_qty += average_qty
        total_opening_value += opening_value
        total_closing_value += closing_value
        total_average_value += average_value

        rows.append(
            {
                "codigo": product["code"],
                "nombre_producto": product["description"],
                "grupo": product["group"],
                "cantidad_apertura": float(opening_qty),
                "cantidad_cierre": float(closing_qty),
                "cantidad_promedio": float(average_qty),
                "costo_unitario": float(unit_cost),
                "valor_apertura": float(opening_value),
                "valor_cierre": float(closing_value),
                "valor_promedio": float(average_value),
                # Alias de compatibilidad con formato de inventario actual.
                "cantidad": float(average_qty),
                "valor": float(average_value),
            }
        )

    rows.sort(key=lambda item: item["valor_promedio"], reverse=True)
    total_count_unbounded = len(rows)
    if limit_value > 0:
        rows = rows[:limit_value]
    total_count = len(rows)

    if page_size_value > 0:
        start = min(offset_value, total_count)
        end = min(start + page_size_value, total_count)
        page_rows = rows[start:end]
    else:
        start = 0
        end = total_count
        page_rows = rows

    return {
        "month": month_key,
        "month_start": month_start.isoformat(),
        "month_end": month_end.isoformat(),
        "products": page_rows,
        "products_count": total_count,
        "products_count_unbounded": total_count_unbounded,
        "totals": {
            "opening_quantity": float(total_opening_qty),
            "closing_quantity": float(total_closing_qty),
            "average_quantity": float(total_average_qty),
            "opening_value": float(total_opening_value),
            "closing_value": float(total_closing_value),
            "average_value": float(total_average_value),
        },
        # Alias de compatibilidad para cliente tipo inventario actual.
        "total_quantity": float(total_average_qty),
        "total_value": float(total_average_value),
        "truncated": bool(limit_value and total_count_unbounded > total_count),
        "limit": limit_value,
        "offset": start,
        "page_size": page_size_value,
        "has_next_page": end < total_count,
    }


def get_range_product_cuts_data(
    inventory_name="default",
    date_from="",
    date_to="",
    warehouse_filter="",
    category_filter="",
    search_filter="",
    limit="",
):
    """
    Calcula el inventario promedio por producto para un rango de fechas arbitrario.

    Usa la misma fórmula que get_monthly_cuts_data:
        cantidad_promedio = (cantidad_apertura + cantidad_cierre) / 2

    Esto garantiza que filtrar Feb 1 → Feb 28 dé el mismo resultado que
    el corte mensual de febrero en la pestaña Cortes Mensuales.
    """
    # ── Parseo de fechas ─────────────────────────────────────────────────────
    period_start = None
    period_end = None

    if date_from:
        try:
            period_start = datetime.strptime(date_from, "%Y-%m-%d").date()
        except ValueError:
            period_start = None

    if date_to:
        try:
            period_end = datetime.strptime(date_to, "%Y-%m-%d").date()
        except ValueError:
            period_end = None

    # Fallback: usar el rango máximo de registros del inventario
    if period_start is None or period_end is None:
        records_all = InventoryRecord.objects.filter(
            product__inventory_name=inventory_name
        )
        if warehouse_filter:
            records_all = records_all.filter(warehouse__icontains=warehouse_filter)
        agg = records_all.aggregate(min_d=Min("date"), max_d=Max("date"))
        if period_start is None:
            period_start = agg["min_d"] if agg["min_d"] else datetime.now().date()
        if period_end is None:
            period_end = agg["max_d"] if agg["max_d"] else datetime.now().date()

    if period_start > period_end:
        period_start, period_end = period_end, period_start

    # Cantidad de días (solo para el label informativo del response)
    days_count = (period_end - period_start).days + 1

    # ── Productos filtrados ──────────────────────────────────────────────────
    products_qs = Product.objects.filter(inventory_name=inventory_name)
    if category_filter:
        products_qs = products_qs.filter(group__icontains=category_filter)
    if warehouse_filter:
        products_qs = products_qs.filter(
            Q(warehousedetail__warehouse__icontains=warehouse_filter)
            | Q(inventoryrecord__warehouse__icontains=warehouse_filter)
        ).distinct()
    if search_filter:
        products_qs = products_qs.filter(
            _search_q(search_filter)
        )

    try:
        limit_value = int(limit) if str(limit).strip() else 0
    except (TypeError, ValueError):
        limit_value = 0
    if limit_value < 0:
        limit_value = 0

    products_meta = list(
        products_qs.values("id", "code", "description", "group", "initial_balance", "initial_unit_cost")
    )
    product_ids = [p["id"] for p in products_meta]
    if not product_ids:
        return {
            "date_from": period_start.isoformat(),
            "date_to": period_end.isoformat(),
            "days_count": days_count,
            "products": [],
            "products_count": 0,
            "totals": {
                "opening_quantity": 0.0,
                "closing_quantity": 0.0,
                "average_quantity": 0.0,
                "opening_value": 0.0,
                "closing_value": 0.0,
                "average_value": 0.0,
            },
        }

    records_scope = InventoryRecord.objects.filter(product_id__in=product_ids)
    if warehouse_filter:
        records_scope = records_scope.filter(warehouse__icontains=warehouse_filter)

    warehouse_query = WarehouseDetail.objects.filter(product_id__in=product_ids)
    if warehouse_filter:
        warehouse_query = warehouse_query.filter(warehouse__icontains=warehouse_filter)

    # ── Cantidades iniciales (WarehouseDetail) ───────────────────────────────
    initial_qty_by_warehouse: dict[tuple, Decimal] = {
        (row["product_id"], row["warehouse"]): Decimal(row["initial_quantity"] or 0)
        for row in warehouse_query.values("product_id", "warehouse", "initial_quantity")
    }

    # ── Movimientos ANTES del período (saldo apertura) ───────────────────────
    movement_before_start_by_warehouse: dict[tuple, Decimal] = {
        (row["product_id"], row["warehouse"]): row["qty"] or Decimal("0")
        for row in records_scope.filter(date__lt=period_start)
        .values("product_id", "warehouse")
        .annotate(qty=Sum("quantity"))
    }
    movement_before_start_by_product: dict[int, Decimal] = {
        row["product_id"]: row["qty"] or Decimal("0")
        for row in records_scope.filter(date__lt=period_start)
        .values("product_id")
        .annotate(qty=Sum("quantity"))
    }

    # ── final_quantity de apertura (último registro con final_quantity antes
    #    del período, para productos que usan saldo directo)  ─────────────────
    opening_final_ids = [
        row["latest_id"]
        for row in records_scope.filter(final_quantity__isnull=False, date__lt=period_start)
        .values("product_id", "warehouse")
        .annotate(latest_id=Max("id"))
        if row["latest_id"]
    ]
    opening_final_by_warehouse: dict[tuple, Decimal] = {
        (row["product_id"], row["warehouse"]): Decimal(row["final_quantity"] or 0)
        for row in InventoryRecord.objects.filter(id__in=opening_final_ids).values(
            "product_id", "warehouse", "final_quantity"
        )
    }

    # ── Lista de días del rango (para promedio diario real) ──────────────────
    range_days = []
    day_cursor = period_start
    while day_cursor <= period_end:
        range_days.append(day_cursor)
        day_cursor += timedelta(days=1)
    # days_count ya fue calculado antes como (period_end - period_start).days + 1

    # ── Movimientos DÍA A DÍA por almacén (dentro del período) ───────────────
    movement_by_day_by_warehouse: dict[tuple, Decimal] = {
        (row["product_id"], row["warehouse"], row["date"]): row["qty"] or Decimal("0")
        for row in records_scope.filter(date__gte=period_start, date__lte=period_end)
        .values("product_id", "warehouse", "date")
        .annotate(qty=Sum("quantity"))
    }

    # ── final_quantity DÍA A DÍA por almacén (dentro del período) ────────────
    daily_final_ids = [
        row["latest_id"]
        for row in records_scope.filter(
            final_quantity__isnull=False,
            date__gte=period_start,
            date__lte=period_end,
        )
        .values("product_id", "warehouse", "date")
        .annotate(latest_id=Max("id"))
        if row["latest_id"]
    ]
    daily_final_by_warehouse: dict[tuple, Decimal] = {
        (row["product_id"], row["warehouse"], row["date"]): Decimal(row["final_quantity"] or 0)
        for row in InventoryRecord.objects.filter(id__in=daily_final_ids).values(
            "product_id", "warehouse", "date", "final_quantity"
        )
    }

    # ── Movimientos DÍA A DÍA por producto (sin desglose por almacén) ────────
    movement_by_day_by_product: dict[tuple, Decimal] = {
        (row["product_id"], row["date"]): row["qty"] or Decimal("0")
        for row in records_scope.filter(date__gte=period_start, date__lte=period_end)
        .values("product_id", "date")
        .annotate(qty=Sum("quantity"))
    }

    # ── final_quantity DÍA A DÍA por producto (sin desglose por almacén) ─────
    daily_final_product_ids = [
        item["latest_id"]
        for item in records_scope.filter(
            final_quantity__isnull=False,
            date__gte=period_start,
            date__lte=period_end,
        )
        .values("product_id", "date")
        .annotate(latest_id=Max("id"))
        if item["latest_id"]
    ]
    daily_final_by_product: dict[tuple, Decimal] = {
        (row["product_id"], row["date"]): Decimal(row["final_quantity"] or 0)
        for row in InventoryRecord.objects.filter(id__in=daily_final_product_ids).values(
            "product_id", "date", "final_quantity"
        )
    }

    # ── Costo unitario más reciente (al cierre del período) ──────────────────
    latest_cost_ids = [
        row["latest_id"]
        for row in records_scope.filter(date__lte=period_end)
        .values("product_id")
        .annotate(latest_id=Max("id"))
        if row["latest_id"]
    ]
    latest_cost_by_product: dict[int, Decimal] = {
        row["product_id"]: Decimal(row["unit_cost"] or 0)
        for row in InventoryRecord.objects.filter(id__in=latest_cost_ids).values(
            "product_id", "unit_cost"
        )
    }

    # ── Almacenes por producto ───────────────────────────────────────────────
    warehouses_by_product: dict[int, set] = {}
    for row in warehouse_query.values("product_id", "warehouse"):
        warehouses_by_product.setdefault(row["product_id"], set()).add(row["warehouse"])
    for row in records_scope.values("product_id", "warehouse").distinct():
        warehouses_by_product.setdefault(row["product_id"], set()).add(row["warehouse"])

    # ── Cálculo por producto: promedio DIARIO REAL del stock ─────────────────
    # Igual que get_monthly_product_cuts_data pero para el rango elegido.
    rows = []
    total_opening_qty = Decimal("0")
    total_closing_qty = Decimal("0")
    total_average_qty = Decimal("0")
    total_opening_value = Decimal("0")
    total_closing_value = Decimal("0")
    total_average_value = Decimal("0")

    for product in products_meta:
        pid = product["id"]
        product_warehouses = warehouses_by_product.get(pid, set())
        opening_qty = Decimal("0")
        closing_qty = Decimal("0")
        sum_daily_qty = Decimal("0")

        if product_warehouses:
            for warehouse in product_warehouses:
                key = (pid, warehouse)

                # Saldo apertura
                opening_wh_qty = opening_final_by_warehouse.get(key)
                if opening_wh_qty is None:
                    opening_wh_qty = (
                        initial_qty_by_warehouse.get(key, Decimal("0"))
                        + movement_before_start_by_warehouse.get(key, Decimal("0"))
                    )

                # Iterar día a día para acumular el stock diario
                running_wh_qty = opening_wh_qty
                sum_daily_wh_qty = Decimal("0")
                for day in range_days:
                    day_final_qty = daily_final_by_warehouse.get((pid, warehouse, day))
                    if day_final_qty is not None:
                        running_wh_qty = day_final_qty
                    else:
                        running_wh_qty += movement_by_day_by_warehouse.get(
                            (pid, warehouse, day), Decimal("0")
                        )
                    sum_daily_wh_qty += running_wh_qty

                opening_qty += opening_wh_qty
                closing_qty += running_wh_qty
                sum_daily_qty += sum_daily_wh_qty
        else:
            base_initial = Decimal(product["initial_balance"] or 0)
            opening_qty = base_initial + movement_before_start_by_product.get(pid, Decimal("0"))
            running_qty = opening_qty
            for day in range_days:
                day_final_qty = daily_final_by_product.get((pid, day))
                if day_final_qty is not None:
                    running_qty = day_final_qty
                else:
                    running_qty += movement_by_day_by_product.get((pid, day), Decimal("0"))
                sum_daily_qty += running_qty
            closing_qty = running_qty

        average_qty = (
            sum_daily_qty / Decimal(days_count) if days_count > 0 else closing_qty
        )

        unit_cost = latest_cost_by_product.get(pid, Decimal(product["initial_unit_cost"] or 0))
        opening_value = opening_qty * unit_cost
        closing_value = closing_qty * unit_cost
        average_value = average_qty * unit_cost

        total_opening_qty += opening_qty
        total_closing_qty += closing_qty
        total_average_qty += average_qty
        total_opening_value += opening_value
        total_closing_value += closing_value
        total_average_value += average_value

        rows.append({
            "codigo": product["code"],
            "nombre_producto": product["description"],
            "grupo": product["group"],
            "cantidad_apertura": float(opening_qty),
            "cantidad_cierre": float(closing_qty),
            "cantidad_promedio": float(average_qty),
            "costo_unitario": float(unit_cost),
            "valor_apertura": float(opening_value),
            "valor_cierre": float(closing_value),
            "valor_promedio": float(average_value),
        })

    rows.sort(key=lambda item: item["valor_promedio"], reverse=True)
    if limit_value > 0:
        rows = rows[:limit_value]

    return {
        "date_from": period_start.isoformat(),
        "date_to": period_end.isoformat(),
        "days_count": days_count,
        "products": rows,
        "products_count": len(rows),
        "totals": {
            "opening_quantity": float(total_opening_qty),
            "closing_quantity": float(total_closing_qty),
            "average_quantity": float(total_average_qty),
            "opening_value": float(total_opening_value),
            "closing_value": float(total_closing_value),
            "average_value": float(total_average_value),
        },
    }


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
    cache_payload = {
        "inventory_name": inventory_name,
        "category_filter": category_filter,
        "warehouse_filter": warehouse_filter,
        "rotation_filter": rotation_filter,
        "stagnant_filter": stagnant_filter,
        "high_rotation_filter": high_rotation_filter,
        "date_from": date_from,
        "date_to": date_to,
        "search_filter": search_filter,
        "limit": str(limit or ""),
    }
    cache_key_src = json.dumps(cache_payload, sort_keys=True, ensure_ascii=False)
    cache_key = f"analysis:v1:{hashlib.sha256(cache_key_src.encode('utf-8')).hexdigest()}"
    cached_value = cache.get(cache_key)
    if cached_value is not None:
        return cached_value

    start_date = None
    if date_from:
        try:
            start_date = datetime.strptime(date_from, "%Y-%m-%d").date()
        except ValueError:
            start_date = None

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
            Q(warehousedetail__warehouse__icontains=warehouse_filter)
            | Q(inventoryrecord__warehouse__icontains=warehouse_filter)
        ).distinct()
    if search_filter:
        products_qs = products_qs.filter(_search_q(search_filter))
    if limit:
        try:
            products_qs = products_qs[: int(limit)]
        except ValueError:
            pass

    products_list = list(products_qs)
    if not products_list:
        cache.set(cache_key, [], timeout=300)
        return []

    product_ids = [p["id"] for p in products_list]

    # ── 2. Scope de movimientos para stock/costo/rotación ────────────────────
    # Importante: el calendario de evaluación (año de rotación) se determina
    # a nivel inventario para que no cambie al filtrar productos específicos.
    records_calendar_scope = InventoryRecord.objects.filter(
        product__inventory_name=inventory_name
    )
    if target_date:
        records_calendar_scope = records_calendar_scope.filter(date__lte=target_date)
    if warehouse_filter:
        records_calendar_scope = records_calendar_scope.filter(
            warehouse__icontains=warehouse_filter
        )

    records_scope = InventoryRecord.objects.filter(product_id__in=product_ids)
    if target_date:
        records_scope = records_scope.filter(date__lte=target_date)
    if warehouse_filter:
        records_scope = records_scope.filter(warehouse__icontains=warehouse_filter)

    movement_qty_by_warehouse: dict[tuple[int, str], Decimal] = {
        (row["product_id"], row["warehouse"]): row["total_qty"] or Decimal("0")
        for row in records_scope.values("product_id", "warehouse").annotate(
            total_qty=Sum("quantity")
        )
    }
    movement_qty_by_product: dict[int, Decimal] = {
        row["product_id"]: row["total_qty"] or Decimal("0")
        for row in records_scope.values("product_id").annotate(total_qty=Sum("quantity"))
    }

    wd_query = WarehouseDetail.objects.filter(product_id__in=product_ids)
    if warehouse_filter:
        wd_query = wd_query.filter(warehouse__icontains=warehouse_filter)

    initial_qty_by_warehouse: dict[tuple[int, str], Decimal] = {
        (row["product_id"], row["warehouse"]): Decimal(row["initial_quantity"] or 0)
        for row in wd_query.values("product_id", "warehouse", "initial_quantity")
    }
    initial_qty_by_product: dict[int, Decimal] = {
        row["product_id"]: row["total_qty"] or Decimal("0")
        for row in wd_query.values("product_id").annotate(total_qty=Sum("initial_quantity"))
    }

    latest_record_ids = [
        row["latest_id"]
        for row in records_scope.values("product_id").annotate(latest_id=Max("id"))
        if row["latest_id"]
    ]
    latest_cost_by_product: dict[int, Decimal] = {
        row["product_id"]: Decimal(row["unit_cost"] or 0)
        for row in InventoryRecord.objects.filter(id__in=latest_record_ids).values(
            "product_id", "unit_cost"
        )
    }
    latest_final_record_ids = [
        row["latest_id"]
        for row in records_scope.filter(final_quantity__isnull=False)
        .values("product_id", "warehouse")
        .annotate(latest_id=Max("id"))
        if row["latest_id"]
    ]
    latest_final_by_warehouse: dict[tuple[int, str], Decimal] = {
        (row["product_id"], row["warehouse"]): Decimal(row["final_quantity"] or 0)
        for row in InventoryRecord.objects.filter(id__in=latest_final_record_ids).values(
            "product_id", "warehouse", "final_quantity"
        )
    }

    #  3. Nombres de almacenes por producto (base + movimientos)
    warehouses_dict: dict[int, set] = {}
    for row in wd_query.values("product_id", "warehouse"):
        warehouses_dict.setdefault(row["product_id"], set()).add(row["warehouse"])
    for row in records_scope.values("product_id", "warehouse").distinct():
        warehouses_dict.setdefault(row["product_id"], set()).add(row["warehouse"])
    warehouses_str = {
        pid: ", ".join(sorted(ws)) if ws else "Todos"
        for pid, ws in warehouses_dict.items()
    }

    #  4. Movimientos acumulados antes del año de rotación (balance_pre_year)
    # Si no se filtra fecha explícita, usamos el último año con movimientos
    # para no evaluar contra un año futuro sin datos.
    latest_scope_date = None
    if target_date:
        rotation_year = target_date.year
    else:
        latest_scope_date = records_calendar_scope.aggregate(max_date=Max("date"))["max_date"]
        rotation_year = latest_scope_date.year if latest_scope_date else datetime.now().year

        if latest_scope_date:
            _ry_start = datetime(rotation_year, 1, 1).date()
            _ry_end = datetime(rotation_year, 12, 31).date()
            months_in_latest_year = (
                records_calendar_scope.filter(date__range=(_ry_start, _ry_end))
                .values("date__month")
                .distinct()
                .count()
            )
            if months_in_latest_year < 3:
                previous_year_last_date = (
                    records_calendar_scope.filter(date__lt=_ry_start)
                    .aggregate(max_date=Max("date"))["max_date"]
                )
                if previous_year_last_date:
                    rotation_year = previous_year_last_date.year

    if target_date and target_date.year == rotation_year:
        evaluation_end_date = target_date
    elif latest_scope_date and latest_scope_date.year == rotation_year:
        evaluation_end_date = latest_scope_date
    else:
        evaluation_end_date = datetime(rotation_year, 12, 31).date()

    # Punto de corte del año de rotación — usado en todos los filtros siguientes.
    rotation_year_start = datetime(rotation_year, 1, 1).date()

    pre_year_filter = Q(product_id__in=product_ids, date__lt=rotation_year_start)
    if warehouse_filter:
        pre_year_filter &= Q(warehouse__icontains=warehouse_filter)

    pre_year_dict: dict[int, Decimal] = {
        row["product_id"]: row["total"] or Decimal("0")
        for row in InventoryRecord.objects.filter(pre_year_filter)
        .values("product_id")
        .annotate(total=Sum("quantity"))
    }

    #  5. Movimientos del año de rotación (evaluación mensual optimizada)
    # Usamos date__range en lugar de date__year para que MySQL pueda usar el
    # índice B-tree sobre la columna `date` (YEAR() es non-sargable).
    monthly_filter = Q(
        product_id__in=product_ids,
        date__range=(rotation_year_start, evaluation_end_date),
    )
    if warehouse_filter:
        monthly_filter &= Q(warehouse__icontains=warehouse_filter)

    daily_movements_by_product: dict[int, dict] = {}
    for row in (
        InventoryRecord.objects.filter(monthly_filter)
        .values("product_id", "date")
        .annotate(daily_total=Sum("quantity"))
    ):
        pid = row["product_id"]
        daily_movements_by_product.setdefault(pid, {})[row["date"]] = row[
            "daily_total"
        ] or Decimal("0")

    qty_output = DecimalField(max_digits=28, decimal_places=6)
    movement_stats_filter = monthly_filter
    if start_date:
        movement_stats_filter = Q(product_id__in=product_ids)
        if warehouse_filter:
            movement_stats_filter &= Q(warehouse__icontains=warehouse_filter)
        movement_stats_filter &= Q(date__gte=start_date)
        if target_date:
            movement_stats_filter &= Q(date__lte=target_date)

    value_output = DecimalField(max_digits=28, decimal_places=6)
    movement_stats_by_product: dict[int, dict[str, Decimal | int]] = {
        row["product_id"]: {
            "entries_qty": row["entries_qty"] or Decimal("0"),
            "exits_qty": row["exits_qty"] or Decimal("0"),
            "entries_value": row["entries_value"] or Decimal("0"),
            "exits_value": row["exits_value"] or Decimal("0"),
            "movement_count": row["movement_count"] or 0,
        }
        for row in InventoryRecord.objects.filter(movement_stats_filter)
        .values("product_id")
        .annotate(
            entries_qty=Sum(
                Case(
                    When(quantity__gt=0, then=F("quantity")),
                    default=Value(Decimal("0"), output_field=qty_output),
                    output_field=qty_output,
                )
            ),
            exits_qty=Sum(
                Case(
                    When(quantity__lt=0, then=ExpressionWrapper(-1 * F("quantity"), output_field=qty_output)),
                    default=Value(Decimal("0"), output_field=qty_output),
                    output_field=qty_output,
                )
            ),
            entries_value=Sum(
                Case(
                    When(
                        quantity__gt=0,
                        then=ExpressionWrapper(F("quantity") * F("unit_cost"), output_field=value_output),
                    ),
                    default=Value(Decimal("0"), output_field=value_output),
                    output_field=value_output,
                )
            ),
            exits_value=Sum(
                Case(
                    When(
                        quantity__lt=0,
                        then=ExpressionWrapper(-1 * F("quantity") * F("unit_cost"), output_field=value_output),
                    ),
                    default=Value(Decimal("0"), output_field=value_output),
                    output_field=value_output,
                )
            ),
            movement_count=Count("id"),
        )
    }

    #  6. Construir resultado
    analysis_data = []
    for product in products_list:
        try:
            pid = product["id"]

            initial_base = initial_qty_by_product.get(pid)
            if initial_base is None:
                initial_base = Decimal(product["initial_balance"] or 0) if not warehouse_filter else Decimal("0")

            # Stock actual: prioriza SALDO FINAL reportado por Siesa por almacén.
            # Si no existe final_quantity para un almacén, usa inicial + movimientos.
            current_stock = Decimal("0")
            warehouses = warehouses_dict.get(pid, set())
            if warehouses:
                for warehouse in warehouses:
                    key = (pid, warehouse)
                    if key in latest_final_by_warehouse:
                        current_stock += latest_final_by_warehouse[key]
                    else:
                        current_stock += initial_qty_by_warehouse.get(key, Decimal("0"))
                        current_stock += movement_qty_by_warehouse.get(key, Decimal("0"))
            else:
                # Fallback para productos sin detalle de almacén.
                current_stock = initial_base + movement_qty_by_product.get(pid, Decimal("0"))

            current_unit_cost = latest_cost_by_product.get(
                pid, Decimal(product["initial_unit_cost"] or 0)
            )
            negative_stock_alert = current_stock < 0

            is_consumed = current_stock <= 0

            # Rotación
            pre_year_sum = pre_year_dict.get(pid, Decimal("0"))
            balance_pre_year = initial_base + pre_year_sum
            daily_movements = daily_movements_by_product.get(pid, {})

            # ── Loop de rotación optimizado: mes a mes en lugar de día a día ──
            # Agrupa los días con movimientos por mes para evitar iterar N=365
            # veces por producto. El costo es O(meses + días_con_movimiento).
            period_start = rotation_year_start
            period_end = evaluation_end_date

            _movements_by_month: dict[int, list] = {}
            for _day, _qty in daily_movements.items():
                if period_start <= _day <= period_end:
                    _movements_by_month.setdefault(_day.month, []).append((_day, _qty))
            for _ml in _movements_by_month.values():
                _ml.sort()

            monthly_balances = []
            monthly_changed = []
            month_numbers = []
            month_has_daily_changes: dict[int, bool] = {}
            running = balance_pre_year
            had_positive_stock = balance_pre_year > 0
            all_daily_zero = balance_pre_year == 0

            for _month_num in range(1, period_end.month + 1):
                _month_movements = _movements_by_month.get(_month_num, [])
                _has_change = False
                _prev_running = running
                for _, _qty in _month_movements:
                    running += _qty
                    if running != _prev_running:
                        _has_change = True
                    _prev_running = running
                    if running > 0:
                        had_positive_stock = True
                    if running != 0:
                        all_daily_zero = False
                month_has_daily_changes[_month_num] = _has_change
                previous_month_balance = monthly_balances[-1] if monthly_balances else balance_pre_year
                monthly_balances.append(running)
                monthly_changed.append(running != previous_month_balance)
                month_numbers.append(_month_num)

            if not monthly_balances:
                monthly_balances = [balance_pre_year]
                monthly_changed = [False]
                month_numbers = [period_start.month]

            unique_b = set(monthly_balances)

            movement_stats = movement_stats_by_product.get(pid, {})
            entries_qty = movement_stats.get("entries_qty", Decimal("0"))
            exits_qty = movement_stats.get("exits_qty", Decimal("0"))
            entries_value = movement_stats.get("entries_value", Decimal("0"))
            exits_value = movement_stats.get("exits_value", Decimal("0"))
            movement_count = movement_stats.get("movement_count", 0)

            has_movements = bool(movement_count)
            has_variations = any(month_has_daily_changes.values())
            all_same_year = len(unique_b) == 1 and not has_variations
            all_zero_year = all_daily_zero
            month_change_flags = [
                month_has_daily_changes.get(month, False) for month in month_numbers
            ]
            last_three_months = month_numbers[-3:]
            last_three_same = (
                len(monthly_balances) >= 3
                and len(set(monthly_balances[-3:])) == 1
                and all(not month_has_daily_changes.get(month, False) for month in last_three_months)
            )

            zero_stock_reason = ""
            zero_type = "sin_cero"
            zero_by_depletion = False
            zero_by_inactivity = False
            year_end_balance = monthly_balances[-1] if monthly_balances else Decimal("0")

            if current_stock <= 0 or all_zero_year:
                if all_zero_year:
                    zero_stock_reason = "Inactivo en cero (todo el año en 0)"
                    zero_type = "obsoleto_cero"
                elif Decimal(exits_qty) > 0 and had_positive_stock:
                    zero_stock_reason = "Agotamiento"
                    zero_type = "agotamiento"
                    zero_by_depletion = True
                elif not has_movements and balance_pre_year <= 0:
                    zero_stock_reason = "Sin movimientos (sin entradas/salidas)"
                    zero_type = "inactividad"
                    zero_by_inactivity = True
                else:
                    zero_stock_reason = "Cero con movimiento no concluyente"
                    zero_type = "no_concluyente"

            # Columna Estancado (Sí/No)
            # Sí: saldo final igual en todos los meses del año y diferente de cero.
            # No: si hay variaciones o saldo de cierre en cero.
            is_stagnant = all_same_year and year_end_balance != 0

            # Columna Rotación
            # - Inactivo: stock actual <= 0 (sin existencias reales).
            # - Obsoleto: mismo saldo todo el año y no cero, O balance simulado
            #             siempre en cero pero stock real positivo (discrepancia
            #             simulación vs. Siesa: producto sin actividad registrada).
            # - Estancado: mismo saldo en últimos 3 meses y no cero.
            # - Activo: variaciones durante el año.
            rotation_rule = ""
            if current_stock <= 0:
                rotation = "Inactivo"
                rotation_rule = "stock_real_en_cero_o_negativo"
            elif all_zero_year:
                # Stock real > 0 pero la simulación de saldo del año estuvo
                # siempre en cero: sin actividad registrada → Obsoleto.
                rotation = "Obsoleto"
                rotation_rule = "saldo_simulado_cero_stock_real_positivo"
            elif all_same_year and year_end_balance != 0:
                rotation = "Obsoleto"
                rotation_rule = "saldo_constante_todo_el_anio_no_cero"
            elif last_three_same and year_end_balance != 0:
                rotation = "Estancado"
                rotation_rule = "ultimos_tres_meses_constantes_no_cero"
            elif has_variations:
                rotation = "Activo"
                rotation_rule = "variaciones_detectadas"
            else:
                rotation = "Activo"
                rotation_rule = "fallback_activo"

            # Alta rotación:
            # "Sí" si hubo cambios en al menos 2 meses consecutivos
            # en actividad mensual real (detectada día a día).
            has_two_consecutive_changes = any(
                month_change_flags[i] and month_change_flags[i + 1]
                for i in range(len(month_change_flags) - 1)
            )
            high_rotation = "Sí" if has_two_consecutive_changes else "No"

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
                    "regla_rotacion_aplicada": rotation_rule,
                    "causa_stock_cero": zero_stock_reason,
                    "tipo_cero": zero_type,
                    "cero_por_agotamiento": "Sí" if zero_by_depletion else "No",
                    "cero_por_inactividad": "Sí" if zero_by_inactivity else "No",
                    "entradas_periodo": float(entries_qty),
                    "salidas_periodo": float(exits_qty),
                    "valor_entradas_periodo": float(entries_value),
                    "valor_salidas_periodo": float(exits_value),
                    "alta_rotacion": high_rotation,
                    "almacen": warehouses_str.get(pid, "Todos"),
                    "negative_stock_alert": negative_stock_alert,
                    "has_negative_stock_alert": negative_stock_alert,
                }
            )
        except Exception as exc:
            logger.error(
                "Error processing product %s: %s", product.get("code"), exc, exc_info=True
            )
            continue

    cache.set(cache_key, analysis_data, timeout=300)
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
            Q(warehousedetail__warehouse__icontains=warehouse_filter)
            | Q(inventoryrecord__warehouse__icontains=warehouse_filter)
        ).distinct()

    product_ids = list(products_query.values_list("id", flat=True))
    if not product_ids:
        return {
            "date": date_str,
            "total_quantity": 0.0,
            "total_value": 0.0,
            "products": [],
        }

    warehouse_query = WarehouseDetail.objects.filter(product_id__in=product_ids)
    if warehouse_filter:
        warehouse_query = warehouse_query.filter(warehouse__icontains=warehouse_filter)
    initial_qty_by_warehouse: dict[tuple[int, str], Decimal] = {
        (row["product_id"], row["warehouse"]): Decimal(row["initial_quantity"] or 0)
        for row in warehouse_query.values("product_id", "warehouse", "initial_quantity")
    }
    initial_qty_map = {
        row["product_id"]: row["qty"] or Decimal("0")
        for row in warehouse_query.values("product_id").annotate(qty=Sum("initial_quantity"))
    }

    movements_query = InventoryRecord.objects.filter(
        product_id__in=product_ids,
        date__lte=target_date,
    )
    if warehouse_filter:
        movements_query = movements_query.filter(warehouse__icontains=warehouse_filter)
    movement_qty_by_warehouse: dict[tuple[int, str], Decimal] = {
        (row["product_id"], row["warehouse"]): row["qty"] or Decimal("0")
        for row in movements_query.values("product_id", "warehouse").annotate(qty=Sum("quantity"))
    }
    movement_qty_map = {
        row["product_id"]: row["qty"] or Decimal("0")
        for row in movements_query.values("product_id").annotate(qty=Sum("quantity"))
    }

    latest_final_record_ids = [
        row["latest_id"]
        for row in movements_query.filter(final_quantity__isnull=False)
        .values("product_id", "warehouse")
        .annotate(latest_id=Max("id"))
        if row["latest_id"]
    ]
    latest_final_by_warehouse: dict[tuple[int, str], Decimal] = {
        (row["product_id"], row["warehouse"]): Decimal(row["final_quantity"] or 0)
        for row in InventoryRecord.objects.filter(id__in=latest_final_record_ids).values(
            "product_id", "warehouse", "final_quantity"
        )
    }

    latest_record_ids = [
        row["latest_id"]
        for row in movements_query.values("product_id").annotate(latest_id=Max("id"))
        if row["latest_id"]
    ]
    latest_cost_dict = {
        row["product_id"]: Decimal(row["unit_cost"] or 0)
        for row in InventoryRecord.objects.filter(id__in=latest_record_ids).values(
            "product_id", "unit_cost"
        )
    }

    total_quantity = Decimal("0")
    total_value = Decimal("0")
    products_data = []
    warehouse_names_by_product: dict[int, set[str]] = {}
    for row in warehouse_query.values("product_id", "warehouse"):
        warehouse_names_by_product.setdefault(row["product_id"], set()).add(row["warehouse"])
    for row in movements_query.values("product_id", "warehouse").distinct():
        warehouse_names_by_product.setdefault(row["product_id"], set()).add(row["warehouse"])

    for product in products_query:
        product_warehouses = warehouse_names_by_product.get(product.id, set())
        if product_warehouses:
            product_quantity = Decimal("0")
            for warehouse in product_warehouses:
                key = (product.id, warehouse)
                if key in latest_final_by_warehouse:
                    product_quantity += latest_final_by_warehouse[key]
                else:
                    product_quantity += initial_qty_by_warehouse.get(key, Decimal("0"))
                    product_quantity += movement_qty_by_warehouse.get(key, Decimal("0"))
        else:
            initial_quantity = initial_qty_map.get(product.id)
            if initial_quantity is None:
                initial_quantity = Decimal(product.initial_balance or 0) if not warehouse_filter else Decimal("0")
            product_quantity = initial_quantity + movement_qty_map.get(product.id, Decimal("0"))

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
