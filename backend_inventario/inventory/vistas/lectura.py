import logging
from datetime import datetime

from django.db.models import F, Value
from django.db.models.functions import Coalesce, Length
from django.http import JsonResponse
from django.views.decorators.cache import cache_page
from django.views.decorators.http import require_http_methods

from ..models import ImportBatch, InventoryRecord, Product
from ..services.analitica_inventario_service import (
    obtener_datos_analisis_producto,
    obtener_datos_cortes_mensuales,
    obtener_datos_cortes_mensuales_por_producto,
    obtener_datos_inventario_a_fecha,
    obtener_datos_movimientos_mensuales,
)
from ..services.consulta_registros_service import (
    aplicar_filtros_registros,
    filtros_registros_desde_request,
    slice_desde_request,
)
from ..services.resumen_inventario_service import obtener_resumen_inventario

logger = logging.getLogger(__name__)

API_CACHE_RAPIDO_SEGUNDOS = 300   # 5 minutos
API_CACHE_PESADO_SEGUNDOS = 600   # 10 minutos


def _ordenar_por_documento_desc(qs):
    """Ordena por última fecha primero y, dentro de la misma fecha, por número
    de documento mayor (más dígitos → mayor valor lexicográfico)."""
    return qs.annotate(
        _doc_number_text=Coalesce('document_number', Value('')),
        _doc_number_len=Length(Coalesce('document_number', Value(''))),
    ).order_by('-date', '-_doc_number_len', '-_doc_number_text', '-id')


@cache_page(API_CACHE_RAPIDO_SEGUNDOS)
@require_http_methods(["GET"])
def get_monthly_movements(request):
    inventory_name = request.GET.get('inventory_name', 'default')
    warehouse_filter = request.GET.get('warehouse', '')
    category_filter = request.GET.get('category', '')
    search_filter = request.GET.get('search', '')

    try:
        result_data = obtener_datos_movimientos_mensuales(
            inventory_name=inventory_name,
            warehouse_filter=warehouse_filter,
            category_filter=category_filter,
            search_filter=search_filter,
        )
        return JsonResponse(result_data, safe=False)
    except Exception as exc:
        logger.error(f"Error in get_monthly_movements: {str(exc)}", exc_info=True)
        return JsonResponse({'error': str(exc)}, status=500)


@cache_page(API_CACHE_RAPIDO_SEGUNDOS)
@require_http_methods(["GET"])
def get_monthly_cuts(request):
    inventory_name = request.GET.get('inventory_name', 'default')
    warehouse_filter = request.GET.get('warehouse', '')
    category_filter = request.GET.get('category', '')
    search_filter = request.GET.get('search', '')
    months = request.GET.get('months', '12')

    try:
        result_data = obtener_datos_cortes_mensuales(
            inventory_name=inventory_name,
            warehouse_filter=warehouse_filter,
            category_filter=category_filter,
            search_filter=search_filter,
            months=months,
        )
        return JsonResponse(result_data)
    except Exception as exc:
        logger.error(f"Error in get_monthly_cuts: {str(exc)}", exc_info=True)
        return JsonResponse({'error': str(exc)}, status=500)


@cache_page(API_CACHE_PESADO_SEGUNDOS)
@require_http_methods(["GET"])
def get_monthly_product_cuts(request):
    inventory_name = request.GET.get('inventory_name', 'default')
    warehouse_filter = request.GET.get('warehouse', '')
    category_filter = request.GET.get('category', '')
    search_filter = request.GET.get('search', '')
    month = request.GET.get('month', '')
    limit = request.GET.get('limit', '')
    offset = request.GET.get('offset', '')
    page_size = request.GET.get('page_size', '')

    try:
        result_data = obtener_datos_cortes_mensuales_por_producto(
            inventory_name=inventory_name,
            target_month=month,
            warehouse_filter=warehouse_filter,
            category_filter=category_filter,
            search_filter=search_filter,
            limit=limit,
            offset=offset,
            page_size=page_size,
        )
        return JsonResponse(result_data)
    except Exception as exc:
        logger.error(f"Error in get_monthly_product_cuts: {str(exc)}", exc_info=True)
        return JsonResponse({'error': str(exc)}, status=500)


