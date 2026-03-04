import os
from decimal import Decimal, ROUND_HALF_UP

from django.core.cache import cache
from django.db.models import Max, Sum

from ..models import Product, InventoryRecord, ImportBatch, WarehouseDetail


_MONEY_QUANT = Decimal("0.01")
_QTY_QUANT = Decimal("0.001")
HISTORIC_CACHE_TTL_SECONDS = int(
    os.environ.get("INVENTORY_HISTORIC_CACHE_TTL_SECONDS", "604800")
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
    cache_key = f"inventory:summary:{inventory_name}"
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

    # Movimientos acumulados por (producto, almacén)
    movement_map: dict[tuple, Decimal] = {
        (row["product_id"], row["warehouse"]): row["qty"] or Decimal("0")
        for row in InventoryRecord.objects.filter(product__inventory_name=inventory_name)
        .values("product_id", "warehouse")
        .annotate(qty=Sum("quantity"))
    }
    latest_final_record_ids = [
        row["latest_id"]
        for row in InventoryRecord.objects.filter(
            product__inventory_name=inventory_name,
            final_quantity__isnull=False,
        )
        .values("product_id", "warehouse")
        .annotate(latest_id=Max("id"))
        if row["latest_id"]
    ]
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

    #  Último unit_cost por producto (MAX id = registro más reciente) 
    latest_ids = {
        row["product_id"]: row["lid"]
        for row in InventoryRecord.objects.filter(product__inventory_name=inventory_name)
        .values("product_id")
        .annotate(lid=Max("id"))
    }
    cost_map: dict[int, Decimal] = {
        row["product_id"]: Decimal(row["unit_cost"] or 0)
        for row in InventoryRecord.objects.filter(id__in=latest_ids.values()).values(
            "product_id", "unit_cost"
        )
    }

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
