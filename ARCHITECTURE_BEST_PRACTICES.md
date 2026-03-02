# Arquitectura y mejores prácticas (Geo Inventario)

Este documento define estándares para mantenimiento, escalabilidad y rendimiento con bajo consumo de recursos.

## 0) Convención global (obligatoria para TODO el proyecto)

- **Idioma**: nombres de módulos/servicios/helpers en **español claro e intuitivo**.
- **Intención explícita**: cada archivo debe expresar su responsabilidad por nombre (ejemplo: `vistas/lectura.py`, `resumen_analisis_service.dart`).
- **UI vs lógica**: widgets y views solo orquestan; cálculos, filtros y transformaciones viven en servicios.
- **Compatibilidad gradual**: refactorizar por capas sin romper contratos existentes.
- **Sin duplicación**: si una regla se repite en 2+ lugares, moverla a un servicio compartido.

## 1) Principios base

- **Simpleza primero**: resolver con menos moving parts posibles.
- **I/O sobre CPU**: priorizar filtros en DB y evitar loops Python sobre millones de filas.
- **Límites defensivos**: todo endpoint listado debe tener `limit` y `offset` con topes.
- **Cache corta e inteligente**: TTLs cortos en lectura; invalidación explícita en escritura.
- **Carga diferida**: librerías pesadas solo cuando se usan (exports/reportes).

## 2) Estructura backend (Django)

- `inventory/vistas/lectura.py`: endpoints GET y consultas.
- `inventory/vistas/escritura.py`: endpoints POST/rollback y mutaciones.
- `inventory/vistas/exportacion.py`: endpoints de exportación.
- `inventory/views.py`: compatibilidad legacy mínima (reexporta módulos nuevos).
- `inventory/services/*`: lógica de negocio, cálculos, filtros y renderización.
- `inventory/services/analitica_inventario_service.py`: fachada en español para cálculos analíticos.
- `inventory/services/consulta_registros_service.py`: fachada en español para filtros/slicing de registros.
- `inventory/services/resumen_inventario_service.py`: fachada en español para resumen general.
- `inventory/services/importacion_inventario_service.py`: fachada en español para importación.
- `inventory/services/record_query_service.py`: filtros comunes para movimientos y slicing seguro.
- `inventory/services/datos_exportacion_service.py`: construcción de datasets para exportes.
- `inventory/services/render_exportacion_service.py`: render Excel/PDF de exportes con carga diferida de dependencias.
- `inventory/services/import_service.py`: procesamiento por chunks para archivos grandes.

### Estado actual de migración

- Migración modular de endpoints completada en `vistas/lectura.py`, `vistas/escritura.py` y `vistas/exportacion.py`.
- `views.py` queda como puente de compatibilidad para imports históricos, sin lógica pesada.

### Convención recomendada

- Nuevo endpoint pesado => crear servicio dedicado en `services/`.
- Reglas de filtrado compartidas => no duplicar en views, mover a servicio reutilizable.

### Mapa de transición (legacy -> español)

- `analytics_service.py` -> `analitica_inventario_service.py`
- `record_query_service.py` -> `consulta_registros_service.py`
- `summary_service.py` -> `resumen_inventario_service.py`
- `import_service.py` -> `importacion_inventario_service.py`

> Nota: la base legacy se mantiene para compatibilidad; nuevas vistas/servicios deben preferir las fachadas en español.

### Política de rutas API (compatibilidad + mantenimiento)

- Mantener rutas legacy activas mientras existan clientes dependientes.
- Publicar y usar rutas en español para nuevos desarrollos y pruebas internas.
- Convención sugerida de prefijos:
  - lectura: `obtener-*`
  - escritura: `crear-*`, `actualizar-*`, `revertir-*`, `subir-*`
  - exportación: `exportar-*`
- Registrar en `urls.py` ambas rutas (legacy y español) apuntando a la misma vista.

## 3) Performance y consumo

### Backend

- Mantener `CONN_MAX_AGE` activo para reuso de conexiones DB.
- Evitar `select_related/prefetch_related` innecesarios cuando `values()` cubra la respuesta.
- Limitar respuestas de listados (`max_limit`) para proteger RAM/CPU.
- Usar cache corto (`15-30s`) en endpoints más consultados.
- En endpoints de escritura (`upload`, `rollback`) limpiar cache para evitar lecturas obsoletas.

### Base de datos

- Indexar campos de filtro frecuentes (`inventory_name`, fechas, llaves compuestas de búsqueda).
- Revisar planes de ejecución periódicamente (`EXPLAIN`) para endpoints más costosos.
- Evitar `LIKE %term%` en tablas gigantes sin estrategia adicional (cuando escale, considerar índices full-text o columna normalizada).

## 4) Modularización y mantenibilidad

- Máximo recomendado por módulo: **~400-600 líneas**; si crece, extraer submódulos temáticos.
- Evitar helpers repetidos en views; centralizarlos en servicios.
- Definir contratos de entrada/salida por servicio (docstring corto + tipos).

## 5) Observabilidad mínima (obligatoria)

- Log de errores con contexto (`inventory_name`, endpoint, tamaño de lote).
- Métricas periódicas de:
  - latencia p50/p95/p99,
  - tasa de error,
  - consumo RSS del proceso,
  - duración de importaciones y exportaciones.
- Recomendación: ejecutar `perf/perf_runner.py` antes de cada release mayor.

## 6) Política de cambios seguros

- Todo cambio de rendimiento debe validar:
  - no rompe contrato API,
  - no aumenta error rate,
  - no sube p95 de endpoints críticos,
  - no aumenta consumo pico de memoria.

## 7) Frontend Flutter

- Evitar refrescos redundantes de análisis; usar cache local temporal y deduplicación de requests.
- Limitar render de listas grandes; preferir paginación o cargas incrementales.
- Mantener lógica de negocio fuera de widgets (en servicios).
- Organizar por dominio funcional bajo `lib/tabs/<dominio>/` cuando el tab crezca.
- Nombrar servicios de forma descriptiva y en español (`*_service.dart`) para facilitar mantenimiento operativo.

## 8) Checklist operativo para despliegue en servidor limitado

- `DJANGO_DEBUG=0`
- `DB_CONN_MAX_AGE=120` (ajustar según carga)
- `DJANGO_CACHE_TIMEOUT=60`
- Ejecutar migraciones e índices antes de pruebas de carga
- Ejecutar benchmark rápido + soak test antes de pasar a producción