@cache_page(API_CACHE_PESADO_SEGUNDOS)
@require_http_methods(["GET"])
def get_product_analysis(request):
    inventory_name = request.GET.get('inventory_name', 'default')
    category_filter = request.GET.get('category', '')
    warehouse_filter = request.GET.get('warehouse', '')
    rotation_filter = request.GET.get('rotation', '')
    stagnant_filter = request.GET.get('stagnant', '')
    high_rotation_filter = request.GET.get('high_rotation', '')
    exact_date = request.GET.get('date', '')
    date_from = request.GET.get('date_from', '')
    date_to = request.GET.get('date_to', '')
    search_filter = request.GET.get('search', '')
    limit = request.GET.get('limit', '')

    if exact_date and not date_to:
        date_to = exact_date

    try:
        analysis_data = obtener_datos_analisis_producto(
            inventory_name=inventory_name,
            category_filter=category_filter,
            warehouse_filter=warehouse_filter,
            rotation_filter=rotation_filter,
            stagnant_filter=stagnant_filter,
            high_rotation_filter=high_rotation_filter,
            date_from=date_from,
            date_to=date_to,
            search_filter=search_filter,
            limit=limit,
        )
        return JsonResponse(analysis_data, safe=False)
    except Exception as exc:
        logger.error(f"Error in product analysis: {str(exc)}", exc_info=True)
        return JsonResponse([], safe=False)


@cache_page(API_CACHE_RAPIDO_SEGUNDOS)
@require_http_methods(["GET"])
def get_batches(request):
    inventory_name = request.GET.get('inventory_name', 'default')
    batches = ImportBatch.objects.filter(inventory_name=inventory_name).order_by('-started_at').values(
        'id', 'file_name', 'inventory_name', 'started_at', 'processed_at', 'rows_imported', 'rows_total', 'checksum'
    )

    batches_data = [{
        'id': batch['id'],
        'file_name': batch['file_name'],
        'inventory_name': batch['inventory_name'],
        'started_at': batch['started_at'].isoformat() if batch['started_at'] else None,
        'processed_at': batch['processed_at'].isoformat() if batch['processed_at'] else None,
        'rows_imported': batch['rows_imported'],
        'rows_total': batch['rows_total'],
        'checksum': batch['checksum'],
    } for batch in batches]
    return JsonResponse(batches_data, safe=False)


@cache_page(API_CACHE_RAPIDO_SEGUNDOS)
@require_http_methods(["GET"])
def get_products(request):
    inventory_name = request.GET.get('inventory_name', 'default')
    products = Product.objects.filter(inventory_name=inventory_name).values(
        'code', 'description', 'group', 'initial_balance', 'initial_unit_cost'
    )
    products_data = [{
        'code': product['code'],
        'description': product['description'],
        'group': product['group'],
        'initial_balance': float(product['initial_balance']),
        'initial_unit_cost': float(product['initial_unit_cost']),
    } for product in products]
    return JsonResponse(products_data, safe=False)


@cache_page(API_CACHE_RAPIDO_SEGUNDOS)
@require_http_methods(["GET"])
def get_records(request):
    filters = filtros_registros_desde_request(request)
    slice_params = slice_desde_request(
        request,
        default_limit=1000,
        max_limit=5000,
        default_offset=0,
        max_offset=50000,
    )

    try:
        records_query = aplicar_filtros_registros(InventoryRecord.objects.all(), filters)

        # Los campos que ya existen en el modelo se listan como args posicionales.
        # Solo los traversals FK se pasan como kwargs (renombrados).
        # Esto evita el conflicto de anotación con campos del modelo.
        records = _ordenar_por_documento_desc(records_query).values(
            'id',
            'warehouse',
            'date',
            'document_type',
            'document_number',
            'quantity',
            'unit_cost',
            'total',
            'category',
            'batch_id',
            product_code=F('product__code'),
            product_description=F('product__description'),
        )[slice_params.offset:slice_params.offset + slice_params.limit]

        records_data = [{
            'id': record['id'],
            'product_code': record['product_code'],
            'product_description': record['product_description'],
            'warehouse': record['warehouse'],
            'date': record['date'].isoformat() if record['date'] else None,
            'document_type': record['document_type'],
            'document_number': record['document_number'],
            'quantity': float(record['quantity']),
            'unit_cost': float(record['unit_cost']),
            'total': float(record['total']),
            'category': record['category'],
            'batch_id': record['batch_id'],
        } for record in records]
        return JsonResponse(records_data, safe=False)

    except Exception as exc:
        logger.error(f"Error en obtener registros: {str(exc)}", exc_info=True)
        return JsonResponse([], safe=False)


