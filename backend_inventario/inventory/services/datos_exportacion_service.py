from django.db.models import F

from ..models import InventoryRecord
from .analitica_inventario_service import (
    obtener_datos_analisis_producto,
    obtener_datos_cortes_mensuales,
    obtener_datos_cortes_mensuales_por_producto,
)
from .consulta_registros_service import (
    aplicar_filtros_registros,
    filtros_registros_desde_request,
    slice_desde_request,
)


def _texto_filtro(value, default='Todos'):
    text = str(value or '').strip()
    return text if text else default


def _texto_periodo(exact_date='', date_from='', date_to=''):
    if exact_date:
        return exact_date
    if date_from or date_to:
        return f"{date_from or 'inicio'} - {date_to or 'fin'}"
    return 'Histórico completo'


def construir_datos_analisis_exportacion(request, inventory_name_default='default'):
    inventory_name = request.GET.get('inventory_name', inventory_name_default)
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

    analysis_list = obtener_datos_analisis_producto(
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
    filters_txt = (
        f"Almacén: {_texto_filtro(warehouse_filter)} | "
        f"Categoría: {_texto_filtro(category_filter)} | "
        f"Rotación: {_texto_filtro(rotation_filter)} | "
        f"Estancado: {_texto_filtro(stagnant_filter)} | "
        f"Alta rot.: {_texto_filtro(high_rotation_filter)} | "
        f"Fecha: {_texto_periodo(exact_date, date_from, date_to)} | "
        f"Búsqueda: {_texto_filtro(search_filter)} | "
        f"Límite: {_texto_filtro(limit, 'sin límite')}"
    )
    return inventory_name, analysis_list, filters_txt


def construir_datos_movimientos_exportacion(request, inventory_name_default='default'):
    filters = filtros_registros_desde_request(request, inventory_name_default)
    export_slice = slice_desde_request(
        request,
        default_limit=10000,
        max_limit=20000,
        default_offset=0,
        max_offset=100000,
    )

    records_query = aplicar_filtros_registros(InventoryRecord.objects.all(), filters)
    # Ordenar por fecha DESC e id DESC para que el corte por límite recoja todos
    # los tipos de documento proporcionalmente (evita que el orden alfabético de
    # número de documento excluya tipos como EN/EA cuando SA domina la cabeza).
    records = records_query.order_by('-fecha', '-id').values(
        'fecha',
        'almacen',
        'tipo_documento',
        'cantidad',
        'costo_unitario',
        'categoria',
        codigo=F('producto__codigo'),
        nombre_producto=F('producto__descripcion'),
        documento=F('numero_documento'),
        costo_total=F('valor_total'),
    )[export_slice.offset:export_slice.offset + export_slice.limit]

    movements_data = [
        {
            'fecha': row['fecha'].isoformat() if row['fecha'] else None,
            'codigo': row['codigo'],
            'nombre_producto': row['nombre_producto'],
            'almacen': row['almacen'],
            'tipo_documento': row['tipo_documento'],
            'documento': row['documento'],
            'cantidad': float(row['cantidad']),
            'costo_unitario': (
                abs(float(row['costo_total'])) / abs(float(row['cantidad']))
                if float(row['cantidad']) != 0
                else float(row['costo_unitario'])
            ),
            'costo_total': float(row['costo_total']),
            'categoria': row['categoria'],
        }
        for row in records
    ]

    filters_txt = (
        f"Almacén: {_texto_filtro(filters.warehouse_filter)} | "
        f"Categoría: {_texto_filtro(filters.category_filter)} | "
        f"Tipo doc.: {_texto_filtro(filters.document_type_filter)} | "
        f"Núm. doc.: {_texto_filtro(filters.document_number_filter)} | "
        f"Fecha: {_texto_periodo(filters.exact_date, filters.date_from, filters.date_to)} | "
        f"Búsqueda: {_texto_filtro(filters.search_filter)} | "
        f"Límite: {export_slice.limit} | Offset: {export_slice.offset}"
    )

    return filters.inventory_name, movements_data, filters_txt


def construir_datos_cortes_mensuales_exportacion(request, inventory_name_default='default'):
    inventory_name = request.GET.get('inventory_name', inventory_name_default)
    warehouse_filter = request.GET.get('warehouse', '')
    category_filter = request.GET.get('category', '')
    search_filter = request.GET.get('search', '')
    months = request.GET.get('months', '12')
    month = request.GET.get('month', '')
    product_limit = request.GET.get('product_limit', '5000')

    cuts_payload = obtener_datos_cortes_mensuales(
        inventory_name=inventory_name,
        warehouse_filter=warehouse_filter,
        category_filter=category_filter,
        search_filter=search_filter,
        months=months,
    )
    cuts_rows = cuts_payload.get('months', [])
    period_average_general = cuts_payload.get('period_average_general', 0)

    product_cuts_payload = obtener_datos_cortes_mensuales_por_producto(
        inventory_name=inventory_name,
        target_month=month,
        warehouse_filter=warehouse_filter,
        category_filter=category_filter,
        search_filter=search_filter,
        limit=product_limit,
    )
    product_rows = product_cuts_payload.get('products', [])

    export_rows = []
    for row in cuts_rows:
        export_rows.append(
            {
                'mes': row.get('month'),
                'corte_inicial': row.get('opening_balance', 0),
                'entradas': row.get('total_entries', 0),
                'salidas': row.get('total_exits', 0),
                'corte_final': row.get('closing_balance', 0),
                'corte_promedio_general': row.get('average_balance_general', row.get('average_balance', 0)),
            }
        )

    target_month = (
        product_cuts_payload.get('month')
        or month
        or 'último mes con datos'
    )
    filters_txt = (
        f"Meses: {months} | "
        f"Mes objetivo: {target_month} | "
        f"Almacén: {_texto_filtro(warehouse_filter)} | "
        f"Categoría: {_texto_filtro(category_filter)} | "
        f"Búsqueda: {_texto_filtro(search_filter)} | "
        f"Límite productos: {product_limit}"
    )

    return {
        'inventory_name': inventory_name,
        'period_average_general': period_average_general,
        'export_rows': export_rows,
        'product_rows': product_rows,
        'product_cuts_payload': product_cuts_payload,
        'filters_txt': filters_txt,
    }


def construir_datos_tops_exportacion(request, inventory_name_default='default'):
    inventory_name = request.GET.get('inventory_name', inventory_name_default)
    warehouse_filter = request.GET.get('warehouse', '')
    category_filter = request.GET.get('category', '')
    rotation_filter = request.GET.get('rotation', '')
    search_filter = request.GET.get('search', '')
    group_filter = request.GET.get('group', '')
    exact_cutoff_date = request.GET.get('date', '')
    movement_date_from = request.GET.get('movement_date_from', '') or request.GET.get('date_from', '')
    movement_date_to = request.GET.get('movement_date_to', '') or request.GET.get('date_to', '')

    try:
        top_limit = int(request.GET.get('top', '30'))
    except (TypeError, ValueError):
        top_limit = 30
    top_limit = max(1, min(top_limit, 500))

    def _safe_float(value):
        try:
            return float(value or 0)
        except (TypeError, ValueError):
            return 0.0

    # Reutilizar un mismo resultado si ambas consultas tienen los mismos filtros
    # de fecha (situación más común: sin fechas o con la misma fecha de corte).
    _queries_identical = (
        movement_date_from == ''
        and movement_date_to == exact_cutoff_date
    )
    if _queries_identical:
        cutoff_analysis = range_analysis = obtener_datos_analisis_producto(
            inventory_name=inventory_name,
            category_filter=category_filter,
            warehouse_filter=warehouse_filter,
            rotation_filter=rotation_filter,
            stagnant_filter='',
            high_rotation_filter='',
            date_from='',
            date_to=exact_cutoff_date,
            search_filter=search_filter,
            limit='',
        )
    else:
        cutoff_analysis = obtener_datos_analisis_producto(
            inventory_name=inventory_name,
            category_filter=category_filter,
            warehouse_filter=warehouse_filter,
            rotation_filter=rotation_filter,
            stagnant_filter='',
            high_rotation_filter='',
            date_from='',
            date_to=exact_cutoff_date,
            search_filter=search_filter,
            limit='',
        )
        range_analysis = obtener_datos_analisis_producto(
            inventory_name=inventory_name,
            category_filter=category_filter,
            warehouse_filter=warehouse_filter,
            rotation_filter=rotation_filter,
            stagnant_filter='',
            high_rotation_filter='',
            date_from=movement_date_from,
            date_to=movement_date_to,
            search_filter=search_filter,
            limit='',
        )

    def _apply_group_filter(items):
        if not group_filter:
            return items
        return [item for item in items if str(item.get('grupo', '')) == group_filter]

    cutoff_base = _apply_group_filter(cutoff_analysis)
    range_base = _apply_group_filter(range_analysis)

    def _top_by(items, selector):
        return sorted(items, key=selector, reverse=True)[:top_limit]

    def _movement_value(item, qty_key, value_key):
        val = _safe_float(item.get(value_key))
        if val != 0:
            return val
        return _safe_float(item.get(qty_key)) * _safe_float(item.get('costo_unitario'))

    top_valor = _top_by(cutoff_base, lambda item: _safe_float(item.get('valor_saldo_actual')))
    top_entradas = _top_by(range_base, lambda item: _movement_value(item, 'entradas_periodo', 'valor_entradas_periodo'))
    top_salidas = _top_by(range_base, lambda item: _movement_value(item, 'salidas_periodo', 'valor_salidas_periodo'))

    sections = [
        {
            'title': 'Top valor en inventario',
            'items': top_valor,
            'val_fn': lambda item: _safe_float(item.get('valor_saldo_actual')),
        },
        {
            'title': 'Más valor entradas',
            'items': top_entradas,
            'val_fn': lambda item: _movement_value(item, 'entradas_periodo', 'valor_entradas_periodo'),
        },
        {
            'title': 'Más valor salidas',
            'items': top_salidas,
            'val_fn': lambda item: _movement_value(item, 'salidas_periodo', 'valor_salidas_periodo'),
        },
    ]

    filters_txt = (
        f"Top {top_limit} | Grupo: {group_filter or 'Todos'} | "
        f"Rotación: {rotation_filter or 'Todos'} | "
        f"Corte valor: {exact_cutoff_date or 'sin fecha'} | "
        f"Rango ent/sal.: {movement_date_from or 'sin'} - {movement_date_to or 'rango'}"
    )

    return {
        'inventory_name': inventory_name,
        'sections': sections,
        'filters_txt': filters_txt,
    }
