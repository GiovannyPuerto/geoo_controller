from datetime import datetime
from importlib import import_module
from io import BytesIO

from django.http import HttpResponse


# Dependencias lazily-loaded para no penalizar arranque de backend.
_Workbook = None
_Font = None
_Alignment = None
_get_column_letter = None

_rl_colors = None
_landscape = None
_A4 = None
_SimpleDocTemplate = None
_Paragraph = None
_Table = None
_TableStyle = None
_Spacer = None
_ParagraphStyle = None
_getSampleStyleSheet = None


def _cargar_dependencias_excel():
    global _Workbook, _Font, _Alignment, _get_column_letter
    if _Workbook is not None:
        return

    openpyxl_module = import_module('openpyxl')
    openpyxl_styles = import_module('openpyxl.styles')
    openpyxl_utils = import_module('openpyxl.utils')

    _Workbook = openpyxl_module.Workbook
    _Font = openpyxl_styles.Font
    _Alignment = openpyxl_styles.Alignment
    _get_column_letter = openpyxl_utils.get_column_letter


def _cargar_dependencias_pdf():
    global _rl_colors, _landscape, _A4
    global _SimpleDocTemplate, _Paragraph, _Table, _TableStyle, _Spacer
    global _ParagraphStyle, _getSampleStyleSheet

    if _SimpleDocTemplate is not None:
        return

    reportlab_colors = import_module('reportlab.lib.colors')
    reportlab_pages = import_module('reportlab.lib.pagesizes')
    reportlab_styles = import_module('reportlab.lib.styles')
    reportlab_platypus = import_module('reportlab.platypus')

    _rl_colors = reportlab_colors
    _landscape = reportlab_pages.landscape
    _A4 = reportlab_pages.A4
    _SimpleDocTemplate = reportlab_platypus.SimpleDocTemplate
    _Paragraph = reportlab_platypus.Paragraph
    _Table = reportlab_platypus.Table
    _TableStyle = reportlab_platypus.TableStyle
    _Spacer = reportlab_platypus.Spacer
    _ParagraphStyle = reportlab_styles.ParagraphStyle
    _getSampleStyleSheet = reportlab_styles.getSampleStyleSheet


def _estilo_tabla_pdf(filas_totales: int):
    style = [
        ('BACKGROUND', (0, 0), (-1, 0), _rl_colors.HexColor('#EF7C91')),
        ('TEXTCOLOR', (0, 0), (-1, 0), _rl_colors.white),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, 0), 8),
        ('GRID', (0, 0), (-1, -1), 0.4, _rl_colors.HexColor('#D1D5DB')),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('LEFTPADDING', (0, 0), (-1, -1), 3),
        ('RIGHTPADDING', (0, 0), (-1, -1), 3),
    ]
    for row in range(1, filas_totales):
        if row % 2 == 0:
            style.append(('BACKGROUND', (0, row), (-1, row), _rl_colors.HexColor('#FFF5F7')))
    return _TableStyle(style)


def _agregar_encabezado_excel(ws, titulo: str, inventory_name: str):
    ws['A1'] = titulo
    ws['A1'].font = _Font(name='Calibri', size=14, bold=True)
    ws['A2'] = f'Inventario: {inventory_name}'
    ws['A2'].font = _Font(name='Calibri', size=10)
    ws['A3'] = f'Generado: {datetime.now().strftime("%Y-%m-%d %H:%M")}'
    ws['A3'].font = _Font(name='Calibri', size=9)


