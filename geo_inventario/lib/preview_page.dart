import 'package:flutter/material.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:geo_inventario/theme/app_theme.dart';

/// Previsualización de las primeras 50 filas de un archivo Excel antes de procesarlo.
/// Las columnas requeridas se muestran con fondo verde, las opcionales en amarillo.
class PreviewPage extends StatelessWidget {
  final List<List<dynamic>> data;
  final String filePath;

  const PreviewPage({super.key, required this.data, required this.filePath});

  // Columnas requeridas (verde) y opcionales (amarillo)
  static const _required = {
    'LOCALIZACION', 'CATEGORIA', 'CODIGO', 'DESCRIPCION',
    'FECHA', 'ENTRADA', 'SALIDA', 'UNITARIO', 'TOTAL', 'LOTE/UBIC',
  };
  static const _optional = {'ORIGEN/DES', 'PROYECT', 'DESC_LI', 'LINE'};

  @override
  Widget build(BuildContext context) {
    final headers = data.isNotEmpty ? data[0] : [];
    final fileName = filePath.split('/').last.split('\\').last;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: const BoxDecoration(
            gradient: AppGradients.primary,
            boxShadow: AppShadows.elevated,
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Previsualización del archivo',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                Text(
                  'Primeras 50 filas',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.upload_file_rounded, size: 16),
                  label: const Text('Procesar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primaryDark,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: 6),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Barra de info + leyenda ──────────────────────────────────────
          Container(
            color: AppColors.surfaceVariant,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined,
                    size: 16, color: AppColors.textMuted),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    fileName,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                _LegendDot(
                    color: AppColors.successLight,
                    border: AppColors.success,
                    label: 'Requerida'),
                const SizedBox(width: AppSpacing.sm),
                _LegendDot(
                    color: const Color(0xFFFFF9C4),
                    border: const Color(0xFFF9A825),
                    label: 'Opcional'),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // ── Tabla ────────────────────────────────────────────────────────
          Expanded(
            child: DataTable2(
              columnSpacing: 12,
              horizontalMargin: 12,
              minWidth: 800,
              headingRowColor:
                  WidgetStateProperty.all(AppColors.surfaceVariant),
              headingTextStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
              dataTextStyle: const TextStyle(
                  fontSize: 12, color: AppColors.textPrimary),
              columns: [
                for (var i = 0; i < headers.length; i++)
                  DataColumn2(
                    label: Container(
                      decoration: BoxDecoration(
                        color: _required.contains(headers[i])
                            ? AppColors.successLight
                            : _optional.contains(headers[i])
                                ? const Color(0xFFFFF9C4)
                                : Colors.transparent,
                        borderRadius:
                            BorderRadius.circular(AppRadius.sm),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Text(
                        headers[i].toString(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _required.contains(headers[i])
                              ? AppColors.successDark
                              : _optional.contains(headers[i])
                                  ? const Color(0xFFF57F17)
                                  : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
              rows: data.skip(1).take(50).toList().asMap().entries.map((e) {
                final i = e.key;
                final row = e.value;
                return DataRow(
                  color: WidgetStateProperty.all(
                    i.isEven ? AppColors.surface : AppColors.surfaceVariant,
                  ),
                  cells: row
                      .map((cell) => DataCell(Text(cell.toString())))
                      .toList(),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Punto de leyenda con etiqueta.
class _LegendDot extends StatelessWidget {
  const _LegendDot(
      {required this.color, required this.border, required this.label});

  final Color color;
  final Color border;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: border, width: 1.5),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}
