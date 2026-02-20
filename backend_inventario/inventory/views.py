import logging
import json
from datetime import datetime

from io import BytesIO
import pandas as pd

from django.http import JsonResponse, HttpResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from django.db.models import Q

from .models import ImportBatch, Product, InventoryRecord
from .services.analytics_service import (
    get_inventory_at_date_data,
    get_monthly_movements_data,
    get_product_analysis_data,
)
from .services.import_service import procesar_importacion_inventario
from .services.summary_service import get_inventory_summary_data

logger = logging.getLogger(__name__)


@csrf_exempt
@require_http_methods(["POST"])
def update_inventory(request, inventory_name='default'):
    """
    Endpoint HTTP para importación de inventario.

    La lógica de negocio y procesamiento de archivos se delega al
    servicio `inventory.services.import_service`.
    """
    return procesar_importacion_inventario(request, inventory_name)

@require_http_methods(["GET"])
def get_monthly_movements(request):
    """
    Retorna entradas, salidas y saldo de cierre de los últimos 12 meses.
    """
    inventory_name = request.GET.get('inventory_name', 'default')
    warehouse_filter = request.GET.get('warehouse', '')
    category_filter = request.GET.get('category', '')
    search_filter = request.GET.get('search', '')

    try:
        result_data = get_monthly_movements_data(
            inventory_name=inventory_name,
            warehouse_filter=warehouse_filter,
            category_filter=category_filter,
            search_filter=search_filter,
        )
        return JsonResponse(result_data, safe=False)
    except Exception as e:
        logger.error(f"Error in get_monthly_movements: {str(e)}", exc_info=True)
        return JsonResponse({'error': str(e)}, status=500)


