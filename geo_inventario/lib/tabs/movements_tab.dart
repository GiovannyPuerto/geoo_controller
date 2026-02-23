import 'dart:convert';
import 'dart:io' as io;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html
    if (dart.library.io) 'package:geo_inventario/stubs/html_stub.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:geo_inventario/models/monthly_movement.dart';
import 'package:geo_inventario/services/api_service.dart';
import 'package:geo_inventario/services/refresh_notifier.dart';
import 'package:geo_inventario/theme/app_theme.dart';
import 'package:geo_inventario/utils/currency_formatter.dart';
import 'package:geo_inventario/widgets/data_sources.dart';

class MovementsTabPage extends StatefulWidget {
  const MovementsTabPage({super.key});

  @override
  State<MovementsTabPage> createState() => _MovementsTabPageState();
}

class _MovementsTabPageState extends State<MovementsTabPage> {
  final ApiService _apiService = ApiService();

  // estado
  List<Map<String, dynamic>> allMovements = [];
  List<Map<String, dynamic>> movements = [];
  List<Map<String, dynamic>> filteredMovements = [];
  List<MonthlyMovement> monthlyMovements = [];
  bool isLoading = true;

  // filtros
  DateTimeRange? selectedDateRange;
  String? selectedWarehouse;
  String? selectedGroup;
  List<String> availableWarehouses = [];
  List<String> availableGroups = [];
  String? searchQuery;

  @override
  void initState() {
    super.initState();
    inventoryRefreshNotifier.addListener(_onExternalRefresh);
    _loadAllMovementsData();
  }

  @override
  void dispose() {
    inventoryRefreshNotifier.removeListener(_onExternalRefresh);
    super.dispose();
  }

  /// Se llama cuando el Dashboard sube un Excel exitosamente.
  /// Resetea los filtros para mostrar todos los datos actualizados.
  void _onExternalRefresh() {
    setState(() {
      selectedDateRange = null;
      selectedWarehouse = null;
      selectedGroup = null;
      searchQuery = null;
    });
    _loadAllMovementsData();
  }

