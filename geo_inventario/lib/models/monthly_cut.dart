class MonthlyCut {
  final String month;
  final double openingBalance;
  final double totalEntries;
  final double totalExits;
  final double closingBalance;
  final double averageBalanceGeneral;
  final double averageBalancePerProduct;
  final int productsCount;

  MonthlyCut({
    required this.month,
    required this.openingBalance,
    required this.totalEntries,
    required this.totalExits,
    required this.closingBalance,
    required this.averageBalanceGeneral,
    required this.averageBalancePerProduct,
    required this.productsCount,
  });

  double get averageBalance => averageBalanceGeneral;

  factory MonthlyCut.fromJson(Map<String, dynamic> json) {
    final avgGeneral = ((json['average_balance_general'] as num?) ??
            (json['average_balance'] as num?) ??
            0)
        .toDouble();
    final count = (json['products_count'] as int?) ?? 0;
    final avgPerProduct = ((json['average_balance_per_product'] as num?) ??
            (count > 0 ? avgGeneral / count : avgGeneral))
        .toDouble();

    return MonthlyCut(
      month: (json['month'] ?? '').toString(),
      openingBalance: ((json['opening_balance'] as num?) ?? 0).toDouble(),
      totalEntries: ((json['total_entries'] as num?) ?? 0).toDouble(),
      totalExits: ((json['total_exits'] as num?) ?? 0).toDouble(),
      closingBalance: ((json['closing_balance'] as num?) ?? 0).toDouble(),
      averageBalanceGeneral: avgGeneral,
      averageBalancePerProduct: avgPerProduct,
      productsCount: count,
    );
  }
}