@require_http_methods(["GET"])
def get_product_analysis(request):
    """
    Retorna el análisis de productos con filtros de rotación y estancamiento.
    """
    inventory_name = request.GET.get('inventory_name', 'default')
    category_filter = request.GET.get('category', '')
    warehouse_filter = request.GET.get('warehouse', '')
    rotation_filter = request.GET.get('rotation', '')
    stagnant_filter = request.GET.get('stagnant', '')
    high_rotation_filter = request.GET.get('high_rotation', '')
    date_from = request.GET.get('date_from', '')
    date_to = request.GET.get('date_to', '')
    search_filter = request.GET.get('search', '')
    limit = request.GET.get('limit', '')

    try:
        analysis_data = get_product_analysis_data(
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
    except Exception as e:
        logger.error(f"Error in product analysis: {str(e)}", exc_info=True)
        return JsonResponse([], safe=False)



@require_http_methods(["GET"])
def get_batches(request):
    """
    Retrieves a list of import batches for the specified inventory.

    Args:
        request: Django HttpRequest with query parameter 'inventory_name'

    Returns:
        JsonResponse: List of batch data including IDs, file names, timestamps, and processing stats
    """
    inventory_name = request.GET.get('inventory_name', 'default')
    batches = ImportBatch.objects.filter(inventory_name=inventory_name).order_by('-started_at')
    
    batches_data = [{
        'id': batch.id,
        'file_name': batch.file_name,
        'inventory_name': batch.inventory_name,
        'started_at': batch.started_at.isoformat(),
        'processed_at': batch.processed_at.isoformat() if batch.processed_at else None,
        'rows_imported': batch.rows_imported,
        'rows_total': batch.rows_total,
        'checksum': batch.checksum,
    } for batch in batches]
    return JsonResponse(batches_data, safe=False)

@require_http_methods(["GET"])
def get_products(request):
    """
    Retrieves a list of products for the specified inventory.

    Args:
        request: Django HttpRequest with query parameter 'inventory_name'

    Returns:
        JsonResponse: List of product data including codes, descriptions, groups, and balances
    """
    inventory_name = request.GET.get('inventory_name', 'default')
    products = Product.objects.filter(inventory_name=inventory_name)
    products_data = [{
        'code': p.code,
        'description': p.description,
        'group': p.group,
        'initial_balance': float(p.initial_balance),
        'initial_unit_cost': float(p.initial_unit_cost),
    } for p in products]
    return JsonResponse(products_data, safe=False)

@require_http_methods(["GET"])
def get_records(request):
    """
    Retrieves inventory records with optional filtering.

    Args:
        request: Django HttpRequest with query parameters for filtering

    Query Parameters:
        inventory_name (str): Name of the inventory
        warehouse (str): Filter by warehouse
        category (str): Filter by category
        date_from (str): Start date filter
        date_to (str): End date filter
        search (str): Search by product code or description

    Returns:
        JsonResponse: List of inventory records or empty list on error
    """
    inventory_name = request.GET.get('inventory_name', 'default')
    warehouse_filter = request.GET.get('warehouse', '')
    category_filter = request.GET.get('category', '')
    date_from = request.GET.get('date_from', '')
    date_to = request.GET.get('date_to', '')
    search_filter = request.GET.get('search', '')

    try:
        records_query = InventoryRecord.objects.filter(
            product__inventory_name=inventory_name
        ).select_related('product', 'batch').only(
            'id', 'warehouse', 'date', 'document_type', 'document_number',
            'quantity', 'unit_cost', 'total', 'category',
            'product__code', 'product__description', 'batch__id'
        )

        # Aplicar filtros
        if warehouse_filter:
            records_query = records_query.filter(warehouse__icontains=warehouse_filter)
        if category_filter:
            records_query = records_query.filter(category__icontains=category_filter)
        if date_from:
            records_query = records_query.filter(date__gte=date_from)
        if date_to:
            records_query = records_query.filter(date__lte=date_to)
        if search_filter:
            records_query = records_query.filter(
                Q(product__code__icontains=search_filter) | Q(product__description__icontains=search_filter)
            )

        # Limit records for performance - return only recent 1000 records
        records = records_query.order_by('-date')[:1000]
        records_data = [{
            'id': r.id,
            'product_code': r.product.code,
            'product_description': r.product.description,
            'warehouse': r.warehouse,
            'date': r.date.isoformat(),
            'document_type': r.document_type,
            'document_number': r.document_number,
            'quantity': float(r.quantity),
            'unit_cost': float(r.unit_cost),
            'total': float(r.total),
            'category': r.category,
            'batch_id': r.batch.id,
        } for r in records]
        return JsonResponse(records_data, safe=False)

    except Exception as e:
        logger.error(f"Error retrieving records: {str(e)}", exc_info=True)
        return JsonResponse([], safe=False)


@require_http_methods(["POST"])
def create_inventory(request):
    """
    Creates a new inventory.

    Args:
        request: Django HttpRequest with inventory data

    Returns:
        JsonResponse: Success or error response
    """
    try:
        data = json.loads(request.body)
        inventory_name = data.get('inventory_name', '').strip().lower()
        if not inventory_name:
            return JsonResponse({'ok': False, 'error': 'Nombre de inventario requerido'}, status=400)

        # Check if inventory already exists
        if Product.objects.filter(inventory_name=inventory_name).exists():
            return JsonResponse({'ok': False, 'error': 'El inventario ya existe'}, status=400)

        return JsonResponse({'ok': True, 'inventory_name': inventory_name})
    except Exception as e:
        logger.error(f"Error creating inventory: {str(e)}", exc_info=True)
        return JsonResponse({'ok': False, 'error': str(e)}, status=500)


@require_http_methods(["GET"])
def get_product_history(request, product_code, inventory_name='default'):
    """
    Retrieves the history of movements for a specific product.

    Args:
        request: Django HttpRequest
        product_code (str): Product code
        inventory_name (str): Inventory name

    Returns:
        JsonResponse: List of product movement records
    """
    try:
        records = InventoryRecord.objects.filter(
            product__code=product_code,
            product__inventory_name=inventory_name
        ).select_related('product', 'batch').order_by('date')

        history_data = [{
            'id': r.id,
            'date': r.date.isoformat(),
            'quantity': float(r.quantity),
            'unit_cost': float(r.unit_cost),
            'total': float(r.total),
            'warehouse': r.warehouse,
            'document_type': r.document_type,
            'document_number': r.document_number,
            'batch_id': r.batch.id,
        } for r in records]

        return JsonResponse(history_data, safe=False)
    except Exception as e:
        logger.error(f"Error retrieving product history: {str(e)}", exc_info=True)
        return JsonResponse([], safe=False)


@require_http_methods(["GET"])
def get_summary(request):
    """
    Retrieves a summary of the inventory.

    Args:
        request: Django HttpRequest

    Returns:
        JsonResponse: Inventory summary data
    """
    inventory_name = request.GET.get('inventory_name', 'default')
    try:
        summary_data = get_inventory_summary_data(inventory_name=inventory_name)
        return JsonResponse(summary_data)
    except Exception as e:
        logger.error(f"Error retrieving summary: {str(e)}", exc_info=True)
        return JsonResponse({'error': str(e)}, status=500)


@require_http_methods(["GET"])
def export_analysis(request, inventory_name='default'):
    """
    Exports product analysis data.

    Args:
        request: Django HttpRequest
        inventory_name (str): Inventory name

    Returns:
        HttpResponse: File response
    """
    try:
        # Get format from query params
        format_type = request.GET.get('format', 'excel')

        #
        analysis_response = get_product_analysis(request)
        analysis_data = analysis_response.content.decode('utf-8')
        analysis_list = json.loads(analysis_data)

        if format_type == 'excel':
            # Create Excel file with proper column widths
            df = pd.DataFrame(analysis_list)
            buffer = BytesIO()
            with pd.ExcelWriter(buffer, engine='openpyxl') as writer:
                df.to_excel(writer, index=False, sheet_name='Analysis')
                workbook = writer.book
                worksheet = writer.sheets['Analysis']
                # Set column widths to prevent overlapping
                column_widths = {
                    'A': 15,  # codigo
                    'B': 40,  # nombre_producto
                    'C': 20,  # grupo
                    'D': 18,  # cantidad_saldo_actual
                    'E': 18,  # valor_saldo_actual
                    'F': 18,  # costo_unitario
                    'G': 12,  # consumed
                    'H': 12,  # estancado
                    'I': 15,  # rotacion
                    'J': 15,  # alta_rotacion
                    'K': 25   # almacen
                }
                for col, width in column_widths.items():
                    worksheet.column_dimensions[col].width = width
            buffer.seek(0)
            response = HttpResponse(buffer.getvalue(), content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
            response['Content-Disposition'] = f'attachment; filename="inventory_analysis_{inventory_name}.xlsx"'
            return response
        elif format_type == 'pdf':
            try:
                from reportlab.lib import colors
                from reportlab.lib.pagesizes import A4, landscape
                from reportlab.platypus import (
                    Paragraph,
                    SimpleDocTemplate,
                    Spacer,
                    Table,
                    TableStyle,
                )
                from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
            except ImportError:
                return JsonResponse(
                    {
                        'error': (
                            'Exportación PDF no disponible: falta la librería '
                            '"reportlab". Instala dependencias con '
                            '`pip install -r backend_inventario/requirements.txt`.'
                        )
                    },
                    status=503
                )

            # Create PDF file in landscape orientation
            buffer = BytesIO()
            doc = SimpleDocTemplate(buffer, pagesize=landscape(A4))
            elements = []

            # Use Times fonts which support Unicode/Latin characters
            styles = getSampleStyleSheet()
            title_style = ParagraphStyle(
                'CustomTitle',
                parent=styles['Title'],
                fontName='Times-Bold',
                fontSize=18,
            )
            title = Paragraph(f"Análisis de Inventario - {datetime.now().strftime('%Y-%m-%d')}", title_style)
            elements.append(title)
            elements.append(Spacer(1, 12))

            # Prepare data for table
            if analysis_list:
                # Create styles for text wrapping
                normal_style = ParagraphStyle(
                    'Normal',
                    parent=styles['Normal'],
                    fontName='Times-Roman',
                    fontSize=7,
                    wordWrap='LTR',
                    splitLongWords=True,
                    leading=9,  # Line spacing
                )
                header_style = ParagraphStyle(
                    'Header',
                    parent=styles['Normal'],
                    fontName='Times-Bold',
                    fontSize=9,
                    alignment=1,  # Center
                )

                headers = [
                    Paragraph('Código', header_style),
                    Paragraph('Producto', header_style),
                    Paragraph('Grupo', header_style),
                    Paragraph('Cantidad Actual', header_style),
                    Paragraph('Valor Actual', header_style),
                    Paragraph('Costo Unitario', header_style),
                    Paragraph('Estancado', header_style),
                    Paragraph('Rotación', header_style),
                    Paragraph('Alta Rotación', header_style),
                    Paragraph('Almacén', header_style)
                ]
                formatted_data = []
                for item in analysis_list:
                    formatted_item = [
                        Paragraph(str(item['codigo']), normal_style),
                        Paragraph(str(item['nombre_producto']), normal_style),
                        Paragraph(str(item['grupo']), normal_style),
                        Paragraph(f"{item['cantidad_saldo_actual']:,.2f}", normal_style),
                        Paragraph(f"${item['valor_saldo_actual']:,.2f}", normal_style),
                        Paragraph(f"${item['costo_unitario']:,.2f}", normal_style),
                        Paragraph(str(item['consumed']), normal_style),
                        Paragraph(str(item['estancado']), normal_style),
                        Paragraph(str(item['rotacion']), normal_style),
                        Paragraph(str(item['alta_rotacion']), normal_style),
                        Paragraph(str(item['almacen']), normal_style),
                    ]
                    formatted_data.append(formatted_item)
                data = [headers] + formatted_data

                # Define column widths to fit landscape A4 page (842 points total)
                colWidths = [57, 130, 71, 71, 78, 71, 57, 57, 64, 64, 105]

                # Create table with column widths
                table = Table(data, colWidths=colWidths, repeatRows=1)  # Repeat headers on each page
                style = TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.green),
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                    ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                    ('ALIGN', (3, 1), (5, -1), 'CENTER'),  # Alineacion de columna numericas
                    ('FONTNAME', (0, 0), (-1, 0), 'Times-Bold'),
                    ('FONTSIZE', (0, 0), (-1, 0), 9),
                    ('BOTTOMPADDING', (0, 0), (-1, 0), 4),
                    ('TOPPADDING', (0, 0), (-1, 0), 4),
                    ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.black),
                    ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                    ('LEFTPADDING', (0, 0), (-1, -1), 2),
                    ('RIGHTPADDING', (0, 0), (-1, -1), 2),
                ])
                table.setStyle(style)
                elements.append(table)

            try:
                doc.build(elements)
                buffer.seek(0)
                pdf_content = buffer.getvalue()
                if not pdf_content:
                    logger.error("PDF buffer is empty after build")
                    return JsonResponse({'error': 'PDF generation failed - empty content'}, status=500)
            except Exception as e:
                logger.error(f"Error building PDF: {str(e)}", exc_info=True)
                return JsonResponse({'error': f'PDF generation failed: {str(e)}'}, status=500)

            response = HttpResponse(buffer.getvalue(), content_type='application/pdf')
            response['Content-Disposition'] = f'attachment; filename="inventory_analysis_{inventory_name}.pdf"'
            return response
        else:
            return JsonResponse({'error': 'Formato no soportado'}, status=400)
    except Exception as e:
        logger.error(f"Error exporting analysis: {str(e)}", exc_info=True)
        return JsonResponse({'error': str(e)}, status=500)


