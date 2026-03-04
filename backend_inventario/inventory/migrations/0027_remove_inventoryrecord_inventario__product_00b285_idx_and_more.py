from django.db import migrations
import django.db.models


class Migration(migrations.Migration):

    dependencies = [
        ('inventory', '0026_rename_model_fields_to_spanish'),
    ]

    operations = [
        # Solo ajusta el estado de migraciones: en BD los indices ya existen
        # con los nombres y columnas correctas.
        migrations.SeparateDatabaseAndState(
            database_operations=[],
            state_operations=[
                migrations.RemoveIndex(
                    model_name='inventoryrecord',
                    name='inventario__product_00b285_idx',
                ),
                migrations.RemoveIndex(
                    model_name='inventoryrecord',
                    name='inventario__almacen_065fc3_idx',
                ),
                migrations.RemoveIndex(
                    model_name='inventoryrecord',
                    name='inventario__tipo_do_f42158_idx',
                ),
                migrations.RemoveIndex(
                    model_name='inventoryrecord',
                    name='inventario__product_75623a_idx',
                ),
                migrations.RemoveIndex(
                    model_name='inventoryrecord',
                    name='inventario__product_1a8882_idx',
                ),
                migrations.RemoveIndex(
                    model_name='inventoryrecord',
                    name='inventario__fecha_56f2eb_idx',
                ),
                migrations.RemoveIndex(
                    model_name='inventoryrecord',
                    name='inventory_i_source_doc_rec_idx',
                ),
                migrations.AddIndex(
                    model_name='inventoryrecord',
                    index=django.db.models.Index(
                        fields=['producto', 'fecha'],
                        name='inventario__product_00b285_idx',
                    ),
                ),
                migrations.AddIndex(
                    model_name='inventoryrecord',
                    index=django.db.models.Index(
                        fields=['producto', 'almacen'],
                        name='inventario__product_75623a_idx',
                    ),
                ),
                migrations.AddIndex(
                    model_name='inventoryrecord',
                    index=django.db.models.Index(
                        fields=['producto', 'almacen', 'fecha'],
                        name='inventario__product_1a8882_idx',
                    ),
                ),
                migrations.AddIndex(
                    model_name='inventoryrecord',
                    index=django.db.models.Index(
                        fields=['almacen', 'fecha'],
                        name='inventario__almacen_065fc3_idx',
                    ),
                ),
                migrations.AddIndex(
                    model_name='inventoryrecord',
                    index=django.db.models.Index(
                        fields=['tipo_documento', 'numero_documento'],
                        name='inventario__tipo_do_f42158_idx',
                    ),
                ),
                migrations.AddIndex(
                    model_name='inventoryrecord',
                    index=django.db.models.Index(
                        fields=['documento_origen', 'registro_origen'],
                        name='inventory_i_source_doc_rec_idx',
                    ),
                ),
                migrations.AddIndex(
                    model_name='inventoryrecord',
                    index=django.db.models.Index(
                        fields=['fecha'],
                        name='inventario__fecha_56f2eb_idx',
                    ),
                ),
            ],
        ),
    ]
