from decimal import Decimal

from django.db.models import Sum, Subquery, OuterRef

from ..models import Product, InventoryRecord, ImportBatch, WarehouseDetail


def get_inventory_summary_data(inventory_name="default"):
    """
    Construye el payload de resumen de inventario para la API.
    """
    product_qs = Product.objects.filter(inventory_name=inventory_name).only(
        "id", "code", "description", "initial_unit_cost"
    )
    total_products = product_qs.count()
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

    product_ids = list(product_qs.values_list("id", flat=True))

    # Cargar datos por almacén y movimientos en bloque.
    warehouse_rows = WarehouseDetail.objects.filter(product_id__in=product_ids).values(
        "product_id", "warehouse"
    ).annotate(initial_qty=Sum("initial_quantity"))
    movement_rows = InventoryRecord.objects.filter(product_id__in=product_ids).values(
        "product_id", "warehouse"
    ).annotate(movement_qty=Sum("quantity"))

    warehouse_by_product = {}
    for row in warehouse_rows:
        product_id = row["product_id"]
        if product_id not in warehouse_by_product:
            warehouse_by_product[product_id] = []
        warehouse_by_product[product_id].append(
            {
                "warehouse": row["warehouse"],
                "initial_qty": row["initial_qty"] or Decimal("0"),
            }
        )

    movement_map = {
        (row["product_id"], row["warehouse"]): row["movement_qty"] or Decimal("0")
        for row in movement_rows
    }

    latest_unit_cost_subquery = (
        InventoryRecord.objects.filter(product_id=OuterRef("id"))
        .order_by("-date", "-id")
        .values("unit_cost")[:1]
    )
    product_rows = Product.objects.filter(id__in=product_ids).annotate(
        latest_unit_cost=Subquery(latest_unit_cost_subquery)
    ).values("id", "code", "description", "initial_unit_cost", "latest_unit_cost")

    total_value = Decimal("0")
    total_quantity = Decimal("0")
    negative_stock_alerts = []

    for product in product_rows:
        # Mantener comportamiento funcional actual: solo almacenes de WarehouseDetail.
        current_stock = Decimal("0")
        for warehouse_data in warehouse_by_product.get(product["id"], []):
            warehouse_stock = Decimal(warehouse_data["initial_qty"] or 0)
            movements_sum = movement_map.get(
                (product["id"], warehouse_data["warehouse"]),
                Decimal("0"),
            )
            warehouse_stock += movements_sum
            current_stock += warehouse_stock

        total_quantity += current_stock

        current_unit_cost = Decimal(
            product["latest_unit_cost"] or product["initial_unit_cost"] or 0
        )
        total_value += current_stock * current_unit_cost

        if current_stock < 0:
            negative_stock_alerts.append(
                {
                    "codigo": product["code"],
                    "nombre_producto": product["description"],
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