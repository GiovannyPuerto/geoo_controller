"""Compatibilidad de vistas legacy.

Este módulo conserva los nombres históricos de endpoints y reexporta la
implementación modular en español ubicada en `inventory.vistas.*`.
"""

from .vistas.escritura import create_inventory, rollback_batch, update_inventory, upload_base_file
from .vistas.exportacion import (
    export_analysis,
    export_monthly_cuts,
    export_movements,
    export_tops,
)
from .vistas.lectura import (
    get_batches,
    get_inventory_at_date,
    get_last_update_time,
    get_monthly_cuts,
    get_monthly_movements,
    get_monthly_product_cuts,
    get_product_analysis,
    get_product_history,
    get_products,
    get_records,
    get_summary,
    list_inventories,
    welcome,
)

# Alias en español para uso interno gradual.
crear_inventario = create_inventory
revertir_lote = rollback_batch
actualizar_inventario = update_inventory
subir_archivo_base = upload_base_file

exportar_analisis = export_analysis
exportar_cortes_mensuales = export_monthly_cuts
exportar_movimientos = export_movements
exportar_tops = export_tops

obtener_lotes = get_batches
obtener_inventario_a_fecha = get_inventory_at_date
obtener_ultima_actualizacion = get_last_update_time
obtener_cortes_mensuales = get_monthly_cuts
obtener_movimientos_mensuales = get_monthly_movements
obtener_cortes_mensuales_productos = get_monthly_product_cuts
obtener_analisis_producto = get_product_analysis
obtener_historial_producto = get_product_history
obtener_productos = get_products
obtener_registros = get_records
obtener_resumen = get_summary
obtener_inventarios = list_inventories
bienvenida = welcome

__all__ = [
    'create_inventory',
    'export_analysis',
    'export_monthly_cuts',
    'export_movements',
    'export_tops',
    'get_batches',
    'get_inventory_at_date',
    'get_last_update_time',
    'get_monthly_cuts',
    'get_monthly_movements',
    'get_monthly_product_cuts',
    'get_product_analysis',
    'get_product_history',
    'get_products',
    'get_records',
    'get_summary',
    'list_inventories',
    'rollback_batch',
    'update_inventory',
    'upload_base_file',
    'welcome',

    'actualizar_inventario',
    'bienvenida',
    'crear_inventario',
    'exportar_analisis',
    'exportar_cortes_mensuales',
    'exportar_movimientos',
    'exportar_tops',
    'obtener_analisis_producto',
    'obtener_cortes_mensuales',
    'obtener_cortes_mensuales_productos',
    'obtener_historial_producto',
    'obtener_inventario_a_fecha',
    'obtener_inventarios',
    'obtener_lotes',
    'obtener_movimientos_mensuales',
    'obtener_productos',
    'obtener_registros',
    'obtener_resumen',
    'obtener_ultima_actualizacion',
    'revertir_lote',
    'subir_archivo_base',
]
