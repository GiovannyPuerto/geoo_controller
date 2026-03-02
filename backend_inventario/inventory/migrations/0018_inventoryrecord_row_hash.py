"""
Agrega el campo row_hash a InventoryRecord.

row_hash es un SHA-256 (32 hex chars) del contenido del movimiento:
  product_id | date | doc_type | doc_number | source_document |
  quantity | unit_cost | warehouse | cost_center

Actúa como 3ª capa de deduplicación:
- 1ª capa: row_signature tuple (deduplica dentro del mismo archivo)
- 2ª capa: unique_together source_document/source_record (BD + memoria)
- 3ª capa: row_hash (detecta el mismo movimiento aunque source_record varíe,
           usa casefold para comparación case-insensitive de bodegas/doc_type)

El campo es nullable para compatibilidad con registros históricos.
Los registros cargados desde esta versión en adelante llevarán row_hash.
"""

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('inventory', '0017_add_product_date_sargable_index'),
    ]

    operations = [
        migrations.AddField(
            model_name='inventoryrecord',
            name='row_hash',
            field=models.CharField(
                max_length=64,
                null=True,
                blank=True,
                db_index=True,
                help_text=(
                    'SHA-256 (32 hex chars) del contenido del movimiento. '
                    '3ª capa de deduplicación: detecta el mismo movimiento '
                    'aunque source_record o document_number cambien entre cargas.'
                ),
            ),
        ),
    ]
