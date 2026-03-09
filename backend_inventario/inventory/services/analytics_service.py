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
import os
import re
from datetime import date, datetime
from decimal import Decimal, ROUND_HALF_UP

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
from .cache_version_service import get_inventory_cache_version

logger = logging.getLogger(__name__)


_MONEY_QUANT = Decimal("0.01")
_QTY_QUANT = Decimal("0.001")
HISTORIC_CACHE_TTL_SECONDS = int(
    os.environ.get("INVENTORY_HISTORIC_CACHE_TTL_SECONDS", "604800")
)

# Versión interna de la lógica de cálculo.
# Incrementar cuando cambie el algoritmo (ej: nueva fórmula de costo por mes)
# para invalidar automáticamente el caché en disco sin borrar archivos.
# Historial:
#   cv1 → costo global al final del período (incorrecto para meses históricos)
#   cv2 → costo al cierre de cada mes específico (correcto, alineado con tabla)
_ANALYTICS_CALC_VERSION = "cv2"


def _to_decimal(value, default="0"):
    if value is None:
        return Decimal(default)
    if isinstance(value, Decimal):
        return value
    try:
        return Decimal(str(value))
    except Exception:
        return Decimal(default)


def _money_float(value) -> float:
    return float(_to_decimal(value).quantize(_MONEY_QUANT, rounding=ROUND_HALF_UP))


def _qty_float(value) -> float:
    return float(_to_decimal(value).quantize(_QTY_QUANT, rounding=ROUND_HALF_UP))


def _parse_iso_date(value):
    if not value:
        return None
    try:
        return datetime.strptime(str(value), "%Y-%m-%d").date()
    except Exception:
        return None


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


def _sum_running_qty_from_event_days(
    *,
    period_start: date,
    days_count: int,
    opening_qty: Decimal,
    movement_by_day: dict[date, Decimal],
    final_by_day: dict[date, Decimal],
    event_days: list[date],
) -> tuple[Decimal, Decimal]:
    """
    Calcula (closing_qty, sum_daily_qty) iterando solo días con eventos.

    Mantiene exactitud del promedio diario con gap-filling:
    para días sin movimiento/final_quantity, el stock se asume constante.
    """
    if days_count <= 0:
        return opening_qty, opening_qty

    if not event_days:
        return opening_qty, opening_qty * Decimal(days_count)

    running_qty = opening_qty
    sum_daily_qty = Decimal("0")
    prev_idx = -1

    for event_day in event_days:
        day_idx = (event_day - period_start).days
        if day_idx < 0 or day_idx >= days_count:
            continue

        gap = day_idx - (prev_idx + 1)
        if gap > 0:
            sum_daily_qty += running_qty * gap

        day_final_qty = final_by_day.get(event_day)
        if day_final_qty is not None:
            running_qty = day_final_qty
        else:
            running_qty += movement_by_day.get(event_day, Decimal("0"))
        sum_daily_qty += running_qty
        prev_idx = day_idx

    remaining = days_count - 1 - prev_idx
    if remaining > 0:
        sum_daily_qty += running_qty * remaining

    return running_qty, sum_daily_qty


def _get_monthly_value_series(
    inventory_name="Por defecto",
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
        base_queryset = base_queryset.filter(warehouse__iexact=warehouse_filter)
    if category_filter:
        base_queryset = base_queryset.filter(category__iexact=category_filter)
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
            warehouse__iexact=warehouse_filter,
        )
        if category_filter:
            initial_stock_query = initial_stock_query.filter(
                product__group__iexact=category_filter
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
                group__iexact=category_filter
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
    inventory_name="Por defecto",
    warehouse_filter="",
    category_filter="",
    search_filter="",
    date_from="",
    date_to="",
    months=12,
):
    """
    Calcula entradas, salidas y saldo mensual para una ventana de 12 meses.

    Importante:
    Para evitar diferencias entre el "Saldo" de Movimientos y el
    "Valor Cierre" de Cortes Mensuales, ambos se derivan de la misma
    metodología de valuación (get_monthly_qty_value_series).
    """
    date_from_value = _parse_iso_date(date_from)
    date_to_value = _parse_iso_date(date_to)
    if date_from_value and date_to_value and date_from_value > date_to_value:
        date_from_value, date_to_value = date_to_value, date_from_value

    try:
        requested_months = int(months or 12)
    except (TypeError, ValueError):
        requested_months = 12
    requested_months = max(1, min(requested_months, 36))

    # Si se filtra por rango de fechas, ampliamos la ventana para cubrirlo.
    # Luego se recorta por mes para devolver exactamente el rango solicitado.
    window_months = requested_months
    if date_from_value and date_to_value:
        range_months = (
            (date_to_value.year - date_from_value.year) * 12
            + (date_to_value.month - date_from_value.month)
            + 1
        )
        window_months = max(1, min(max(requested_months, range_months), 36))

    (
        _start_month_date,
        _months_count,
        rows,
        _period_avg_general,
        _products_count,
    ) = _get_monthly_qty_value_series(
        inventory_name=inventory_name,
        warehouse_filter=warehouse_filter,
        category_filter=category_filter,
        search_filter=search_filter,
        months=window_months,
    )

    from_month = (
        date_from_value.replace(day=1)
        if date_from_value
        else None
    )
    to_month = (
        date_to_value.replace(day=1)
        if date_to_value
        else None
    )

    filtered_rows = []
    for row in rows:
        month_text = row.get("month")
        if not month_text:
            continue
        try:
            month_date = datetime.strptime(f"{month_text}-01", "%Y-%m-%d").date()
        except Exception:
            continue
        if from_month and month_date < from_month:
            continue
        if to_month and month_date > to_month:
            continue
        filtered_rows.append(row)

    return [
        {
            "month": row.get("month"),
            "total_entries": _money_float(row.get("total_entries", 0)),
            "total_exits": _money_float(row.get("total_exits", 0)),
            "closing_balance": _money_float(row.get("closing_balance", 0)),
        }
        for row in filtered_rows
    ]


