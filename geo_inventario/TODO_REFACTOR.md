He completado la modularización del frontend. A continuación, se detallan los cambios que realicé:

1. **Creación de Widgets de Pestaña Independientes**: He refactorizado la interfaz de usuario creando un widget `StatefulWidget` independiente para cada una de las tres pestañas principales (Resumen, Análisis y Movimientos). Cada widget de pestaña ahora gestiona su propio estado, la carga de datos y la lógica de la interfaz de usuario, lo que hace que el código sea mucho más limpio y fácil de mantener.

2. **Nueva Organización de Archivos**: Los nuevos widgets de pestaña se encuentran en un nuevo directorio `lib/tabs/`:
   - `lib/tabs/summary_tab.dart`
   - `lib/tabs/analysis_tab.dart`
   - `lib/tabs/movements_tab.dart`

3. **Simplificación de `dashboard.dart`**: El archivo `dashboard.dart` ha sido simplificado enormemente. Ahora actúa como un "shell" o contenedor principal que únicamente gestiona la barra de aplicaciones (`AppBar`) y el controlador de pestañas (`TabController`). Toda la lógica de negocio y la interfaz de usuario de las pestañas han sido delegadas a sus respectivos widgets.

4. **Eliminación de Lógica Redundante**: Se ha eliminado la lógica duplicada para la gestión de filtros y exportaciones. Cada pestaña ahora maneja sus propias acciones, como filtrar y exportar, a través de sus propios controles de interfaz de usuario.

**Archivos Antiguos**:
No he podido eliminar los archivos de widgets antiguos que han quedado obsoletos debido a la refactorización:
- `lib/widgets/summary_widgets.dart`
- `lib/widgets/movements_widgets.dart`
- `lib/widgets/analysis_tab.dart`

Estos archivos ya no se utilizan y pueden ser eliminados manualmente.

Si hay algo más en lo que pueda ayudarte, no dudes en decírmelo.