@cache_page(API_CACHE_RAPIDO_SEGUNDOS)
@require_http_methods(["GET"])
def get_product_history(request, product_code, inventory_name='default'):
    try:
        slice_params = slice_desde_request(
            request,
            default_limit=2000,
            max_limit=10000,
            default_offset=0,
            max_offset=50000,
        )

        records = InventoryRecord.objects.filter(
            product__code=product_code,
            product__inventory_name=inventory_name
        ).order_by('date').values(
            'id',
            'date',
            'quantity',
            'unit_cost',
            'total',
            'warehouse',
            'document_type',
            'document_number',
            batch_id=F('batch_id'),
        )[slice_params.offset:slice_params.offset + slice_params.limit]

        history_data = [{
            'id': record['id'],
            'date': record['date'].isoformat() if record['date'] else None,
            'quantity': float(record['quantity']),
            'unit_cost': float(record['unit_cost']),
            'total': float(record['total']),
            'warehouse': record['warehouse'],
            'document_type': record['document_type'],
            'document_number': record['document_number'],
            'batch_id': record['batch_id'],
        } for record in records]

        return JsonResponse(history_data, safe=False)
    except Exception as exc:
        logger.error(f"Error retrieving product history: {str(exc)}", exc_info=True)
        return JsonResponse([], safe=False)


@cache_page(API_CACHE_RAPIDO_SEGUNDOS)
@require_http_methods(["GET"])
def get_summary(request):
    inventory_name = request.GET.get('inventory_name', 'default')
    try:
        summary_data = obtener_resumen_inventario(inventory_name=inventory_name)
        return JsonResponse(summary_data)
    except Exception as exc:
        logger.error(f"Error retrieving summary: {str(exc)}", exc_info=True)
        return JsonResponse({'error': str(exc)}, status=500)


@cache_page(API_CACHE_RAPIDO_SEGUNDOS)
@require_http_methods(["GET"])
def list_inventories(request):
    try:
        inventories = Product.objects.order_by('inventory_name').values_list('inventory_name', flat=True).distinct()
        return JsonResponse(list(inventories), safe=False)
    except Exception as exc:
        logger.error(f"Error listing inventories: {str(exc)}", exc_info=True)
        return JsonResponse([], safe=False)


@cache_page(API_CACHE_RAPIDO_SEGUNDOS)
@require_http_methods(["GET"])
def get_last_update_time(request):
    inventory_name = request.GET.get('inventory_name', 'default')
    try:
        last_batch = ImportBatch.objects.filter(
            inventory_name=inventory_name,
            processed_at__isnull=False,
        ).order_by('-processed_at').first()

        if last_batch:
            return JsonResponse({'last_update': last_batch.processed_at.isoformat()})
        return JsonResponse({'last_update': None})
    except Exception as exc:
        logger.error(f"Error retrieving last update time: {str(exc)}", exc_info=True)
        return JsonResponse({'error': str(exc)}, status=500)


@cache_page(API_CACHE_PESADO_SEGUNDOS)
@require_http_methods(["GET"])
def get_inventory_at_date(request):
    inventory_name = request.GET.get('inventory_name', 'default')
    date_str = request.GET.get('date', '')
    warehouse_filter = request.GET.get('warehouse', '')
    category_filter = request.GET.get('category', '')

    if not date_str:
        return JsonResponse({'error': 'Date parameter is required (format: YYYY-MM-DD)'}, status=400)

    try:
        target_date = datetime.strptime(date_str, '%Y-%m-%d').date()
    except ValueError:
        return JsonResponse({'error': 'Invalid date format. Use YYYY-MM-DD'}, status=400)

    try:
        data = obtener_datos_inventario_a_fecha(
            inventory_name=inventory_name,
            date_str=date_str,
            target_date=target_date,
            warehouse_filter=warehouse_filter,
            category_filter=category_filter,
        )
        return JsonResponse(data)

    except Exception as exc:
        logger.error(f"Error calculating inventory at date: {str(exc)}", exc_info=True)
        return JsonResponse({'error': str(exc)}, status=500)


@require_http_methods(["GET"])
def welcome(request):
    logger.info(f"Request received: {request.method} {request.path}")
    return JsonResponse({'message': 'Bienvenido a el sistema de analisis de inventarios'})
