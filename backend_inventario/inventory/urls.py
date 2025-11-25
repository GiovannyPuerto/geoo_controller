from django.urls import path
from .views import (
    update_inventory, get_batches, get_products, get_records,
    get_product_analysis, create_inventory, get_product_history,
    get_summary, export_analysis, list_inventories,
    upload_base_file, welcome, get_monthly_movements, get_last_update_time
)

urlpatterns = [
    path('monthly-movements/', get_monthly_movements, name='get_monthly_movements'),
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
    path('summary/', get_summary, name='get_summary'),
    path('export/excel/', export_analysis, name='export_excel'),
    path('export/excel/<str:inventory_name>/', export_analysis, name='export_excel_with_inventory'),
    path('export/pdf/', export_analysis, {'format_type': 'pdf'}, name='export_pdf'),
    path('export/pdf/<str:inventory_name>/', export_analysis, {'format_type': 'pdf'}, name='export_pdf_with_inventory'),
    path('create/', create_inventory, name='create_inventory'),
    path('inventories/', list_inventories, name='list_inventories'),
    path('upload-base/', upload_base_file, name='upload_base_file'),
    path('upload-base/<str:inventory_name>/', upload_base_file, name='upload_base_file_with_inventory'),
    path('welcome/', welcome, name='welcome'),
]
