"""Fachada en español para el servicio de resumen de inventario."""

from .summary_service import get_inventory_summary_data


def obtener_resumen_inventario(inventory_name='default'):
    return get_inventory_summary_data(inventory_name=inventory_name)


__all__ = [
    'obtener_resumen_inventario',
    'get_inventory_summary_data',
]
