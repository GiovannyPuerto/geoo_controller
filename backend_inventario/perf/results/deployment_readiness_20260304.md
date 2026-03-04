# Deployment Readiness - 2026-03-04

## Alcance ejecutado
- Django `check`: OK
- Smoke HTTP (22 endpoints API/export): 22/22 OK
- Stress runner (3 corridas): medio, alto-1, alto-2
- Stress de actualizaciones v?lidas/idempotencia: 11/11 OK

## Resultado general
- Estado: **CONDICIONAL (NO-GO para low-resource sin ajustes)**
- Motivo principal: latencias/extremos de memoria en exportaciones pesadas y ausencia de suite de tests automatizados.

## M?tricas clave

### Corrida media `perf_report_20260304_103146`
- RSS pico: 547.945 MB
- `cortes-mensuales` p95: 7003.152 ms
- `exportar-analisis/pdf` p95: 64027.923 ms
- `update_uploads` error rate: 100.0%

### Corrida alta-1 `perf_report_20260304_103749`
- RSS pico: 542.969 MB
- `exportar-analisis/excel` error rate: 100.0%
- `exportar-analisis/pdf` error rate: 100.0%
- `cortes-mensuales-productos` p95: 15651.438 ms

### Corrida alta-2 `perf_report_20260304_104948`
- RSS pico: 1111.0 MB
- `cortes-mensuales` p95: 16044.316 ms
- `exportar-analisis/pdf` p95: 146384.284 ms
- `update_uploads` error rate: 100.0%

### Stress actualizaciones v?lidas `valid_update_stress_20260304_110522`
- Requests: 11 | OK: 11 | Error: 0
- Incluye re-subidas de los mismos CSV (idempotencia): OK (all_duplicates con status 200).

## Hallazgos cr?ticos
- No existe suite de tests backend (`manage.py test` -> 0 tests).
- Hay drift de esquema pendiente: `makemigrations --check` propone `0028_alter_importbatch_nombre_inventario_and_more.py`.
- En carga alta, exportaciones de an?lisis exceden 100s-140s y pueden fallar por timeout bajo concurrencia.
- En low-resource, RSS lleg? a ~1.1 GB durante estr?s alto, riesgo de presi?n de memoria.
- El 100% de error en `update_uploads` del perf runner proviene de datos sint?ticos fuera de rango temporal respecto al base (no representa falla de endpoint).

## Recomendaciones antes de producci?n
- Ajustar timeout de export en cliente/backend o mover exportaciones pesadas a proceso as?ncrono (cola + polling).
- Ejecutar backend con Waitress/NSSM y l?mites controlados de concurrencia en Windows 2012 R2.
- Reducir cardinalidad de exportaci?n por defecto (limit/paginaci?n server-side para an?lisis pesado).
- Resolver migraci?n pendiente y versionar ese cambio antes de deploy.
- Implementar tests autom?ticos m?nimos: importaci?n base/actualizaci?n, duplicados, fechas, endpoints cr?ticos.

Generado: 2026-03-04T11:06:12.205069