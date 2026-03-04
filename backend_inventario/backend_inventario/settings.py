"""
Selector de configuración por perfil.

Perfiles soportados (INVENTORY_SETTINGS_PROFILE / DJANGO_ENV):
- dev      : desarrollo local.
- win_low  : despliegue Windows Server 2012 R2 con recursos bajos.
"""

import os

_PROFILE = (
    os.environ.get("INVENTORY_SETTINGS_PROFILE")
    or os.environ.get("DJANGO_ENV")
    or "dev"
).strip().lower()

if _PROFILE in {"win_low", "prod", "production", "windows"}:
    from .settings_win_low import *  # noqa: F401,F403
else:
    from .settings_dev import *  # noqa: F401,F403
