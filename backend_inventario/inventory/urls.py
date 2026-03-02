from django.urls import path
from .vistas.escritura import (
    create_inventory,
    rollback_batch,
    update_inventory,
    upload_base_file,
)
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

urlpatterns = [
    path('movimientos-mensuales/', obtener_movimientos_mensuales, name='obtener_movimientos_mensuales'),
    path('cortes-mensuales/', obtener_cortes_mensuales, name='obtener_cortes_mensuales'),
    path('cortes-mensuales-productos/', obtener_cortes_mensuales_productos, name='obtener_cortes_mensuales_productos'),
    path('ultima-actualizacion/', obtener_ultima_actualizacion, name='obtener_ultima_actualizacion'),
    path('cargar/', actualizar_inventario, name='cargar_excel'),
    path('cargar/<str:inventory_name>/', actualizar_inventario, name='cargar_excel_con_inventario'),
    path('actualizar/', actualizar_inventario, name='actualizar_inventario'),
    path('actualizar/<str:inventory_name>/', actualizar_inventario, name='actualizar_inventario_con_inventario'),
    path('lotes/', obtener_lotes, name='obtener_lotes'),
    path('productos/', obtener_productos, name='obtener_productos'),
    path('registros/', obtener_registros, name='obtener_registros'),
    path('analisis-producto/', obtener_analisis_producto, name='obtener_analisis_producto'),
    path('producto/<str:product_code>/historial/', obtener_historial_producto, name='obtener_historial_producto'),
    path('producto/<str:inventory_name>/<str:product_code>/historial/', obtener_historial_producto, name='obtener_historial_producto_con_inventario'),
    path('resumen/', obtener_resumen, name='obtener_resumen'),
    path('exportar-analisis/', exportar_analisis, name='exportar_analisis'),
    path('exportar-analisis/<str:inventory_name>/', exportar_analisis, name='exportar_analisis_con_inventario'),
    path('exportar-movimientos/', exportar_movimientos, name='exportar_movimientos'),
    path('exportar-movimientos/<str:inventory_name>/', exportar_movimientos, name='exportar_movimientos_con_inventario'),
    path('exportar-cortes-mensuales/', exportar_cortes_mensuales, name='exportar_cortes_mensuales'),
    path('exportar-cortes-mensuales/<str:inventory_name>/', exportar_cortes_mensuales, name='exportar_cortes_mensuales_con_inventario'),
    path('exportar-tops/', exportar_tops, name='exportar_tops'),
    path('exportar-tops/<str:inventory_name>/', exportar_tops, name='exportar_tops_con_inventario'),
    path('crear-inventario/', crear_inventario, name='crear_inventario'),
    path('inventarios/', obtener_inventarios, name='obtener_inventarios'),
    path('revertir-lote/', revertir_lote, name='revertir_lote'),
    path('subir-base/', subir_archivo_base, name='subir_archivo_base'),
    path('subir-base/<str:inventory_name>/', subir_archivo_base, name='subir_archivo_base_con_inventario'),
    path('inventario-a-fecha/', obtener_inventario_a_fecha, name='obtener_inventario_a_fecha'),
    path('bienvenida/', bienvenida, name='bienvenida'),
]
