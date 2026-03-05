"""Vistas de exportación (Excel/PDF) para reportes de inventario."""

import hashlib
import json
import logging
import os
import threading

from django.core.cache import cache, caches
from django.http import HttpResponse
from django.http import JsonResponse
from django.views.decorators.http import require_http_methods

from ..services.datos_exportacion_service import (
    construir_datos_cortes_mensuales_exportacion,
    construir_datos_analisis_exportacion,
    construir_datos_movimientos_exportacion,
    construir_datos_tops_exportacion,
)
from ..services.cache_version_service import get_inventory_cache_version
from ..services.render_exportacion_service import (
    construir_respuesta_cortes_mensuales_excel,
    construir_respuesta_cortes_mensuales_pdf,
    construir_respuesta_analisis_excel,
    construir_respuesta_analisis_pdf,
    construir_respuesta_movimientos_excel,
    construir_respuesta_movimientos_pdf,
    construir_respuesta_tops_excel,
    construir_respuesta_tops_pdf,
)

logger = logging.getLogger(__name__)
EXPORT_RESPONSE_CACHE_TTL_SECONDS = int(
    os.environ.get("INVENTORY_EXPORT_RESPONSE_CACHE_TTL_SECONDS", "900")
)
EXPORT_RESPONSE_CACHE_MAX_BYTES = int(
    os.environ.get("INVENTORY_EXPORT_RESPONSE_CACHE_MAX_BYTES", str(20 * 1024 * 1024))
)
EXPORT_CACHE_ALIAS = os.environ.get("INVENTORY_EXPORT_CACHE_ALIAS", "exports")
_EXPORT_LOCKS: dict[str, threading.Lock] = {}
_EXPORT_LOCKS_GUARD = threading.Lock()


def _export_cache_backend():
    try:
        return caches[EXPORT_CACHE_ALIAS]
    except Exception:
        logger.warning(
            "Cache alias '%s' no disponible. Se usa cache por defecto.", EXPORT_CACHE_ALIAS
        )
        return cache


def _get_export_lock(cache_key: str) -> threading.Lock:
    with _EXPORT_LOCKS_GUARD:
        lock = _EXPORT_LOCKS.get(cache_key)
        if lock is None:
            lock = threading.Lock()
            _EXPORT_LOCKS[cache_key] = lock
        return lock


def _release_export_lock(cache_key: str) -> None:
    """Elimina el lock del dict global una vez que ya no se necesita,
    evitando el crecimiento indefinido de _EXPORT_LOCKS."""
    with _EXPORT_LOCKS_GUARD:
        _EXPORT_LOCKS.pop(cache_key, None)


def _build_export_cache_key(export_name: str, inventory_name: str, request) -> str:
    data_version = get_inventory_cache_version(inventory_name)
    payload = {
        "export_name": export_name,
        "inventory_name": inventory_name,
        "data_version": data_version,
        "query": dict(request.GET.items()),
    }
    src = json.dumps(payload, sort_keys=True, ensure_ascii=False)
    digest = hashlib.sha256(src.encode("utf-8")).hexdigest()
    return f"export:v2:{digest}"


def _build_response_from_blob(blob: dict) -> HttpResponse:
    response = HttpResponse(
        blob.get("content", b""),
        content_type=blob.get("content_type", "application/octet-stream"),
        status=int(blob.get("status_code", 200)),
    )
    content_disposition = blob.get("content_disposition", "")
    if content_disposition:
        response["Content-Disposition"] = content_disposition
    return response


def _resolve_cached_export_response(cache_key: str, build_response):
    if EXPORT_RESPONSE_CACHE_TTL_SECONDS <= 0:
        return build_response()

    export_cache = _export_cache_backend()
    cached_blob = export_cache.get(cache_key)
    if cached_blob is not None:
        logger.info("Export cache hit: key=%s", cache_key)
        return _build_response_from_blob(cached_blob)

    lock = _get_export_lock(cache_key)
    with lock:
        try:
            cached_blob = export_cache.get(cache_key)
            if cached_blob is not None:
                logger.info("Export cache hit (post-lock): key=%s", cache_key)
                return _build_response_from_blob(cached_blob)

            response = build_response()
            if 200 <= response.status_code < 300:
                content_bytes = bytes(response.content)
                content_size = len(content_bytes)
                if (
                    EXPORT_RESPONSE_CACHE_MAX_BYTES <= 0
                    or content_size <= EXPORT_RESPONSE_CACHE_MAX_BYTES
                ):
                    export_cache.set(
                        cache_key,
                        {
                            "status_code": response.status_code,
                            "content_type": response.get("Content-Type", ""),
                            "content_disposition": response.get(
                                "Content-Disposition", ""
                            ),
                            "content": content_bytes,
                        },
                        timeout=EXPORT_RESPONSE_CACHE_TTL_SECONDS,
                    )
                else:
                    logger.info(
                        "Export cache skip (too large): key=%s size=%s max=%s",
                        cache_key,
                        content_size,
                        EXPORT_RESPONSE_CACHE_MAX_BYTES,
                    )
            return response
        finally:
            _release_export_lock(cache_key)


