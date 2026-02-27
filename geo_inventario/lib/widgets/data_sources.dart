import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geo_inventario/models/monthly_product_cut.dart';
import 'package:geo_inventario/theme/app_theme.dart';
import 'package:geo_inventario/utils/currency_formatter.dart';

/// Fila alterna: filas pares blancas, impares gris muy suave.
Color _rowColor(int index) =>
    index.isEven ? AppColors.surface : AppColors.surfaceVariant;

/// Badge de estado con color de fondo y texto.
Widget _StatusBadge({
  required String label,
  required Color bg,
  required Color fg,
  IconData? icon,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.full),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: fg, size: 11),
          const SizedBox(width: 3),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ],
    ),
  );
}

// MovementsDataSource
class MovementsDataSource extends DataTableSource {
  final List<Map<String, dynamic>> movements;

  MovementsDataSource(this.movements);

  Color _typeColor(String? type) {
    if (type == null) return AppColors.textMuted;
    final t = type.toUpperCase();
    if (t.contains('ENTRADA') || t.contains('COMPRA') || t.contains('IN')) {
      return AppColors.success;
    }
    if (t.contains('SALIDA') || t.contains('VENTA') || t.contains('OUT')) {
      return AppColors.error;
    }
    return AppColors.textMuted;
  }

  @override
  DataRow getRow(int index) {
    final item = movements[index];
    final docType = item['document_type']?.toString() ?? '';
    final qty = item['quantity'];
    final qtyNum = qty is num
        ? qty.toDouble()
        : double.tryParse(qty?.toString() ?? '') ?? 0.0;
    final isNegative = qtyNum < 0;

    return DataRow(
      color: WidgetStateProperty.resolveWith((_) => _rowColor(index)),
      cells: [
        // Fecha
        DataCell(
          Text(
            _formatDate(item['date']),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        // Producto
        DataCell(
          Tooltip(
            message: item['product_description'] ?? '',
            child: Text(
              item['product_description'] ?? '',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // Almacén
        DataCell(
          Text(
            item['warehouse'] ?? '',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        // Tipo Doc — con badge de color
        DataCell(
          _StatusBadge(
            label: docType.isEmpty ? '—' : docType,
            bg: _typeColor(docType).withValues(alpha: 0.12),
            fg: _typeColor(docType),
          ),
        ),
        // Documento
        DataCell(
          Text(
            item['document_number'] ?? '',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              fontFamily: 'monospace',
            ),
          ),
        ),
        // Cantidad — rojo si negativa
        DataCell(
          Text(
            qtyNum.toStringAsFixed(3),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isNegative ? AppColors.error : AppColors.textPrimary,
            ),
          ),
        ),
        // Costo unitario
        DataCell(
          Text(
            CurrencyFormatter.format(item['unit_cost'] ?? 0),
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        // Total
        DataCell(
          Text(
            CurrencyFormatter.format(item['total'] ?? 0),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '—';
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  @override
  int get rowCount => movements.length;

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => 0;
}

// ─── AnalysisDataSource ─────────────────────────────────────────────────────

class AnalysisDataSource extends DataTableSource {
  final List<Map<String, dynamic>> analysis;

  AnalysisDataSource(this.analysis);

  Widget _rotationBadge(String rotation) {
    switch (rotation) {
      case 'Activo':
        return _StatusBadge(
          label: 'Activo',
          bg: AppColors.successLight,
          fg: AppColors.successDark,
          icon: Icons.check_circle_rounded,
        );
      case 'Estancado':
        return _StatusBadge(
          label: 'Estancado',
          bg: AppColors.warningLight,
          fg: AppColors.warningDark,
          icon: Icons.hourglass_bottom_rounded,
        );
      case 'Obsoleto':
        return _StatusBadge(
          label: 'Obsoleto',
          bg: AppColors.errorLight,
          fg: AppColors.errorDark,
          icon: Icons.cancel_rounded,
        );
      case 'Inactivo':
        return _StatusBadge(
          label: 'Inactivo',
          bg: AppColors.surfaceVariant,
          fg: AppColors.textMuted,
          icon: Icons.pause_circle_rounded,
        );
      default:
        return _StatusBadge(
          label: rotation,
          bg: AppColors.surfaceVariant,
          fg: AppColors.textMuted,
        );
    }
  }

  Widget _boolBadge(String value, {required bool positiveIsGood}) {
    final isYes = value == 'Sí';
    final isGood = positiveIsGood ? isYes : !isYes;
    return _StatusBadge(
      label: value,
      bg: isGood ? AppColors.successLight : AppColors.surfaceVariant,
      fg: isGood ? AppColors.successDark : AppColors.textMuted,
      icon: isGood ? Icons.check_rounded : null,
    );
  }

  @override
  DataRow getRow(int index) {
    final item = analysis[index];
    final qty = item['cantidad_saldo_actual'];
    final qtyNum = qty is num
        ? qty.toDouble()
        : double.tryParse(qty?.toString() ?? '') ?? 0.0;
    final isNegative = qtyNum < 0;

    return DataRow(
      color: WidgetStateProperty.resolveWith((_) => _rowColor(index)),
      cells: [
        // Código
        DataCell(
          Text(
            item['codigo'] ?? '',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              fontFamily: 'monospace',
            ),
          ),
        ),
        // Nombre producto
        DataCell(
          Tooltip(
            message: item['nombre_producto'] ?? '',
            child: Text(
              item['nombre_producto'] ?? '',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // Grupo
        DataCell(
          Text(
            item['grupo'] ?? '',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Cantidad saldo — rojo si negativa
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: isNegative
                ? BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  )
                : null,
            child: Text(
              qtyNum.toStringAsFixed(3),
              style: TextStyle(
                fontSize: 12,
                fontWeight: isNegative ? FontWeight.bold : FontWeight.normal,
                color: isNegative ? AppColors.error : AppColors.textPrimary,
              ),
            ),
          ),
        ),
        // Valor saldo
        DataCell(
          Text(
            CurrencyFormatter.format(item['valor_saldo_actual'] ?? 0),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        // Costo unitario
        DataCell(
          Text(
            CurrencyFormatter.format(item['costo_unitario'] ?? 0),
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        // Estancado — badge amarillo/gris
        DataCell(
          _boolBadge(item['estancado'] ?? 'No', positiveIsGood: false),
        ),
        // Rotación — badge con color semántico
        DataCell(
          _rotationBadge(item['rotacion'] ?? 'Activo'),
        ),
        // Alta rotación — badge verde/gris
        DataCell(
          _boolBadge(item['alta_rotacion'] ?? 'No', positiveIsGood: true),
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

// ─── MonthlyProductCutDataSource ────────────────────────────────────────────

class MonthlyProductCutDataSource extends DataTableSource {
  final List<MonthlyProductCut> rows;
  final NumberFormat _qtyFmt = NumberFormat('#,##0.###', 'es_CO');

  MonthlyProductCutDataSource(this.rows);

  @override
  DataRow getRow(int index) {
    final row = rows[index];
    return DataRow(
      color: WidgetStateProperty.resolveWith((_) => _rowColor(index)),
      cells: [
        DataCell(Text(
          row.code,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textMuted,
            fontFamily: 'monospace',
          ),
        )),
        DataCell(Tooltip(
          message: row.description,
          child: Text(
            row.description,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        )),
        DataCell(Text(
          row.group,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          overflow: TextOverflow.ellipsis,
        )),
        DataCell(Text(
          _qtyFmt.format(row.averageQuantity),
          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
        )),
        DataCell(Text(
          CurrencyFormatter.format(row.averageValue),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        )),
        DataCell(Text(
          CurrencyFormatter.format(row.unitCost),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        )),
      ],
    );
  }

  @override
  int get rowCount => rows.length;

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => 0;
}
