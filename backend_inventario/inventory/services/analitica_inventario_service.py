"""Fachada en español para servicios analíticos de inventario."""

from .analytics_service import (
    get_inventory_at_date_data,
    get_monthly_cuts_data,
    get_monthly_movements_data,
    get_monthly_product_cuts_data,
    get_product_analysis_data,
    get_range_product_cuts_data,
)


def obtener_datos_movimientos_mensuales(**kwargs):
    return get_monthly_movements_data(**kwargs)


def obtener_datos_cortes_mensuales(**kwargs):
    return get_monthly_cuts_data(**kwargs)


def obtener_datos_cortes_mensuales_por_producto(**kwargs):
    return get_monthly_product_cuts_data(**kwargs)


def obtener_datos_analisis_producto(**kwargs):
    return get_product_analysis_data(**kwargs)


def obtener_datos_inventario_a_fecha(**kwargs):
    return get_inventory_at_date_data(**kwargs)


def obtener_cortes_rango_producto(**kwargs):
    return get_range_product_cuts_data(**kwargs)


__all__ = [
    'obtener_datos_movimientos_mensuales',
    'obtener_datos_cortes_mensuales',
    'obtener_datos_cortes_mensuales_por_producto',
    'obtener_datos_analisis_producto',
    'obtener_datos_inventario_a_fecha',
    'obtener_cortes_rango_producto',
    'get_monthly_movements_data',
    'get_monthly_cuts_data',
    'get_monthly_product_cuts_data',
    'get_product_analysis_data',
    'get_inventory_at_date_data',
    'get_range_product_cuts_data',
]
