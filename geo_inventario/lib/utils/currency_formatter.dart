import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'es_CO',
    symbol: '\$',
    decimalDigits: 2,
  );

  static String format(double value) {
    return _currencyFormat.format(value);
  }

  static String formatNullable(double? value) {
    if (value == null) return '\$0.00';
    return _currencyFormat.format(value);
  }

  static double? parse(String? value) {
    if (value == null || value.isEmpty) return null;
    // Remove currency symbol and replace comma with dot for parsing
    String cleaned =
        value.replaceAll('\$', '').replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(cleaned);
  }
}
