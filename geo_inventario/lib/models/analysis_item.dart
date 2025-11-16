class AnalysisItem {
  final String codigo;
  final String nombreProducto;
  final String grupo;
  final double cantidadSaldoActual;
  final double valorSaldoActual;
  final double costoUnitario;
  final String estancado;
  final String rotacion;
  final String altaRotacion;
  final String almacen;

  AnalysisItem({
    required this.codigo,
    required this.nombreProducto,
    required this.grupo,
    required this.cantidadSaldoActual,
    required this.valorSaldoActual,
    required this.costoUnitario,
    required this.estancado,
    required this.rotacion,
    required this.altaRotacion,
    required this.almacen,
  });

  factory AnalysisItem.fromJson(Map<String, dynamic> json) {
    return AnalysisItem(
      codigo: json['codigo'] ?? '',
      nombreProducto: json['nombre_producto'] ?? '',
      grupo: json['grupo'] ?? '',
      cantidadSaldoActual: (json['cantidad_saldo_actual'] ?? 0).toDouble(),
      valorSaldoActual: (json['valor_saldo_actual'] ?? 0).toDouble(),
      costoUnitario: (json['costo_unitario'] ?? 0).toDouble(),
      estancado: json['estancado'] ?? 'No',
      rotacion: json['rotacion'] ?? 'Activo',
      altaRotacion: json['alta_rotacion'] ?? 'No',
      almacen: json['almacen'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'codigo': codigo,
      'nombre_producto': nombreProducto,
      'grupo': grupo,
      'cantidad_saldo_actual': cantidadSaldoActual,
      'valor_saldo_actual': valorSaldoActual,
      'costo_unitario': costoUnitario,
      'estancado': estancado,
      'rotacion': rotacion,
      'alta_rotacion': altaRotacion,
      'almacen': almacen,
    };
  }

  // Propiedades calculadas para compatibilidad
  bool get isStagnant => estancado == 'Sí';
  bool get isHighRotation => altaRotacion == 'Sí';
  bool get isActive => rotacion == 'Activo';
  bool get isObsolete => rotacion == 'Obsoleto';
  bool get isStagnantRotation => rotacion == 'Estancado';
}
