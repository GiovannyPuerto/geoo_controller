"""
Versionado de caché por inventario.

Permite invalidar caches de forma inteligente cuando cambia el estado base
de datos, incluso si el cambio ocurrió fuera del flujo normal de la app
(por ejemplo, truncate/delete directo en producción).
"""

import hashlib
import json
import logging
import os

from django.core.cache import cache
from django.db.models import Count, Max

from ..models import ImportBatch, InventoryRecord, Product

logger = logging.getLogger(__name__)


CACHE_VERSION_TTL_SECONDS = int(
    os.environ.get("INVENTORY_CACHE_VERSION_TTL_SECONDS", "30")
)


def get_inventory_cache_version(inventory_name: str = "default") -> str:
    """
    Retorna una versión corta de datos para incluir en cache-keys.

    Se basa en agregados livianos de productos/movimientos/lotes del inventario.
    Si cambian conteos o máximos de ID, cambia la versión y se invalidan keys.
    """
    inv = str(inventory_name or "default").strip()
    cache_key = f"inv:cachever:v1:{inv}"
    cached = cache.get(cache_key)
    if cached:
        return str(cached)

    try:
        products_stats = Product.objects.filter(inventory_name=inv).aggregate(
            count=Count("id"),
            max_id=Max("id"),
        )
        movements_stats = InventoryRecord.objects.filter(
            product__inventory_name=inv
        ).aggregate(
            count=Count("id"),
            max_id=Max("id"),
        )
        batches_stats = ImportBatch.objects.filter(inventory_name=inv).aggregate(
            count=Count("id"),
            max_id=Max("id"),
        )

        payload = {
            "inventory": inv,
            "products_count": int(products_stats.get("count") or 0),
            "products_max_id": int(products_stats.get("max_id") or 0),
            "movements_count": int(movements_stats.get("count") or 0),
            "movements_max_id": int(movements_stats.get("max_id") or 0),
            "batches_count": int(batches_stats.get("count") or 0),
            "batches_max_id": int(batches_stats.get("max_id") or 0),
        }
        src = json.dumps(payload, sort_keys=True, ensure_ascii=False)
        version = hashlib.sha1(src.encode("utf-8")).hexdigest()[:12]
    except Exception:
        logger.warning(
            "No se pudo calcular cache-version para inventario '%s'.", inv, exc_info=True
        )
        version = "fallback"

    cache.set(cache_key, version, timeout=CACHE_VERSION_TTL_SECONDS)
    return version

