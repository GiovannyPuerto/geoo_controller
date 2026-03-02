import 'dart:io' as io;
import 'package:data_table_2/data_table_2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:universal_html/html.dart' as html
    if (dart.library.io) 'package:geo_inventario/stubs/html_stub.dart';
import 'package:geo_inventario/models/monthly_cut.dart';
import 'package:geo_inventario/models/monthly_product_cut.dart';
import 'package:geo_inventario/services/api_service.dart';
import 'package:geo_inventario/services/refresh_notifier.dart';
import 'package:geo_inventario/tabs/monthly_cuts/monthly_cuts_filtros_service.dart';
import 'package:geo_inventario/theme/app_theme.dart';
import 'package:geo_inventario/utils/currency_formatter.dart';
import 'package:geo_inventario/widgets/data_sources.dart';

class MonthlyCutsTabPage extends StatefulWidget {
  const MonthlyCutsTabPage({super.key});

  @override
  State<MonthlyCutsTabPage> createState() => _MonthlyCutsTabPageState();
}

class _MonthlyCutsTabPageState extends State<MonthlyCutsTabPage> {
  final ApiService _apiService = ApiService();

  List<MonthlyCut> monthlyCuts = [];
  List<MonthlyProductCut> productCuts = [];
  Map<String, double> productTotals = const {
    'average_quantity': 0.0,
    'average_value': 0.0,
  };

  bool isLoading = true;
  bool isProductLoading = false;
  bool productCutsTruncated = false;

  int monthsWindow = 12;
  int productLimit = 5000;

  // Paginación de la tabla de productos
  MonthlyProductCutDataSource? _productDataSource;
  int _productPageRows = 10;

  String? selectedWarehouse;
  String? selectedCategory;
  String? searchQuery;
  String? selectedMonth;

  double periodAverageGeneral = 0;
  int productsCount = 0;
  int monthProductsCount = 0;

  List<String> _warehouseOptions = const [];
  List<String> _categoryOptions = const [];

  @override
  void initState() {
    super.initState();
    inventoryRefreshNotifier.addListener(_onExternalRefresh);
    _loadSelectableFilterOptions();
    _loadData();
  }

  @override
  void dispose() {
    inventoryRefreshNotifier.removeListener(_onExternalRefresh);
    _productDataSource?.dispose();
    super.dispose();
  }

  void _onExternalRefresh() => _loadData();

  Future<void> _loadSelectableFilterOptions() async {
    try {
      final rows = await _apiService.getMovements();
      final options = MonthlyCutsFiltrosService.buildSelectableOptions(
        rows,
        selectedWarehouse: selectedWarehouse,
        selectedCategory: selectedCategory,
      );

      if (!mounted) return;
      setState(() {
        _warehouseOptions = options.warehouses;
        _categoryOptions = options.categories;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _warehouseOptions = const [];
        _categoryOptions = const [];
      });
    }
  }

  List<String> get _monthOptions {
    return MonthlyCutsFiltrosService.monthOptions(monthlyCuts);
  }

