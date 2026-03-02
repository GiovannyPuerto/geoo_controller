"""Fachada en español para filtros y slicing de registros."""

from .record_query_service import (
    RecordFilterParams,
    SliceParams,
    apply_record_filters,
    clamp_int,
    record_filters_from_request,
    slice_from_request,
)


def aplicar_filtros_registros(queryset, filtros):
    return apply_record_filters(queryset, filtros)


def filtros_registros_desde_request(request, inventory_name='default'):
    return record_filters_from_request(request, inventory_name)


def slice_desde_request(
    request,
    *,
    default_limit,
    max_limit,
    default_offset=0,
    max_offset=100000,
):
    return slice_from_request(
        request,
        default_limit=default_limit,
        max_limit=max_limit,
        default_offset=default_offset,
        max_offset=max_offset,
    )


def limitar_entero(value, default, min_value, max_value):
    return clamp_int(value, default, min_value, max_value)


__all__ = [
    'RecordFilterParams',
    'SliceParams',
    'aplicar_filtros_registros',
    'filtros_registros_desde_request',
    'slice_desde_request',
    'limitar_entero',
    'apply_record_filters',
    'record_filters_from_request',
    'slice_from_request',
    'clamp_int',
]