@require_http_methods(["GET"])
def export_movements(request, inventory_name='default'):
    """
    Exports inventory movements data.

    Args:
        request: Django HttpRequest
        inventory_name (str): Inventory name

    Returns:
        HttpResponse: File response
    """
    try:
        # Get format from query params
        format_type = request.GET.get('format', 'excel')

        # Get movements data using the same filtering as get_records
        inventory_name_param = request.GET.get('inventory_name', inventory_name)
        warehouse_filter = request.GET.get('warehouse', '')
        category_filter = request.GET.get('category', '')
        date_from = request.GET.get('date_from', '')
        date_to = request.GET.get('date_to', '')
        search_filter = request.GET.get('search', '')

        records_query = InventoryRecord.objects.filter(product__inventory_name=inventory_name_param).select_related('product', 'batch')

        # Apply filters
        if warehouse_filter:
            records_query = records_query.filter(warehouse__icontains=warehouse_filter)
        if category_filter:
            records_query = records_query.filter(category__icontains=category_filter)
        if date_from:
            records_query = records_query.filter(date__gte=date_from)
        if date_to:
            records_query = records_query.filter(date__lte=date_to)
        if search_filter:
            records_query = records_query.filter(
                Q(product__code__icontains=search_filter) | Q(product__description__icontains=search_filter)
            )

        # Limit records for performance - export up to 5000 records
        records = records_query.order_by('-date')[:5000]
        movements_data = [{
            'fecha': r.date.isoformat(),
            'codigo': r.product.code,
            'nombre_producto': r.product.description,
            'almacen': r.warehouse,
            'tipo_documento': r.document_type,
            'documento': r.document_number,
            'cantidad': float(r.quantity),
            'costo_unitario': float(r.unit_cost),
            'costo_total': float(r.total),
            'categoria': r.category,
        } for r in records]

        if format_type == 'excel':
            # Cracion archivo excel
            df = pd.DataFrame(movements_data)
            response = HttpResponse(content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
            response['Content-Disposition'] = f'attachment; filename="movimientos_inventario_{inventory_name_param}.xlsx"'
            df.to_excel(response, index=False)
            return response
        elif format_type == 'pdf':
            try:
                from reportlab.lib import colors
                from reportlab.lib.pagesizes import A4, landscape
                from reportlab.platypus import (
                    Paragraph,
                    SimpleDocTemplate,
                    Spacer,
                    Table,
                    TableStyle,
                )
                from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
            except ImportError:
                return JsonResponse(
                    {
                        'error': (
                            'Exportación PDF no disponible: falta la librería '
                            '"reportlab". Instala dependencias con '
                            '`pip install -r backend_inventario/requirements.txt`.'
                        )
                    },
                    status=503
                )

            # Create PDF file in landscape orientation
            buffer = BytesIO()
            doc = SimpleDocTemplate(buffer, pagesize=landscape(A4))
            elements = []

            # Use Times fonts which support Unicode/Latin characters
            styles = getSampleStyleSheet()
            title_style = ParagraphStyle(
                'CustomTitle',
                parent=styles['Title'],
                fontName='Times-Bold',
                fontSize=18,
            )
            title = Paragraph(f"Movimientos de Inventario - {datetime.now().strftime('%Y-%m-%d')}", title_style)
            elements.append(title)
            elements.append(Spacer(1, 12))

            # Prepare data for table
            if movements_data:
                # Create styles for text wrapping
                normal_style = ParagraphStyle(
                    'Normal',
                    parent=styles['Normal'],
                    fontName='Times-Roman',
                    fontSize=7,
                    wordWrap='LTR',
                    splitLongWords=True,
                    leading=9,  # Line spacing
                )
                header_style = ParagraphStyle(
                    'Header',
                    parent=styles['Normal'],
                    fontName='Times-Bold',
                    fontSize=9,
                    alignment=1,  # Center
                )

                headers = [
                    Paragraph('Fecha', header_style),
                    Paragraph('Código', header_style),
                    Paragraph('Producto', header_style),
                    Paragraph('Almacén', header_style),
                    Paragraph('Tipo Doc.', header_style),
                    Paragraph('Documento', header_style),
                    Paragraph('Cantidad', header_style),
                    Paragraph('Costo Unit.', header_style),
                    Paragraph('Total', header_style),
                    Paragraph('Categoría', header_style)
                ]
                formatted_data = []
                for item in movements_data:
                    formatted_item = [
                        Paragraph(str(item['fecha']), normal_style),
                        Paragraph(str(item['codigo']), normal_style),
                        Paragraph(str(item['nombre_producto']), normal_style),
                        Paragraph(str(item['almacen']), normal_style),
                        Paragraph(str(item['tipo_documento'] or ''), normal_style),
                        Paragraph(str(item['documento'] or ''), normal_style),
                        Paragraph(f"{item['cantidad']:,.2f}", normal_style),
                        Paragraph(f"${item['costo_unitario']:,.2f}", normal_style),
                        Paragraph(f"${item['costo_total']:,.2f}", normal_style),
                        Paragraph(str(item['categoria']), normal_style),
                    ]
                    formatted_data.append(formatted_item)
                data = [headers] + formatted_data

                # Define column widths to fit landscape A4 page (842 points total)
                colWidths = [70, 60, 150, 80, 60, 60, 80, 90, 90, 70]

                # Create table with column widths
                table = Table(data, colWidths=colWidths, repeatRows=1)  # Repeat headers on each page
                style = TableStyle([
                    ('BACKGROUND', (0, 0), (-1, 0), colors.green),
                    ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
                    ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
                    ('ALIGN', (6, 1), (8, -1), 'CENTER'),  # Alineacion de columna numericas
                    ('FONTNAME', (0, 0), (-1, 0), 'Times-Bold'),
                    ('FONTSIZE', (0, 0), (-1, 0), 9),
                    ('BOTTOMPADDING', (0, 0), (-1, 0), 4),
                    ('TOPPADDING', (0, 0), (-1, 0), 4),
                    ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
                    ('GRID', (0, 0), (-1, -1), 0.5, colors.black),
                    ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                    ('LEFTPADDING', (0, 0), (-1, -1), 2),
                    ('RIGHTPADDING', (0, 0), (-1, -1), 2),
                ])
                table.setStyle(style)
                elements.append(table)

            try:
                doc.build(elements)
                buffer.seek(0)
                pdf_content = buffer.getvalue()
                if not pdf_content:
                    logger.error("PDF buffer is empty after build")
                    return JsonResponse({'error': 'PDF generation failed - empty content'}, status=500)
            except Exception as e:
                logger.error(f"Error building PDF: {str(e)}", exc_info=True)
                return JsonResponse({'error': f'PDF generation failed: {str(e)}'}, status=500)

            response = HttpResponse(buffer.getvalue(), content_type='application/pdf')
            response['Content-Disposition'] = f'attachment; filename="movimientos_inventario_{inventory_name_param}.pdf"'
            return response
        else:
            return JsonResponse({'error': 'Formato no soportado'}, status=400)
    except Exception as e:
        logger.error(f"Error exporting movements: {str(e)}", exc_info=True)
        return JsonResponse({'error': str(e)}, status=500)


@require_http_methods(["GET"])
def list_inventories(request):
    """
    Lists all available inventories.

    Args:
        request: Django HttpRequest

    Returns:
        JsonResponse: List of inventory names
    """
    try:
        inventories = Product.objects.values_list('inventory_name', flat=True).distinct()
        return JsonResponse(list(inventories), safe=False)
    except Exception as e:
        logger.error(f"Error listing inventories: {str(e)}", exc_info=True)
        return JsonResponse([], safe=False)



@require_http_methods(["GET"])
def get_last_update_time(request):
    """
    Retrieves the timestamp of the last inventory update.
    """
    inventory_name = request.GET.get('inventory_name', 'default')
    try:
        last_batch = ImportBatch.objects.filter(
            inventory_name=inventory_name,
            processed_at__isnull=False
        ).order_by('-processed_at').first()

        if last_batch:
            return JsonResponse({'last_update': last_batch.processed_at.isoformat()})
        else:
            return JsonResponse({'last_update': None})
    except Exception as e:
        logger.error(f"Error retrieving last update time: {str(e)}", exc_info=True)
        return JsonResponse({'error': str(e)}, status=500)


@csrf_exempt
@require_http_methods(["POST"])
def upload_base_file(request, inventory_name='default'):
    """
    Uploads a base file for inventory initialization.

    Args:
        request: Django HttpRequest with uploaded file
        inventory_name (str): Inventory name

    Returns:
        JsonResponse: Success or error response
    """
    # This is similar to update_inventory but only for base files
    return update_inventory(request, inventory_name)


@require_http_methods(["GET"])
def get_inventory_at_date(request):
    """
    Calcula el estado del inventario (cantidad y valor) para una fecha.
    """
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
        data = get_inventory_at_date_data(
            inventory_name=inventory_name,
            date_str=date_str,
            target_date=target_date,
            warehouse_filter=warehouse_filter,
            category_filter=category_filter,
        )
        return JsonResponse(data)

    except Exception as e:
        logger.error(f"Error calculating inventory at date: {str(e)}", exc_info=True)
        return JsonResponse({'error': str(e)}, status=500)


@require_http_methods(["GET"])
def welcome(request):
    """
    Returns a welcome message for the API.

    Args:
        request: Django HttpRequest

    Returns:
        JsonResponse: Welcome message
    """
    logger.info(f"Request received: {request.method} {request.path}")
    return JsonResponse({'message': 'Bienvenido a el sistema de analisis de inventarios'})