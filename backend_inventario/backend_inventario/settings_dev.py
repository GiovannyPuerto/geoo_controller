"""
Configuración de desarrollo.
"""

import os

from .settings_base import *  # noqa: F401,F403

# En desarrollo se permite activar DEBUG fácilmente.
DEBUG = os.environ.get("DJANGO_DEBUG", "1") == "1"

# Hosts locales por defecto; se puede sobrescribir por variable de entorno.
ALLOWED_HOSTS = [
    h.strip()
    for h in os.environ.get(
        "DJANGO_ALLOWED_HOSTS",
        "127.0.0.1,localhost",
    ).split(",")
    if h.strip()
]

CORS_ALLOW_ALL_ORIGINS = True
CORS_ALLOW_CREDENTIALS = True
