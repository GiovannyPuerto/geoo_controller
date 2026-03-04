from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('inventory', '0020_remove_inventoryrecord_inv_rec_product_date_idx_and_more'),
    ]

    operations = [
        migrations.AlterUniqueTogether(
            name='inventoryrecord',
            unique_together={
                ('source_document', 'source_record', 'product', 'cost_center', 'date', 'warehouse', 'lote'),
            },
        ),
    ]