def _get_monthly_qty_value_series(
    inventory_name="Por defecto ",
    warehouse_filter="",
    category_filter="",
    search_filter="",
    months=12,
):
    """
    Construye la serie de cortes mensuales usando EXACTAMENTE la misma
    metodología que get_monthly_product_cuts_data (tabla de inventario):

    - Itera día a día, POR ALMACÉN dentro de cada producto.
    - Usa WarehouseDetail.initial_quantity como stock base por almacén.
    - Aplica snapshots de final_quantity por (producto, almacén, día).
    - El promedio mensual = Σ(valor total inventario en cada día) / días_del_mes.

    Así el campo average_balance_general coincide exactamente con el
    "Valor total promedio" del chip de la tabla de inventario.

    Retorna: (start_month_date, months_count, rows, period_avg_general, products_count)
    """
    try:
        months_count = int(months or 12)
    except (TypeError, ValueError):
        months_count = 12
    months_count = max(1, min(months_count, 36))

    today = now().date()
    start_month_date = (today - relativedelta(months=months_count - 1)).replace(day=1)
    last_month_start = start_month_date + relativedelta(months=months_count - 1)
    period_end = (last_month_start + relativedelta(months=1)) - relativedelta(days=1)

    # ── Productos ────────────────────────────────────────────────────────────
    products_qs = Product.objects.filter(inventory_name=inventory_name)
    if category_filter:
        products_qs = products_qs.filter(group__iexact=category_filter)
    if search_filter:
        products_qs = products_qs.filter(_search_q(search_filter))

    products_meta = list(
        products_qs.values("id", "initial_balance", "initial_unit_cost")
    )
    product_ids = [p["id"] for p in products_meta]
    products_map = {p["id"]: p for p in products_meta}

    if not product_ids:
        return start_month_date, months_count, [], Decimal("0"), 0

    records_qs = InventoryRecord.objects.filter(product_id__in=product_ids)
    if warehouse_filter:
        records_qs = records_qs.filter(warehouse__iexact=warehouse_filter)

    warehouse_query = WarehouseDetail.objects.filter(product_id__in=product_ids)
    if warehouse_filter:
        warehouse_query = warehouse_query.filter(warehouse__iexact=warehouse_filter)

    # ── Último costo unitario por producto (calculado como abs(total) ÷ abs(cantidad)) ──
    latest_cost_ids = [
        row["latest_id"]
        for row in records_qs.filter(date__lte=period_end)
        .values("product_id")
        .annotate(latest_id=Max("id"))
        if row["latest_id"]
    ]
    latest_cost_by_product: dict[int, Decimal] = {}
    for _row in InventoryRecord.objects.filter(id__in=latest_cost_ids).values(
        "product_id", "unit_cost", "quantity", "total"
    ):
        _qty = Decimal(_row["quantity"] or 0)
        _total = Decimal(_row["total"] or 0)
        latest_cost_by_product[_row["product_id"]] = (
            abs(_total) / abs(_qty) if _qty != 0 else Decimal(_row["unit_cost"] or 0)
        )

    def get_cost(pid: int) -> Decimal:
        return latest_cost_by_product.get(
            pid, Decimal(products_map[pid]["initial_unit_cost"] or 0)
        )

    # ── Historial de costos por (producto, mes-calendario) ────────────────────
    # Permite usar el costo al cierre de cada mes específico en lugar del
    # costo global al final del período, garantizando que average_balance_general
    # de la gráfica coincida con average_value de la tabla de inventario
    # promediado (ambos usan el mismo criterio: último costo hasta fin de mes).
    _monthly_cost_ids_by_pid: dict[int, dict] = {}
    for _crow in (
        records_qs.filter(date__lte=period_end)
        .annotate(rec_month=TruncMonth("date"))
        .values("product_id", "rec_month")
        .annotate(latest_id=Max("id"))
    ):
        _pid_r = _crow["product_id"]
        _rec_month = _crow["rec_month"]
        if hasattr(_rec_month, "date"):  # datetime → date
            _rec_month = _rec_month.date()
        _monthly_cost_ids_by_pid.setdefault(_pid_r, {})[_rec_month] = _crow["latest_id"]

    _all_monthly_cost_record_ids = [
        _rid
        for _pid_months in _monthly_cost_ids_by_pid.values()
        for _rid in _pid_months.values()
    ]
    _monthly_cost_detail: dict[int, dict] = {
        _rec["id"]: _rec
        for _rec in InventoryRecord.objects.filter(
            id__in=_all_monthly_cost_record_ids
        ).values("id", "unit_cost", "quantity", "total")
    }

    def get_cost_at_month_end(pid: int, month_end: date) -> Decimal:
        """
        Costo unitario de `pid` vigente al cierre del mes que termina en `month_end`.
        Espeja la lógica de get_monthly_product_cuts_data: max(id) con date <= month_end,
        calculado como abs(total) ÷ abs(quantity).
        Fallback: initial_unit_cost del producto.
        """
        _pid_months = _monthly_cost_ids_by_pid.get(pid)
        if _pid_months:
            _month_start = month_end.replace(day=1)
            _eligible = sorted(
                (_m for _m in _pid_months if _m <= _month_start), reverse=True
            )
            if _eligible:
                _record_id = _pid_months[_eligible[0]]
                _rec = _monthly_cost_detail.get(_record_id)
                if _rec:
                    _qty = Decimal(_rec["quantity"] or 0)
                    _total = Decimal(_rec["total"] or 0)
                    return abs(_total) / abs(_qty) if _qty != 0 else Decimal(_rec["unit_cost"] or 0)
        return Decimal(products_map[pid]["initial_unit_cost"] or 0)

    # ── Almacenes por producto (WarehouseDetail + registros) ─────────────────
    warehouses_by_product: dict[int, set] = {}
    for row in warehouse_query.values("product_id", "warehouse"):
        warehouses_by_product.setdefault(row["product_id"], set()).add(row["warehouse"])
    for row in records_qs.values("product_id", "warehouse").distinct():
        warehouses_by_product.setdefault(row["product_id"], set()).add(row["warehouse"])

    # ── Cantidades iniciales por (producto, almacén) en WarehouseDetail ──────
    initial_qty_by_warehouse: dict[tuple, Decimal] = {
        (row["product_id"], row["warehouse"]): Decimal(row["initial_quantity"] or 0)
        for row in warehouse_query.values("product_id", "warehouse", "initial_quantity")
    }

    # ── Movimientos antes del período ────────────────────────────────────────
    # Por (producto, almacén) — para apertura warehouse-level
    movement_before_start_by_wh: dict[tuple, Decimal] = {
        (row["product_id"], row["warehouse"]): row["qty"] or Decimal("0")
        for row in records_qs.filter(date__lt=start_month_date)
        .values("product_id", "warehouse")
        .annotate(qty=Sum("quantity"))
    }
    # Por producto — para productos sin WarehouseDetail
    movement_before_start_by_product: dict[int, Decimal] = {
        row["product_id"]: row["qty"] or Decimal("0")
        for row in records_qs.filter(date__lt=start_month_date)
        .values("product_id")
        .annotate(qty=Sum("quantity"))
    }

    # ── opening final_quantity por (producto, almacén) antes del período ─────
    opening_final_ids_wh = [
        row["latest_id"]
        for row in records_qs.filter(
            final_quantity__isnull=False, date__lt=start_month_date
        )
        .values("product_id", "warehouse")
        .annotate(latest_id=Max("id"))
        if row["latest_id"]
    ]
    opening_final_by_wh: dict[tuple, Decimal] = {
        (row["product_id"], row["warehouse"]): Decimal(row["final_quantity"] or 0)
        for row in InventoryRecord.objects.filter(id__in=opening_final_ids_wh).values(
            "product_id", "warehouse", "final_quantity"
        )
    }
    # Para productos sin almacén
    opening_final_ids_prod = [
        row["latest_id"]
        for row in records_qs.filter(
            final_quantity__isnull=False, date__lt=start_month_date
        )
        .values("product_id")
        .annotate(latest_id=Max("id"))
        if row["latest_id"]
    ]
    opening_final_by_product: dict[int, Decimal] = {
        row["product_id"]: Decimal(row["final_quantity"] or 0)
        for row in InventoryRecord.objects.filter(id__in=opening_final_ids_prod).values(
            "product_id", "final_quantity"
        )
    }

    # ── Movimientos diarios por (producto, almacén, fecha) ───────────────────
    _vf = DecimalField(max_digits=28, decimal_places=6)
    _zero = Value(Decimal("0"), output_field=_vf)

    movement_by_day_by_wh: dict[tuple, Decimal] = {
        (row["product_id"], row["warehouse"], row["date"]): row["qty"] or Decimal("0")
        for row in records_qs.filter(date__gte=start_month_date, date__lte=period_end)
        .values("product_id", "warehouse", "date")
        .annotate(qty=Sum("quantity"))
    }
    # Para productos sin almacén
    movement_by_day_by_product: dict[tuple, Decimal] = {
        (row["product_id"], row["date"]): row["qty"] or Decimal("0")
        for row in records_qs.filter(date__gte=start_month_date, date__lte=period_end)
        .values("product_id", "date")
        .annotate(qty=Sum("quantity"))
    }

    # Entradas/salidas diarias por (producto, almacén) para valor de movimientos
    daily_pos_wh: dict[tuple, Decimal] = {}
    daily_neg_wh: dict[tuple, Decimal] = {}
    for row in (
        records_qs.filter(date__gte=start_month_date, date__lte=period_end)
        .values("product_id", "warehouse", "date")
        .annotate(
            pos_qty=Sum(
                Case(When(quantity__gt=0, then=F("quantity")), default=_zero, output_field=_vf)
            ),
            neg_qty=Sum(
                Case(When(quantity__lt=0, then=F("quantity")), default=_zero, output_field=_vf)
            ),
        )
    ):
        k = (row["product_id"], row["warehouse"], row["date"])
        daily_pos_wh[k] = row["pos_qty"] or Decimal("0")
        daily_neg_wh[k] = abs(row["neg_qty"] or Decimal("0"))

    # ── Snapshots final_quantity diarios por (producto, almacén, fecha) ──────
    daily_final_ids_wh = [
        row["latest_id"]
        for row in records_qs.filter(
            final_quantity__isnull=False,
            date__gte=start_month_date,
            date__lte=period_end,
        )
        .values("product_id", "warehouse", "date")
        .annotate(latest_id=Max("id"))
        if row["latest_id"]
    ]
    daily_final_by_wh: dict[tuple, Decimal] = {
        (row["product_id"], row["warehouse"], row["date"]): Decimal(row["final_quantity"] or 0)
        for row in InventoryRecord.objects.filter(id__in=daily_final_ids_wh).values(
            "product_id", "warehouse", "date", "final_quantity"
        )
    }
    # Para productos sin almacén
    daily_final_ids_prod = [
        row["latest_id"]
        for row in records_qs.filter(
            final_quantity__isnull=False,
            date__gte=start_month_date,
            date__lte=period_end,
        )
        .values("product_id", "date")
        .annotate(latest_id=Max("id"))
        if row["latest_id"]
    ]
    daily_final_by_product: dict[tuple, Decimal] = {
        (row["product_id"], row["date"]): Decimal(row["final_quantity"] or 0)
        for row in InventoryRecord.objects.filter(id__in=daily_final_ids_prod).values(
            "product_id", "date", "final_quantity"
        )
    }

    # ── Estado inicial de running_qty: (producto, almacén) → qty ─────────────
    # Para productos con almacenes usa apertura por almacén.
    # Para productos sin almacenes usa apertura a nivel producto.
    running_wh: dict[tuple, Decimal] = {}   # clave (pid, wh)
    running_prod: dict[int, Decimal] = {}   # clave pid (sin almacén)

    for pid in product_ids:
        whs = warehouses_by_product.get(pid, set())
        if whs:
            for wh in whs:
                key = (pid, wh)
                snap = opening_final_by_wh.get(key)
                if snap is not None:
                    running_wh[key] = snap
                else:
                    running_wh[key] = (
                        initial_qty_by_warehouse.get(key, Decimal("0"))
                        + movement_before_start_by_wh.get(key, Decimal("0"))
                    )
        else:
            snap = opening_final_by_product.get(pid)
            if snap is not None:
                running_prod[pid] = snap
            else:
                running_prod[pid] = (
                    Decimal(products_map[pid]["initial_balance"] or 0)
                    + movement_before_start_by_product.get(pid, Decimal("0"))
                )

    # ── Construir filas mensuales con promedio diario real ────────────────────
    # El valor monetario se recomputa al inicio de cada mes con el costo de
    # ESE mes (get_cost_at_month_end), así opening_balance, closing_balance y
    # average_balance_general coinciden con la tabla de inventario promediado.

    # Pre-calcular entradas y salidas valorizadas por mes (YYYY-MM)
    # Usa el costo al cierre de cada mes para coherencia con la tabla.
    _entries_by_month: dict = {}
    for (pid, wh, day), pos_qty in daily_pos_wh.items():
        mk = day.strftime("%Y-%m")
        _dme = (day.replace(day=1) + relativedelta(months=1)) - relativedelta(days=1)
        _entries_by_month[mk] = _entries_by_month.get(mk, Decimal("0")) + pos_qty * get_cost_at_month_end(pid, _dme)
    _exits_by_month: dict = {}
    for (pid, wh, day), neg_qty in daily_neg_wh.items():
        mk = day.strftime("%Y-%m")
        _dme = (day.replace(day=1) + relativedelta(months=1)) - relativedelta(days=1)
        _exits_by_month[mk] = _exits_by_month.get(mk, Decimal("0")) + neg_qty * get_cost_at_month_end(pid, _dme)

    # Índice de días con eventos: day → list of (event_type, pid, wh_or_None)
    # final_quantity tiene precedencia sobre movimiento neto para el mismo (pid, wh, day).
    _event_days_in_period: dict = {}
    for (pid, wh, day_e) in daily_final_by_wh:
        _event_days_in_period.setdefault(day_e, []).append(('final_wh', pid, wh))
    for (pid, wh, day_e) in movement_by_day_by_wh:
        if (pid, wh, day_e) not in daily_final_by_wh:
            _event_days_in_period.setdefault(day_e, []).append(('move_wh', pid, wh))
    # SOLO productos SIN almacén: los que sí tienen almacén ya se cubren con
    # final_wh / move_wh; incluirlos aquí provocaría doble conteo en total_value.
    for (pid, day_e) in daily_final_by_product:
        if pid not in warehouses_by_product:
            _event_days_in_period.setdefault(day_e, []).append(('final_prod', pid, None))
    for (pid, day_e) in movement_by_day_by_product:
        if pid not in warehouses_by_product and (pid, day_e) not in daily_final_by_product:
            _event_days_in_period.setdefault(day_e, []).append(('move_prod', pid, None))

    # Pre-agrupar días con eventos por mes para O(1) lookup en el loop
    _event_days_by_month: dict = {}
    for day_e in sorted(_event_days_in_period.keys()):
        mk = day_e.strftime("%Y-%m")
        _event_days_by_month.setdefault(mk, []).append(day_e)

    rows = []
    average_sum = Decimal("0")
    products_count = len(product_ids)

    for i in range(months_count):
        current_month_date = start_month_date + relativedelta(months=i)
        month_key = current_month_date.strftime("%Y-%m")
        month_end_date = (current_month_date + relativedelta(months=1)) - relativedelta(days=1)
        days_count = (month_end_date - current_month_date).days + 1

        # ── Valor del portafolio con el costo de ESTE mes ─────────────────────
        # Recomputa desde las cantidades corrientes para que opening_balance,
        # closing_balance y average_balance_general usen el mismo costo que
        # la tabla de inventario (costo al cierre de cada mes consultado).
        month_costs = {_p: get_cost_at_month_end(_p, month_end_date) for _p in product_ids}
        total_value = Decimal("0")
        for _p in product_ids:
            _mc = month_costs[_p]
            _whs = warehouses_by_product.get(_p, set())
            if _whs:
                for _wh in _whs:
                    total_value += running_wh.get((_p, _wh), Decimal("0")) * _mc
            else:
                total_value += running_prod.get(_p, Decimal("0")) * _mc

        opening_val = total_value
        entries_val = _entries_by_month.get(month_key, Decimal("0"))
        exits_val = _exits_by_month.get(month_key, Decimal("0"))

        # Solo procesar días con eventos; gap-filling para días sin cambios
        month_event_days = _event_days_by_month.get(month_key, [])

        sum_daily_val = Decimal("0")
        prev_idx = -1  # índice (0-based) del día anterior al primer procesado

        for event_day in month_event_days:
            day_idx = (event_day - current_month_date).days  # 0-based

            # Días sin eventos entre el último procesado y este (valor constante)
            gap = day_idx - (prev_idx + 1)
            if gap > 0:
                sum_daily_val += total_value * gap

            # Aplicar eventos del día y actualizar total_value incrementalmente
            for event_type, pid, wh in _event_days_in_period[event_day]:
                cost = month_costs[pid]
                if event_type == 'final_wh':
                    old_qty = running_wh.get((pid, wh), Decimal("0"))
                    new_qty = daily_final_by_wh[(pid, wh, event_day)]
                    running_wh[(pid, wh)] = new_qty
                    total_value += (new_qty - old_qty) * cost
                elif event_type == 'move_wh':
                    delta = movement_by_day_by_wh.get((pid, wh, event_day), Decimal("0"))
                    running_wh[(pid, wh)] = running_wh.get((pid, wh), Decimal("0")) + delta
                    total_value += delta * cost
                elif event_type == 'final_prod':
                    old_qty = running_prod.get(pid, Decimal("0"))
                    new_qty = daily_final_by_product[(pid, event_day)]
                    running_prod[pid] = new_qty
                    total_value += (new_qty - old_qty) * cost
                elif event_type == 'move_prod':
                    delta = movement_by_day_by_product.get((pid, event_day), Decimal("0"))
                    running_prod[pid] = running_prod.get(pid, Decimal("0")) + delta
                    total_value += delta * cost

            # Valor al cierre del día (ya actualizado con los eventos)
            sum_daily_val += total_value
            prev_idx = day_idx

        # Días finales del mes sin eventos (valor constante)
        remaining = days_count - 1 - prev_idx
        if remaining > 0:
            sum_daily_val += total_value * remaining

        closing_val = total_value
        average_val = sum_daily_val / Decimal(days_count) if days_count > 0 else closing_val
        average_sum += average_val

        avg_per_product = (
            average_val / Decimal(products_count) if products_count > 0 else Decimal("0")
        )

        rows.append(
            {
                "month": month_key,
                "opening_balance": _money_float(opening_val),
                "total_entries": _money_float(entries_val),
                "total_exits": _money_float(exits_val),
                "closing_balance": _money_float(closing_val),
                "average_balance": _money_float(average_val),
                "average_balance_general": _money_float(average_val),
                "average_balance_per_product": _money_float(avg_per_product),
                "products_count": products_count,
            }
        )

    period_avg_general = (
        average_sum / Decimal(months_count) if months_count > 0 else Decimal("0")
    )
    return start_month_date, months_count, rows, period_avg_general, products_count


