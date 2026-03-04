"""
Configuración recomendada para despliegue en Windows Server 2012 R2
con recursos limitados.
"""

import os
from pathlib import Path

from .settings_base import *  # noqa: F401,F403


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "t", "yes", "y", "on"}


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        return int(raw)
    except (TypeError, ValueError):
        return default


BASE_DIR = Path(__file__).resolve().parent.parent
VAR_DIR = BASE_DIR / "var"
CACHE_DIR = VAR_DIR / "cache"
LOG_DIR = VAR_DIR / "logs"

os.makedirs(CACHE_DIR, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)

DEBUG = _env_bool("DJANGO_DEBUG", False)

_allowed_hosts_default = "127.0.0.1,localhost"
ALLOWED_HOSTS = [
    h.strip()
    for h in os.environ.get("DJANGO_ALLOWED_HOSTS", _allowed_hosts_default).split(",")
    if h.strip()
]

# Seguridad básica de cabeceras (sin exigir HTTPS para facilitar intranet local).
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = "SAMEORIGIN"

SESSION_COOKIE_SECURE = _env_bool("SESSION_COOKIE_SECURE", False)
CSRF_COOKIE_SECURE = _env_bool("CSRF_COOKIE_SECURE", False)

USE_X_FORWARDED_HOST = _env_bool("USE_X_FORWARDED_HOST", False)
if _env_bool("USE_X_FORWARDED_PROTO", False):
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

# CORS restringido por defecto (más seguro en despliegue).
CORS_ALLOW_ALL_ORIGINS = _env_bool("CORS_ALLOW_ALL_ORIGINS", False)
CORS_ALLOW_CREDENTIALS = _env_bool("CORS_ALLOW_CREDENTIALS", True)
if not CORS_ALLOW_ALL_ORIGINS:
    CORS_ALLOWED_ORIGINS = [
        origin.strip()
        for origin in os.environ.get("CORS_ALLOWED_ORIGINS", "").split(",")
        if origin.strip()
    ]

# Límites de subida conservadores para no disparar RAM.
DATA_UPLOAD_MAX_MEMORY_SIZE = _env_int("DATA_UPLOAD_MAX_MEMORY_SIZE", 10 * 1024 * 1024)
FILE_UPLOAD_MAX_MEMORY_SIZE = _env_int("FILE_UPLOAD_MAX_MEMORY_SIZE", 8 * 1024 * 1024)
DATA_UPLOAD_MAX_NUMBER_FIELDS = _env_int("DATA_UPLOAD_MAX_NUMBER_FIELDS", 2000)

# Ajustes DB recomendados para servidor pequeño.
DATABASES["default"]["CONN_MAX_AGE"] = _env_int("DB_CONN_MAX_AGE", 120)
DATABASES["default"]["CONN_HEALTH_CHECKS"] = True
DATABASES["default"].setdefault("OPTIONS", {})
DATABASES["default"]["OPTIONS"].update(
    {
        "connect_timeout": _env_int("DB_CONNECT_TIMEOUT", 8),
        "read_timeout": _env_int("DB_READ_TIMEOUT", 30),
        "write_timeout": _env_int("DB_WRITE_TIMEOUT", 30),
    }
)

# Cache en disco para ahorrar memoria RAM cuando se usa un solo proceso.
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.filebased.FileBasedCache",
        "LOCATION": str(CACHE_DIR),
        "TIMEOUT": _env_int("DJANGO_CACHE_TIMEOUT", 3600),
        "OPTIONS": {
            "MAX_ENTRIES": _env_int("DJANGO_CACHE_MAX_ENTRIES", 20000),
            "CULL_FREQUENCY": _env_int("DJANGO_CACHE_CULL_FREQUENCY", 4),
        },
        "KEY_PREFIX": os.environ.get("DJANGO_CACHE_KEY_PREFIX", "geo_inv"),
    }
}

# Logging a archivo rotativo + consola (nivel bajo para ahorrar IO).
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "standard": {
            "format": "%(asctime)s %(levelname)s [%(name)s] %(message)s",
            "datefmt": "%Y-%m-%d %H:%M:%S",
        },
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "standard",
            "level": os.environ.get("DJANGO_CONSOLE_LOG_LEVEL", "WARNING"),
        },
        "file": {
            "class": "logging.handlers.RotatingFileHandler",
            "filename": str(LOG_DIR / "backend.log"),
            "maxBytes": _env_int("DJANGO_LOG_MAX_BYTES", 3 * 1024 * 1024),
            "backupCount": _env_int("DJANGO_LOG_BACKUP_COUNT", 3),
            "formatter": "standard",
            "encoding": "utf-8",
            "level": os.environ.get("DJANGO_FILE_LOG_LEVEL", "INFO"),
        },
    },
    "loggers": {
        "": {
            "handlers": ["console", "file"],
            "level": os.environ.get("DJANGO_LOG_LEVEL", "WARNING"),
            "propagate": False,
        },
        "inventory.services.import_service": {
            "handlers": ["console", "file"],
            "level": os.environ.get("INVENTORY_IMPORT_LOG_LEVEL", "INFO"),
            "propagate": False,
        },
    },
}
