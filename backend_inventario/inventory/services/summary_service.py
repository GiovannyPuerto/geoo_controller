import os
from decimal import Decimal, ROUND_HALF_UP

from django.core.cache import cache
from django.db.models import BigIntegerField, Case, F, Max, Sum, Value, When

from ..models import Product, InventoryRecord, ImportBatch, WarehouseDetail
from .cache_version_service import get_inventory_cache_version


_MONEY_QUANT = Decimal("0.01")
_QTY_QUANT = Decimal("0.001")
HISTORIC_CACHE_TTL_SECONDS = int(
    os.environ.get("INVENTORY_HISTORIC_CACHE_TTL_SECONDS", "86400")
)


def _money_float(value) -> float:
    return float(Decimal(value or 0).quantize(_MONEY_QUANT, rounding=ROUND_HALF_UP))


def _qty_float(value) -> float:
    return float(Decimal(value or 0).quantize(_QTY_QUANT, rounding=ROUND_HALF_UP))


def get_inventory_summary_data(inventory_name="default"):
    """
    Construye el payload de resumen de inventario para la API.
    Usa queries SQL masivas para evitar loops lentos N+1.
    """
    data_version = get_inventory_cache_version(inventory_name)
    cache_key = f"inventory:summary:{inventory_name}:v={data_version}"
    cached_value = cache.get(cache_key)
    if cached_value is not None:
        return cached_value

    products_qs = Product.objects.filter(inventory_name=inventory_name)
    total_products = products_qs.count()
    total_records = InventoryRecord.objects.filter(
        product__inventory_name=inventory_name
    ).count()
    total_batches = ImportBatch.objects.filter(inventory_name=inventory_name).count()

    if total_products == 0:
        payload = {
            "inventory_name": inventory_name,
            "total_products": 0,
            "total_records": total_records,
            "total_batches": total_batches,
            "total_quantity": 0.0,
            "total_value": 0.0,
            "negative_stock_alerts": [],
        }
        cache.set(cache_key, payload, timeout=HISTORIC_CACHE_TTL_SECONDS)
        return payload

    product_meta = {
        p["id"]: p
        for p in products_qs.values(
            "id", "code", "description", "initial_balance", "initial_unit_cost"
        )
    }
    product_ids = list(product_meta.keys())

    # Stock inicial agregado por (producto, almacén)
    initial_map: dict[int, dict[str, Decimal]] = {}
    for row in WarehouseDetail.objects.filter(product__inventory_name=inventory_name).values(
        "product_id", "warehouse", "initial_quantity"
    ):
        initial_map.setdefault(row["product_id"], {})[row["warehouse"]] = Decimal(
            row["initial_quantity"] or 0
        )

    # ── Una sola query: qty acumulada + último id con final_quantity + último id global ──
    # Antes eran 3 queries + 2 fetches = 5 round-trips. Ahora son 1 query agregada + 2 fetches = 3.
    all_movements = list(
        InventoryRecord.objects.filter(product__inventory_name=inventory_name)
        .values("product_id", "warehouse")
        .annotate(
            qty=Sum("quantity"),
            # MAX(id) solo sobre registros que tienen final_quantity registrado
            latest_final_id=Max(
                Case(
                    When(final_quantity__isnull=False, then=F("id")),
                    default=None,
                    output_field=BigIntegerField(),
                )
            ),
            # MAX(id) global por (producto, almacén) para determinar el costo más reciente
            max_id=Max("id"),
        )
    )

    movement_map: dict[tuple, Decimal] = {}
    latest_final_record_ids: list[int] = []
    # Costo más reciente por producto = max(max_id) de todos sus almacenes
    max_id_by_product: dict[int, int] = {}

    for row in all_movements:
        pid = row["product_id"]
        wh = row["warehouse"]
        movement_map[(pid, wh)] = row["qty"] or Decimal("0")
        if row["latest_final_id"]:
            latest_final_record_ids.append(row["latest_final_id"])
        mid = row["max_id"]
        if mid and mid > max_id_by_product.get(pid, 0):
            max_id_by_product[pid] = mid

    latest_final_map: dict[tuple, Decimal] = {
        (row["product_id"], row["warehouse"]): Decimal(row["final_quantity"] or 0)
        for row in InventoryRecord.objects.filter(id__in=latest_final_record_ids).values(
            "product_id", "warehouse", "final_quantity"
        )
    }

    # Unificamos almacenes presentes en base y en movimientos para evitar descuadres.
    warehouses_by_product: dict[int, set[str]] = {}
    for pid, warehouses in initial_map.items():
        warehouses_by_product.setdefault(pid, set()).update(warehouses.keys())
    for pid, warehouse in movement_map.keys():
        warehouses_by_product.setdefault(pid, set()).add(warehouse)

    #  Último costo unitario por producto calculado como abs(total) ÷ abs(quantity) 
    cost_map: dict[int, Decimal] = {}
    for _row in InventoryRecord.objects.filter(id__in=max_id_by_product.values()).values(
        "product_id", "unit_cost", "quantity", "total"
    ):
        _qty = Decimal(_row["quantity"] or 0)
        _total = Decimal(_row["total"] or 0)
        cost_map[_row["product_id"]] = (
            abs(_total) / abs(_qty) if _qty != 0 else Decimal(_row["unit_cost"] or 0)
        )

    #  Calcular totales en Python (una sola pasada) 
    total_quantity = Decimal("0")
    total_value = Decimal("0")
    negative_stock_alerts = []

    for pid in product_ids:
        current_stock = Decimal("0")
        warehouses = warehouses_by_product.get(pid, set())
        if warehouses:
            for warehouse in warehouses:
                key = (pid, warehouse)
                if key in latest_final_map:
                    current_stock += latest_final_map[key]
                else:
                    init_qty = initial_map.get(pid, {}).get(warehouse, Decimal("0"))
                    mov_qty = movement_map.get(key, Decimal("0"))
                    current_stock += init_qty + mov_qty
        else:
            meta = product_meta.get(pid, {})
            current_stock = Decimal(meta.get("initial_balance") or 0)

        total_quantity += current_stock

        meta = product_meta.get(pid, {})
        unit_cost = cost_map.get(pid) or Decimal(meta.get("initial_unit_cost") or 0)
        total_value += current_stock * unit_cost

        if current_stock < 0:
            negative_stock_alerts.append(
                {
                    "codigo": meta.get("code", ""),
                    "nombre_producto": meta.get("description", ""),
                    "cantidad_saldo_actual": _qty_float(current_stock),
                    "justification": f"Stock actual negativo: {current_stock} unidades.",
                }
            )

    payload = {
        "inventory_name": inventory_name,
        "total_products": total_products,
        "total_records": total_records,
        "total_batches": total_batches,
        "total_quantity": _qty_float(total_quantity),
        "total_value": _money_float(total_value),
        "negative_stock_alerts": negative_stock_alerts,
    }
    cache.set(cache_key, payload, timeout=HISTORIC_CACHE_TTL_SECONDS)
    return payload
