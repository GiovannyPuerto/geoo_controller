import 'package:intl/intl.dart';
import 'package:geo_inventario/models/monthly_cut.dart';

class MonthlyCutsFilterOptions {
  const MonthlyCutsFilterOptions({
    required this.warehouses,
    required this.categories,
  });

  final List<String> warehouses;
  final List<String> categories;
}

class MonthlyCutsFiltrosService {
  static String formatMonth(String month, {bool longLabel = false}) {
    try {
      final dt = DateTime.parse('$month-01');
      return DateFormat(longLabel ? 'MMMM yyyy' : 'MMM yy', 'es_CO').format(dt);
    } catch (_) {
      return month;
    }
  }

  static bool hasActiveFilters({
    String? selectedWarehouse,
    String? selectedCategory,
    String? searchQuery,
  }) {
    return selectedWarehouse != null ||
        selectedCategory != null ||
        searchQuery != null;
  }

  static List<String> monthOptions(List<MonthlyCut> monthlyCuts) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final item in monthlyCuts) {
      if (item.month.isNotEmpty && seen.add(item.month)) {
        ordered.add(item.month);
      }
    }
    return ordered;
  }

  static MonthlyCutsFilterOptions buildSelectableOptions(
    List<Map<String, dynamic>> rows, {
    String? selectedWarehouse,
    String? selectedCategory,
  }) {
    final warehouses = <String>{};
    final categories = <String>{};

    for (final row in rows) {
      final warehouse = (row['warehouse'] ?? '').toString().trim();
      final category = (row['category'] ?? '').toString().trim();

      if (warehouse.isNotEmpty) warehouses.add(warehouse);
      if (category.isNotEmpty) categories.add(category);
    }

    if (selectedWarehouse != null && selectedWarehouse.isNotEmpty) {
      warehouses.add(selectedWarehouse);
    }
    if (selectedCategory != null && selectedCategory.isNotEmpty) {
      categories.add(selectedCategory);
    }
    final warehouseList = warehouses.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final categoryList = categories.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return MonthlyCutsFilterOptions(
      warehouses: warehouseList,
      categories: categoryList,
    );
  }
}