def get_monthly_cuts_data(
    inventory_name="Por defecto",
    warehouse_filter="",
    category_filter="",
    search_filter="",
    months=12,
):
    """
    Calcula cortes mensuales valorados usando cantidad × costo_unitario_actual
    por producto, con la misma metodología que la tabla de inventario
    (get_monthly_product_cuts_data), garantizando que gráfica y tabla muestren
    cifras coherentes aunque hayan cambiado los costos unitarios.
    """
    data_version = get_inventory_cache_version(inventory_name)
    _svc_cache_key = (
        f"svc:monthly_cuts:{inventory_name}|v={data_version}|{_ANALYTICS_CALC_VERSION}"
        f"|{warehouse_filter}|{category_filter}|{search_filter}|{months}"
    )
    _cached = cache.get(_svc_cache_key)
    if _cached is not None:
        return _cached

    (
        _start,
        months_count,
        rows,
        period_avg_general,
        products_count,
    ) = _get_monthly_qty_value_series(
        inventory_name=inventory_name,
        warehouse_filter=warehouse_filter,
        category_filter=category_filter,
        search_filter=search_filter,
        months=months,
    )

    period_average_per_product = (
        period_avg_general / Decimal(products_count)
        if products_count > 0
        else Decimal("0")
    )

    result = {
        "months": rows,
        "period_average_cut": _money_float(period_average_per_product),
        "period_average_general": _money_float(period_avg_general),
        "period_average_per_product": _money_float(period_average_per_product),
        "products_count": products_count,
        "months_count": months_count,
    }
    cache.set(_svc_cache_key, result, HISTORIC_CACHE_TTL_SECONDS)
    return result


