from django.db import migrations, models
from django.db.models import Count, Min


def _dedupe_existing_row_hashes(apps, schema_editor):
    """
    Limpia duplicados históricos por row_hash antes de activar UNIQUE.
    Conserva el registro más antiguo (menor id) y elimina los repetidos.
    """
    InventoryRecord = apps.get_model('inventory', 'InventoryRecord')

    duplicate_groups = (
        InventoryRecord.objects
        .exclude(row_hash__isnull=True)
        .exclude(row_hash='')
        .values('row_hash')
        .annotate(total=Count('id'), keep_id=Min('id'))
        .filter(total__gt=1)
    )

    for group in duplicate_groups.iterator(chunk_size=500):
        (
            InventoryRecord.objects
            .filter(row_hash=group['row_hash'])
            .exclude(id=group['keep_id'])
            .delete()
        )


class Migration(migrations.Migration):

    dependencies = [
        ('inventory', '0021_alter_inventoryrecord_unique_with_lote'),
    ]

    operations = [
        migrations.RunPython(_dedupe_existing_row_hashes, migrations.RunPython.noop),
        migrations.AddConstraint(
            model_name='inventoryrecord',
            constraint=models.UniqueConstraint(
                fields=('row_hash',),
                condition=models.Q(row_hash__isnull=False) & ~models.Q(row_hash=''),
                name='inventory_i_row_hash_uniq',
            ),
        ),
    ]
