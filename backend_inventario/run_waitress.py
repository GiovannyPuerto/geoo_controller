"""
Servidor WSGI para Windows usando Waitress.

Uso:
    python run_waitress.py

Variables de entorno (opcionales):
    WSGI_HOST=0.0.0.0
    WSGI_PORT=8000
    WSGI_THREADS=4
    WSGI_CONNECTION_LIMIT=100
    WSGI_BACKLOG=64
    WSGI_CHANNEL_TIMEOUT=120
"""

import os

from waitress import serve

from backend_inventario.wsgi import application


def _env_int(name: str, default: int) -> int:
    value = os.environ.get(name)
    if value is None:
        return default
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


if __name__ == "__main__":
    host = os.environ.get("WSGI_HOST", "0.0.0.0")
    port = _env_int("WSGI_PORT", 8000)
    threads = _env_int("WSGI_THREADS", 4)
    connection_limit = _env_int("WSGI_CONNECTION_LIMIT", 100)
    backlog = _env_int("WSGI_BACKLOG", 64)
    channel_timeout = _env_int("WSGI_CHANNEL_TIMEOUT", 120)

    print(
        "Iniciando Waitress "
        f"host={host} port={port} threads={threads} "
        f"connection_limit={connection_limit} backlog={backlog} "
        f"channel_timeout={channel_timeout}"
    )

    serve(
        application,
        host=host,
        port=port,
        threads=threads,
        connection_limit=connection_limit,
        backlog=backlog,
        channel_timeout=channel_timeout,
        asyncore_use_poll=True,
    )
