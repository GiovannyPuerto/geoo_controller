# TODO: Mejoras de UI en Flutter App

## Información Gathered
- **Archivos principales**: `main.dart` (WelcomePage) y `dashboard.dart` (DashboardPage con tabs).
- **Estructura actual**: Usa Material Design con colores verdes (#10B981). Incluye logos, botones elevados, cards, y navegación básica.
- **Funcionalidades**: Subida de archivos, filtros, exportación, gráficos con Syncfusion.
- **Estado actual**: UI básica, sin gradientes, sombras avanzadas, animaciones o efectos modernos.

## Plan
- **main.dart**:
  - Actualizar theme con gradientes, sombras y colores modernos.
  - Mejorar botones: agregar íconos, sombras, efectos hover/tap, animaciones.
  - Rediseñar header: gradientes, mejor espaciado, íconos animados.
  - Agregar animaciones a secciones (hero, fade-in).
  - Mejorar navegación: transiciones suaves.

- **dashboard.dart**:
  - Rediseñar AppBar: gradientes, sombras, íconos modernos, animaciones.
  - Mejorar botones: estilos elevados con gradientes, íconos, efectos.
  - Agregar animaciones a tabs y contenido (slide, fade).
  - Mejorar cards y gráficos: sombras, bordes redondeados, gradientes.
  - Optimizar navegación: transiciones entre tabs.

## Dependent Files to be edited
- `geo_inventario/lib/main.dart`
- `geo_inventario/lib/dashboard.dart`

## Followup steps
- Ejecutar la app para verificar renderizado.
- Probar en diferentes tamaños de pantalla.
- Verificar funcionalidad (subida, filtros, exportación).
- Ajustar si hay problemas de rendimiento.
