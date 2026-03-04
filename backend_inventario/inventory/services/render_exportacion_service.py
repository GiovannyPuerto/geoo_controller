"""
render_exportacion_service.py
Genera respuestas HTTP con archivos Excel (.xlsx) y PDF para todos los reportes
de inventario.  Las dependencias (openpyxl / reportlab) se cargan de forma lazy
para no impactar el arranque del backend.
"""
from datetime import datetime
from importlib import import_module
from io import BytesIO

from django.http import HttpResponse

# ── Lazy globals ──────────────────────────────────────────────────────────────
_Workbook          = None
_Font              = None
_Alignment         = None
_PatternFill       = None
_Border            = None
_Side              = None
_get_column_letter = None

_rl_colors           = None
_landscape           = None
_A4                  = None
_inch                = None
_SimpleDocTemplate   = None
_Paragraph           = None
_Table               = None
_TableStyle          = None
_Spacer              = None
_ParagraphStyle      = None
_getSampleStyleSheet = None

# ── Cached style instances (built once after lazy load, reused every row) ────
# Evita crear miles de objetos idénticos por cada fila de datos en los exports.
_CACHED_THIN_BORDER    = None
_CACHED_ALT_FILL       = None
_CACHED_HEADER_FILL    = None
_CACHED_SUBHEADER_FILL = None
_CACHED_PDF_STYLES     = None

# ── Paleta corporativa Geoflora ─────────────────────────────────────────────
# Extraída de AppColors (app_theme.dart):
#   primary      #005286  azul profundo corporativo
#   cyan         #00AFD4  cian corporativo (acento)
#   primaryLight #CCE4F0  azul claro (fila alterna suave)
#   primaryLighter #EBF5FA fondo muy suave
#   border       #D7E0EA  bordes
_COLOR_PRIMARY     = '005286'       # Azul Geoflora
_COLOR_PRIMARY_HX  = '#005286'
_COLOR_CYAN        = '00AFD4'       # Cian acento
_COLOR_CYAN_HX     = '#00AFD4'
_COLOR_PRIMARY_DARK = '003D66'      # Azul oscuro (totales / resumen)
_COLOR_ALT_ROW     = 'EBF5FA'       # primaryLighter
_COLOR_ALT_ROW_HX  = '#EBF5FA'
_COLOR_HEADER_TXT  = 'FFFFFF'
_COLOR_BORDER      = 'D7E0EA'       # border del sistema
_COLOR_SUBHEADER   = 'CCE4F0'       # primaryLight (filas de sección)

# ── Formatos numéricos Excel ──────────────────────────────────────────────────
_FMT_MONEY = '#,##0.00'
_FMT_QTY   = '#,##0.000'
_FMT_QTY2  = '#,##0.00'


# ─────────────────────────────────────────────────────────────────────────────
# CARGA DE DEPENDENCIAS
# ─────────────────────────────────────────────────────────────────────────────

def _cargar_dependencias_excel():
    global _Workbook, _Font, _Alignment, _PatternFill, _Border, _Side
    global _get_column_letter
    if _Workbook is not None:
        return
    openpyxl_module = import_module('openpyxl')
    openpyxl_styles = import_module('openpyxl.styles')
    openpyxl_utils  = import_module('openpyxl.utils')
    _Workbook          = openpyxl_module.Workbook
    _Font              = openpyxl_styles.Font
    _Alignment         = openpyxl_styles.Alignment
    _PatternFill       = openpyxl_styles.PatternFill
    _Border            = openpyxl_styles.Border
    _Side              = openpyxl_styles.Side
    _get_column_letter = openpyxl_utils.get_column_letter


def _cargar_dependencias_pdf():
    global _rl_colors, _landscape, _A4, _inch
    global _SimpleDocTemplate, _Paragraph, _Table, _TableStyle, _Spacer
    global _ParagraphStyle, _getSampleStyleSheet
    if _SimpleDocTemplate is not None:
        return
    reportlab_colors   = import_module('reportlab.lib.colors')
    reportlab_pages    = import_module('reportlab.lib.pagesizes')
    reportlab_units    = import_module('reportlab.lib.units')
    reportlab_styles   = import_module('reportlab.lib.styles')
    reportlab_platypus = import_module('reportlab.platypus')
    _rl_colors           = reportlab_colors
    _landscape           = reportlab_pages.landscape
    _A4                  = reportlab_pages.A4
    _inch                = reportlab_units.inch
    _SimpleDocTemplate   = reportlab_platypus.SimpleDocTemplate
    _Paragraph           = reportlab_platypus.Paragraph
    _Table               = reportlab_platypus.Table
    _TableStyle          = reportlab_platypus.TableStyle
    _Spacer              = reportlab_platypus.Spacer
    _ParagraphStyle      = reportlab_styles.ParagraphStyle
    _getSampleStyleSheet = reportlab_styles.getSampleStyleSheet