def get_monthly_product_cuts_data(
    inventory_name="Por defecto",
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
    data_version = get_inventory_cache_version(inventory_name)
    _svc_cache_key = (
        f"svc:monthly_prod_cuts:{inventory_name}|v={data_version}|{_ANALYTICS_CALC_VERSION}"
        f"|{target_month}|{warehouse_filter}|{category_filter}|{search_filter}"
        f"|{limit}|{offset}|{page_size}"
    )
    _cached = cache.get(_svc_cache_key)
    if _cached is not None:
        return _cached

    records_base = InventoryRecord.objects.filter(product__inventory_name=inventory_name)
    if warehouse_filter:
        records_base = records_base.filter(warehouse__iexact=warehouse_filter)
    if category_filter:
        records_base = records_base.filter(category__iexact=category_filter)
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
    days_count = (month_end - month_start).days + 1

    products_qs = Product.objects.filter(inventory_name=inventory_name)
    if category_filter:
        products_qs = products_qs.filter(group__iexact=category_filter)
    if warehouse_filter:
        products_qs = products_qs.filter(
            Q(warehousedetail__warehouse__iexact=warehouse_filter)
            | Q(inventoryrecord__warehouse__iexact=warehouse_filter)
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
        result = {
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
        cache.set(_svc_cache_key, result, HISTORIC_CACHE_TTL_SECONDS)
        return result

    records_scope = InventoryRecord.objects.filter(product_id__in=product_ids)
    if warehouse_filter:
        records_scope = records_scope.filter(warehouse__iexact=warehouse_filter)

    warehouse_query = WarehouseDetail.objects.filter(product_id__in=product_ids)
    if warehouse_filter:
        warehouse_query = warehouse_query.filter(warehouse__iexact=warehouse_filter)

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
    latest_cost_by_product: dict[int, Decimal] = {}
    for _row in InventoryRecord.objects.filter(id__in=latest_cost_ids).values(
        "product_id", "unit_cost", "quantity", "total"
    ):
        _qty = Decimal(_row["quantity"] or 0)
        _total = Decimal(_row["total"] or 0)
        latest_cost_by_product[_row["product_id"]] = (
            abs(_total) / abs(_qty) if _qty != 0 else Decimal(_row["unit_cost"] or 0)
        )

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

    # Índices por clave para procesar solo días con eventos.
    movement_days_by_warehouse: dict[tuple[int, str], dict[date, Decimal]] = {}
    final_days_by_warehouse: dict[tuple[int, str], dict[date, Decimal]] = {}
    event_days_by_warehouse: dict[tuple[int, str], set[date]] = {}
    for (pid, wh, day), qty in movement_by_day_by_warehouse.items():
        key = (pid, wh)
        movement_days_by_warehouse.setdefault(key, {})[day] = qty
        event_days_by_warehouse.setdefault(key, set()).add(day)
    for (pid, wh, day), final_qty in daily_final_by_warehouse.items():
        key = (pid, wh)
        final_days_by_warehouse.setdefault(key, {})[day] = final_qty
        event_days_by_warehouse.setdefault(key, set()).add(day)
    event_days_sorted_by_warehouse: dict[tuple[int, str], list[date]] = {
        key: sorted(days) for key, days in event_days_by_warehouse.items()
    }

    movement_days_by_product: dict[int, dict[date, Decimal]] = {}
    final_days_by_product: dict[int, dict[date, Decimal]] = {}
    event_days_by_product: dict[int, set[date]] = {}
    for (pid, day), qty in movement_by_day_by_product.items():
        movement_days_by_product.setdefault(pid, {})[day] = qty
        event_days_by_product.setdefault(pid, set()).add(day)
    for (pid, day), final_qty in daily_final_by_product.items():
        final_days_by_product.setdefault(pid, {})[day] = final_qty
        event_days_by_product.setdefault(pid, set()).add(day)
    event_days_sorted_by_product: dict[int, list[date]] = {
        pid: sorted(days) for pid, days in event_days_by_product.items()
    }
    _days_count_dec = Decimal(days_count)

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

                opening_qty += opening_wh_qty

                event_days = event_days_sorted_by_warehouse.get(key, [])
                if not event_days:
                    # Ruta rápida: sin eventos → balance constante todo el mes
                    closing_qty += opening_wh_qty
                    sum_daily_qty += opening_wh_qty * _days_count_dec
                else:
                    closing_wh_qty, sum_daily_wh_qty = _sum_running_qty_from_event_days(
                        period_start=month_start,
                        days_count=days_count,
                        opening_qty=opening_wh_qty,
                        movement_by_day=movement_days_by_warehouse.get(key, {}),
                        final_by_day=final_days_by_warehouse.get(key, {}),
                        event_days=event_days,
                    )
                    closing_qty += closing_wh_qty
                    sum_daily_qty += sum_daily_wh_qty
        else:
            base_initial = Decimal(product["initial_balance"] or 0)
            opening_qty = base_initial + movement_before_start_by_product.get(
                pid, Decimal("0")
            )
            event_days = event_days_sorted_by_product.get(pid, [])
            if not event_days:
                # Ruta rápida: sin eventos → balance constante todo el mes
                closing_qty = opening_qty
                sum_daily_qty = opening_qty * _days_count_dec
            else:
                closing_qty, sum_daily_qty = _sum_running_qty_from_event_days(
                    period_start=month_start,
                    days_count=days_count,
                    opening_qty=opening_qty,
                    movement_by_day=movement_days_by_product.get(pid, {}),
                    final_by_day=final_days_by_product.get(pid, {}),
                    event_days=event_days,
                )

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
                "cantidad_apertura": _qty_float(opening_qty),
                "cantidad_cierre": _qty_float(closing_qty),
                "cantidad_promedio": _qty_float(average_qty),
                "costo_unitario": _money_float(unit_cost),
                "valor_apertura": _money_float(opening_value),
                "valor_cierre": _money_float(closing_value),
                "valor_promedio": _money_float(average_value),
                # Alias de compatibilidad con formato de inventario actual.
                "cantidad": _qty_float(average_qty),
                "valor": _money_float(average_value),
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

    result = {
        "month": month_key,
        "month_start": month_start.isoformat(),
        "month_end": month_end.isoformat(),
        "products": page_rows,
        "products_count": total_count,
        "products_count_unbounded": total_count_unbounded,
        "totals": {
            "opening_quantity": _qty_float(total_opening_qty),
            "closing_quantity": _qty_float(total_closing_qty),
            "average_quantity": _qty_float(total_average_qty),
            "opening_value": _money_float(total_opening_value),
            "closing_value": _money_float(total_closing_value),
            "average_value": _money_float(total_average_value),
        },
        # Alias de compatibilidad para cliente tipo inventario actual.
        "total_quantity": _qty_float(total_average_qty),
        "total_value": _money_float(total_average_value),
        "truncated": bool(limit_value and total_count_unbounded > total_count),
        "limit": limit_value,
        "offset": start,
        "page_size": page_size_value,
        "has_next_page": end < total_count,
    }
    cache.set(_svc_cache_key, result, HISTORIC_CACHE_TTL_SECONDS)
    return result


def get_range_product_cuts_data(
    inventory_name="Por defecto",
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
    data_version = get_inventory_cache_version(inventory_name)
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
            records_all = records_all.filter(warehouse__iexact=warehouse_filter)
        agg = records_all.aggregate(min_d=Min("date"), max_d=Max("date"))
        if period_start is None:
            period_start = agg["min_d"] if agg["min_d"] else datetime.now().date()
        if period_end is None:
            period_end = agg["max_d"] if agg["max_d"] else datetime.now().date()

    if period_start > period_end:
        period_start, period_end = period_end, period_start

    # Cantidad de días (solo para el label informativo del response)
    days_count = (period_end - period_start).days + 1

    cache_payload = {
        "inventory_name": inventory_name,
        "data_version": data_version,
        "date_from": period_start.isoformat(),
        "date_to": period_end.isoformat(),
        "warehouse_filter": warehouse_filter,
        "category_filter": category_filter,
        "search_filter": search_filter,
        "limit": str(limit or ""),
    }
    cache_payload["_calc_version"] = _ANALYTICS_CALC_VERSION
    cache_key_src = json.dumps(cache_payload, sort_keys=True, ensure_ascii=False)
    cache_key = (
        f"range_cuts:v1:{hashlib.sha256(cache_key_src.encode('utf-8')).hexdigest()}"
    )
    cached_value = cache.get(cache_key)
    if cached_value is not None:
        return cached_value

    # ── Productos filtrados ──────────────────────────────────────────────────
    products_qs = Product.objects.filter(inventory_name=inventory_name)
    if category_filter:
        products_qs = products_qs.filter(group__iexact=category_filter)
    if warehouse_filter:
        products_qs = products_qs.filter(
            Q(warehousedetail__warehouse__iexact=warehouse_filter)
            | Q(inventoryrecord__warehouse__iexact=warehouse_filter)
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
        result = {
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
        cache.set(cache_key, result, timeout=HISTORIC_CACHE_TTL_SECONDS)
        return result

    records_scope = InventoryRecord.objects.filter(product_id__in=product_ids)
    if warehouse_filter:
        records_scope = records_scope.filter(warehouse__iexact=warehouse_filter)

    warehouse_query = WarehouseDetail.objects.filter(product_id__in=product_ids)
    if warehouse_filter:
        warehouse_query = warehouse_query.filter(warehouse__iexact=warehouse_filter)

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
    latest_cost_by_product: dict[int, Decimal] = {}
    for _row in InventoryRecord.objects.filter(id__in=latest_cost_ids).values(
        "product_id", "unit_cost", "quantity", "total"
    ):
        _qty = Decimal(_row["quantity"] or 0)
        _total = Decimal(_row["total"] or 0)
        latest_cost_by_product[_row["product_id"]] = (
            abs(_total) / abs(_qty) if _qty != 0 else Decimal(_row["unit_cost"] or 0)
        )

    # ── Almacenes por producto ───────────────────────────────────────────────
    warehouses_by_product: dict[int, set] = {}
    for row in warehouse_query.values("product_id", "warehouse"):
        warehouses_by_product.setdefault(row["product_id"], set()).add(row["warehouse"])
    for row in records_scope.values("product_id", "warehouse").distinct():
        warehouses_by_product.setdefault(row["product_id"], set()).add(row["warehouse"])

    # Índices por clave para procesar solo días con eventos.
    movement_days_by_warehouse: dict[tuple[int, str], dict[date, Decimal]] = {}
    final_days_by_warehouse: dict[tuple[int, str], dict[date, Decimal]] = {}
    event_days_by_warehouse: dict[tuple[int, str], set[date]] = {}
    for (pid, wh, day), qty in movement_by_day_by_warehouse.items():
        key = (pid, wh)
        movement_days_by_warehouse.setdefault(key, {})[day] = qty
        event_days_by_warehouse.setdefault(key, set()).add(day)
    for (pid, wh, day), final_qty in daily_final_by_warehouse.items():
        key = (pid, wh)
        final_days_by_warehouse.setdefault(key, {})[day] = final_qty
        event_days_by_warehouse.setdefault(key, set()).add(day)
    event_days_sorted_by_warehouse: dict[tuple[int, str], list[date]] = {
        key: sorted(days) for key, days in event_days_by_warehouse.items()
    }

    movement_days_by_product: dict[int, dict[date, Decimal]] = {}
    final_days_by_product: dict[int, dict[date, Decimal]] = {}
    event_days_by_product: dict[int, set[date]] = {}
    for (pid, day), qty in movement_by_day_by_product.items():
        movement_days_by_product.setdefault(pid, {})[day] = qty
        event_days_by_product.setdefault(pid, set()).add(day)
    for (pid, day), final_qty in daily_final_by_product.items():
        final_days_by_product.setdefault(pid, {})[day] = final_qty
        event_days_by_product.setdefault(pid, set()).add(day)
    event_days_sorted_by_product: dict[int, list[date]] = {
        pid: sorted(days) for pid, days in event_days_by_product.items()
    }

    # ── Cálculo por producto: promedio DIARIO REAL del stock ─────────────────
    # Igual que get_monthly_product_cuts_data pero para el rango elegido.
    rows = []
    total_opening_qty = Decimal("0")
    total_closing_qty = Decimal("0")
    total_average_qty = Decimal("0")
    total_opening_value = Decimal("0")
    total_closing_value = Decimal("0")
    total_average_value = Decimal("0")
    _days_count_dec = Decimal(days_count)

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

                opening_qty += opening_wh_qty
                event_days = event_days_sorted_by_warehouse.get(key, [])
                if not event_days:
                    closing_qty += opening_wh_qty
                    sum_daily_qty += opening_wh_qty * _days_count_dec
                    continue

                closing_wh_qty, sum_daily_wh_qty = _sum_running_qty_from_event_days(
                    period_start=period_start,
                    days_count=days_count,
                    opening_qty=opening_wh_qty,
                    movement_by_day=movement_days_by_warehouse.get(key, {}),
                    final_by_day=final_days_by_warehouse.get(key, {}),
                    event_days=event_days,
                )
                closing_qty += closing_wh_qty
                sum_daily_qty += sum_daily_wh_qty
        else:
            base_initial = Decimal(product["initial_balance"] or 0)
            opening_qty = base_initial + movement_before_start_by_product.get(
                pid, Decimal("0")
            )
            event_days = event_days_sorted_by_product.get(pid, [])
            if not event_days:
                closing_qty = opening_qty
                sum_daily_qty = opening_qty * _days_count_dec
            else:
                closing_qty, sum_daily_qty = _sum_running_qty_from_event_days(
                    period_start=period_start,
                    days_count=days_count,
                    opening_qty=opening_qty,
                    movement_by_day=movement_days_by_product.get(pid, {}),
                    final_by_day=final_days_by_product.get(pid, {}),
                    event_days=event_days,
                )

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
            "cantidad_apertura": _qty_float(opening_qty),
            "cantidad_cierre": _qty_float(closing_qty),
            "cantidad_promedio": _qty_float(average_qty),
            "costo_unitario": _money_float(unit_cost),
            "valor_apertura": _money_float(opening_value),
            "valor_cierre": _money_float(closing_value),
            "valor_promedio": _money_float(average_value),
        })

    rows.sort(key=lambda item: item["valor_promedio"], reverse=True)
    if limit_value > 0:
        rows = rows[:limit_value]

    result = {
        "date_from": period_start.isoformat(),
        "date_to": period_end.isoformat(),
        "days_count": days_count,
        "products": rows,
        "products_count": len(rows),
        "totals": {
            "opening_quantity": _qty_float(total_opening_qty),
            "closing_quantity": _qty_float(total_closing_qty),
            "average_quantity": _qty_float(total_average_qty),
            "opening_value": _money_float(total_opening_value),
            "closing_value": _money_float(total_closing_value),
            "average_value": _money_float(total_average_value),
        },
    }
    cache.set(cache_key, result, timeout=HISTORIC_CACHE_TTL_SECONDS)
    return result


def get_product_analysis_data(
    inventory_name="Por defecto",
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
    data_version = get_inventory_cache_version(inventory_name)
    cache_payload = {
        "inventory_name": inventory_name,
        "data_version": data_version,
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
    cache_payload["_calc_version"] = _ANALYTICS_CALC_VERSION
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
        products_qs = products_qs.filter(group__iexact=category_filter)
    if warehouse_filter:
        products_qs = products_qs.filter(
            Q(warehousedetail__warehouse__iexact=warehouse_filter)
            | Q(inventoryrecord__warehouse__iexact=warehouse_filter)
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
        cache.set(cache_key, [], timeout=HISTORIC_CACHE_TTL_SECONDS)
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
            warehouse__iexact=warehouse_filter
        )

    records_scope = InventoryRecord.objects.filter(product_id__in=product_ids)
    if target_date:
        records_scope = records_scope.filter(date__lte=target_date)
    if warehouse_filter:
        records_scope = records_scope.filter(warehouse__iexact=warehouse_filter)

    movement_qty_rows = list(
        records_scope.values("product_id", "warehouse").annotate(total_qty=Sum("quantity"))
    )
    movement_qty_by_warehouse: dict[tuple[int, str], Decimal] = {}
    movement_qty_by_product: dict[int, Decimal] = {}
    for row in movement_qty_rows:
        pid = row["product_id"]
        warehouse = row["warehouse"]
        qty = row["total_qty"] or Decimal("0")
        movement_qty_by_warehouse[(pid, warehouse)] = qty
        movement_qty_by_product[pid] = movement_qty_by_product.get(pid, Decimal("0")) + qty

    wd_query = WarehouseDetail.objects.filter(product_id__in=product_ids)
    if warehouse_filter:
        wd_query = wd_query.filter(warehouse__iexact=warehouse_filter)

    warehouse_rows = list(wd_query.values("product_id", "warehouse", "initial_quantity"))
    initial_qty_by_warehouse: dict[tuple[int, str], Decimal] = {}
    initial_qty_by_product: dict[int, Decimal] = {}
    for row in warehouse_rows:
        pid = row["product_id"]
        warehouse = row["warehouse"]
        qty = Decimal(row["initial_quantity"] or 0)
        initial_qty_by_warehouse[(pid, warehouse)] = qty
        initial_qty_by_product[pid] = initial_qty_by_product.get(pid, Decimal("0")) + qty

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
    for pid, warehouse in initial_qty_by_warehouse.keys():
        warehouses_dict.setdefault(pid, set()).add(warehouse)
    for pid, warehouse in movement_qty_by_warehouse.keys():
        warehouses_dict.setdefault(pid, set()).add(warehouse)
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
        pre_year_filter &= Q(warehouse__iexact=warehouse_filter)

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
        monthly_filter &= Q(warehouse__iexact=warehouse_filter)

    daily_rows_by_product: dict[int, list[tuple[date, Decimal]]] = {}
    for row in (
        InventoryRecord.objects.filter(monthly_filter)
        .values("product_id", "date")
        .annotate(daily_total=Sum("quantity"))
        .order_by("product_id", "date")
    ):
        pid = row["product_id"]
        daily_rows_by_product.setdefault(pid, []).append(
            (row["date"], row["daily_total"] or Decimal("0"))
        )

    # Primera fecha con movimiento por producto dentro del alcance consultado.
    # Se usa para no marcar como "Obsoleto" productos que aparecieron después
    # del periodo de evaluación (p.ej. cuando el año de rotación se ajusta al
    # año anterior por tener pocos meses en el año más reciente).
    first_record_date_by_product: dict[int, datetime.date] = {
        row["product_id"]: row["first_date"]
        for row in records_scope.values("product_id").annotate(first_date=Min("date"))
        if row["first_date"]
    }

    qty_output = DecimalField(max_digits=28, decimal_places=6)
    movement_stats_filter = monthly_filter
    if start_date:
        movement_stats_filter = Q(product_id__in=product_ids)
        if warehouse_filter:
            movement_stats_filter &= Q(warehouse__iexact=warehouse_filter)
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
                        # `total` ya viene valorizado por el ERP y conserva
                        # la regla real de costeo del movimiento.
                        total__gt=0,
                        then=F("total"),
                    ),
                    default=Value(Decimal("0"), output_field=value_output),
                    output_field=value_output,
                )
            ),
            exits_value=Sum(
                Case(
                    When(
                        # En salidas `total` es negativo; se reporta en valor
                        # absoluto para mantener formato Entradas/Salidas.
                        total__lt=0,
                        then=ExpressionWrapper(-1 * F("total"), output_field=value_output),
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
            daily_rows = daily_rows_by_product.get(pid, [])

            # ── Loop de rotación optimizado: mes a mes en lugar de día a día ──
            period_end = evaluation_end_date

            monthly_balances = []
            monthly_changed = []
            month_numbers = []
            month_has_daily_changes: dict[int, bool] = {}
            running = balance_pre_year
            had_positive_stock = balance_pre_year > 0
            all_daily_zero = balance_pre_year == 0
            _daily_idx = 0
            _daily_count = len(daily_rows)

            for _month_num in range(1, period_end.month + 1):
                _has_change = False
                _prev_running = running
                while _daily_idx < _daily_count:
                    _day, _qty = daily_rows[_daily_idx]
                    if _day.month != _month_num:
                        break
                    _daily_idx += 1
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
                month_numbers = [rotation_year_start.month]

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
            first_record_date = first_record_date_by_product.get(pid)
            is_new_after_evaluation_window = bool(
                first_record_date and first_record_date > evaluation_end_date
            )
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
            elif is_new_after_evaluation_window:
                # Producto nuevo posterior al periodo evaluado:
                # no debe penalizarse como "Obsoleto" por no existir aún
                # en el año de rotación.
                rotation = "Activo"
                rotation_rule = "producto_nuevo_posterior_al_periodo_evaluado"
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

    cache.set(cache_key, analysis_data, timeout=HISTORIC_CACHE_TTL_SECONDS)
    return analysis_data


def get_inventory_at_date_data(
    inventory_name="Por defecto",
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
        products_query = products_query.filter(group__iexact=category_filter)
    if warehouse_filter:
        products_query = products_query.filter(
            Q(warehousedetail__warehouse__iexact=warehouse_filter)
            | Q(inventoryrecord__warehouse__iexact=warehouse_filter)
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
        warehouse_query = warehouse_query.filter(warehouse__iexact=warehouse_filter)
    warehouse_rows = list(warehouse_query.values("product_id", "warehouse", "initial_quantity"))
    initial_qty_by_warehouse: dict[tuple[int, str], Decimal] = {}
    initial_qty_map: dict[int, Decimal] = {}
    warehouse_names_by_product: dict[int, set[str]] = {}
    for row in warehouse_rows:
        pid = row["product_id"]
        warehouse = row["warehouse"]
        qty = Decimal(row["initial_quantity"] or 0)
        initial_qty_by_warehouse[(pid, warehouse)] = qty
        initial_qty_map[pid] = initial_qty_map.get(pid, Decimal("0")) + qty
        warehouse_names_by_product.setdefault(pid, set()).add(warehouse)

    movements_query = InventoryRecord.objects.filter(
        product_id__in=product_ids,
        date__lte=target_date,
    )
    if warehouse_filter:
        movements_query = movements_query.filter(warehouse__iexact=warehouse_filter)
    movement_rows = list(
        movements_query.values("product_id", "warehouse").annotate(qty=Sum("quantity"))
    )
    movement_qty_by_warehouse: dict[tuple[int, str], Decimal] = {}
    movement_qty_map: dict[int, Decimal] = {}
    for row in movement_rows:
        pid = row["product_id"]
        warehouse = row["warehouse"]
        qty = row["qty"] or Decimal("0")
        movement_qty_by_warehouse[(pid, warehouse)] = qty
        movement_qty_map[pid] = movement_qty_map.get(pid, Decimal("0")) + qty
        warehouse_names_by_product.setdefault(pid, set()).add(warehouse)

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
    latest_cost_dict: dict[int, Decimal] = {}
    for _row in InventoryRecord.objects.filter(id__in=latest_record_ids).values(
        "product_id", "unit_cost", "quantity", "total"
    ):
        _qty = Decimal(_row["quantity"] or 0)
        _total = Decimal(_row["total"] or 0)
        latest_cost_dict[_row["product_id"]] = (
            abs(_total) / abs(_qty) if _qty != 0 else Decimal(_row["unit_cost"] or 0)
        )

    total_quantity = Decimal("0")
    total_value = Decimal("0")
    products_data = []

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
                "cantidad": _qty_float(product_quantity),
                "valor": _money_float(product_value),
                "costo_unitario": _money_float(unit_cost),
            }
        )

    return {
        "date": date_str,
        "total_quantity": _qty_float(total_quantity),
        "total_value": _money_float(total_value),
        "products": products_data,
    }