  bool get _hasActiveFilters =>
      MonthlyCutsFiltrosService.hasActiveFilters(
        selectedWarehouse: selectedWarehouse,
        selectedCategory: selectedCategory,
        searchQuery: searchQuery,
      );

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      isProductLoading = productCuts.isNotEmpty;
    });

    try {
      final cutsResponse = await _apiService.getMonthlyCuts(
        months: monthsWindow,
        warehouse: selectedWarehouse,
        category: selectedCategory,
        search: searchQuery,
      );
      final cuts =
          (cutsResponse['months'] as List).whereType<MonthlyCut>().toList();
      String? month = selectedMonth;
      if (cuts.isEmpty) {
        month = null;
      } else {
        final validMonths = cuts.map((e) => e.month).toSet();
        if (month == null || !validMonths.contains(month)) month = cuts.last.month;
      }

      if (!mounted) return;
      setState(() {
        monthlyCuts = cuts;
        periodAverageGeneral =
            ((cutsResponse['period_average_general'] as num?) ?? 0).toDouble();
        productsCount = (cutsResponse['products_count'] as int?) ?? 0;
        selectedMonth = month;
        isLoading = false;
      });

      _loadSelectableFilterOptions();

      await _loadProductCuts(month: month);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        isProductLoading = false;
      });
      context.showErrorSnackBar('Error al cargar cortes mensuales: $e');
    }
  }

  Future<void> _loadProductCuts({String? month}) async {
    final targetMonth = month ?? selectedMonth;
    if (targetMonth == null || targetMonth.isEmpty) {
      if (!mounted) return;
      setState(() {
        productCuts = [];
        _productDataSource?.dispose();
        _productDataSource = null;
        monthProductsCount = 0;
        productCutsTruncated = false;
        productTotals = const {'average_quantity': 0.0, 'average_value': 0.0};
        isProductLoading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() => isProductLoading = true);
    try {
      final response = await _apiService.getMonthlyProductCuts(
        warehouse: selectedWarehouse,
        category: selectedCategory,
        search: searchQuery,
        month: targetMonth,
        limit: productLimit,
      );
      final rows =
          (response['products'] as List).whereType<MonthlyProductCut>().toList();
      final totals = (response['totals'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        productCuts = rows;
        _productDataSource?.dispose();
        _productDataSource = MonthlyProductCutDataSource(rows);
        monthProductsCount = (response['products_count'] as int?) ?? rows.length;
        selectedMonth = (response['month'] as String?) ?? targetMonth;
        productCutsTruncated = response['truncated'] == true;
        productTotals = {
          'average_quantity': ((totals['average_quantity'] as num?) ?? 0).toDouble(),
          'average_value': ((totals['average_value'] as num?) ?? 0).toDouble(),
        };
        isProductLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isProductLoading = false);
      context.showErrorSnackBar('Error al cargar inventario mensual por producto: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: AppSpacing.md),
            Text(
              'Cargando cortes mensuales…',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPageHeader(),
              const SizedBox(height: AppSpacing.lg),
              _buildChart(),
              const SizedBox(height: AppSpacing.lg),
              _buildMonthlyTable(),
              const SizedBox(height: AppSpacing.lg),
              _buildProductMonthTable(),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Encabezado de página ──────────────────────────────────────────────────

  Widget _buildPageHeader() {
    return Column(
      children: [
        // ── Banner gradiente corporativo ──────────────────────────────────
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
                child: const Icon(Icons.calendar_month_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cortes Mensuales',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    Text(
                      'Inventario promedio por período',
                      style: TextStyle(fontSize: 12, color: Color(0xCCFFFFFF)),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.download_outlined,
                    size: 20, color: Colors.white),
                tooltip: 'Exportar',
                onPressed: _showExportDialog,
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                icon: const Icon(Icons.filter_list_rounded,
                    size: 20, color: Colors.white),
                tooltip: 'Filtros',
                onPressed: _showFiltersDialog,
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // ── KPI chips + filtros activos ───────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _kpiChip(
                    Icons.bar_chart_rounded,
                    'Promedio general',
                    CurrencyFormatter.format(periodAverageGeneral),
                    AppColors.info,
                  ),
                  _kpiChip(
                    Icons.inventory_2_outlined,
                    'Productos base',
                    '$productsCount',
                    AppColors.warning,
                  ),
                  _kpiChip(
                    Icons.date_range_rounded,
                    'Período',
                    '$monthsWindow meses',
                    AppColors.textMuted,
                  ),
                ],
              ),
              if (_hasActiveFilters) ...[
                const SizedBox(height: AppSpacing.sm),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.sm),
                _buildActiveFilterChips(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _kpiChip(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilterChips() {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Filtros activos:',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        if (selectedWarehouse != null)
          _deletableChip(
            'Almacén: $selectedWarehouse',
            () {
              setState(() => selectedWarehouse = null);
              _loadData();
            },
          ),
        if (selectedCategory != null)
          _deletableChip(
            'Categoría: $selectedCategory',
            () {
              setState(() => selectedCategory = null);
              _loadData();
            },
          ),
        if (searchQuery != null)
          _deletableChip(
            'Búsqueda: $searchQuery',
            () {
              setState(() => searchQuery = null);
              _loadData();
            },
          ),
        TextButton.icon(
          onPressed: () {
            setState(() {
              selectedWarehouse = null;
              selectedCategory = null;
              searchQuery = null;
              selectedMonth = null;
            });
            _loadData();
          },
          icon: const Icon(Icons.clear_all, size: 14),
          label: const Text('Limpiar', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.error,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _deletableChip(String label, VoidCallback onDelete) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onDeleted: onDelete,
      deleteIconColor: AppColors.infoDark,
      backgroundColor: AppColors.infoLight,
      side: BorderSide(color: AppColors.info.withValues(alpha: 0.3)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  // ─── Gráfica ───────────────────────────────────────────────────────────────

  Widget _buildChart() {
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
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.show_chart_rounded,
                    color: AppColors.primaryDark, size: 16),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text(
                'Evolución de Cortes',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (monthlyCuts.isNotEmpty) ...[_buildChartKpis(), const SizedBox(height: AppSpacing.md)],
          SizedBox(
            height: 380,
            child: monthlyCuts.isEmpty
                ? _buildEmptyState(
                    Icons.show_chart_rounded,
                    'Sin datos de cortes',
                    'Carga datos de inventario para ver la evolución.',
                  )
                : SfCartesianChart(
                    plotAreaBorderWidth: 0,
                    plotAreaBackgroundColor: Colors.transparent,
                    primaryXAxis: const CategoryAxis(
                      majorGridLines: MajorGridLines(width: 0),
                      axisLine: AxisLine(width: 0),
                      labelStyle: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                      labelIntersectAction: AxisLabelIntersectAction.rotate45,
                    ),
                    primaryYAxis: NumericAxis(
                      axisLine: const AxisLine(width: 0),
                      majorGridLines: const MajorGridLines(
                        width: 1,
                        color: AppColors.border,
                        dashArray: [4, 4],
                      ),
                      labelStyle: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                      // Formato compacto: $1.2M, $450K, etc.
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
                    legend: const Legend(
                      isVisible: true,
                      position: LegendPosition.bottom,
                      textStyle: TextStyle(fontSize: 11),
                      overflowMode: LegendItemOverflowMode.wrap,
                    ),
                    // Trackball: muestra las 3 series simultáneamente al hacer hover
                    trackballBehavior: TrackballBehavior(
                      enable: true,
                      activationMode: ActivationMode.singleTap,
                      lineType: TrackballLineType.vertical,
                      lineColor: AppColors.textMuted,
                      lineWidth: 1,
                      lineDashArray: const [4, 3],
                      tooltipSettings: const InteractiveTooltip(
                        enable: true,
                        color: Color(0xFF1E293B),
                        textStyle: TextStyle(color: Colors.white, fontSize: 11),
                        borderWidth: 0,
                      ),
                      tooltipDisplayMode: TrackballDisplayMode.groupAllPoints,
                      builder: (context, details) {
                        // Formateador moneda compacto dentro del tooltip
                        String fmt(num v) {
                          return CurrencyFormatter.format(v.toDouble());
                        }
                        final points = details.groupingModeInfo?.points ?? [];
                        if (points.isEmpty) return const SizedBox.shrink();
                        // x está directamente en CartesianChartPoint
                        final xLabel = points.first.x?.toString() ?? '';
                        const seriesNames = [
                          'Corte Promedio',
                          'Corte Final',
                          'Promedio período',
                        ];
                        const seriesColors = [
                          AppColors.chartCutAverage,
                          AppColors.chartCutFinal,
                          AppColors.chartPositive,
                        ];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
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
                              ...points.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final p = entry.value;
                                // y está directamente en CartesianChartPoint
                                final yVal = p.y;
                                final dotColor = idx < seriesColors.length
                                    ? seriesColors[idx]
                                    : Colors.white;
                                final label = idx < seriesNames.length
                                    ? seriesNames[idx]
                                    : 'Serie ${idx + 1}';
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 2),
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
                                        yVal != null ? fmt(yVal) : '—',
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
                      // Barras semi-transparentes para no tapar las líneas
                      ColumnSeries<MonthlyCut, String>(
                        dataSource: monthlyCuts,
                        xValueMapper: (d, _) =>
                          MonthlyCutsFiltrosService.formatMonth(d.month),
                        yValueMapper: (d, _) => d.averageBalanceGeneral,
                        name: 'Corte Promedio General',
                        color: AppColors.chartCutAverage
                            .withValues(alpha: 0.55),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                        width: 0.55,
                        spacing: 0.1,
                        dataLabelSettings: const DataLabelSettings(
                          isVisible: false,
                        ),
                      ),
                      // Línea de corte final con marcadores destacados
                      LineSeries<MonthlyCut, String>(
                        dataSource: monthlyCuts,
                        xValueMapper: (d, _) =>
                          MonthlyCutsFiltrosService.formatMonth(d.month),
                        yValueMapper: (d, _) => d.closingBalance,
                        name: 'Corte Final',
                        color: AppColors.chartCutFinal,
                        width: 2.5,
                        markerSettings: const MarkerSettings(
                          isVisible: true,
                          height: 7,
                          width: 7,
                          color: AppColors.chartCutFinal,
                          borderColor: Colors.white,
                          borderWidth: 1.5,
                        ),
                        dataLabelMapper: (d, _) {
                          final v = d.closingBalance;
                          if (v.abs() >= 1000000) return '\$${(v / 1000000).toStringAsFixed(2)}M';
                          if (v.abs() >= 1000) return '\$${(v / 1000).toStringAsFixed(0)}K';
                          return '\$${v.toStringAsFixed(0)}';
                        },
                        dataLabelSettings: DataLabelSettings(
                          isVisible: true,
                          textStyle: TextStyle(
                            fontSize: 9,
                            color: AppColors.chartCutFinal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Línea de promedio del período (punteada)
                      if (periodAverageGeneral > 0)
                        LineSeries<MonthlyCut, String>(
                          dataSource: monthlyCuts,
                          xValueMapper: (d, _) =>
                            MonthlyCutsFiltrosService.formatMonth(d.month),
                          yValueMapper: (d, _) => periodAverageGeneral,
                          name: 'Promedio $monthsWindow meses',
                          color: AppColors.chartPositive,
                          width: 2,
                          dashArray: const [10, 6],
                          markerSettings: const MarkerSettings(
                            isVisible: false,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ─── KPIs de resumen del período para la gráfica ──────────────────────────

  Widget _buildChartKpis() {
    final opening = monthlyCuts.first.openingBalance;
    final totalEntries = monthlyCuts.fold(0.0, (s, c) => s + c.totalEntries);
    final totalExits = monthlyCuts.fold(0.0, (s, c) => s + c.totalExits);
    final closing = monthlyCuts.last.closingBalance;
    return Row(
      children: [
        _kpiCard(
          label: 'Apertura período',
          value: opening,
          icon: Icons.start_rounded,
          color: AppColors.primary,
        ),
        const SizedBox(width: AppSpacing.sm),
        _kpiCard(
          label: 'Entradas totales',
          value: totalEntries,
          icon: Icons.add_circle_outline_rounded,
          color: AppColors.success,
        ),
        const SizedBox(width: AppSpacing.sm),
        _kpiCard(
          label: 'Salidas totales',
          value: totalExits,
          icon: Icons.remove_circle_outline_rounded,
          color: AppColors.error,
        ),
        const SizedBox(width: AppSpacing.sm),
        _kpiCard(
          label: 'Cierre período',
          value: closing,
          icon: Icons.flag_rounded,
          color: AppColors.chartCutFinal,
        ),
      ],
    );
  }

  Widget _kpiCard({
    required String label,
    required double value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              CurrencyFormatter.format(value),
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Tabla de cortes mensuales ─────────────────────────────────────────────

  Widget _buildMonthlyTable() {
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
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.table_chart_outlined,
                    color: AppColors.infoDark, size: 16),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text(
                'Resumen Mensual',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (monthlyCuts.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    '${monthlyCuts.length} meses',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (monthlyCuts.isEmpty)
            _buildEmptyState(
              Icons.calendar_today_outlined,
              'Sin datos de cortes',
              'No hay cortes para los filtros seleccionados.',
            )
          else
            SizedBox(
              height: 300,
              child: DataTable2(
                minWidth: 980,
                headingRowColor: WidgetStateProperty.all(AppColors.surfaceVariant),
                headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                dataTextStyle: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
                columns: const [
                  DataColumn2(label: Text('Mes')),
                  DataColumn2(label: Text('Apertura'), numeric: true),
                  DataColumn2(label: Text('Entradas'), numeric: true),
                  DataColumn2(label: Text('Salidas'), numeric: true),
                  DataColumn2(label: Text('Cierre'), numeric: true),
                  DataColumn2(label: Text('Prom. General'), numeric: true),
                ],
                rows: monthlyCuts.asMap().entries.map((entry) {
                  final i = entry.key;
                  final row = entry.value;
                  return DataRow(
                    color: WidgetStateProperty.all(
                      i.isOdd ? AppColors.surfaceVariant : AppColors.surface,
                    ),
                    cells: [
                      DataCell(Text(MonthlyCutsFiltrosService.formatMonth(
                        row.month,
                        longLabel: true,
                      ))),
                      DataCell(Text(CurrencyFormatter.format(row.openingBalance))),
                      DataCell(Text(
                        CurrencyFormatter.format(row.totalEntries),
                        style: const TextStyle(color: AppColors.success),
                      )),
                      DataCell(Text(
                        CurrencyFormatter.format(row.totalExits),
                        style: const TextStyle(color: AppColors.error),
                      )),
                      DataCell(Text(CurrencyFormatter.format(row.closingBalance))),
                      DataCell(Text(CurrencyFormatter.format(row.averageBalanceGeneral))),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Tabla de productos por mes ────────────────────────────────────────────

  Widget _buildProductMonthTable() {
    final options = _monthOptions;
    final activeMonth = options.contains(selectedMonth)
        ? selectedMonth
        : (options.isNotEmpty ? options.last : null);

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
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.inventory_2_outlined,
                    color: AppColors.warningDark, size: 16),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'Inventario promedio del mes',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (options.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: options.asMap().entries.map((entry) {
                  final m = entry.value;
                  final isActive = m == activeMonth;
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: ChoiceChip(
                      label: Text(
                        MonthlyCutsFiltrosService.formatMonth(m),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isActive
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                      ),
                      selected: isActive,
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surfaceVariant,
                      side: BorderSide(
                        color: isActive
                            ? AppColors.primary
                            : AppColors.border,
                        width: isActive ? 1.5 : 1.0,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 4),
                      onSelected: (selected) {
                        if (!selected || m == selectedMonth) return;
                        setState(() => selectedMonth = m);
                        _loadProductCuts(month: m);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _kpiChip(
                Icons.grid_3x3_rounded,
                'Productos del mes',
                '$monthProductsCount',
                AppColors.primaryDark,
              ),
              _kpiChip(
                Icons.monetization_on_outlined,
                'Valor total promedio',
                CurrencyFormatter.format(productTotals['average_value'] ?? 0),
                AppColors.warning,
              ),
            ],
          ),
          if (productCutsTruncated) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 14, color: AppColors.warningDark),
                  const SizedBox(width: 6),
                  Text(
                    'Mostrando top $productLimit productos por valor promedio.',
                    style: const TextStyle(
                        color: AppColors.warningDark, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (isProductLoading)
            const SizedBox(
              height: 200,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: AppSpacing.md),
                    Text(
                      'Cargando productos del mes…',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else if (productCuts.isEmpty)
            _buildEmptyState(
              Icons.inventory_2_outlined,
              'Sin inventario mensual',
              'No hay productos registrados para este mes.',
            )
          else
            _buildProductTable(),
        ],
      ),
    );
  }

  // ─── Tabla paginada de productos ───────────────────────────────────────────

  Widget _buildProductTable() {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: 400,
        maxHeight: 650,
      ),
      child: PaginatedDataTable2(
        key: ValueKey(selectedMonth),
        columnSpacing: 12,
        horizontalMargin: 12,
        minWidth: 1100,
        scrollController: ScrollController(),
        isHorizontalScrollBarVisible: true,
        headingRowColor:
            WidgetStateProperty.all(AppColors.surfaceVariant),
        headingTextStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        dataTextStyle: const TextStyle(
          fontSize: 12,
          color: AppColors.textPrimary,
        ),
        dividerThickness: 1,
        rowsPerPage: _productPageRows,
        availableRowsPerPage: const [10, 25, 50],
        onRowsPerPageChanged: (value) {
          if (value != null) setState(() => _productPageRows = value);
        },
        columns: const [
          DataColumn2(label: Text('Código'), size: ColumnSize.S),
          DataColumn2(label: Text('Nombre Producto'), size: ColumnSize.L),
          DataColumn2(label: Text('Grupo')),
          DataColumn2(label: Text('Cant. Promedio'), numeric: true),
          DataColumn2(label: Text('Valor Promedio'), numeric: true),
          DataColumn2(label: Text('Costo Unitario'), numeric: true),
        ],
        source: _productDataSource!,
      ),
    );
  }

  // ─── Estado vacío ──────────────────────────────────────────────────────────

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Icon(icon, size: 40, color: AppColors.textDisabled),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Dialogs ───────────────────────────────────────────────────────────────

  void _showFiltersDialog() {
    int localMonths = monthsWindow;
    String? localWarehouse = selectedWarehouse;
    String? localCategory = selectedCategory;
    String localSearch = searchQuery ?? '';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
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
                child: const Icon(Icons.filter_alt_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text('Filtros — Cortes Mensuales',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Ventana mensual ──────────────────────────────────
                  const Text('Ventana de meses',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted)),
                  const SizedBox(height: AppSpacing.xs),
                  DropdownButtonFormField<int>(
                    initialValue: localMonths,
                    isDense: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon:
                          Icon(Icons.date_range_rounded, size: 18),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 6,
                          child: Text('Últimos 6 meses',
                              style: TextStyle(fontSize: 14))),
                      DropdownMenuItem(
                          value: 12,
                          child: Text('Últimos 12 meses',
                              style: TextStyle(fontSize: 14))),
                      DropdownMenuItem(
                          value: 18,
                          child: Text('Últimos 18 meses',
                              style: TextStyle(fontSize: 14))),
                      DropdownMenuItem(
                          value: 24,
                          child: Text('Últimos 24 meses',
                              style: TextStyle(fontSize: 14))),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDlgState(() => localMonths = value);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── Almacén ─────────────────────────────────────────
                  const Text('Almacén',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted)),
                  const SizedBox(height: AppSpacing.xs),
                  DropdownButtonFormField<String>(
                    initialValue: localWarehouse,
                    isDense: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon:
                          Icon(Icons.warehouse_outlined, size: 18),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Todos',
                              style: TextStyle(fontSize: 14))),
                      ..._warehouseOptions.map(
                        (item) => DropdownMenuItem<String>(
                          value: item,
                          child: Text(item,
                              style: const TextStyle(fontSize: 14)),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setDlgState(() => localWarehouse = value),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── Categoría ────────────────────────────────────────
                  const Text('Categoría',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted)),
                  const SizedBox(height: AppSpacing.xs),
                  DropdownButtonFormField<String>(
                    initialValue: localCategory,
                    isDense: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon:
                          Icon(Icons.category_outlined, size: 18),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Todas',
                              style: TextStyle(fontSize: 14))),
                      ..._categoryOptions.map(
                        (item) => DropdownMenuItem<String>(
                          value: item,
                          child: Text(item,
                              style: const TextStyle(fontSize: 14)),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setDlgState(() => localCategory = value),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── Búsqueda ─────────────────────────────────────────
                  const Text('Producto o código',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted)),
                  const SizedBox(height: AppSpacing.xs),
                  TextFormField(
                    initialValue: localSearch,
                    decoration: const InputDecoration(
                      hintText: 'Escribe código o descripción',
                      prefixIcon:
                          Icon(Icons.search_rounded, size: 18),
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        setDlgState(() => localSearch = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  monthsWindow = 12;
                  selectedWarehouse = null;
                  selectedCategory = null;
                  searchQuery = null;
                  selectedMonth = null;
                });
                Navigator.of(dialogContext).pop();
                _loadData();
              },
              child: const Text('Limpiar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  monthsWindow = localMonths;
                  selectedWarehouse = localWarehouse;
                  selectedCategory = localCategory;
                  searchQuery = localSearch.trim().isEmpty
                      ? null
                      : localSearch.trim();
                });
                Navigator.of(dialogContext).pop();
                _loadData();
              },
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
            const Text('Exportar Cortes Mensuales',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text('Selecciona el formato del informe:'),
        actions: [
          TextButton(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.table_chart_outlined, size: 16),
            label: const Text('Excel'),
            onPressed: () {
              _exportCuts('excel');
              Navigator.of(dialogContext).pop();
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text('PDF'),
            onPressed: () {
              _exportCuts('pdf');
              Navigator.of(dialogContext).pop();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _exportCuts(String format) async {
    try {
      final response = await _apiService.exportMonthlyCuts(
        format: format,
        warehouse: selectedWarehouse,
        category: selectedCategory,
        search: searchQuery,
        months: monthsWindow,
        month: selectedMonth,
        productLimit: productLimit,
      );
      if (response.statusCode != 200) {
        throw Exception('Error de exportación (${response.statusCode})');
      }

      final bytes = response.bodyBytes;
      final extension = format == 'excel' ? 'xlsx' : 'pdf';
      final fileName =
          'cortes_mensuales_${DateTime.now().toIso8601String().replaceAll(':', '-')}.$extension';

      if (kIsWeb) {
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar informe de cortes mensuales',
          fileName: fileName,
          allowedExtensions: [extension],
          type: FileType.custom,
        );
        if (path == null) return;
        await io.File(path).writeAsBytes(bytes);
      }
      if (!mounted) return;
      context.showSuccessSnackBar('Informe exportado correctamente');
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Error al exportar cortes mensuales: $e');
    }
  }
}
