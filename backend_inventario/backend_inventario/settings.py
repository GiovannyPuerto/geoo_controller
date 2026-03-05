"""
Single Django settings module for deployment-oriented configuration.

All behavior is controlled by environment variables.
"""

import os
from pathlib import Path
from tempfile import gettempdir


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


def _resolve_runtime_dir() -> Path:
    env_runtime = os.environ.get("DJANGO_RUNTIME_DIR", "").strip()
    if env_runtime:
        return Path(env_runtime)

    if os.name == "nt":
        program_data = os.environ.get("PROGRAMDATA", "").strip()
        if program_data:
            return Path(program_data) / "GeoInventario"

    return Path(gettempdir()) / "geo_inventario"


RUNTIME_DIR = _resolve_runtime_dir()
CACHE_DIR = Path(os.environ.get("DJANGO_CACHE_DIR", str(RUNTIME_DIR / "cache")))
EXPORT_CACHE_DIR = Path(
    os.environ.get("DJANGO_EXPORT_CACHE_DIR", str(CACHE_DIR / "exports"))
)
LOG_DIR = Path(os.environ.get("DJANGO_LOG_DIR", str(RUNTIME_DIR / "logs")))

os.makedirs(CACHE_DIR, exist_ok=True)
os.makedirs(EXPORT_CACHE_DIR, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)


def _default_cache_backend() -> str:
    configured = os.environ.get("DJANGO_CACHE_BACKEND", "").strip()
    if configured:
        return configured

    # En Windows low-resource preferimos cache en disco para evitar picos de RAM.
    if os.name == "nt":
        return "django.core.cache.backends.filebased.FileBasedCache"
    return "django.core.cache.backends.locmem.LocMemCache"

SECRET_KEY = os.environ.get(
    "DJANGO_SECRET_KEY",
    "django-insecure-94%twijjr$x^=!_2m770k)*+a%%vba9#lwhgiagyknz)r6w0hk",
)
DEBUG = _env_bool("DJANGO_DEBUG", False)

ALLOWED_HOSTS = [
    h.strip()
    for h in os.environ.get("DJANGO_ALLOWED_HOSTS", "127.0.0.1,localhost").split(",")
    if h.strip()
]

INSTALLED_APPS = [
    # Django auth/contenttypes se mantienen por dependencias de migraciones existentes.
    "django.contrib.auth",
    "django.contrib.contenttypes",
    # Apps de usuario
    "rest_framework",
    "corsheaders",
    "inventory",
]

MIDDLEWARE = [
    "django.middleware.gzip.GZipMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.middleware.common.CommonMiddleware",
]

ROOT_URLCONF = "backend_inventario.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            # Solo se necesita request; auth y messages ya no están instalados.
            "context_processors": [
                "django.template.context_processors.request",
            ],
        },
    },
]

WSGI_APPLICATION = "backend_inventario.wsgi.application"

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.mysql",
        "NAME": os.environ.get("DB_NAME", "manage_inventory"),
        "USER": os.environ.get("DB_USER", "root"),
        "PASSWORD": os.environ.get("DB_PASSWORD", "12345"),
        "HOST": os.environ.get("DB_HOST", "localhost"),
        "PORT": os.environ.get("DB_PORT", "3306"),
        # En low-resource cerramos conexión al final de cada request para
        # minimizar conexiones MySQL en estado SLEEP.
        "CONN_MAX_AGE": _env_int("DB_CONN_MAX_AGE", 0),
        "CONN_HEALTH_CHECKS": True,
        "OPTIONS": {
            "init_command": "SET sql_mode='STRICT_TRANS_TABLES'",
            "charset": "utf8mb4",
            "connect_timeout": _env_int("DB_CONNECT_TIMEOUT", 8),
            "read_timeout": _env_int("DB_READ_TIMEOUT", 30),
            "write_timeout": _env_int("DB_WRITE_TIMEOUT", 30),
        },
    }
}


CACHES = {
    "default": {
        "BACKEND": _default_cache_backend(),
        # Solo aplica cuando se usa FileBasedCache.
        "LOCATION": str(CACHE_DIR),
        "TIMEOUT": _env_int("DJANGO_CACHE_TIMEOUT", 3600),
        "OPTIONS": {
            "MAX_ENTRIES": _env_int("DJANGO_CACHE_MAX_ENTRIES", 20000),
            "CULL_FREQUENCY": _env_int("DJANGO_CACHE_CULL_FREQUENCY", 4),
        },
        "KEY_PREFIX": os.environ.get("DJANGO_CACHE_KEY_PREFIX", "geo_inv"),
    },
    # Alias dedicado a binarios de exportación (Excel/PDF): evita llevar blobs
    # grandes al cache in-memory cuando el backend está en Windows low-resource.
    "exports": {
        "BACKEND": "django.core.cache.backends.filebased.FileBasedCache",
        "LOCATION": str(EXPORT_CACHE_DIR),
        "TIMEOUT": _env_int("INVENTORY_EXPORT_RESPONSE_CACHE_TTL_SECONDS", 900),
        "OPTIONS": {
            "MAX_ENTRIES": _env_int("DJANGO_EXPORT_CACHE_MAX_ENTRIES", 256),
            "CULL_FREQUENCY": _env_int("DJANGO_EXPORT_CACHE_CULL_FREQUENCY", 2),
        },
        "KEY_PREFIX": os.environ.get("DJANGO_EXPORT_CACHE_KEY_PREFIX", "geo_inv_exp"),
    }
}

REST_FRAMEWORK = {
    "DEFAULT_RENDERER_CLASSES": [
        "rest_framework.renderers.JSONRenderer",
    ],
    "DEFAULT_PARSER_CLASSES": [
        "rest_framework.parsers.JSONParser",
    ],
}

AUTH_PASSWORD_VALIDATORS = [
    {
        "NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator",
    },
    {
        "NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
    },
    {
        "NAME": "django.contrib.auth.password_validation.CommonPasswordValidator",
    },
    {
        "NAME": "django.contrib.auth.password_validation.NumericPasswordValidator",
    },
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = False
USE_TZ = True

STATIC_URL = "static/"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = "SAMEORIGIN"
SESSION_COOKIE_SECURE = _env_bool("SESSION_COOKIE_SECURE", False)
CSRF_COOKIE_SECURE = _env_bool("CSRF_COOKIE_SECURE", False)

USE_X_FORWARDED_HOST = _env_bool("USE_X_FORWARDED_HOST", False)
if _env_bool("USE_X_FORWARDED_PROTO", False):
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

CORS_ALLOW_ALL_ORIGINS = _env_bool("CORS_ALLOW_ALL_ORIGINS", False)
CORS_ALLOW_CREDENTIALS = _env_bool("CORS_ALLOW_CREDENTIALS", True)
if not CORS_ALLOW_ALL_ORIGINS:
    CORS_ALLOWED_ORIGINS = [
        origin.strip()
        for origin in os.environ.get("CORS_ALLOWED_ORIGINS", "").split(",")
        if origin.strip()
    ]

DATA_UPLOAD_MAX_MEMORY_SIZE = _env_int("DATA_UPLOAD_MAX_MEMORY_SIZE", 10 * 1024 * 1024)
FILE_UPLOAD_MAX_MEMORY_SIZE = _env_int("FILE_UPLOAD_MAX_MEMORY_SIZE", 8 * 1024 * 1024)
DATA_UPLOAD_MAX_NUMBER_FIELDS = _env_int("DATA_UPLOAD_MAX_NUMBER_FIELDS", 2000)

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
