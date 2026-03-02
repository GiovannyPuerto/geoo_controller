# Pruebas exhaustivas de consumo y velocidad

Este módulo corre benchmarks sobre endpoints pesados de la API:

- Subida de archivos: `POST /api/inventory/actualizar/<inventory>/`
- Lecturas pesadas: `analisis-producto`, `registros`, `movimientos-mensuales`, `cortes-mensuales`, `cortes-mensuales-productos`, `inventario-a-fecha`, `resumen`
- Descargas pesadas: `exportar-analisis`, `exportar-movimientos`, `exportar-cortes-mensuales`, `exportar-tops` (excel/pdf)

Además, si pasas `--server-pid`, mide consumo del proceso backend (CPU y RAM).

## Requisitos

Instalar dependencias en el backend:

```powershell
Set-Location backend_inventario
..\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

## 1) Levantar backend

```powershell
Set-Location backend_inventario
..\.venv\Scripts\python.exe manage.py runserver 0.0.0.0:8000
```

## 2) Obtener PID del proceso backend (opcional, recomendado)

```powershell
Get-Process python | Select-Object Id,ProcessName,Path
```

## 3) Ejecutar benchmark completo

```powershell
Set-Location backend_inventario
..\.venv\Scripts\python.exe perf\perf_runner.py `
  --base-url http://127.0.0.1:8000/api/inventory `
  --server-pid 12345 `
  --base-rows 30000 `
  --update-rows 50000 `
  --update-files 4 `
  --read-workers 10 `
  --read-repeats 12 `
  --export-workers 4 `
  --export-repeats 3 `
  --upload-workers 3 `
  --upload-repeats 3
```

> Cambia `12345` por el PID real.

## Reportes

Se generan en `backend_inventario/perf/results/`:

- `perf_report_YYYYMMDD_HHMMSS.json` (detalle completo)
- `perf_report_YYYYMMDD_HHMMSS.md` (resumen ejecutivo)

## Interpretación rápida

Prioriza estos umbrales en servidor limitado:

- `error_rate_pct` cercano a `0`
- `p95_ms` estable y menor a `2x` del `avg_ms`
- `rss_peak_mb` sin crecimiento sostenido entre corridas
- Exportaciones PDF/Excel sin timeouts

## Prueba de estrés larga (soak test)

Para detectar degradación por memoria/caché, ejecuta 3 rondas seguidas y compara `rss_peak_mb` y `p95_ms`.

```powershell
Set-Location backend_inventario
.\perf\run_soak_3_rounds.ps1 -BaseUrl http://127.0.0.1:8000/api/inventory -ServerPid 12345
```