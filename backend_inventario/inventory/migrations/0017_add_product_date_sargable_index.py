"""
Agrega índice compuesto (product_id, date) en InventoryRecord.

Propósito:
  Las consultas de análisis de rotación y de movimientos históricos filtran por
  `product_id IN (...)  AND  date BETWEEN start AND end` sin restricción de
  almacén.  Los índices previos cubren (product, warehouse, date) y (date), pero
  ninguno cubre eficientemente el par (product_id, date) sin almacén — lo que
  obliga a MySQL a hacer un index-range scan sobre (date) y luego filtrar por
  product_id en memoria.

  Con este índice las queries siguientes pasan de O(registros_totales) a
  O(registros_del_producto):
    - pre_year_dict  (date__lt=rotation_year_start)
    - daily_movements_by_product  (date__range=(year_start, year_end))
    - movement_stats_by_product   (date__range o date__gte)
"""
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('inventory', '0016_add_inventory_name_indexes'),
    ]

    operations = [
        migrations.AddIndex(
            model_name='inventoryrecord',
            index=models.Index(
                fields=['product', 'date'],
                name='inv_rec_product_date_idx',
            ),
        ),
    ]
