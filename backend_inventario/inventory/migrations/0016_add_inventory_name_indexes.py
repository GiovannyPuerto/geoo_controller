from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('inventory', '0015_inventoryrecord_source_fields_and_unique'),
    ]

    operations = [
        migrations.AlterField(
            model_name='importbatch',
            name='inventory_name',
            field=models.CharField(db_index=True, default='default', max_length=128),
        ),
        migrations.AlterField(
            model_name='product',
            name='inventory_name',
            field=models.CharField(db_index=True, default='default', max_length=128),
        ),
    ]