def construir_respuesta_analisis_excel(analysis_list, inventory_name: str):
    _cargar_dependencias_excel()

    workbook = _Workbook()
    worksheet = workbook.active
    worksheet.title = 'Analisis'

    _agregar_encabezado_excel(worksheet, 'Análisis de Inventario', inventory_name)

    headers = [
        'Código', 'Producto', 'Grupo', 'Cantidad Actual', 'Valor Actual',
        'Costo Unitario', 'Consumido', 'Estancado', 'Rotación', 'Alta Rotación', 'Almacén',
    ]
    widths = [15, 40, 20, 18, 18, 18, 12, 12, 15, 15, 25]

    header_row = 5
    for index, (header, width) in enumerate(zip(headers, widths), 1):
        cell = worksheet.cell(row=header_row, column=index, value=header)
        cell.font = _Font(name='Calibri', size=10, bold=True)
        cell.alignment = _Alignment(horizontal='center')
        worksheet.column_dimensions[_get_column_letter(index)].width = width

    for idx, item in enumerate(analysis_list, 1):
        row = header_row + idx
        worksheet.cell(row=row, column=1, value=str(item.get('codigo', '')))
        worksheet.cell(row=row, column=2, value=str(item.get('nombre_producto', '')))
        worksheet.cell(row=row, column=3, value=str(item.get('grupo', '')))
        worksheet.cell(row=row, column=4, value=float(item.get('cantidad_saldo_actual', 0)))
        worksheet.cell(row=row, column=5, value=float(item.get('valor_saldo_actual', 0)))
        worksheet.cell(row=row, column=6, value=float(item.get('costo_unitario', 0)))
        worksheet.cell(row=row, column=7, value=str(item.get('consumed', '')))
        worksheet.cell(row=row, column=8, value=str(item.get('estancado', '')))
        worksheet.cell(row=row, column=9, value=str(item.get('rotacion', '')))
        worksheet.cell(row=row, column=10, value=str(item.get('alta_rotacion', '')))
        worksheet.cell(row=row, column=11, value=str(item.get('almacen', '')))

    buffer = BytesIO()
    workbook.save(buffer)
    buffer.seek(0)

    response = HttpResponse(
        buffer.getvalue(),
        content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    )
    response['Content-Disposition'] = f'attachment; filename="inventory_analysis_{inventory_name}.xlsx"'
    return response


def construir_respuesta_movimientos_excel(movements_data, inventory_name: str):
    _cargar_dependencias_excel()

    workbook = _Workbook()
    worksheet = workbook.active
    worksheet.title = 'Movimientos'

    _agregar_encabezado_excel(worksheet, 'Movimientos de Inventario', inventory_name)

    headers = ['Fecha', 'Código', 'Producto', 'Almacén', 'Tipo Doc.', 'Documento', 'Cantidad', 'Costo Unit.', 'Total', 'Categoría']
    widths = [12, 14, 38, 20, 14, 16, 14, 16, 16, 18]

    header_row = 5
    for index, (header, width) in enumerate(zip(headers, widths), 1):
        cell = worksheet.cell(row=header_row, column=index, value=header)
        cell.font = _Font(name='Calibri', size=10, bold=True)
        cell.alignment = _Alignment(horizontal='center')
        worksheet.column_dimensions[_get_column_letter(index)].width = width

    for idx, item in enumerate(movements_data, 1):
        row = header_row + idx
        worksheet.cell(row=row, column=1, value=item.get('fecha'))
        worksheet.cell(row=row, column=2, value=item.get('codigo'))
        worksheet.cell(row=row, column=3, value=item.get('nombre_producto'))
        worksheet.cell(row=row, column=4, value=item.get('almacen'))
        worksheet.cell(row=row, column=5, value=item.get('tipo_documento') or '')
        worksheet.cell(row=row, column=6, value=item.get('documento') or '')
        worksheet.cell(row=row, column=7, value=item.get('cantidad'))
        worksheet.cell(row=row, column=8, value=item.get('costo_unitario'))
        worksheet.cell(row=row, column=9, value=item.get('costo_total'))
        worksheet.cell(row=row, column=10, value=item.get('categoria'))

    buffer = BytesIO()
    workbook.save(buffer)
    buffer.seek(0)

    response = HttpResponse(
        buffer.getvalue(),
        content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    )
    response['Content-Disposition'] = f'attachment; filename="inventory_movements_{inventory_name}.xlsx"'
    return response


