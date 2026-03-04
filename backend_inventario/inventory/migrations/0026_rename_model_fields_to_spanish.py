from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        (
            'inventory',
            '0025_rename_inventory_i_product_2f833d_idx_inventario__product_00b285_idx_and_more',
        ),
    ]

    operations = [
        # ImportBatch
        migrations.RenameField(model_name='importbatch', old_name='file_name', new_name='archivo'),
        migrations.RenameField(model_name='importbatch', old_name='started_at', new_name='iniciado_en'),
        migrations.RenameField(model_name='importbatch', old_name='processed_at', new_name='procesado_en'),
        migrations.RenameField(model_name='importbatch', old_name='rows_total', new_name='filas_totales'),
        migrations.RenameField(model_name='importbatch', old_name='rows_imported', new_name='filas_importadas'),
        migrations.RenameField(model_name='importbatch', old_name='checksum', new_name='suma_verificacion'),
        migrations.RenameField(model_name='importbatch', old_name='inventory_name', new_name='nombre_inventario'),

        # Product
        migrations.RenameField(model_name='product', old_name='code', new_name='codigo'),
        migrations.RenameField(model_name='product', old_name='description', new_name='descripcion'),
        migrations.RenameField(model_name='product', old_name='group', new_name='grupo'),
        migrations.RenameField(model_name='product', old_name='inventory_name', new_name='nombre_inventario'),
        migrations.RenameField(model_name='product', old_name='initial_balance', new_name='saldo_inicial'),
        migrations.RenameField(model_name='product', old_name='initial_unit_cost', new_name='costo_unitario_inicial'),
        migrations.RenameField(model_name='product', old_name='current_quantity', new_name='cantidad_actual'),
        migrations.RenameField(model_name='product', old_name='current_unit_cost', new_name='costo_unitario_actual'),

        # WarehouseDetail
        migrations.RenameField(model_name='warehousedetail', old_name='product', new_name='producto'),
        migrations.RenameField(model_name='warehousedetail', old_name='warehouse', new_name='almacen'),
        migrations.RenameField(model_name='warehousedetail', old_name='initial_quantity', new_name='cantidad_inicial'),
        migrations.RenameField(model_name='warehousedetail', old_name='initial_value', new_name='valor_inicial'),

        # InventoryRecord
        migrations.RenameField(model_name='inventoryrecord', old_name='batch', new_name='lote_importacion'),
        migrations.RenameField(model_name='inventoryrecord', old_name='product', new_name='producto'),
        migrations.RenameField(model_name='inventoryrecord', old_name='warehouse', new_name='almacen'),
        migrations.RenameField(model_name='inventoryrecord', old_name='date', new_name='fecha'),
        migrations.RenameField(model_name='inventoryrecord', old_name='document_type', new_name='tipo_documento'),
        migrations.RenameField(model_name='inventoryrecord', old_name='document_number', new_name='numero_documento'),
        migrations.RenameField(model_name='inventoryrecord', old_name='source_document', new_name='documento_origen'),
        migrations.RenameField(model_name='inventoryrecord', old_name='source_record', new_name='registro_origen'),
        migrations.RenameField(model_name='inventoryrecord', old_name='quantity', new_name='cantidad'),
        migrations.RenameField(model_name='inventoryrecord', old_name='unit_cost', new_name='costo_unitario'),
        migrations.RenameField(model_name='inventoryrecord', old_name='total', new_name='valor_total'),
        migrations.RenameField(model_name='inventoryrecord', old_name='category', new_name='categoria'),
        migrations.RenameField(model_name='inventoryrecord', old_name='final_quantity', new_name='cantidad_final'),
        migrations.RenameField(model_name='inventoryrecord', old_name='cost_center', new_name='centro_costo'),
        migrations.RenameField(model_name='inventoryrecord', old_name='row_hash', new_name='hash_fila'),
    ]
