"""
Comando de administración: clear_inventory_cache
================================================
Limpia toda la caché de Django (default + exports) de forma compatible con
cualquier backend (FileBasedCache, LocMemCache, Redis, Memcached).

Se usa cuando se despliega una nueva versión del código que cambia la lógica
de cálculo, para forzar que el backend recompute todos los valores.
La versión por datos (get_inventory_cache_version) invalida automáticamente
cuando cambian los datos en BD, pero NO cuando solo cambia el código.

Uso:
    python manage.py clear_inventory_cache
    python manage.py clear_inventory_cache --cache exports
    python manage.py clear_inventory_cache --cache default --cache exports
"""

import logging

from django.core.cache import caches, DEFAULT_CACHE_ALIAS
from django.core.management.base import BaseCommand

logger = logging.getLogger(__name__)

# Alias de caché reconocidos por la aplicación
KNOWN_CACHE_ALIASES = ["default", "exports"]


class Command(BaseCommand):
    help = (
        "Limpia la caché de cortes mensuales y analíticas. "
        "Úselo tras desplegar una versión que cambia la lógica de cálculo."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--cache",
            action="append",
            dest="cache_aliases",
            metavar="ALIAS",
            help=(
                "Alias de caché a limpiar (default / exports). "
                "Puede repetirse. Sin este flag limpia todos los conocidos."
            ),
        )

    def handle(self, *args, **options):
        aliases = options.get("cache_aliases") or KNOWN_CACHE_ALIASES

        total_cleared = 0
        for alias in aliases:
            try:
                c = caches[alias]
                c.clear()
                self.stdout.write(self.style.SUCCESS(f"  ✓ cache '{alias}' limpiado"))
                total_cleared += 1
            except Exception as exc:
                self.stderr.write(
                    self.style.ERROR(f"  ✗ error limpiando cache '{alias}': {exc}")
                )
                logger.warning("Error limpiando cache '%s'", alias, exc_info=True)

        if total_cleared == len(aliases):
            self.stdout.write(
                self.style.SUCCESS(
                    f"\nCaché limpiado correctamente ({total_cleared} alias). "
                    "El backend recalculará los cortes en la próxima petición."
                )
            )
        else:
            self.stdout.write(
                self.style.WARNING(
                    f"\n{total_cleared}/{len(aliases)} alias limpiados. Revise los errores arriba."
                )
            )
