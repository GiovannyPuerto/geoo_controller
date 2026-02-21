from decimal import Decimal

from django.db.models import Max, Sum

from ..models import Product, InventoryRecord, ImportBatch, WarehouseDetail


def get_inventory_summary_data(inventory_name="default"):
    """
    Construye el payload de resumen de inventario para la API.
    Usa queries SQL masivas para evitar loops lentos N+1.
    """
    product_ids = list(
        Product.objects.filter(inventory_name=inventory_name).values_list("id", flat=True)
    )
    total_products = len(product_ids)
    total_records = InventoryRecord.objects.filter(
        product__inventory_name=inventory_name
    ).count()
    total_batches = ImportBatch.objects.filter(inventory_name=inventory_name).count()

    if total_products == 0:
        return {
            "inventory_name": inventory_name,
            "total_products": 0,
            "total_records": total_records,
            "total_batches": total_batches,
            "total_quantity": 0.0,
            "total_value": 0.0,
            "negative_stock_alerts": [],
        }

    # Stock inicial agregado por (producto, almacén) 
    initial_map: dict[int, dict[str, Decimal]] = {}
    for row in WarehouseDetail.objects.filter(product_id__in=product_ids).values(
        "product_id", "warehouse", "initial_quantity"
    ):
        initial_map.setdefault(row["product_id"], {})[row["warehouse"]] = Decimal(
            row["initial_quantity"] or 0
        )

    # Movimientos acumulados por (producto, almacén)
    movement_map: dict[tuple, Decimal] = {
        (row["product_id"], row["warehouse"]): row["qty"] or Decimal("0")
        for row in InventoryRecord.objects.filter(product_id__in=product_ids)
        .values("product_id", "warehouse")
        .annotate(qty=Sum("quantity"))
    }

    #  Último unit_cost por producto (MAX id = registro más reciente) 
    latest_ids = {
        row["product_id"]: row["lid"]
        for row in InventoryRecord.objects.filter(product_id__in=product_ids)
        .values("product_id")
        .annotate(lid=Max("id"))
    }
    cost_map: dict[int, Decimal] = {
        row["product_id"]: Decimal(row["unit_cost"] or 0)
        for row in InventoryRecord.objects.filter(id__in=latest_ids.values()).values(
            "product_id", "unit_cost"
        )
    }

    # Datos de producto (code, description, initial_unit_cost)
    product_meta = {
        p["id"]: p
        for p in Product.objects.filter(id__in=product_ids).values(
            "id", "code", "description", "initial_unit_cost"
        )
    }

    #  Calcular totales en Python (una sola pasada) 
    total_quantity = Decimal("0")
    total_value = Decimal("0")
    negative_stock_alerts = []

    for pid in product_ids:
        current_stock = Decimal("0")
        warehouses = initial_map.get(pid, {})
        for warehouse, init_qty in warehouses.items():
            current_stock += init_qty + movement_map.get((pid, warehouse), Decimal("0"))

        total_quantity += current_stock

        meta = product_meta.get(pid, {})
        unit_cost = cost_map.get(pid) or Decimal(meta.get("initial_unit_cost") or 0)
        total_value += current_stock * unit_cost

        if current_stock < 0:
            negative_stock_alerts.append(
                {
                    "codigo": meta.get("code", ""),
                    "nombre_producto": meta.get("description", ""),
                    "cantidad_saldo_actual": float(current_stock),
                    "justification": f"Stock actual negativo: {current_stock} unidades.",
                }
            )

    return {
        "inventory_name": inventory_name,
        "total_products": total_products,
        "total_records": total_records,
        "total_batches": total_batches,
        "total_quantity": float(total_quantity),
        "total_value": float(total_value),
        "negative_stock_alerts": negative_stock_alerts,
    }