# Despliegue Backend en Windows Server 2012 R2 (Recursos Bajos)

## 1. Objetivo
Esta guía deja el backend Django en modo estable para entorno histórico:
- sin recálculos innecesarios en cada consulta,
- con caché de larga duración,
- con servidor WSGI liviano para Windows (`waitress`).

## 2. Requisitos mínimos recomendados
- Windows Server 2012 R2
- Python 3.10.x
- MySQL 5.7+ / 8.x
- 2 vCPU, 4 GB RAM (mínimo funcional)

## 3. Preparación del entorno
Desde `backend_inventario`:

```powershell
python -m venv .venv310
.venv310\Scripts\Activate.ps1
pip install --upgrade pip
pip install -r requirements.txt
```

## 4. Variables de entorno
Usar como base: `.env.win_low.example`.

Variables clave:
- `DJANGO_DEBUG=0`
- `DJANGO_ALLOWED_HOSTS=IP_LOCAL,localhost`
- credenciales `DB_*`
- opcional: `DJANGO_RUNTIME_DIR` para definir dónde guardar cache/logs (fuera del código)

## 5. Inicializar base de datos
```powershell
python manage.py migrate
```

Nota:
- La migración más reciente agrega índices para lectura histórica.
- En bases grandes, la primera ejecución puede tardar algunos minutos.

## 6. Ejecutar backend con Waitress
```powershell
python run_waitress.py
```

Por defecto escucha en `0.0.0.0:8000`.

Alternativa con carga automática de variables desde archivo:
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_backend_win_low.ps1 -EnvFile .\.env.win_low.example
```

## 7. Ejecutar como servicio (NSSM recomendado)
1. Instalar NSSM.
2. Crear servicio apuntando a:
   - Aplicación: `C:\ruta\backend_inventario\.venv310\Scripts\python.exe`
   - Argumentos: `C:\ruta\backend_inventario\run_waitress.py`
   - Directorio: `C:\ruta\backend_inventario`
3. Definir variables de entorno del servicio (`DJANGO_DEBUG`, `DB_*`, etc.).
4. Iniciar servicio.

## 8. Ajustes de bajo consumo
- `WSGI_THREADS=4` (subir a 6 si hay CPU disponible).
- `DB_CONN_MAX_AGE=0` para evitar conexiones MySQL en `SLEEP` cuando el servidor
  tiene pocos recursos.
- `DJANGO_LOG_LEVEL=WARNING`.
- Mantener `INVENTORY_HISTORIC_CACHE_TTL_SECONDS` alto (ej. 7 días) porque los datos son históricos.
- `INVENTORY_CACHE_VERSION_TTL_SECONDS=30` para detectar cambios de BD y
  rotar claves de caché automáticamente.
- Activar cache de exportaciones: `INVENTORY_EXPORT_RESPONSE_CACHE_TTL_SECONDS=900`
  para reutilizar archivos Excel/PDF iguales y reducir picos de CPU/RAM.
- Mantener exportaciones grandes fuera de RAM:
  - `INVENTORY_EXPORT_CACHE_ALIAS=exports` (alias file-based),
  - `INVENTORY_EXPORT_RESPONSE_CACHE_MAX_BYTES` para limitar blobs cacheados.

## 9. Buenas prácticas operativas
- No usar `runserver` en producción.
- Respaldos diarios de MySQL.
- Monitorear:
  - tamaño del archivo de log configurado (`%DJANGO_LOG_DIR%\backend.log` o `%PROGRAMDATA%\GeoInventario\logs\backend.log`),
  - uso de RAM del proceso Python,
  - latencia de `/api/inventory/resumen/` y `/api/inventory/analisis-producto/`.

## 10. Verificación rápida
```powershell
python manage.py check
python -c "import backend_inventario.settings as s; print('OK', hasattr(s, 'DATABASES'))"
```
