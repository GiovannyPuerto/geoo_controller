/// Servicio de persistencia para los valores de inventario ideal por grupo.
/// El valor ideal (objetivo) es definido por el usuario y se almacena
/// localmente usando shared_preferences.  La clave de cada entrada es el
/// nombre normalizado del grupo (mismo criterio que AnalisisCatalogoService).
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class IdealInventoryService {
  IdealInventoryService._();
  static final IdealInventoryService instance = IdealInventoryService._();

  static const String _key = 'ideal_inventory_values';

  Map<String, double> _values = {};

  /// Carga los valores guardados desde shared_preferences.
  /// Debe llamarse una vez en [State.initState] antes de leer los valores.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      _values = {};
      return;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _values = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      _values = {};
    }
  }

  /// Persiste el mapa completo (reemplaza todo lo anterior).
  /// Entradas con valor ≤ 0 son descartadas automáticamente.
  Future<void> save(Map<String, double> values) async {
    _values = Map<String, double>.from(values)..removeWhere((_, v) => v <= 0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_values));
  }

  /// Devuelve una copia de todos los valores guardados.
  Map<String, double> getAll() => Map<String, double>.from(_values);

  /// Valor ideal para un grupo específico, o [null] si no está definido.
  double? getValue(String groupName) => _values[groupName];

  /// Suma de todos los valores ideales definidos (valor general ideal).
  double getTotal() => _values.values.fold(0.0, (s, v) => s + v);
}
