class Product {
  final String code;
  final String description;
  final String group;
  final double initialBalance;
  final double initialUnitCost;
  final String inventoryName;

  Product({
    required this.code,
    required this.description,
    required this.group,
    required this.initialBalance,
    required this.initialUnitCost,
    required this.inventoryName,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      code: json['code'] ?? '',
      description: json['description'] ?? '',
      group: json['group'] ?? '',
      initialBalance: (json['initial_balance'] ?? 0).toDouble(),
      initialUnitCost: (json['initial_unit_cost'] ?? 0).toDouble(),
      inventoryName: json['inventory_name'] ?? 'default',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'description': description,
      'group': group,
      'initial_balance': initialBalance,
      'initial_unit_cost': initialUnitCost,
      'inventory_name': inventoryName,
    };
  }
}