# ─────────────────────────────────────────────────────────────────────────────
# HELPERS PDF
# ─────────────────────────────────────────────────────────────────────────────

def _pdf_doc(buffer, horizontal=True):
    """SimpleDocTemplate con márgenes apropiados para evitar solapamiento."""
    pagesize = _landscape(_A4) if horizontal else _A4
    return _SimpleDocTemplate(
        buffer,
        pagesize=pagesize,
        leftMargin=0.50 * _inch,
        rightMargin=0.50 * _inch,
        topMargin=0.60 * _inch,
        bottomMargin=0.50 * _inch,
    )


def _pdf_styles():
    """Retorna tupla (title_style, subtitle_style, section_style, cell_style)."""
    global _CACHED_PDF_STYLES
    if _CACHED_PDF_STYLES is not None:
        return _CACHED_PDF_STYLES
    styles = _getSampleStyleSheet()
    title_style = _ParagraphStyle(
        'GeoTitle',
        parent=styles['Heading1'],
        fontSize=14,
        textColor=_rl_colors.HexColor(_COLOR_PRIMARY_HX),
        spaceAfter=3,
        spaceBefore=0,
    )
    subtitle_style = _ParagraphStyle(
        'GeoSubtitle',
        parent=styles['Normal'],
        fontSize=8,
        textColor=_rl_colors.HexColor('#003D66'),
        spaceAfter=2,
    )
    section_style = _ParagraphStyle(
        'GeoSection',
        parent=styles['Heading2'],
        fontSize=10,
        textColor=_rl_colors.HexColor(_COLOR_CYAN_HX),
        spaceBefore=8,
        spaceAfter=3,
    )
    cell_style = _ParagraphStyle(
        'GeoCell',
        parent=styles['Normal'],
        fontSize=7,
        leading=9,
    )
    _CACHED_PDF_STYLES = (title_style, subtitle_style, section_style, cell_style)
    return _CACHED_PDF_STYLES


def _pdf_header_elements(title: str, inventory_name: str, extra_lines=None):
    """Lista normalizada de elementos de cabecera para todos los PDFs con identidad Geoflora."""
    ts, ss, _, _ = _pdf_styles()
    brand_style = _ParagraphStyle(
        'GeoBrand',
        parent=_getSampleStyleSheet()['Normal'],
        fontSize=7,
        textColor=_rl_colors.HexColor(_COLOR_PRIMARY_HX),
        spaceAfter=1,
    )
    elems = [
        _Paragraph('GEOFLORA \u2014 Sistema de Gesti\u00f3n de Inventario', brand_style),
        _Paragraph(title, ts),
        _Paragraph(f'Inventario: <b>{inventory_name}</b>', ss),
        _Paragraph(f'Generado: {datetime.now().strftime("%d/%m/%Y %H:%M")}', ss),
    ]
    for line in (extra_lines or []):
        elems.append(_Paragraph(str(line), ss))
    elems.append(_Spacer(1, 10))
    return elems