def construir_respuesta_analisis_pdf(analysis_list, inventory_name: str):
    _cargar_dependencias_pdf()

    buffer = BytesIO()
    document = _SimpleDocTemplate(buffer, pagesize=_landscape(_A4))

    styles = _getSampleStyleSheet()
    title_style = _ParagraphStyle('title', parent=styles['Heading2'], fontSize=13)
    normal_style = _ParagraphStyle('normal', parent=styles['Normal'], fontSize=7)

    elements = [
        _Paragraph('Análisis de Inventario', title_style),
        _Paragraph(f'Inventario: {inventory_name}', normal_style),
        _Paragraph(f'Generado: {datetime.now().strftime("%Y-%m-%d %H:%M")}', normal_style),
        _Spacer(1, 8),
    ]

    headers = ['Código', 'Producto', 'Grupo', 'Cantidad', 'Valor', 'Costo U.', 'Estancado', 'Rotación', 'Alta Rot.', 'Almacén']
    rows = [headers]
    for item in analysis_list:
        rows.append([
            str(item.get('codigo', '')),
            str(item.get('nombre_producto', '')),
            str(item.get('grupo', '')),
            f"{item.get('cantidad_saldo_actual', 0):,.2f}",
            f"${item.get('valor_saldo_actual', 0):,.2f}",
            f"${item.get('costo_unitario', 0):,.2f}",
            str(item.get('estancado', '')),
            str(item.get('rotacion', '')),
            str(item.get('alta_rotacion', '')),
            str(item.get('almacen', '')),
        ])

    col_widths = [55, 120, 70, 62, 72, 62, 50, 55, 55, 75]
    table = _Table(rows, colWidths=col_widths, repeatRows=1)
    table.setStyle(_estilo_tabla_pdf(len(rows)))
    elements.append(table)

    document.build(elements)
    buffer.seek(0)

    response = HttpResponse(buffer.getvalue(), content_type='application/pdf')
    response['Content-Disposition'] = f'attachment; filename="inventory_analysis_{inventory_name}.pdf"'
    return response


def construir_respuesta_movimientos_pdf(movements_data, inventory_name: str):
    _cargar_dependencias_pdf()

    buffer = BytesIO()
    document = _SimpleDocTemplate(buffer, pagesize=_landscape(_A4))

    styles = _getSampleStyleSheet()
    title_style = _ParagraphStyle('title', parent=styles['Heading2'], fontSize=13)
    normal_style = _ParagraphStyle('normal', parent=styles['Normal'], fontSize=7)

    elements = [
        _Paragraph('Movimientos de Inventario', title_style),
        _Paragraph(f'Inventario: {inventory_name}', normal_style),
        _Paragraph(f'Generado: {datetime.now().strftime("%Y-%m-%d %H:%M")}', normal_style),
        _Spacer(1, 8),
    ]

    headers = ['Fecha', 'Código', 'Producto', 'Almacén', 'Tipo', 'Documento', 'Cantidad', 'Costo U.', 'Total', 'Categoría']
    rows = [headers]
    for item in movements_data:
        rows.append([
            str(item.get('fecha', '')),
            str(item.get('codigo', '')),
            str(item.get('nombre_producto', '')),
            str(item.get('almacen', '')),
            str(item.get('tipo_documento', '') or ''),
            str(item.get('documento', '') or ''),
            f"{item.get('cantidad', 0):,.3f}",
            f"${item.get('costo_unitario', 0):,.2f}",
            f"${item.get('costo_total', 0):,.2f}",
            str(item.get('categoria', '')),
        ])

    col_widths = [55, 60, 130, 72, 48, 70, 62, 62, 70, 65]
    table = _Table(rows, colWidths=col_widths, repeatRows=1)
    table.setStyle(_estilo_tabla_pdf(len(rows)))
    elements.append(table)

    document.build(elements)
    buffer.seek(0)

    response = HttpResponse(buffer.getvalue(), content_type='application/pdf')
    response['Content-Disposition'] = f'attachment; filename="inventory_movements_{inventory_name}.pdf"'
    return response