  Future<void> _loadAllMovementsData() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
    });

    try {
      final results = await Future.wait([
        _apiService.getMovements(),
        _apiService.getMonthlyMovements(),
      ]);
      final allMovementsData = results[0] as List<Map<String, dynamic>>;
      final monthlyMovementsData = results[1] as List<MonthlyMovement>;

      if (mounted) {
        setState(() {
          allMovements = allMovementsData;
          movements = allMovementsData;
          filteredMovements = movements;
          monthlyMovements = monthlyMovementsData;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        context.showErrorSnackBar('Error al cargar movimientos: ${e.toString()}');
      }
    }
  }

  Future<void> _loadMovementsData() async {
    final localContext = context;
    if (!mounted) return;

    try {
      final results = await Future.wait([
        _apiService.getMovements(
          warehouse: selectedWarehouse,
          category: selectedGroup,
          search: searchQuery,
          dateFrom: selectedDateRange?.start,
          dateTo: selectedDateRange?.end,
        ),
        _apiService.getMonthlyMovements(
          warehouse: selectedWarehouse,
          category: selectedGroup,
          search: searchQuery,
          dateFrom: selectedDateRange?.start,
          dateTo: selectedDateRange?.end,
        ),
      ]);
      final filteredMovementsData = results[0] as List<Map<String, dynamic>>;
      final filteredMonthlyMovementsData = results[1] as List<MonthlyMovement>;

      if (mounted) {
        setState(() {
          movements = filteredMovementsData;
          filteredMovements = movements;
          monthlyMovements = filteredMonthlyMovementsData;
        });
      }
    } catch (e) {
      if (mounted) {
        localContext.showErrorSnackBar('Error al cargar movimientos: ${e.toString()}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
            SizedBox(height: AppSpacing.md),
            Text(
              'Cargando movimientos…',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadAllMovementsData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Encabezado de sección ──────────────────────────────────
              Text(
                'Historial de Movimientos',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Vista detallada de todas las entradas y salidas de inventario',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              _buildMovementsChart(),
              const SizedBox(height: AppSpacing.lg),
              _buildChartDataTable(),
              const SizedBox(height: AppSpacing.lg),
              _buildMovementsTable(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMovementsChart() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.bar_chart_rounded, size: 18, color: AppColors.primary),
              SizedBox(width: AppSpacing.sm),
              Text(
                'Movimientos por Mes',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(builder: (ctx, cons) {
            final chartH = cons.maxWidth < 480 ? 220.0 : 300.0;
            return SizedBox(
            height: chartH,
            child: SfCartesianChart(
              primaryXAxis: const CategoryAxis(
                labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                axisLine: AxisLine(width: 1, color: AppColors.border),
                majorTickLines: MajorTickLines(size: 0),
                majorGridLines: MajorGridLines(width: 0),
              ),
              primaryYAxis: NumericAxis(
                numberFormat: NumberFormat.currency(locale: 'es_CO', symbol: '\$'),
                labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                axisLine: const AxisLine(width: 1, color: AppColors.border),
                majorTickLines: const MajorTickLines(size: 0),
                majorGridLines: MajorGridLines(
                  width: 0.5,
                  color: AppColors.border,
                  dashArray: const [5, 5],
                ),
                title: const AxisTitle(
                  text: 'Valor (\$)',
                  textStyle: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              plotAreaBorderWidth: 0,
              legend: const Legend(
                isVisible: true,
                textStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              tooltipBehavior: TooltipBehavior(
                enable: true,
                color: AppColors.dark,
                textStyle: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              series: <CartesianSeries>[
                ColumnSeries<MonthlyMovement, String>(
                  dataSource: monthlyMovements,
                  xValueMapper: (MonthlyMovement data, _) =>
                      DateFormat('MMM yy').format(DateTime.parse('${data.month}-01')),
                  yValueMapper: (MonthlyMovement data, _) => data.totalEntries,
                  name: 'Entradas',
                  color: AppColors.success,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(3),
                    topRight: Radius.circular(3),
                  ),
                  width: 0.6,
                ),
                ColumnSeries<MonthlyMovement, String>(
                  dataSource: monthlyMovements,
                  xValueMapper: (MonthlyMovement data, _) =>
                      DateFormat('MMM yy').format(DateTime.parse('${data.month}-01')),
                  yValueMapper: (MonthlyMovement data, _) => data.totalExits,
                  name: 'Salidas',
                  color: AppColors.error,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(3),
                    topRight: Radius.circular(3),
                  ),
                  width: 0.6,
                ),
                LineSeries<MonthlyMovement, String>(
                  dataSource: monthlyMovements,
                  xValueMapper: (MonthlyMovement data, _) =>
                      DateFormat('MMM yy').format(DateTime.parse('${data.month}-01')),
                  yValueMapper: (MonthlyMovement data, _) => data.closingBalance,
                  name: 'Saldo',
                  color: AppColors.info,
                  width: 2,
                  markerSettings: const MarkerSettings(
                    isVisible: true,
                    height: 6,
                    width: 6,
                    color: AppColors.info,
                    borderColor: Colors.white,
                    borderWidth: 2,
                  ),
                ),
              ],
            ),
          );
          }),
        ],
      ),
    );
  }

  Widget _buildChartDataTable() {
    if (monthlyMovements.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.primary),
              SizedBox(width: AppSpacing.sm),
              Text(
                'Resumen mensual',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 300,
            child: DataTable2(
              columnSpacing: 12,
              horizontalMargin: 12,
              minWidth: 600,
              headingRowColor: WidgetStateProperty.all(AppColors.surfaceVariant),
              headingTextStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
              dataTextStyle: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
              dividerThickness: 1,
              columns: const [
                DataColumn2(label: Text('Mes'), size: ColumnSize.M),
                DataColumn2(label: Text('Entradas'), size: ColumnSize.M, numeric: true),
                DataColumn2(label: Text('Salidas'), size: ColumnSize.M, numeric: true),
                DataColumn2(label: Text('Saldo Final'), size: ColumnSize.M, numeric: true),
              ],
              rows: monthlyMovements.asMap().entries.map((e) {
                final i = e.key;
                final movement = e.value;
                final monthName = DateFormat('MMMM yyyy')
                    .format(DateTime.parse('${movement.month}-01'));
                return DataRow(
                  color: WidgetStateProperty.all(
                    i.isEven ? AppColors.surface : AppColors.surfaceVariant,
                  ),
                  cells: [
                    DataCell(Text(
                      monthName,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    )),
                    DataCell(Text(
                      CurrencyFormatter.format(movement.totalEntries),
                      style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
                    )),
                    DataCell(Text(
                      CurrencyFormatter.format(movement.totalExits),
                      style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
                    )),
                    DataCell(Text(
                      CurrencyFormatter.format(movement.closingBalance),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    )),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovementsTable() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Encabezado ───────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.swap_horiz_rounded,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Todos los movimientos',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      '${filteredMovements.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDarker,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _showExportDialog,
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Exportar'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.filter_list_rounded,
                        color: AppColors.textMuted),
                    tooltip: 'Filtros',
                    onPressed: showFiltersDialog,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),

          // ── Tabla / Estado vacío ─────────────────────────────────────
          if (filteredMovements.isEmpty)
            SizedBox(
              height: 300,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                      ),
                      child: const Icon(Icons.history_rounded,
                          size: 36, color: AppColors.textDisabled),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Text(
                      'Sin movimientos para mostrar',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      'Prueba ajustando los filtros activos.',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: 400,
                maxHeight: 600,
              ),
              child: PaginatedDataTable2(
                columnSpacing: 12,
                horizontalMargin: 12,
                minWidth: 800,
                scrollController: ScrollController(),
                isHorizontalScrollBarVisible: true,
                headingRowColor: WidgetStateProperty.all(AppColors.surfaceVariant),
                headingTextStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                ),
                dataTextStyle: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                ),
                dividerThickness: 1,
                columns: const [
                  DataColumn2(label: Text('Fecha'), size: ColumnSize.S),
                  DataColumn2(label: Text('Producto'), size: ColumnSize.M),
                  DataColumn2(label: Text('Almacén'), size: ColumnSize.S),
                  DataColumn2(label: Text('Tipo Doc.'), size: ColumnSize.S),
                  DataColumn2(label: Text('Documento'), size: ColumnSize.S),
                  DataColumn2(label: Text('Cantidad'), size: ColumnSize.S, numeric: true),
                  DataColumn2(label: Text('Costo Unit.'), size: ColumnSize.S, numeric: true),
                  DataColumn2(label: Text('Total'), size: ColumnSize.S, numeric: true),
                ],
                source: MovementsDataSource(filteredMovements),
              ),
            ),
        ],
      ),
    );
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Exportar Datos'),
          content:
              const Text('¿En qué formato desea exportar los movimientos?'),
          actions: [
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Excel'),
              onPressed: () {
                _exportMovements('excel');
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('PDF'),
              onPressed: () {
                _exportMovements('pdf');
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportMovements(String format) async {
    final localContext = context;
    try {
      final response = await _apiService.exportMovements(
        format: format,
        warehouse: selectedWarehouse,
        category: selectedGroup,
        search: searchQuery,
        dateFrom: selectedDateRange?.start,
        dateTo: selectedDateRange?.end,
      );

      if (response.statusCode == 200) {
        final Uint8List fileBytes = response.bodyBytes;
        final String timestamp = DateTime.now()
            .toString()
            .replaceAll(':', '-')
            .replaceAll('.', '-')
            .replaceAll(' ', '_');
        final String extension = format == 'excel' ? 'xlsx' : 'pdf';
        final String fileName = 'movements_export_$timestamp.$extension';

        if (kIsWeb) {
          // For web, use html.AnchorElement to trigger download
          final blob = html.Blob([fileBytes]);
          final url = html.Url.createObjectUrlFromBlob(blob);
          html.AnchorElement(href: url)
            ..setAttribute('download', fileName)
            ..click();
          html.Url.revokeObjectUrl(url);

          if (mounted) {
            localContext.showSuccessSnackBar('Movimientos exportados correctamente');
          }
        } else {
          // For desktop, use FilePicker to get save path and write file
          final String? path = await FilePicker.platform.saveFile(
            dialogTitle: 'Guardar archivo',
            fileName: fileName,
            allowedExtensions: [extension],
            type: FileType.custom,
          );

          if (path != null) {
            final file = io.File(path);
            await file.writeAsBytes(fileBytes);

            if (mounted) {
              localContext.showSuccessSnackBar('Movimientos exportados a $path');
            }
          } else {
            // User cancelled the save dialog
            if (mounted) {
              localContext.showErrorSnackBar('Exportación cancelada');
            }
          }
        }
      } else {
        throw Exception('Failed to export movements');
      }
    } catch (e) {
      if (mounted) {
        localContext.showErrorSnackBar('Error al exportar movimientos: ${e.toString()}');
      }
    }
  }

  void showFiltersDialog() {
    // Ensure data is loaded before showing filters
    if (allMovements.isEmpty && !isLoading) {
      _loadAllMovementsData();
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        DateTimeRange? selectedDateRange = this.selectedDateRange;
        String dateRangeText = 'Seleccionar rango de fechas (opcional)';

        if (selectedDateRange != null) {
          final dateFormat = DateFormat('dd/MM/yyyy');
          final startDate = dateFormat.format(selectedDateRange.start);
          final endDate = dateFormat.format(selectedDateRange.end);
          dateRangeText = '$startDate - $endDate';
        }

        // Get unique values from allMovements data
        final warehouses =
            ['Todos', ..._getUniqueValues('warehouse')].toSet().toList();
        final groups =
            ['Todos', ..._getUniqueValues('category')].toSet().toList();

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Filtros - Movimientos'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedWarehouse == null ||
                              !warehouses.contains(selectedWarehouse)
                          ? 'Todos'
                          : selectedWarehouse,
                      decoration: const InputDecoration(labelText: 'Almacén'),
                      items: warehouses.map((value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => selectedWarehouse =
                            value == 'Todos' ? null : value);
                      },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: selectedGroup == null ||
                              !groups.contains(selectedGroup)
                          ? 'Todos'
                          : selectedGroup,
                      decoration: const InputDecoration(labelText: 'Categoría'),
                      items: groups.map((value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() =>
                            selectedGroup = value == 'Todos' ? null : value);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: searchQuery,
                      decoration: const InputDecoration(
                        labelText: 'Buscar por código o descripción',
                        hintText: 'Ingrese código o descripción del producto',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (value) {
                        setState(() => searchQuery = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Rango de Fechas',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: selectedDateRange,
                        );
                        if (picked != null) {
                          setState(() {
                            this.selectedDateRange = picked;
                          });
                        }
                      },
                      child: Text(dateRangeText),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      selectedWarehouse = null;
                      selectedGroup = null;
                      selectedDateRange = null;
                      searchQuery = null;
                    });
                    Navigator.of(context).pop();
                    _loadMovementsData();
                  },
                  child: const Text('Limpiar'),
                ),
                TextButton(
                  onPressed: () {
                    _loadMovementsData();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<String> _getUniqueValues(String field) {
    var values = allMovements
        .map((item) => item[field]?.toString() ?? '')
        .where((value) => value.isNotEmpty);

    return values.toSet().toList()..sort();
  }
}