def _estilo_tabla_pdf(filas_totales: int):
    """
    Estilo completo para tablas PDF:
      - Cabecera: fondo primario, texto blanco, bold, centrado, padding
      - Cuerpo: fuente 7 pt, padding 3 pt, filas alternas con fondo suave
      - Grid: líneas grises finas
    """
    style = [
        # Cabecera
        ('BACKGROUND',    (0, 0), (-1, 0), _rl_colors.HexColor(_COLOR_PRIMARY_HX)),
        ('TEXTCOLOR',     (0, 0), (-1, 0), _rl_colors.white),
        ('FONTNAME',      (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE',      (0, 0), (-1, 0), 8),
        ('TOPPADDING',    (0, 0), (-1, 0), 5),
        ('BOTTOMPADDING', (0, 0), (-1, 0), 5),
        ('ALIGN',         (0, 0), (-1, 0), 'CENTER'),
        ('VALIGN',        (0, 0), (-1, 0), 'MIDDLE'),
        # Cuerpo
        ('FONTNAME',      (0, 1), (-1, -1), 'Helvetica'),
        ('FONTSIZE',      (0, 1), (-1, -1), 7),
        ('TOPPADDING',    (0, 1), (-1, -1), 3),
        ('BOTTOMPADDING', (0, 1), (-1, -1), 3),
        ('LEFTPADDING',   (0, 0), (-1, -1), 4),
        ('RIGHTPADDING',  (0, 0), (-1, -1), 4),
        ('VALIGN',        (0, 1), (-1, -1), 'MIDDLE'),
        # Grid
        ('GRID',          (0, 0), (-1, -1), 0.4, _rl_colors.HexColor('#CCCCCC')),
        ('LINEABOVE',     (0, 0), (-1, 0),  1.2, _rl_colors.HexColor(_COLOR_CYAN_HX)),
    ]
    for row in range(1, filas_totales):
        if row % 2 == 0:
            style.append(('BACKGROUND', (0, row), (-1, row),
                           _rl_colors.HexColor(_COLOR_ALT_ROW_HX)))
    return _TableStyle(style)


def _w(text, style):
    """Envuelve texto en Paragraph para que el PDF pueda cortarlo en varias líneas."""
    return _Paragraph(str(text), style)


# ─────────────────────────────────────────────────────────────────────────────
# HELPERS EXCEL
# ─────────────────────────────────────────────────────────────────────────────

def _thin_border():
    global _CACHED_THIN_BORDER
    if _CACHED_THIN_BORDER is None:
        thin = _Side(style='thin', color=_COLOR_BORDER)
        _CACHED_THIN_BORDER = _Border(left=thin, right=thin, top=thin, bottom=thin)
    return _CACHED_THIN_BORDER


def _header_fill():
    """Fondo azul corporativo Geoflora para filas de encabezado."""
    global _CACHED_HEADER_FILL
    if _CACHED_HEADER_FILL is None:
        _CACHED_HEADER_FILL = _PatternFill(fill_type='solid', fgColor=_COLOR_PRIMARY)
    return _CACHED_HEADER_FILL


def _subheader_fill():
    """Fondo azul claro para filas de sección / totales."""
    global _CACHED_SUBHEADER_FILL
    if _CACHED_SUBHEADER_FILL is None:
        _CACHED_SUBHEADER_FILL = _PatternFill(fill_type='solid', fgColor=_COLOR_SUBHEADER)
    return _CACHED_SUBHEADER_FILL


def _alt_fill():
    """Fondo muy suave para filas de datos alternas."""
    global _CACHED_ALT_FILL
    if _CACHED_ALT_FILL is None:
        _CACHED_ALT_FILL = _PatternFill(fill_type='solid', fgColor=_COLOR_ALT_ROW)
    return _CACHED_ALT_FILL


def _agregar_encabezado_excel(
    ws,
    titulo: str,
    inventory_name: str,
    num_cols: int = 1,
    filters_txt: str = '',
):
    """
    Encabezado visual de 4 filas con merge, color y tipografía:
      Fila 1 – título (fondo primario, texto blanco, merge de columnas)
      Fila 2 – nombre del inventario
      Fila 3 – fecha de generación
      Fila 4 – separador
    """
    last_col = _get_column_letter(max(num_cols, 1))

    # ── Fila 1: banda de color primario + nombre del sistema ─────────────────
    ws.merge_cells(f'A1:{last_col}1')
    c1 = ws['A1']
    c1.value     = 'GEOFLORA — Sistema de Gestión de Inventario'
    c1.font      = _Font(name='Calibri', size=9, color=_COLOR_HEADER_TXT, italic=True)
    c1.fill      = _PatternFill(fill_type='solid', fgColor=_COLOR_PRIMARY_DARK)
    c1.alignment = _Alignment(horizontal='right', vertical='center')
    ws.row_dimensions[1].height = 14

    # ── Fila 2: título del reporte (fondo azul corporativo) ──────────────────
    ws.merge_cells(f'A2:{last_col}2')
    c2 = ws['A2']
    c2.value     = titulo
    c2.font      = _Font(name='Calibri', size=14, bold=True, color=_COLOR_HEADER_TXT)
    c2.fill      = _header_fill()
    c2.alignment = _Alignment(horizontal='left', vertical='center', indent=1)
    ws.row_dimensions[2].height = 26

    # ── Fila 3: inventario + cian lateral ───────────────────────────────────
    ws.merge_cells(f'A3:{last_col}3')
    c3 = ws['A3']
    c3.value     = f'Inventario: {inventory_name}'
    c3.font      = _Font(name='Calibri', size=10, bold=True, color=_COLOR_PRIMARY_DARK)
    c3.fill      = _PatternFill(fill_type='solid', fgColor=_COLOR_ALT_ROW)
    c3.alignment = _Alignment(horizontal='left', vertical='center', indent=1)
    ws.row_dimensions[3].height = 18

    # ── Fila 4: fecha generación + filtros aplicados ────────────────────────
    ws.merge_cells(f'A4:{last_col}4')
    c4 = ws['A4']
    generated_txt = f'Generado: {datetime.now().strftime("%d/%m/%Y %H:%M")}'
    if filters_txt:
        c4.value = f'{generated_txt} | Filtros: {filters_txt}'
    else:
        c4.value = generated_txt
    c4.font      = _Font(name='Calibri', size=9, color='64748B')
    c4.alignment = _Alignment(horizontal='left', vertical='center', indent=1, wrap_text=False)
    ws.row_dimensions[4].height = 14

    # ── Fila 5: separador con acento cian ────────────────────────────────────
    ws.merge_cells(f'A5:{last_col}5')
    ws['A5'].fill = _PatternFill(fill_type='solid', fgColor=_COLOR_CYAN)
    ws.row_dimensions[5].height = 3


def _aplicar_encabezado_tabla_excel(ws, header_row: int, headers: list, widths: list):
    """Fila de encabezado de tabla con fondo primario, texto blanco y borde."""
    fill   = _header_fill()
    border = _thin_border()
    for index, (header, width) in enumerate(zip(headers, widths), 1):
        cell = ws.cell(row=header_row, column=index, value=header)
        cell.font      = _Font(name='Calibri', size=10, bold=True, color=_COLOR_HEADER_TXT)
        cell.fill      = fill
        cell.border    = border
        cell.alignment = _Alignment(horizontal='center', vertical='center', wrap_text=True)
        ws.column_dimensions[_get_column_letter(index)].width = width
    ws.row_dimensions[header_row].height = 20


def _aplicar_estilo_fila_datos(ws, row: int, n_cols: int, num_cols: set = None):
    """Aplica fondo alternado, borde fino y alineación a una fila de datos."""
    border  = _thin_border()
    use_alt = (row % 2 == 0)
    fill    = _alt_fill() if use_alt else None
    for col in range(1, n_cols + 1):
        cell = ws.cell(row=row, column=col)
        if fill:
            cell.fill = fill
        cell.border = border
        cell.font   = _Font(name='Calibri', size=9)
        if num_cols and col in num_cols:
            cell.alignment = _Alignment(horizontal='right')
        else:
            cell.alignment = _Alignment(horizontal='left', wrap_text=False)


# ─────────────────────────────────────────────────────────────────────────────
# ANÁLISIS
# ─────────────────────────────────────────────────────────────────────────────

def construir_respuesta_analisis_excel(analysis_list, inventory_name: str, filters_txt: str = ''):
    _cargar_dependencias_excel()

    workbook = _Workbook()
    ws       = workbook.active
    ws.title = 'Analisis'

    headers = ['Código', 'Producto', 'Grupo', 'Cantidad Actual', 'Valor Actual',
               'Costo Unitario', 'Consumido', 'Estancado', 'Rotación', 'Alta Rotación', 'Almacén']
    widths  = [15, 42, 22, 18, 18, 18, 13, 13, 15, 15, 26]
    n_cols  = len(headers)

    _agregar_encabezado_excel(
        ws,
        'Análisis de Inventario',
        inventory_name,
        num_cols=n_cols,
        filters_txt=filters_txt,
    )
    hrow = 7
    _aplicar_encabezado_tabla_excel(ws, hrow, headers, widths)

    num_cols_idx = {4, 5, 6}  # Cantidad, Valor, Costo

    for idx, item in enumerate(analysis_list, 1):
        row  = hrow + idx
        qty  = float(item.get('cantidad_saldo_actual', 0) or 0)
        val  = float(item.get('valor_saldo_actual', 0) or 0)
        cost = float(item.get('costo_unitario', 0) or 0)

        ws.cell(row=row, column=1,  value=str(item.get('codigo', '')))
        ws.cell(row=row, column=2,  value=str(item.get('nombre_producto', '')))
        ws.cell(row=row, column=3,  value=str(item.get('grupo', '')))
        c4 = ws.cell(row=row, column=4,  value=qty);  c4.number_format = _FMT_QTY2
        c5 = ws.cell(row=row, column=5,  value=val);  c5.number_format = _FMT_MONEY
        c6 = ws.cell(row=row, column=6,  value=cost); c6.number_format = _FMT_MONEY
        ws.cell(row=row, column=7,  value=str(item.get('consumed', '')))
        ws.cell(row=row, column=8,  value=str(item.get('estancado', '')))
        ws.cell(row=row, column=9,  value=str(item.get('rotacion', '')))
        ws.cell(row=row, column=10, value=str(item.get('alta_rotacion', '')))
        ws.cell(row=row, column=11, value=str(item.get('almacen', '')))
        _aplicar_estilo_fila_datos(ws, row, n_cols, num_cols_idx)

    ws.freeze_panes = f'A{hrow + 1}'
    ws.auto_filter.ref = f'A{hrow}:{_get_column_letter(n_cols)}{hrow}'
    ws.sheet_view.showGridLines = False

    buf = BytesIO()
    workbook.save(buf)
    buf.seek(0)
    resp = HttpResponse(buf.getvalue(),
                        content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    resp['Content-Disposition'] = f'attachment; filename="inventory_analysis_{inventory_name}.xlsx"'
    return resp


def construir_respuesta_movimientos_excel(movements_data, inventory_name: str, filters_txt: str = ''):
    _cargar_dependencias_excel()

    workbook = _Workbook()
    ws       = workbook.active
    ws.title = 'Movimientos'

    headers = ['Fecha', 'Código', 'Producto', 'Almacén', 'Tipo Doc.',
               'Documento', 'Cantidad', 'Costo Unit.', 'Total', 'Categoría']
    widths  = [13, 15, 40, 22, 15, 17, 14, 16, 16, 20]
    n_cols  = len(headers)

    _agregar_encabezado_excel(
        ws,
        'Movimientos de Inventario',
        inventory_name,
        num_cols=n_cols,
        filters_txt=filters_txt,
    )
    hrow = 7
    _aplicar_encabezado_tabla_excel(ws, hrow, headers, widths)

    num_cols_idx = {7, 8, 9}

    for idx, item in enumerate(movements_data, 1):
        row  = hrow + idx
        qty  = item.get('cantidad')
        cost = item.get('costo_unitario')
        tot  = item.get('costo_total')

        ws.cell(row=row, column=1,  value=item.get('fecha'))
        ws.cell(row=row, column=2,  value=item.get('codigo'))
        ws.cell(row=row, column=3,  value=item.get('nombre_producto'))
        ws.cell(row=row, column=4,  value=item.get('almacen'))
        ws.cell(row=row, column=5,  value=item.get('tipo_documento') or '')
        ws.cell(row=row, column=6,  value=item.get('documento') or '')
        c7 = ws.cell(row=row, column=7,  value=float(qty)  if qty  is not None else ''); c7.number_format = _FMT_QTY
        c8 = ws.cell(row=row, column=8,  value=float(cost) if cost is not None else ''); c8.number_format = _FMT_MONEY
        c9 = ws.cell(row=row, column=9,  value=float(tot)  if tot  is not None else ''); c9.number_format = _FMT_MONEY
        ws.cell(row=row, column=10, value=item.get('categoria'))
        _aplicar_estilo_fila_datos(ws, row, n_cols, num_cols_idx)

    ws.freeze_panes = f'A{hrow + 1}'
    ws.auto_filter.ref = f'A{hrow}:{_get_column_letter(n_cols)}{hrow}'
    ws.sheet_view.showGridLines = False

    buf = BytesIO()
    workbook.save(buf)
    buf.seek(0)
    resp = HttpResponse(buf.getvalue(),
                        content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    resp['Content-Disposition'] = f'attachment; filename="inventory_movements_{inventory_name}.xlsx"'
    return resp


def construir_respuesta_analisis_pdf(analysis_list, inventory_name: str, filters_txt: str = ''):
    _cargar_dependencias_pdf()

    buf      = BytesIO()
    document = _pdf_doc(buf, horizontal=True)
    _, _, _, cell_style = _pdf_styles()

    extra_lines = [filters_txt] if filters_txt else None
    elements = _pdf_header_elements('Análisis de Inventario', inventory_name, extra_lines)

    headers = ['Código', 'Producto', 'Grupo', 'Cantidad', 'Valor', 'Costo U.',
               'Estancado', 'Rotación', 'Alta Rot.', 'Almacén']
    rows = [headers]
    for item in analysis_list:
        rows.append([
            str(item.get('codigo', '')),
            _w(item.get('nombre_producto', ''), cell_style),
            _w(item.get('grupo', ''), cell_style),
            f"{float(item.get('cantidad_saldo_actual', 0) or 0):,.2f}",
            f"${float(item.get('valor_saldo_actual', 0) or 0):,.2f}",
            f"${float(item.get('costo_unitario', 0) or 0):,.2f}",
            str(item.get('estancado', '')),
            str(item.get('rotacion', '')),
            str(item.get('alta_rotacion', '')),
            _w(item.get('almacen', ''), cell_style),
        ])

    col_widths = [52, 130, 72, 60, 72, 60, 50, 55, 54, 72]
    table = _Table(rows, colWidths=col_widths, repeatRows=1)
    table.setStyle(_estilo_tabla_pdf(len(rows)))
    elements.append(table)

    document.build(elements)
    buf.seek(0)
    resp = HttpResponse(buf.getvalue(), content_type='application/pdf')
    resp['Content-Disposition'] = f'attachment; filename="inventory_analysis_{inventory_name}.pdf"'
    return resp


def construir_respuesta_movimientos_pdf(movements_data, inventory_name: str, filters_txt: str = ''):
    _cargar_dependencias_pdf()

    buf      = BytesIO()
    document = _pdf_doc(buf, horizontal=True)
    _, _, _, cell_style = _pdf_styles()

    extra_lines = [filters_txt] if filters_txt else None
    elements = _pdf_header_elements('Movimientos de Inventario', inventory_name, extra_lines)

    headers = ['Fecha', 'Código', 'Producto', 'Almacén', 'Tipo', 'Documento',
               'Cantidad', 'Costo U.', 'Total', 'Categoría']
    rows = [headers]
    for item in movements_data:
        rows.append([
            str(item.get('fecha', '')),
            str(item.get('codigo', '')),
            _w(item.get('nombre_producto', ''), cell_style),
            _w(item.get('almacen', ''), cell_style),
            str(item.get('tipo_documento', '') or ''),
            str(item.get('documento', '') or ''),
            f"{float(item.get('cantidad', 0) or 0):,.3f}",
            f"${float(item.get('costo_unitario', 0) or 0):,.2f}",
            f"${float(item.get('costo_total', 0) or 0):,.2f}",
            str(item.get('categoria', '')),
        ])

    col_widths = [54, 58, 130, 72, 46, 68, 62, 60, 68, 64]
    table = _Table(rows, colWidths=col_widths, repeatRows=1)
    table.setStyle(_estilo_tabla_pdf(len(rows)))
    elements.append(table)

    document.build(elements)
    buf.seek(0)
    resp = HttpResponse(buf.getvalue(), content_type='application/pdf')
    resp['Content-Disposition'] = f'attachment; filename="inventory_movements_{inventory_name}.pdf"'
    return resp


def construir_respuesta_cortes_mensuales_excel(payload: dict):
    _cargar_dependencias_excel()

    inventory_name        = payload['inventory_name']
    export_rows           = payload.get('export_rows', [])
    period_average_general = float(payload.get('period_average_general', 0) or 0)
    product_rows          = payload.get('product_rows', [])
    product_cuts_payload  = payload.get('product_cuts_payload', {})
    filters_txt           = payload.get('filters_txt', '')

    workbook = _Workbook()
    ws       = workbook.active
    ws.title = 'CortesMensuales'

    headers = ['Mes', 'Corte Inicial', 'Entradas', 'Salidas', 'Corte Final', 'Promedio General']
    widths  = [16, 20, 18, 18, 20, 24]
    n_cols  = len(headers)

    _agregar_encabezado_excel(
        ws,
        'Cortes Mensuales de Inventario',
        inventory_name,
        num_cols=n_cols,
        filters_txt=filters_txt,
    )
    hrow = 7
    _aplicar_encabezado_tabla_excel(ws, hrow, headers, widths)

    num_cols_idx = {2, 3, 4, 5, 6}

    for idx, row_data in enumerate(export_rows, 1):
        row = hrow + idx
        ws.cell(row=row, column=1, value=str(row_data.get('mes', '')))
        for col_i, key in enumerate(['corte_inicial', 'entradas', 'salidas', 'corte_final', 'corte_promedio_general'], 2):
            c = ws.cell(row=row, column=col_i, value=float(row_data.get(key, 0) or 0))
            c.number_format = _FMT_MONEY
        _aplicar_estilo_fila_datos(ws, row, n_cols, num_cols_idx)

    sum_row = hrow + len(export_rows) + 2
    for sc in range(1, n_cols + 1):
        ws.cell(row=sum_row, column=sc).fill = _subheader_fill()
    ws.cell(row=sum_row, column=1, value='Promedio del periodo').font = _Font(
        name='Calibri', size=10, bold=True, color=_COLOR_PRIMARY_DARK)
    c_avg = ws.cell(row=sum_row, column=2, value=period_average_general)
    c_avg.number_format = _FMT_MONEY
    c_avg.font = _Font(name='Calibri', size=10, bold=True, color=_COLOR_PRIMARY_DARK)

    ws.freeze_panes = f'A{hrow + 1}'
    ws.sheet_view.showGridLines = False

    if product_rows:
        prod_defs = [
            ('codigo',            'Código',         15),
            ('nombre_producto',   'Producto',        40),
            ('grupo',             'Grupo',           24),
            ('cantidad_apertura', 'Cant. Apertura',  18),
            ('cantidad_promedio', 'Cant. Promedio',  18),
            ('cantidad_cierre',   'Cant. Cierre',    18),
            ('costo_unitario',    'Costo Unitario',  18),
            ('valor_apertura',    'Valor Apertura',  20),
            ('valor_promedio',    'Valor Promedio',  20),
            ('valor_cierre',      'Valor Cierre',    20),
        ]
        prod_n = len(prod_defs)
        prod_ws = workbook.create_sheet('CorteProductosMes')
        _agregar_encabezado_excel(
            prod_ws,
            'Corte de Productos por Mes',
            inventory_name,
            num_cols=prod_n,
            filters_txt=filters_txt,
        )
        phrow = 7
        _aplicar_encabezado_tabla_excel(prod_ws, phrow, [d[1] for d in prod_defs], [d[2] for d in prod_defs])

        money_keys = {'costo_unitario', 'valor_apertura', 'valor_promedio', 'valor_cierre'}
        qty_keys   = {'cantidad_apertura', 'cantidad_promedio', 'cantidad_cierre'}
        prod_num_idx = {4, 5, 6, 7, 8, 9, 10}

        for pidx, prow_data in enumerate(product_rows, 1):
            pr = phrow + pidx
            for col, (key, _h, _w) in enumerate(prod_defs, 1):
                raw = prow_data.get(key, '')
                try:
                    val = float(raw) if raw not in ('', None) else ''
                except (TypeError, ValueError):
                    val = str(raw)
                c = prod_ws.cell(row=pr, column=col, value=val)
                if key in money_keys and isinstance(val, float):
                    c.number_format = _FMT_MONEY
                elif key in qty_keys and isinstance(val, float):
                    c.number_format = _FMT_QTY2
            _aplicar_estilo_fila_datos(prod_ws, pr, prod_n, prod_num_idx)

        prod_ws.freeze_panes = f'A{phrow + 1}'
        prod_ws.sheet_view.showGridLines = False
        totals = product_cuts_payload.get('totals', {})
        for r_off, (label, key) in enumerate([
            ('Apertura', 'opening_value'),
            ('Promedio', 'average_value'),
            ('Cierre',   'closing_value'),
        ], 1):
            prod_ws.cell(row=r_off, column=prod_n + 2, value=label).font = _Font(bold=True)
            ct = prod_ws.cell(row=r_off, column=prod_n + 3, value=float(totals.get(key, 0) or 0))
            ct.number_format = _FMT_MONEY

    buf = BytesIO()
    workbook.save(buf)
    buf.seek(0)
    resp = HttpResponse(buf.getvalue(),
                        content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    resp['Content-Disposition'] = f'attachment; filename="cortes_mensuales_{inventory_name}.xlsx"'
    return resp


def construir_respuesta_cortes_mensuales_pdf(payload: dict):
    _cargar_dependencias_pdf()

    inventory_name        = payload['inventory_name']
    export_rows           = payload.get('export_rows', [])
    period_average_general = float(payload.get('period_average_general', 0) or 0)
    product_rows          = payload.get('product_rows', [])
    filters_txt           = payload.get('filters_txt', '')

    buf      = BytesIO()
    document = _pdf_doc(buf, horizontal=True)
    _, _, section_style, cell_style = _pdf_styles()

    extra_lines = [f'Promedio del periodo: <b>${period_average_general:,.2f}</b>']
    if filters_txt:
        extra_lines.append(filters_txt)
    elements = _pdf_header_elements(
        'Cortes Mensuales de Inventario',
        inventory_name,
        extra_lines,
    )

    rows = [['Mes', 'Corte Inicial', 'Entradas', 'Salidas', 'Corte Final', 'Prom. General']]
    for row_data in export_rows:
        rows.append([
            str(row_data.get('mes', '')),
            f"${float(row_data.get('corte_inicial', 0) or 0):,.2f}",
            f"${float(row_data.get('entradas', 0) or 0):,.2f}",
            f"${float(row_data.get('salidas', 0) or 0):,.2f}",
            f"${float(row_data.get('corte_final', 0) or 0):,.2f}",
            f"${float(row_data.get('corte_promedio_general', 0) or 0):,.2f}",
        ])

    tbl = _Table(rows, colWidths=[74, 96, 86, 86, 96, 96], repeatRows=1)
    tbl.setStyle(_estilo_tabla_pdf(len(rows)))
    elements.append(tbl)

    if product_rows:
        elements.append(_Spacer(1, 14))
        elements.append(_Paragraph('Corte por Producto', section_style))
        elements.append(_Spacer(1, 4))
        prod_rows = [['Código', 'Producto', 'Grupo', 'Cant. Promedio', 'Valor Promedio', 'Costo Unitario']]
        for p in product_rows:
            prod_rows.append([
                str(p.get('codigo', '')),
                _w(p.get('nombre_producto', ''), cell_style),
                _w(p.get('grupo', ''), cell_style),
                f"{float(p.get('cantidad_promedio', 0) or 0):,.2f}",
                f"${float(p.get('valor_promedio', 0) or 0):,.2f}",
                f"${float(p.get('costo_unitario', 0) or 0):,.2f}",
            ])
        prod_tbl = _Table(prod_rows, colWidths=[62, 180, 86, 92, 102, 92], repeatRows=1)
        prod_tbl.setStyle(_estilo_tabla_pdf(len(prod_rows)))
        elements.append(prod_tbl)

    document.build(elements)
    buf.seek(0)
    resp = HttpResponse(buf.getvalue(), content_type='application/pdf')
    resp['Content-Disposition'] = f'attachment; filename="cortes_mensuales_{inventory_name}.pdf"'
    return resp


def construir_respuesta_tops_excel(payload: dict):
    _cargar_dependencias_excel()

    inventory_name = payload['inventory_name']
    sections       = payload.get('sections', [])
    filters_txt    = payload.get('filters_txt', '')

    workbook = _Workbook()
    first    = workbook.active
    workbook.remove(first)

    for section in sections:
        sheet_name = section['title'].replace(' ', '_')[:31]
        ws    = workbook.create_sheet(sheet_name)

        headers = ['Posición', 'Código', 'Producto', 'Grupo', 'Rotación', 'Valor']
        widths  = [12, 17, 44, 26, 17, 22]
        n_cols  = len(headers)

        _agregar_encabezado_excel(
            ws,
            section['title'],
            inventory_name,
            num_cols=n_cols,
            filters_txt=filters_txt,
        )
        hrow = 7
        _aplicar_encabezado_tabla_excel(ws, hrow, headers, widths)

        num_cols_idx = {1, 6}

        for idx, item in enumerate(section.get('items', []), 1):
            rn = hrow + idx
            ws.cell(rn, 1, value=idx)
            ws.cell(rn, 2, value=str(item.get('codigo', '')))
            ws.cell(rn, 3, value=str(item.get('nombre_producto', '')))
            ws.cell(rn, 4, value=str(item.get('grupo', '')))
            ws.cell(rn, 5, value=str(item.get('rotacion', '')))
            cv = ws.cell(rn, 6, value=float(section['val_fn'](item)))
            cv.number_format = _FMT_MONEY
            _aplicar_estilo_fila_datos(ws, rn, n_cols, num_cols_idx)

        ws.freeze_panes = f'A{hrow + 1}'
        ws.sheet_view.showGridLines = False

    buf = BytesIO()
    workbook.save(buf)
    buf.seek(0)
    resp = HttpResponse(buf.getvalue(),
                        content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    resp['Content-Disposition'] = f'attachment; filename="tops_inventario_{inventory_name}.xlsx"'
    return resp


def construir_respuesta_tops_pdf(payload: dict):
    _cargar_dependencias_pdf()

    inventory_name = payload['inventory_name']
    sections       = payload.get('sections', [])
    filters_txt    = payload.get('filters_txt', '')

    buf      = BytesIO()
    document = _pdf_doc(buf, horizontal=True)
    _, _, section_style, cell_style = _pdf_styles()

    extra = [filters_txt] if filters_txt else []
    elements = _pdf_header_elements('Informe de Tops de Inventario', inventory_name, extra)

    for section in sections:
        elements.append(_Paragraph(section['title'], section_style))
        elements.append(_Spacer(1, 4))
        rows = [['Pos.', 'Código', 'Producto', 'Grupo', 'Rotación', 'Valor']]
        for idx, item in enumerate(section.get('items', []), 1):
            rows.append([
                str(idx),
                str(item.get('codigo', '')),
                _w(item.get('nombre_producto', ''), cell_style),
                _w(item.get('grupo', ''), cell_style),
                str(item.get('rotacion', '')),
                f"${float(section['val_fn'](item)):,.2f}",
            ])
        tbl = _Table(rows, colWidths=[40, 68, 188, 106, 88, 112], repeatRows=1)
        tbl.setStyle(_estilo_tabla_pdf(len(rows)))
        elements.append(tbl)
        elements.append(_Spacer(1, 10))

    document.build(elements)
    buf.seek(0)
    resp = HttpResponse(buf.getvalue(), content_type='application/pdf')
    resp['Content-Disposition'] = f'attachment; filename="tops_inventario_{inventory_name}.pdf"'
    return resp
