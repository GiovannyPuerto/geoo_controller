from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('inventory', '0028_alter_importbatch_nombre_inventario_and_more'),
    ]

    operations = [
        migrations.CreateModel(
            name='IdealInventoryGroup',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('nombre_inventario', models.CharField(db_column='nombre_inventario', db_index=True, default='Por defecto', max_length=128)),
                ('grupo', models.CharField(db_column='grupo', max_length=128)),
                ('valor_ideal', models.DecimalField(db_column='valor_ideal', decimal_places=2, default=0, max_digits=20)),
                ('actualizado_en', models.DateTimeField(auto_now=True, db_column='actualizado_en')),
            ],
            options={
                'db_table': 'inventario_ideal_grupos',
                'unique_together': {('nombre_inventario', 'grupo')},
            },
        ),
    ]
