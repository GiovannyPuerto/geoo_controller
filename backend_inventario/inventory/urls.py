from django.urls import path
from .views import (
    update_inventory, get_batches, get_products, get_records,
    get_product_analysis, create_inventory, get_product_history,
    get_summary, export_analysis, export_movements, list_inventories,
    upload_base_file, welcome, get_monthly_movements, get_monthly_cuts,
    get_monthly_product_cuts, get_last_update_time, get_inventory_at_date, rollback_batch,
    export_monthly_cuts
)

urlpatterns = [
    path('monthly-movements/', get_monthly_movements, name='get_monthly_movements'),
    path('monthly-cuts/', get_monthly_cuts, name='get_monthly_cuts'),
    path('monthly-cuts-products/', get_monthly_product_cuts, name='get_monthly_product_cuts'),
    path('last-update/', get_last_update_time, name='get_last_update_time'),
    path('upload/', update_inventory, name='upload_excel'),
    path('upload/<str:inventory_name>/', update_inventory, name='upload_excel_with_inventory'),
    path('update/', update_inventory, name='update_inventory'),
    path('update/<str:inventory_name>/', update_inventory, name='update_inventory_with_inventory'),
    path('batches/', get_batches, name='get_batches'),
    path('products/', get_products, name='get_products'),
    path('records/', get_records, name='get_records'),
    path('analysis/', get_product_analysis, name='get_product_analysis'),
    path('product/<str:product_code>/history/', get_product_history, name='get_product_history'),
    path('product/<str:inventory_name>/<str:product_code>/history/', get_product_history, name='get_product_history_with_inventory'),
    # Alias de compatibilidad con clientes antiguos.
    path('product-history/<str:product_code>/', get_product_history, name='get_product_history_alias'),
    path('summary/', get_summary, name='get_summary'),
    path('export-analysis/', export_analysis, name='export_analysis'),
    path('export-analysis/<str:inventory_name>/', export_analysis, name='export_analysis_with_inventory'),
    path('export-movements/', export_movements, name='export_movements'),
    path('export-movements/<str:inventory_name>/', export_movements, name='export_movements_with_inventory'),
    path('export-monthly-cuts/', export_monthly_cuts, name='export_monthly_cuts'),
    path('export-monthly-cuts/<str:inventory_name>/', export_monthly_cuts, name='export_monthly_cuts_with_inventory'),
    path('create/', create_inventory, name='create_inventory'),
    path('create-inventory/', create_inventory, name='create_inventory_alias'),
    path('inventories/', list_inventories, name='list_inventories'),
    path('list-inventories/', list_inventories, name='list_inventories_alias'),
    path('rollback/', rollback_batch, name='rollback_batch'),
    path('upload-base/', upload_base_file, name='upload_base_file'),
    path('upload-base/<str:inventory_name>/', upload_base_file, name='upload_base_file_with_inventory'),
    path('inventory-at-date/', get_inventory_at_date, name='get_inventory_at_date'),
    path('welcome/', welcome, name='welcome'),
]
