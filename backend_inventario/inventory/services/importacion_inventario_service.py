"""Fachada en español para importación de inventario."""

from .import_service import procesar_importacion_inventario


def procesar_importacion(request, inventory_name='default'):
    return procesar_importacion_inventario(request, inventory_name)


__all__ = [
    'procesar_importacion',
    'procesar_importacion_inventario',
]
