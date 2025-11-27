import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geo_inventario/utils/currency_formatter.dart';

class MovementsDataSource extends DataTableSource {
  final List<Map<String, dynamic>> movements;

  MovementsDataSource(this.movements);

  @override
  DataRow getRow(int index) {
    final item = movements[index];
    return DataRow(
      cells: [
        DataCell(
          Text(
            DateFormat('dd/MM/yyyy').format(
              DateTime.parse(item['date'] ?? ''),
            ),
          ),
        ),
        DataCell(
          Text(item['product_description'] ?? ''),
        ),
        DataCell(Text(item['warehouse'] ?? '')),
        DataCell(Text(item['document_type'] ?? '')),
        DataCell(Text(item['document_number'] ?? '')),
        DataCell(
          Text(item['quantity']?.toString() ?? '0'),
        ),
        DataCell(
          Text(
            CurrencyFormatter.format(
              item['unit_cost'] ?? 0,
            ),
          ),
        ),
        DataCell(
          Text(
            CurrencyFormatter.format(
              item['total'] ?? 0,
            ),
          ),
        ),
      ],
    );
  }

  @override
  int get rowCount => movements.length;

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => 0;
}

class AnalysisDataSource extends DataTableSource {
  final List<Map<String, dynamic>> analysis;

  AnalysisDataSource(this.analysis);

  Color _getRotationColor(String rotation) {
    switch (rotation) {
      case 'Activo':
        return Colors.green;
      case 'Estancado':
        return Colors.orange;
      case 'Obsoleto':
        return Colors.red;
      default:
        return Colors.black;
    }
  }

  Color _getStagnantColor(String stagnant) {
    return stagnant == 'Sí' ? Colors.red : Colors.green;
  }

  Color _getHighRotationColor(String highRotation) {
    return highRotation == 'Sí' ? Colors.green : Colors.grey;
  }

  @override
  DataRow getRow(int index) {
    final item = analysis[index];
    return DataRow(
      cells: [
        DataCell(Text(item['codigo'] ?? '')),
        DataCell(
          Text(item['nombre_producto'] ?? ''),
        ),
        DataCell(Text(item['grupo'] ?? '')),
        DataCell(
          Text(
            item['cantidad_saldo_actual']?.toString() ?? '0',
          ),
        ),
        DataCell(
          Text(
            CurrencyFormatter.format(
              item['valor_saldo_actual'] ?? 0,
            ),
          ),
        ),
        DataCell(
          Text(
            CurrencyFormatter.format(
              item['costo_unitario'] ?? 0,
            ),
          ),
        ),
        DataCell(
          Text(
            item['estancado'] ?? 'No',
            style: TextStyle(
              color: _getStagnantColor(item['estancado'] ?? 'No'),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        DataCell(
          Text(
            item['rotacion'] ?? 'Activo',
            style: TextStyle(
              color: _getRotationColor(item['rotacion'] ?? 'Activo'),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        DataCell(
          Text(
            item['alta_rotacion'] ?? 'No',
            style: TextStyle(
              color: _getHighRotationColor(item['alta_rotacion'] ?? 'No'),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  @override
  int get rowCount => analysis.length;

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => 0;
}