@require_http_methods(["GET"])
def export_analysis(request, inventory_name='default'):
    try:
        format_type = request.GET.get('format', 'excel')
        inventory_name_param, analysis_list, filters_txt = construir_datos_analisis_exportacion(
            request,
            inventory_name_default=inventory_name,
        )

        if format_type not in {'excel', 'pdf'}:
            return JsonResponse({'error': 'Formato no soportado'}, status=400)

        cache_key = _build_export_cache_key("analysis", inventory_name_param, request)

        def _build():
            if format_type == 'excel':
                return construir_respuesta_analisis_excel(
                    analysis_list,
                    inventory_name_param,
                    filters_txt=filters_txt,
                )
            return construir_respuesta_analisis_pdf(
                analysis_list,
                inventory_name_param,
                filters_txt=filters_txt,
            )

        return _resolve_cached_export_response(cache_key, _build)
    except Exception as exc:
        logger.error(f"Error exporting analysis: {str(exc)}", exc_info=True)
        return JsonResponse({'error': str(exc)}, status=500)


@require_http_methods(["GET"])
def export_movements(request, inventory_name='default'):
    try:
        format_type = request.GET.get('format', 'excel')
        inventory_name_param, movements_data, filters_txt = construir_datos_movimientos_exportacion(
            request,
            inventory_name_default=inventory_name,
        )

        if format_type not in {'excel', 'pdf'}:
            return JsonResponse({'error': 'Formato no soportado'}, status=400)

        cache_key = _build_export_cache_key("movements", inventory_name_param, request)

        def _build():
            if format_type == 'excel':
                return construir_respuesta_movimientos_excel(
                    movements_data,
                    inventory_name_param,
                    filters_txt=filters_txt,
                )
            return construir_respuesta_movimientos_pdf(
                movements_data,
                inventory_name_param,
                filters_txt=filters_txt,
            )

        return _resolve_cached_export_response(cache_key, _build)
    except Exception as exc:
        logger.error(f"Error exporting movements: {str(exc)}", exc_info=True)
        return JsonResponse({'error': str(exc)}, status=500)


@require_http_methods(["GET"])
def export_monthly_cuts(request, inventory_name='default'):
    try:
        format_type = request.GET.get('format', 'excel')
        payload = construir_datos_cortes_mensuales_exportacion(
            request,
            inventory_name_default=inventory_name,
        )

        if format_type not in {'excel', 'pdf'}:
            return JsonResponse({'error': 'Formato no soportado'}, status=400)

        cache_key = _build_export_cache_key("monthly_cuts", payload['inventory_name'], request)

        def _build():
            if format_type == 'excel':
                return construir_respuesta_cortes_mensuales_excel(payload)
            return construir_respuesta_cortes_mensuales_pdf(payload)

        return _resolve_cached_export_response(cache_key, _build)
    except Exception as exc:
        logger.error(f"Error exporting monthly cuts: {str(exc)}", exc_info=True)
        return JsonResponse({'error': str(exc)}, status=500)


@require_http_methods(["GET"])
def export_tops(request, inventory_name='default'):
    try:
        format_type = request.GET.get('format', 'excel')
        payload = construir_datos_tops_exportacion(
            request,
            inventory_name_default=inventory_name,
        )

        if format_type not in {'excel', 'pdf'}:
            return JsonResponse({'error': 'Formato no soportado'}, status=400)

        cache_key = _build_export_cache_key("tops", payload['inventory_name'], request)

        def _build():
            if format_type == 'excel':
                return construir_respuesta_tops_excel(payload)
            return construir_respuesta_tops_pdf(payload)

        return _resolve_cached_export_response(cache_key, _build)
    except Exception as exc:
        logger.error(f"Error exporting tops: {str(exc)}", exc_info=True)
        return JsonResponse({'error': str(exc)}, status=500)
