class InventoryRecord {
  final int id;
  final String productCode;
  final String productDescription;
  final String warehouse;
  final String date;
  final String? documentType;
  final String? documentNumber;
  final double quantity;
  final double unitCost;
  final double total;
  final String category;
  final int batchId;
  final double finalQuantity; // Nuevo campo agregado

  InventoryRecord({
    required this.id,
    required this.productCode,
    required this.productDescription,
    required this.warehouse,
    required this.date,
    this.documentType,
    this.documentNumber,
    required this.quantity,
    required this.unitCost,
    required this.total,
    required this.category,
    required this.batchId,
    required this.finalQuantity, // Nuevo campo requerido
  });

  factory InventoryRecord.fromJson(Map<String, dynamic> json) {
    return InventoryRecord(
      id: json['id'] ?? 0,
      productCode: json['product_code'] ?? '',
      productDescription: json['product_description'] ?? '',
      warehouse: json['warehouse'] ?? '',
      date: json['date'] ?? '',
      documentType: json['document_type'],
      documentNumber: json['document_number'],
      quantity: (json['quantity'] ?? 0).toDouble(),
      unitCost: (json['unit_cost'] ?? 0).toDouble(),
      total: (json['total'] ?? 0).toDouble(),
      category: json['category'] ?? '',
      batchId: json['batch_id'] ?? 0,
      finalQuantity: (json['final_quantity'] ?? 0).toDouble(), // Nuevo campo
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_code': productCode,
      'product_description': productDescription,
      'warehouse': warehouse,
      'date': date,
      'document_type': documentType,
      'document_number': documentNumber,
      'quantity': quantity,
      'unit_cost': unitCost,
      'total': total,
      'category': category,
      'batch_id': batchId,
      'final_quantity': finalQuantity, // Nuevo campo
    };
  }

  // Campos adicionales para compatibilidad con el frontend
  String get item => productCode;
  String get descItem => productDescription;
  String get localizacion => warehouse;
  String get categoria => category;
  String get documento => '${documentType ?? ''}${documentNumber ?? ''}';
  double get entradas => quantity > 0 ? quantity : 0;
  double get salidas => quantity < 0 ? quantity.abs() : 0;
  double get unitario => unitCost;
}
