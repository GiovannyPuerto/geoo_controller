class ResumenAnalisisMetricas {
  const ResumenAnalisisMetricas({
    this.activos = 0,
    this.estancados = 0,
    this.obsoletos = 0,
    this.altaRotacion = 0,
    this.estancadoFlag = 0,
    this.topValor = const [],
    this.stockNegativo = const [],
  });

  final int activos;
  final int estancados;
  final int obsoletos;
  final int altaRotacion;
  final int estancadoFlag;
  final List<Map<String, dynamic>> topValor;
  final List<Map<String, dynamic>> stockNegativo;
}

class ResumenAnalisisService {
  static ResumenAnalisisMetricas calcular(
    List<Map<String, dynamic>> analysis, {
    int topLimit = 5,
  }) {
    int activos = 0;
    int estancados = 0;
    int obsoletos = 0;
    int altaRotacion = 0;
    int estancadoFlag = 0;
    final stockNegativo = <Map<String, dynamic>>[];

    for (final item in analysis) {
      final rotacion = (item['rotacion'] ?? '').toString();
      final isAltaRotacion = (item['alta_rotacion'] ?? '').toString() == 'Sí';
      final isEstancado = (item['estancado'] ?? '').toString() == 'Sí';
      final cantidadSaldo = _toDouble(item['cantidad_saldo_actual']);

      if (rotacion == 'Activo') activos++;
      if (rotacion == 'Estancado') estancados++;
      if (rotacion == 'Obsoleto') obsoletos++;
      if (isAltaRotacion) altaRotacion++;
      if (isEstancado) estancadoFlag++;
      if (cantidadSaldo < 0) stockNegativo.add(item);
    }

    final topValor = List<Map<String, dynamic>>.from(analysis)
      ..sort(
        (a, b) => _toDouble(b['valor_saldo_actual'])
            .compareTo(_toDouble(a['valor_saldo_actual'])),
      );

    return ResumenAnalisisMetricas(
      activos: activos,
      estancados: estancados,
      obsoletos: obsoletos,
      altaRotacion: altaRotacion,
      estancadoFlag: estancadoFlag,
      topValor: topValor.take(topLimit).toList(),
      stockNegativo: stockNegativo,
    );
  }

  static int totalProductos(Map<String, dynamic>? summary) {
    return (summary?['total_products'] ?? 0) as int;
  }

  static double valorTotal(Map<String, dynamic>? summary) {
    return _toDouble(summary?['total_value']);
  }

  static bool tieneDatos(Map<String, dynamic>? summary) {
    return totalProductos(summary) > 0;
  }

  static double porcentaje(int cantidad, int total) {
    if (total <= 0) return 0;
    return (cantidad / total) * 100;
  }

  static double _toDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0.0;
  }
}
