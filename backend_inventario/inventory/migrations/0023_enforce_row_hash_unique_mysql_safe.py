from django.db import migrations, models
from django.db.models import Count, Min


def _normalize_and_dedupe_row_hash(apps, schema_editor):
    """
    Normaliza row_hash vacío a NULL y elimina duplicados históricos.
    """
    InventoryRecord = apps.get_model('inventory', 'InventoryRecord')

    # En MySQL un UNIQUE permite múltiples NULL, así que conviene normalizar vacíos.
    InventoryRecord.objects.filter(row_hash='').update(row_hash=None)

    duplicate_groups = (
        InventoryRecord.objects
        .exclude(row_hash__isnull=True)
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
        ('inventory', '0022_inventoryrecord_row_hash_unique_guard'),
    ]

    operations = [
        migrations.RunPython(_normalize_and_dedupe_row_hash, migrations.RunPython.noop),
        migrations.RemoveConstraint(
            model_name='inventoryrecord',
            name='inventory_i_row_hash_uniq',
        ),
        migrations.AlterField(
            model_name='inventoryrecord',
            name='row_hash',
            field=models.CharField(blank=True, max_length=64, null=True, unique=True),
        ),
    ]
