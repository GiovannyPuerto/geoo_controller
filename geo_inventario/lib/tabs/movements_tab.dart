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
import 'package:geo_inventario/tabs/movements/movements_filter_service.dart';
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
  bool _isRefreshing = false;

  // filtros
  DateTime? dateFrom;
  DateTime? dateTo;
  String? selectedWarehouse;
  String? selectedGroup;
  List<String> availableWarehouses = [];
  List<String> availableGroups = [];
  String? searchQuery;
  String? docNumberSearch;
  String? selectedDocType;

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
      dateFrom = null;
      dateTo = null;
      selectedWarehouse = null;
      selectedGroup = null;
      searchQuery = null;
      docNumberSearch = null;
      selectedDocType = null;
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
    if (!mounted) return;

    setState(() => _isRefreshing = true);

    try {
      final results = await Future.wait([
        _apiService.getMovements(
          warehouse: selectedWarehouse,
          category: selectedGroup,
          search: searchQuery,
          documentNumber: docNumberSearch,
          documentType: selectedDocType,
          dateFrom: dateFrom,
          dateTo: dateTo,
        ),
        _apiService.getMonthlyMovements(
          warehouse: selectedWarehouse,
          category: selectedGroup,
          search: searchQuery,
          dateFrom: dateFrom,
          dateTo: dateTo,
        ),
      ]);
      final filteredMovementsData = results[0] as List<Map<String, dynamic>>;
      final filteredMonthlyMovementsData = results[1] as List<MonthlyMovement>;

      if (mounted) {
        setState(() {
          movements = filteredMovementsData;
          filteredMovements = movements;
          monthlyMovements = filteredMonthlyMovementsData;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRefreshing = false);
        context.showErrorSnackBar('Error al cargar movimientos: ${e.toString()}');
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
      body: Stack(
        children: [
          RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadAllMovementsData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Banner corporativo de sección ──────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  gradient: AppGradients.hero,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: AppShadows.elevated,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: const Icon(Icons.swap_horiz_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Historial de Movimientos',
                          style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold,
                            color: Colors.white, letterSpacing: 0.3,
                          ),
                        ),
                        Text(
                          'Entradas, salidas y saldos del inventario',
                          style: TextStyle(fontSize: 12, color: Color(0xCCFFFFFF)),
                        ),
                      ],
                    ),
                  ],
                ),
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
      ), // RefreshIndicator
          if (_isRefreshing)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.12),
                child: const Center(
                  child: Card(
                    elevation: 8,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                              strokeWidth: 2.5,
                            ),
                          ),
                          SizedBox(width: 14),
                          Text(
                            'Aplicando filtros…',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ], // Stack.children
      ), // Stack
    ); // Scaffold
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
                labelStyle: TextStyle(color: AppColors.textMuted, fontSize: 11),
                axisLine: AxisLine(width: 0),
                majorTickLines: MajorTickLines(size: 0),
                majorGridLines: MajorGridLines(width: 0),
                labelIntersectAction: AxisLabelIntersectAction.rotate45,
              ),
              primaryYAxis: NumericAxis(
                axisLine: const AxisLine(width: 0),
                majorTickLines: const MajorTickLines(size: 0),
                labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                majorGridLines: const MajorGridLines(
                  width: 1,
                  color: AppColors.border,
                  dashArray: [4, 4],
                ),
                axisLabelFormatter: (AxisLabelRenderDetails details) {
                  final v = details.value.toDouble();
                  String label;
                  if (v.abs() >= 1000000) {
                    label = '\$${(v / 1000000).toStringAsFixed(1)}M';
                  } else if (v.abs() >= 1000) {
                    label = '\$${(v / 1000).toStringAsFixed(0)}K';
                  } else {
                    label = '\$${v.toStringAsFixed(0)}';
                  }
                  return ChartAxisLabel(label, details.textStyle);
                },
              ),
              plotAreaBorderWidth: 0,
              legend: const Legend(
                isVisible: true,
                position: LegendPosition.bottom,
                textStyle: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                overflowMode: LegendItemOverflowMode.wrap,
              ),
              trackballBehavior: TrackballBehavior(
                enable: true,
                activationMode: ActivationMode.singleTap,
                lineType: TrackballLineType.vertical,
                lineColor: AppColors.textMuted,
                lineWidth: 1,
                lineDashArray: const [4, 3],
                tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
                tooltipSettings: const InteractiveTooltip(
                  enable: true,
                  color: Color(0xFF1E293B),
                  textStyle: TextStyle(color: Colors.white, fontSize: 11),
                  borderWidth: 0,
                ),
                builder: (context, details) {
                  final points = details.groupingModeInfo?.points ?? [];
                  if (points.isEmpty) return const SizedBox.shrink();
                  final xLabel = points.first.x?.toString() ?? '';
                  const seriesNames = ['Entradas', 'Salidas', 'Saldo'];
                  const seriesColors = [
                    AppColors.chartPositive,
                    AppColors.chartNegative,
                    AppColors.chartBalance,
                  ];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          xLabel,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...points.asMap().entries.map((e) {
                          final idx = e.key;
                          final p = e.value;
                          final yVal = p.y;
                          final dotColor = idx < seriesColors.length
                              ? seriesColors[idx]
                              : Colors.white;
                          final label = idx < seriesNames.length
                              ? seriesNames[idx]
                              : 'Serie ${idx + 1}';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: dotColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$label: ',
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  yVal != null
                                      ? CurrencyFormatter.format(yVal.toDouble())
                                      : '—',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
              series: <CartesianSeries>[
                ColumnSeries<MonthlyMovement, String>(
                  dataSource: monthlyMovements,
                  xValueMapper: (MonthlyMovement data, _) =>
                      DateFormat('MMM yy', 'es_CO')
                          .format(DateTime.parse('${data.month}-01')),
                  yValueMapper: (MonthlyMovement data, _) => data.totalEntries,
                  name: 'Entradas',
                  color: AppColors.chartPositive.withValues(alpha: 0.75),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                  width: 0.55,
                  spacing: 0.1,
                ),
                ColumnSeries<MonthlyMovement, String>(
                  dataSource: monthlyMovements,
                  xValueMapper: (MonthlyMovement data, _) =>
                      DateFormat('MMM yy', 'es_CO')
                          .format(DateTime.parse('${data.month}-01')),
                  yValueMapper: (MonthlyMovement data, _) => data.totalExits,
                  name: 'Salidas',
                  color: AppColors.chartNegative.withValues(alpha: 0.75),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                  width: 0.55,
                  spacing: 0.1,
                ),
                LineSeries<MonthlyMovement, String>(
                  dataSource: monthlyMovements,
                  xValueMapper: (MonthlyMovement data, _) =>
                      DateFormat('MMM yy', 'es_CO')
                          .format(DateTime.parse('${data.month}-01')),
                  yValueMapper: (MonthlyMovement data, _) => data.closingBalance,
                  name: 'Saldo',
                  color: AppColors.chartBalance,
                  width: 2,
                  markerSettings: const MarkerSettings(
                    isVisible: true,
                    height: 6,
                    width: 6,
                    color: AppColors.chartBalance,
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
                final monthName = DateFormat('MMMM yyyy', 'es_CO')
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
          if (_hasActiveFilters()) _buildActiveFilterChips(),
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

  bool _hasActiveFilters() => selectedWarehouse != null ||
      selectedGroup != null ||
      (searchQuery != null && searchQuery!.isNotEmpty) ||
      (docNumberSearch != null && docNumberSearch!.isNotEmpty) ||
      selectedDocType != null ||
      dateFrom != null ||
      dateTo != null;

  Widget _buildActiveFilterChips() {
    final chips = <Widget>[];
    final fmt = DateFormat('dd/MM/yyyy', 'es_CO');

    void addChip(String label, VoidCallback onDelete) {
      chips.add(
        Chip(
          label: Text(label, style: const TextStyle(fontSize: 11)),
          onDeleted: onDelete,
          backgroundColor: AppColors.cyanLight,
          deleteIconColor: AppColors.cyanDark,
          side: const BorderSide(color: AppColors.cyan, width: 0.5),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      );
    }

    if (selectedWarehouse != null) {
      addChip('Almacén: $selectedWarehouse', () {
        setState(() => selectedWarehouse = null);
        _loadMovementsData();
      });
    }
    if (selectedGroup != null) {
      addChip('Categoría: $selectedGroup', () {
        setState(() => selectedGroup = null);
        _loadMovementsData();
      });
    }
    if (searchQuery != null && searchQuery!.isNotEmpty) {
      addChip('Búsqueda: $searchQuery', () {
        setState(() => searchQuery = null);
        _loadMovementsData();
      });
    }
    if (docNumberSearch != null && docNumberSearch!.isNotEmpty) {
      addChip('Doc: $docNumberSearch', () {
        setState(() => docNumberSearch = null);
        _loadMovementsData();
      });
    }
    if (selectedDocType != null) {
      addChip('Tipo doc: $selectedDocType', () {
        setState(() => selectedDocType = null);
        _loadMovementsData();
      });
    }
    if (dateFrom != null || dateTo != null) {
      final from = dateFrom != null ? fmt.format(dateFrom!) : '∅';
      final to = dateTo != null ? fmt.format(dateTo!) : 'hoy';
      addChip('Fecha: $from → $to', () {
        setState(() {
          dateFrom = null;
          dateTo = null;
        });
        _loadMovementsData();
      });
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: chips),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                selectedWarehouse = null;
                selectedGroup = null;
                searchQuery = null;
                docNumberSearch = null;
                selectedDocType = null;
                dateFrom = null;
                dateTo = null;
              });
              _loadMovementsData();
            },
            child: const Text('Limpiar todo',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.download_outlined,
                    color: AppColors.primaryDark, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text('Exportar Movimientos',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          content: const Text(
              '¿En qué formato desea exportar los movimientos?'),
          actions: [
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(dialogCtx).pop(),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.table_chart_outlined, size: 16),
              label: const Text('Excel'),
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                _exportMovements('excel');
              },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('PDF'),
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                _exportMovements('pdf');
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportMovements(String format) async {
    try {
      final response = await _apiService.exportMovements(
        format: format,
        warehouse: selectedWarehouse,
        category: selectedGroup,
        search: searchQuery,
        documentType: selectedDocType,
        dateFrom: dateFrom,
        dateTo: dateTo,
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
            context.showSuccessSnackBar('Movimientos exportados correctamente');
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
              context.showSuccessSnackBar('Movimientos exportados a $path');
            }
          } else {
            // User cancelled the save dialog
            if (mounted) {
              context.showErrorSnackBar('Exportación cancelada');
            }
          }
        }
      } else {
        throw Exception('Failed to export movements');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Error al exportar movimientos: ${e.toString()}');
      }
    }
  }

  void showFiltersDialog() {
    if (allMovements.isEmpty && !isLoading) {
      _loadAllMovementsData();
      return;
    }

    // Copias locales para el dialog
    DateTime? localFrom = dateFrom;
    DateTime? localTo = dateTo;
    String? localWarehouse = selectedWarehouse;
    String? localGroup = selectedGroup;
    String? localSearch = searchQuery;
    String? localDocNumber = docNumberSearch;
    String? localDocType = selectedDocType;

    final fmt = DateFormat('dd/MM/yyyy', 'es_CO');
    final warehouses = <String>{
      'Todos',
      ...MovementsFilterService.obtenerValoresUnicos(allMovements, 'warehouse'),
    }.toList();
    final groups = <String>{
      'Todos',
      ...MovementsFilterService.obtenerValoresUnicos(allMovements, 'category'),
    }.toList();
    final docTypes = <String>{
      'Todos',
      ...MovementsFilterService.obtenerValoresUnicos(allMovements, 'document_type'),
    }.toList()..sort();

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          Widget dateRow(String label, DateTime? value, VoidCallback onTap, VoidCallback onClear) {
            return GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: value != null ? AppColors.primary : AppColors.border,
                    width: value != null ? 1.8 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 16,
                        color: value != null ? AppColors.primary : AppColors.textDisabled),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        value != null ? fmt.format(value) : label,
                        style: TextStyle(
                          fontSize: 14,
                          color: value != null ? AppColors.textPrimary : AppColors.textDisabled,
                        ),
                      ),
                    ),
                    if (value != null)
                      GestureDetector(
                        onTap: onClear,
                        child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
                      ),
                  ],
                ),
              ),
            );
          }

          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(Icons.filter_alt_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Text('Filtrar Movimientos',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Rango de fechas ───────────────────────────────
                    const Text('Rango de fechas',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                    const SizedBox(height: AppSpacing.xs),
                    dateRow(
                      'Desde (opcional)',
                      localFrom,
                      () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime(2020),
                          lastDate: localTo ?? DateTime.now(),
                          initialDate: localFrom ?? DateTime.now().subtract(const Duration(days: 30)),
                          locale: const Locale('es', 'CO'),
                        );
                        if (picked != null) setDlgState(() => localFrom = picked);
                      },
                      () => setDlgState(() => localFrom = null),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    dateRow(
                      'Hasta (opcional)',
                      localTo,
                      () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          firstDate: localFrom ?? DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDate: localTo ?? DateTime.now(),
                          locale: const Locale('es', 'CO'),
                        );
                        if (picked != null) setDlgState(() => localTo = picked);
                      },
                      () => setDlgState(() => localTo = null),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Número de documento ───────────────────────────
                    const Text('Número de documento',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                    const SizedBox(height: AppSpacing.xs),
                    TextFormField(
                      initialValue: localDocNumber,
                      decoration: const InputDecoration(
                        hintText: 'Ej. 00123456',
                        prefixIcon: Icon(Icons.tag_rounded, size: 18),
                        isDense: true,
                      ),
                      onChanged: (v) => setDlgState(() => localDocNumber = v.isEmpty ? null : v),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Búsqueda de producto ──────────────────────────
                    const Text('Producto (código o descripción)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                    const SizedBox(height: AppSpacing.xs),
                    TextFormField(
                      initialValue: localSearch,
                      decoration: const InputDecoration(
                        hintText: 'Ingrese código o descripción',
                        prefixIcon: Icon(Icons.search_rounded, size: 18),
                        isDense: true,
                      ),
                      onChanged: (v) => setDlgState(() => localSearch = v.isEmpty ? null : v),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Almacén ───────────────────────────────────────
                    const Text('Almacén',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                    const SizedBox(height: AppSpacing.xs),
                    DropdownButtonFormField<String>(
                      initialValue: localWarehouse == null || !warehouses.contains(localWarehouse)
                          ? 'Todos'
                          : localWarehouse,
                      isDense: true,
                      decoration: const InputDecoration(isDense: true),
                      items: warehouses
                          .map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(fontSize: 14))))
                          .toList(),
                      onChanged: (v) => setDlgState(() => localWarehouse = v == 'Todos' ? null : v),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Categoría ─────────────────────────────────────
                    const Text('Categoría',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                    const SizedBox(height: AppSpacing.xs),
                    DropdownButtonFormField<String>(
                      initialValue: localGroup == null || !groups.contains(localGroup)
                          ? 'Todos'
                          : localGroup,
                      isDense: true,
                      decoration: const InputDecoration(isDense: true),
                      items: groups
                          .map((v) => DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(fontSize: 14))))
                          .toList(),
                      onChanged: (v) => setDlgState(() => localGroup = v == 'Todos' ? null : v),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Tipo de documento ──────────────────────────────────
                    const Text('Tipo de documento',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                    const SizedBox(height: AppSpacing.xs),
                    DropdownButtonFormField<String>(
                      initialValue: localDocType == null || !docTypes.contains(localDocType)
                          ? 'Todos'
                          : localDocType,
                      isDense: true,
                      decoration: const InputDecoration(isDense: true),
                      items: docTypes
                          .map((v) => DropdownMenuItem(
                                value: v,
                                child: Text(v, style: const TextStyle(fontSize: 14, fontFamily: 'monospace')),
                              ))
                          .toList(),
                      onChanged: (v) => setDlgState(() => localDocType = v == 'Todos' ? null : v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    selectedWarehouse = null;
                    selectedGroup = null;
                    searchQuery = null;
                    docNumberSearch = null;
                    selectedDocType = null;
                    dateFrom = null;
                    dateTo = null;
                  });
                  Navigator.of(dialogCtx).pop();
                  _loadMovementsData();
                },
                child: const Text('Limpiar todo'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    selectedWarehouse = localWarehouse;
                    selectedGroup = localGroup;
                    searchQuery = localSearch;
                    docNumberSearch = localDocNumber;
                    selectedDocType = localDocType;
                    dateFrom = localFrom;
                    dateTo = localTo;
                  });
                  Navigator.of(dialogCtx).pop();
                  _loadMovementsData();
                },
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Aplicar'),
              ),
            ],
          );
        },
      ),
    );
  }
}
