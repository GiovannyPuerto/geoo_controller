import 'package:flutter/foundation.dart';

/// Notificador global de actualización del inventario.
///
/// El Dashboard incrementa [version] cada vez que una carga de Excel
/// finaliza con éxito. Las tabs escuchan este notifier mediante
/// [ValueListenableBuilder] o [addListener] para recargar sus datos
/// automáticamente sin necesidad de un framework de estado externo.
///
/// Uso:
///   // En el Dashboard, tras upload exitoso:
///   inventoryRefreshNotifier.refresh();
///
///   // En una tab (initState + dispose):
///   inventoryRefreshNotifier.addListener(_onRefresh);
///   inventoryRefreshNotifier.removeListener(_onRefresh);
final InventoryRefreshNotifier inventoryRefreshNotifier =
    InventoryRefreshNotifier();

class InventoryRefreshNotifier extends ValueNotifier<int> {
  InventoryRefreshNotifier() : super(0);

  /// Incrementa la versión, notificando a todos los oyentes.
  void refresh() => value++;
}
