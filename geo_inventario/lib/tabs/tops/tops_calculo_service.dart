class TopsCalculoService {
  static double toDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0.0;
  }

  static List<Map<String, dynamic>> filtrarBase(
    List<Map<String, dynamic>> source, {
    String? group,
    String? rotation,
    String? search,
  }) {
    final query = (search ?? '').trim().toLowerCase();

    return source.where((item) {
      if (group != null && group.isNotEmpty) {
        if ((item['grupo'] ?? '').toString() != group) return false;
      }
      if (rotation != null && rotation.isNotEmpty) {
        if ((item['rotacion'] ?? '').toString() != rotation) return false;
      }
      if (query.isNotEmpty) {
        final code = (item['codigo'] ?? '').toString().toLowerCase();
        final name = (item['nombre_producto'] ?? '').toString().toLowerCase();
        if (!code.contains(query) && !name.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  static List<Map<String, dynamic>> topBy(
    List<Map<String, dynamic>> source,
    double Function(Map<String, dynamic>) selector,
    int limit,
  ) {
    final sorted = List<Map<String, dynamic>>.from(source)
      ..sort((a, b) => selector(b).compareTo(selector(a)));
    return sorted.take(limit).toList();
  }

  static double valorMovimiento(
    Map<String, dynamic> item,
    String qtyKey,
    String valueKey,
  ) {
    final rawValue = toDouble(item[valueKey]);
    if (rawValue != 0) return rawValue;
    return toDouble(item[qtyKey]) * toDouble(item['costo_unitario']);
  }

  static Map<String, List<Map<String, dynamic>>> computeTopLists({
    required List<Map<String, dynamic>> analysisCutoff,
    required List<Map<String, dynamic>> analysisRange,
    required int topLimit,
    String? group,
    String? rotation,
    String? search,
  }) {
    final topsBaseCutoff = filtrarBase(
      analysisCutoff,
      group: group,
      rotation: rotation,
      search: search,
    );
    final topsBaseRange = filtrarBase(
      analysisRange,
      group: group,
      rotation: rotation,
      search: search,
    );

    return {
      'valor': topBy(
        topsBaseCutoff,
        (item) => toDouble(item['valor_saldo_actual']),
        topLimit,
      ),
      'entradas': topBy(
        topsBaseRange,
        (item) =>
            valorMovimiento(item, 'entradas_periodo', 'valor_entradas_periodo'),
        topLimit,
      ),
      'salidas': topBy(
        topsBaseRange,
        (item) =>
            valorMovimiento(item, 'salidas_periodo', 'valor_salidas_periodo'),
        topLimit,
      ),
    };
  }
}