def construir_respuesta_cortes_mensuales_excel(payload: dict):
    _cargar_dependencias_excel()

    inventory_name = payload['inventory_name']
    export_rows = payload.get('export_rows', [])
    period_average_general = float(payload.get('period_average_general', 0) or 0)
    product_rows = payload.get('product_rows', [])
    product_cuts_payload = payload.get('product_cuts_payload', {})

    workbook = _Workbook()
    worksheet = workbook.active
    worksheet.title = 'CortesMensuales'

    _agregar_encabezado_excel(worksheet, 'Cortes Mensuales de Inventario', inventory_name)

    headers = ['Mes', 'Corte Inicial', 'Entradas', 'Salidas', 'Corte Final', 'Promedio General']
    widths = [14, 18, 16, 16, 18, 22]
    header_row = 5
    for index, (header, width) in enumerate(zip(headers, widths), 1):
        cell = worksheet.cell(row=header_row, column=index, value=header)
        cell.font = _Font(name='Calibri', size=10, bold=True)
        worksheet.column_dimensions[_get_column_letter(index)].width = width

    for idx, row in enumerate(export_rows, 1):
        rn = header_row + idx
        worksheet.cell(row=rn, column=1, value=str(row.get('mes', '')))
        worksheet.cell(row=rn, column=2, value=float(row.get('corte_inicial', 0)))
        worksheet.cell(row=rn, column=3, value=float(row.get('entradas', 0)))
        worksheet.cell(row=rn, column=4, value=float(row.get('salidas', 0)))
        worksheet.cell(row=rn, column=5, value=float(row.get('corte_final', 0)))
        worksheet.cell(row=rn, column=6, value=float(row.get('corte_promedio_general', 0)))

    worksheet['H1'] = 'Promedio del periodo'
    worksheet['I1'] = period_average_general

    if product_rows:
        prod_ws = workbook.create_sheet('CorteProductosMes')
        _agregar_encabezado_excel(prod_ws, 'Corte de Productos por Mes', inventory_name)
        prod_defs = [
            ('codigo', 'Código', 14),
            ('nombre_producto', 'Producto', 38),
            ('grupo', 'Grupo', 22),
            ('cantidad_apertura', 'Cant. Apertura', 18),
            ('cantidad_promedio', 'Cant. Promedio', 18),
            ('cantidad_cierre', 'Cant. Cierre', 18),
            ('costo_unitario', 'Costo Unitario', 18),
            ('valor_apertura', 'Valor Apertura', 20),
            ('valor_promedio', 'Valor Promedio', 20),
            ('valor_cierre', 'Valor Cierre', 20),
        ]
        hrow = 5
        for index, (_key, header, width) in enumerate(prod_defs, 1):
            prod_ws.cell(row=hrow, column=index, value=header)
            prod_ws.column_dimensions[_get_column_letter(index)].width = width

        for idx, row in enumerate(product_rows, 1):
            rn = hrow + idx
            for col, (key, _header, _width) in enumerate(prod_defs, 1):
                prod_ws.cell(row=rn, column=col, value=row.get(key, ''))

        totals = product_cuts_payload.get('totals', {})
        prod_ws['L1'] = 'Mes del corte'
        prod_ws['M1'] = product_cuts_payload.get('month', '')
        prod_ws['L3'] = 'Apertura'
        prod_ws['M3'] = float(totals.get('opening_value', 0) or 0)
        prod_ws['L4'] = 'Promedio'
        prod_ws['M4'] = float(totals.get('average_value', 0) or 0)
        prod_ws['L5'] = 'Cierre'
        prod_ws['M5'] = float(totals.get('closing_value', 0) or 0)

    buffer = BytesIO()
    workbook.save(buffer)
    buffer.seek(0)
    response = HttpResponse(buffer.getvalue(), content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    response['Content-Disposition'] = f'attachment; filename="cortes_mensuales_{inventory_name}.xlsx"'
    return response


def construir_respuesta_cortes_mensuales_pdf(payload: dict):
    _cargar_dependencias_pdf()

    inventory_name = payload['inventory_name']
    export_rows = payload.get('export_rows', [])
    period_average_general = float(payload.get('period_average_general', 0) or 0)
    product_rows = payload.get('product_rows', [])

    buffer = BytesIO()
    document = _SimpleDocTemplate(buffer, pagesize=_landscape(_A4))
    styles = _getSampleStyleSheet()
    title_style = _ParagraphStyle('title', parent=styles['Heading2'], fontSize=13)
    normal_style = _ParagraphStyle('normal', parent=styles['Normal'], fontSize=7)

    elements = [
        _Paragraph('Cortes Mensuales de Inventario', title_style),
        _Paragraph(f'Inventario: {inventory_name}', normal_style),
        _Paragraph(f'Promedio del periodo: ${period_average_general:,.2f}', normal_style),
        _Spacer(1, 8),
    ]

    rows = [['Mes', 'Corte Inicial', 'Entradas', 'Salidas', 'Corte Final', 'Prom. General']]
    for row in export_rows:
        rows.append([
            str(row.get('mes', '')),
            f"${float(row.get('corte_inicial', 0) or 0):,.2f}",
            f"${float(row.get('entradas', 0) or 0):,.2f}",
            f"${float(row.get('salidas', 0) or 0):,.2f}",
            f"${float(row.get('corte_final', 0) or 0):,.2f}",
            f"${float(row.get('corte_promedio_general', 0) or 0):,.2f}",
        ])

    table = _Table(rows, colWidths=[74, 95, 85, 85, 95, 95], repeatRows=1)
    table.setStyle(_estilo_tabla_pdf(len(rows)))
    elements.append(table)

    if product_rows:
        elements.append(_Spacer(1, 12))
        prod_rows = [['Código', 'Producto', 'Grupo', 'Cant. Promedio', 'Valor Promedio']]
        for product in product_rows:
            prod_rows.append([
                str(product.get('codigo', '')),
                str(product.get('nombre_producto', '')),
                str(product.get('grupo', '')),
                f"{float(product.get('cantidad_promedio', 0) or 0):,.2f}",
                f"${float(product.get('valor_promedio', 0) or 0):,.2f}",
            ])
        prod_table = _Table(prod_rows, colWidths=[70, 190, 90, 100, 120], repeatRows=1)
        prod_table.setStyle(_estilo_tabla_pdf(len(prod_rows)))
        elements.append(prod_table)

    document.build(elements)
    buffer.seek(0)
    response = HttpResponse(buffer.getvalue(), content_type='application/pdf')
    response['Content-Disposition'] = f'attachment; filename="cortes_mensuales_{inventory_name}.pdf"'
    return response


def construir_respuesta_tops_excel(payload: dict):
    _cargar_dependencias_excel()

    inventory_name = payload['inventory_name']
    sections = payload.get('sections', [])

    workbook = _Workbook()
    first = workbook.active
    workbook.remove(first)

    for section in sections:
        sheet_name = section['title'].replace(' ', '')[:31]
        ws = workbook.create_sheet(sheet_name)
        _agregar_encabezado_excel(ws, section['title'], inventory_name)
        headers = ['Posición', 'Código', 'Producto', 'Grupo', 'Rotación', 'Valor']
        widths = [10, 16, 42, 24, 16, 20]
        hrow = 5
        for index, (header, width) in enumerate(zip(headers, widths), 1):
            ws.cell(row=hrow, column=index, value=header)
            ws.column_dimensions[_get_column_letter(index)].width = width

        for idx, item in enumerate(section.get('items', []), 1):
            rn = hrow + idx
            ws.cell(row=rn, column=1, value=idx)
            ws.cell(row=rn, column=2, value=str(item.get('codigo', '')))
            ws.cell(row=rn, column=3, value=str(item.get('nombre_producto', '')))
            ws.cell(row=rn, column=4, value=str(item.get('grupo', '')))
            ws.cell(row=rn, column=5, value=str(item.get('rotacion', '')))
            ws.cell(row=rn, column=6, value=float(section['val_fn'](item)))

    buffer = BytesIO()
    workbook.save(buffer)
    buffer.seek(0)
    response = HttpResponse(buffer.getvalue(), content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    response['Content-Disposition'] = f'attachment; filename="tops_inventario_{inventory_name}.xlsx"'
    return response


def construir_respuesta_tops_pdf(payload: dict):
    _cargar_dependencias_pdf()

    inventory_name = payload['inventory_name']
    sections = payload.get('sections', [])
    filters_txt = payload.get('filters_txt', '')

    buffer = BytesIO()
    document = _SimpleDocTemplate(buffer, pagesize=_landscape(_A4))
    styles = _getSampleStyleSheet()
    title_style = _ParagraphStyle('title', parent=styles['Heading2'], fontSize=13)
    normal_style = _ParagraphStyle('normal', parent=styles['Normal'], fontSize=7)

    elements = [
        _Paragraph('Informe de Tops', title_style),
        _Paragraph(f'Inventario: {inventory_name}', normal_style),
        _Paragraph(filters_txt, normal_style),
        _Spacer(1, 8),
    ]

    for section in sections:
        elements.append(_Paragraph(section['title'], title_style))
        elements.append(_Spacer(1, 4))
        rows = [['Posición', 'Código', 'Producto', 'Grupo', 'Rotación', 'Valor']]
        items = section.get('items', [])
        for idx, item in enumerate(items, 1):
            rows.append([
                str(idx),
                str(item.get('codigo', '')),
                str(item.get('nombre_producto', '')),
                str(item.get('grupo', '')),
                str(item.get('rotacion', '')),
                f"${float(section['val_fn'](item)):,.2f}",
            ])
        table = _Table(rows, colWidths=[50, 70, 180, 100, 90, 110], repeatRows=1)
        table.setStyle(_estilo_tabla_pdf(len(rows)))
        elements.append(table)
        elements.append(_Spacer(1, 8))

    document.build(elements)
    buffer.seek(0)
    response = HttpResponse(buffer.getvalue(), content_type='application/pdf')
    response['Content-Disposition'] = f'attachment; filename="tops_inventario_{inventory_name}.pdf"'
    return response
