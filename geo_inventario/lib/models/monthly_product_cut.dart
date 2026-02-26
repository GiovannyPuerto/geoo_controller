class MonthlyProductCut {
  final String code;
  final String description;
  final String group;
  final double openingQuantity;
  final double closingQuantity;
  final double averageQuantity;
  final double unitCost;
  final double openingValue;
  final double closingValue;
  final double averageValue;

  MonthlyProductCut({
    required this.code,
    required this.description,
    required this.group,
    required this.openingQuantity,
    required this.closingQuantity,
    required this.averageQuantity,
    required this.unitCost,
    required this.openingValue,
    required this.closingValue,
    required this.averageValue,
  });

  factory MonthlyProductCut.fromJson(Map<String, dynamic> json) {
    return MonthlyProductCut(
      code: (json['codigo'] ?? '').toString(),
      description: (json['nombre_producto'] ?? '').toString(),
      group: (json['grupo'] ?? '').toString(),
      openingQuantity: ((json['cantidad_apertura'] as num?) ?? 0).toDouble(),
      closingQuantity: ((json['cantidad_cierre'] as num?) ?? 0).toDouble(),
      averageQuantity: ((json['cantidad_promedio'] as num?) ?? 0).toDouble(),
      unitCost: ((json['costo_unitario'] as num?) ?? 0).toDouble(),
      openingValue: ((json['valor_apertura'] as num?) ?? 0).toDouble(),
      closingValue: ((json['valor_cierre'] as num?) ?? 0).toDouble(),
      averageValue: ((json['valor_promedio'] as num?) ?? 0).toDouble(),
    );
  }
}
