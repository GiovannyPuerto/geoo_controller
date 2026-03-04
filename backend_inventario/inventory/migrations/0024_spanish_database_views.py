from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('inventory', '0023_enforce_row_hash_unique_mysql_safe'),
    ]

    operations = [
        migrations.RunSQL(
            sql=[
                """
                CREATE OR REPLACE VIEW inventory_vw_lotes_importacion AS
                SELECT
                    b.id AS lote_id,
                    b.file_name AS archivo,
                    b.started_at AS iniciado_en,
                    b.processed_at AS procesado_en,
                    b.rows_total AS filas_totales,
                    b.rows_imported AS filas_importadas,
                    b.checksum AS checksum,
                    b.inventory_name AS nombre_inventario
                FROM inventory_importbatch b
                """,
                """
                CREATE OR REPLACE VIEW inventory_vw_productos AS
                SELECT
                    p.id AS producto_id,
                    p.code AS codigo,
                    p.description AS descripcion,
                    p.`group` AS grupo,
                    p.inventory_name AS nombre_inventario,
                    p.initial_balance AS saldo_inicial,
                    p.initial_unit_cost AS costo_unitario_inicial,
                    p.current_quantity AS cantidad_actual,
                    p.current_unit_cost AS costo_unitario_actual
                FROM inventory_product p
                """,
                """
                CREATE OR REPLACE VIEW inventory_vw_detalle_almacen AS
                SELECT
                    wd.id AS detalle_id,
                    wd.product_id AS producto_id,
                    wd.warehouse AS almacen,
                    wd.initial_quantity AS cantidad_inicial,
                    wd.initial_value AS valor_inicial
                FROM inventory_warehousedetail wd
                """,
                """
                CREATE OR REPLACE VIEW inventory_vw_movimientos_inventario AS
                SELECT
                    ir.id AS movimiento_id,
                    ir.batch_id AS lote_id,
                    ib.file_name AS archivo_lote,
                    ir.product_id AS producto_id,
                    p.code AS codigo_producto,
                    p.description AS descripcion_producto,
                    ir.warehouse AS almacen,
                    ir.date AS fecha,
                    ir.document_type AS tipo_documento,
                    ir.document_number AS numero_documento,
                    ir.source_document AS documento_origen,
                    ir.source_record AS registro_origen,
                    ir.quantity AS cantidad,
                    ir.unit_cost AS costo_unitario,
                    ir.total AS valor_total,
                    ir.category AS categoria,
                    ir.lote AS lote,
                    ir.final_quantity AS cantidad_final,
                    ir.cost_center AS centro_costo,
                    ir.row_hash AS hash_fila
                FROM inventory_inventoryrecord ir
                INNER JOIN inventory_product p
                    ON p.id = ir.product_id
                LEFT JOIN inventory_importbatch ib
                    ON ib.id = ir.batch_id
                """,
            ],
            reverse_sql=[
                "DROP VIEW IF EXISTS inventory_vw_movimientos_inventario",
                "DROP VIEW IF EXISTS inventory_vw_detalle_almacen",
                "DROP VIEW IF EXISTS inventory_vw_productos",
                "DROP VIEW IF EXISTS inventory_vw_lotes_importacion",
            ],
        ),
    ]
