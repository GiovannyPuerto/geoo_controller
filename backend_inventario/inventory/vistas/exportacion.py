"""Vistas de exportación (Excel/PDF) para reportes de inventario."""

import logging

from django.http import JsonResponse
from django.views.decorators.http import require_http_methods

from ..services.datos_exportacion_service import (
    construir_datos_cortes_mensuales_exportacion,
    construir_datos_analisis_exportacion,
    construir_datos_movimientos_exportacion,
    construir_datos_tops_exportacion,
)
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


@require_http_methods(["GET"])
def export_analysis(request, inventory_name='default'):
    try:
        format_type = request.GET.get('format', 'excel')
        inventory_name_param, analysis_list, filters_txt = construir_datos_analisis_exportacion(
            request,
            inventory_name_default=inventory_name,
        )

        if format_type == 'excel':
            return construir_respuesta_analisis_excel(
                analysis_list,
                inventory_name_param,
                filters_txt=filters_txt,
            )
        if format_type == 'pdf':
            return construir_respuesta_analisis_pdf(
                analysis_list,
                inventory_name_param,
                filters_txt=filters_txt,
            )
        return JsonResponse({'error': 'Formato no soportado'}, status=400)
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

        if format_type == 'excel':
            return construir_respuesta_movimientos_excel(
                movements_data,
                inventory_name_param,
                filters_txt=filters_txt,
            )
        if format_type == 'pdf':
            return construir_respuesta_movimientos_pdf(
                movements_data,
                inventory_name_param,
                filters_txt=filters_txt,
            )
        return JsonResponse({'error': 'Formato no soportado'}, status=400)
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

        if format_type == 'excel':
            return construir_respuesta_cortes_mensuales_excel(payload)
        if format_type == 'pdf':
            return construir_respuesta_cortes_mensuales_pdf(payload)
        return JsonResponse({'error': 'Formato no soportado'}, status=400)
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

        if format_type == 'excel':
            return construir_respuesta_tops_excel(payload)
        if format_type == 'pdf':
            return construir_respuesta_tops_pdf(payload)
        return JsonResponse({'error': 'Formato no soportado'}, status=400)
    except Exception as exc:
        logger.error(f"Error exporting tops: {str(exc)}", exc_info=True)
        return JsonResponse({'error': str(exc)}, status=500)
