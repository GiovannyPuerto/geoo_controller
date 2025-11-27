class MonthlyMovement {
  final String month;
  final double totalEntries;
  final double totalExits;
  final double closingBalance;

  MonthlyMovement({
    required this.month,
    required this.totalEntries,
    required this.totalExits,
    required this.closingBalance,
  });

  factory MonthlyMovement.fromJson(Map<String, dynamic> json) {
    return MonthlyMovement(
      month: json['month'],
      totalEntries: (json['total_entries'] as num).toDouble(),
      totalExits: (json['total_exits'] as num).toDouble(),
      closingBalance: (json['closing_balance'] as num).toDouble(),
    );
  }
}
