import json
import logging
import os

from django.core.cache import caches
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods

from ..models import ImportBatch, InventoryRecord, Product
from ..services.importacion_inventario_service import procesar_importacion

logger = logging.getLogger(__name__)


def _invalidate_inventory_caches() -> None:
    """
    Limpia caches relevantes tras mutaciones de inventario.

    Incluye cache por defecto (vistas/API) y cache de exportaciones
    para evitar respuestas stale y blobs huérfanos en disco.
    """
    export_alias = os.environ.get("INVENTORY_EXPORT_CACHE_ALIAS", "exports").strip() or "exports"
    aliases = {"default", export_alias}
    for alias in aliases:
        try:
            caches[alias].clear()
        except Exception:
            logger.warning("No se pudo limpiar el cache alias '%s'.", alias, exc_info=True)


@csrf_exempt
@require_http_methods(["POST"])
def update_inventory(request, inventory_name='default'):
    response = procesar_importacion(request, inventory_name)
    if response.status_code < 400:
        _invalidate_inventory_caches()
    return response


@require_http_methods(["POST"])
def create_inventory(request):
    try:
        data = json.loads(request.body)
        inventory_name = data.get('inventory_name', '').strip().lower()
        if not inventory_name:
            return JsonResponse({'ok': False, 'error': 'Nombre de inventario requerido'}, status=400)

        if Product.objects.filter(inventory_name=inventory_name).exists():
            return JsonResponse({'ok': False, 'error': 'El inventario ya existe'}, status=400)

        return JsonResponse({'ok': True, 'inventory_name': inventory_name})
    except Exception as exc:
        logger.error(f"Error creating inventory: {str(exc)}", exc_info=True)
        return JsonResponse({'ok': False, 'error': str(exc)}, status=500)


@csrf_exempt
@require_http_methods(["POST"])
def rollback_batch(request):
    inventory_name = request.GET.get('inventory_name', 'default')

    try:
        body = json.loads(request.body) if request.body else {}
    except json.JSONDecodeError:
        return JsonResponse({'ok': False, 'error': 'JSON inválido'}, status=400)

    inventory_name = str(body.get('inventory_name', inventory_name)).strip().lower() or 'default'
    batch_id = body.get('batch_id')

    try:
        batches_qs = ImportBatch.objects.filter(inventory_name=inventory_name).order_by('-processed_at', '-id')
        if batch_id:
            batches_qs = batches_qs.filter(id=batch_id)
        else:
            batch_ids_with_records = InventoryRecord.objects.filter(
                product__inventory_name=inventory_name
            ).values_list('batch_id', flat=True).distinct()
            batches_qs = batches_qs.filter(id__in=batch_ids_with_records)

        batch = batches_qs.first()
        if not batch:
            return JsonResponse(
                {'ok': False, 'error': 'No se encontró el lote a revertir para ese inventario'},
                status=404,
            )

        records_qs = InventoryRecord.objects.filter(
            batch=batch,
            product__inventory_name=inventory_name,
        )
        records_count = records_qs.count()
        if records_count == 0:
            return JsonResponse(
                {
                    'ok': False,
                    'error': 'El lote seleccionado no tiene movimientos para revertir (posible lote base).',
                },
                status=400,
            )

        deleted_rows, _ = records_qs.delete()
        batch_info = {
            'id': batch.id,
            'file_name': batch.file_name,
            'processed_at': batch.processed_at.isoformat() if batch.processed_at else None,
        }
        batch.delete()

        _invalidate_inventory_caches()
        return JsonResponse(
            {
                'ok': True,
                'inventory_name': inventory_name,
                'rolled_back_batch': batch_info,
                'deleted_rows': deleted_rows,
                'deleted_records': records_count,
            }
        )
    except Exception as exc:
        logger.error(f"Error rolling back batch: {str(exc)}", exc_info=True)
        return JsonResponse({'ok': False, 'error': str(exc)}, status=500)


@csrf_exempt
@require_http_methods(["POST"])
def upload_base_file(request, inventory_name='default'):
    return update_inventory(request, inventory_name)


@csrf_exempt
@require_http_methods(["POST"])
def save_ideal_inventory(request, inventory_name='default'):
    """Guarda (upsert) los valores ideales por grupo del inventario."""
    try:
        body = json.loads(request.body) if request.body else {}
    except json.JSONDecodeError:
        return JsonResponse({'ok': False, 'error': 'JSON inválido'}, status=400)

    inventory_name = str(body.get('inventory_name', inventory_name)).strip().lower() or 'default'
    values = body.get('values', {})

    if not isinstance(values, dict):
        return JsonResponse({'ok': False, 'error': 'Se esperaba {grupo: valor}'}, status=400)

    from ..models import IdealInventoryGroup
    for grupo, valor in values.items():
        try:
            val = float(valor)
        except (TypeError, ValueError):
            continue
        grupo = str(grupo).strip()
        if not grupo:
            continue
        if val > 0:
            IdealInventoryGroup.objects.update_or_create(
                nombre_inventario=inventory_name,
                grupo=grupo,
                defaults={'valor_ideal': val},
            )
        else:
            IdealInventoryGroup.objects.filter(
                nombre_inventario=inventory_name,
                grupo=grupo,
            ).delete()

    return JsonResponse({'ok': True})
