import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geo_inventario/services/api_service.dart';
import 'package:geo_inventario/services/refresh_notifier.dart';
import 'package:geo_inventario/tabs/analysis/analisis_catalogo_service.dart';
import 'package:geo_inventario/theme/app_theme.dart';
import 'package:geo_inventario/utils/currency_formatter.dart';
import 'package:geo_inventario/widgets/data_sources.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class AnalysisTabPage extends StatefulWidget {
  const AnalysisTabPage({super.key});

  @override
  State<AnalysisTabPage> createState() => _AnalysisTabPageState();
}

class _AnalysisTabPageState extends State<AnalysisTabPage> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> analysis = [];
  List<Map<String, dynamic>> filteredAnalysis = [];
  bool isLoading = true;
  bool _isRefreshing = false;
  int _analysisRequestEpoch = 0;

  bool _isRangeMode = false;

  // Filters
  DateTime? selectedDateFrom;
  DateTime? selectedDateTo;
  String? searchQuery;
  String? selectedGroup;
  String? selectedRotation;
  String? selectedStagnant;
  String? selectedHighRotation;
  String? selectedWarehouse;

  @override
  void initState() {
    super.initState();
    inventoryRefreshNotifier.addListener(_onExternalRefresh);
    _loadAnalysisData();
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
      selectedDateFrom = null;
      selectedDateTo = null;
      searchQuery = null;
      selectedGroup = null;
      selectedRotation = null;
      selectedStagnant = null;
      selectedHighRotation = null;
      selectedWarehouse = null;
      _isRangeMode = false;
    });
    _loadAnalysisData();
  }

  Future<void> _loadAnalysisData() async {
    if (!mounted) return;
    final requestEpoch = ++_analysisRequestEpoch;
    final bool isFullRange = selectedDateFrom != null && selectedDateTo != null;

    setState(() {
      if (analysis.isEmpty) {
        isLoading = true;
        _isRefreshing = false;
      } else {
        _isRefreshing = true;
      }
    });

    try {
      List<Map<String, dynamic>> rows;

      if (isFullRange) {
        // Rango completo → promedio diario real, igual que los cortes mensuales
        final result = await _apiService.getRangeProductCuts(
          dateFrom: selectedDateFrom!,
          dateTo: selectedDateTo!,
          warehouse: selectedWarehouse,
          category: selectedGroup,
          search: searchQuery,
        );
        final rawProducts =
            List<Map<String, dynamic>>.from(result['products'] as List? ?? []);
        // Mapear al formato que usa AnalysisDataSource
        rows = rawProducts
            .map((p) => <String, dynamic>{
                  'codigo': p['codigo'],
                  'nombre_producto': p['nombre_producto'],
                  'grupo': p['grupo'],
                  'cantidad_saldo_actual': p['cantidad_promedio'],
                  'valor_saldo_actual': p['valor_promedio'],
                  'costo_unitario': p['costo_unitario'],
                  'rotacion': '—',
                  'estancado': '—',
                  'alta_rotacion': '—',
                  'negative_stock_alert': false,
                  // Columnas extra disponibles para referencia
                  'cantidad_apertura': p['cantidad_apertura'],
                  'cantidad_cierre': p['cantidad_cierre'],
                })
            .toList();
      } else {
        // Sin rango o solo un extremo → inventario a la última carga
        rows = await _apiService.getAnalysis(
          warehouse: selectedWarehouse,
          category: selectedGroup,
          rotation: selectedRotation,
          stagnant: selectedStagnant,
          highRotation: selectedHighRotation,
          search: searchQuery,
          dateFrom: selectedDateFrom,
          dateTo: selectedDateTo,
        );
      }

      if (mounted && requestEpoch == _analysisRequestEpoch) {
        final sorted = List<Map<String, dynamic>>.from(rows)
          ..sort((a, b) {
            final va = ((a['valor_saldo_actual'] as num?) ?? 0).toDouble();
            final vb = ((b['valor_saldo_actual'] as num?) ?? 0).toDouble();
            return vb.compareTo(va);
          });
        setState(() {
          analysis = sorted;
          filteredAnalysis = sorted;
          _isRangeMode = isFullRange;
          isLoading = false;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      if (mounted && requestEpoch == _analysisRequestEpoch) {
        setState(() {
          isLoading = false;
          _isRefreshing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading analysis: $e')),
        );
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
              'Cargando análisis…',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Contenido principal (datos o estado vacío).
    Widget content;
    if (filteredAnalysis.isEmpty) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: const Icon(Icons.analytics_outlined,
                    size: 44, color: AppColors.textDisabled),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'Sin datos de análisis',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Carga archivos de inventario para ver el análisis de productos.',
                style: TextStyle(
                    fontSize: 14, color: AppColors.textMuted, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    } else {
      content = RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadAnalysisData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Banner de sección ────────────────────────────────────
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
                      child: const Icon(Icons.analytics_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isRangeMode
                                ? 'Análisis (Promedio Rango)'
                                : 'Análisis de Productos',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                          Text(
                            _isRangeMode
                                ? 'Promedio diario en el período seleccionado'
                                : 'Corte de inventario a la fecha',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xCCFFFFFF)),
                          ),
                        ],
                      ),
                    ),
                    if (_hasActiveFilters())
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: Chip(
                          label: const Text(
                            'Filtro activo',
                            style: TextStyle(
                              color: AppColors.primaryDark,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          backgroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.filter_list_rounded,
                          size: 20, color: Colors.white),
                      tooltip: 'Filtros',
                      onPressed: showFiltersDialog,
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
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_hasActiveFilters()) ...[
                _buildActiveFilterChips(),
                const SizedBox(height: AppSpacing.sm)
              ],
              _buildAnalysisCharts(),
              const SizedBox(height: AppSpacing.lg),
              _buildNegativeStockAlerts(),
              const SizedBox(height: AppSpacing.lg),
              _buildAnalysisTable(),
            ],
          ),
        ),
      );
    } // else

    // Envuelve el contenido en un Stack para mostrar el overlay de recarga
    // cuando el usuario aplica filtros (sin blanquear la pantalla entera).
    return Stack(
      children: [
        content,
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
      ],
    );
  }

  Widget _buildAnalysisCharts() {
    // Prepare data for charts
    final groupData = <String, double>{};
    final rotationData = <String, int>{};
    double totalValue = 0;
    int totalProducts = filteredAnalysis.length;

    for (var item in filteredAnalysis) {
      final rawGroup = item['grupo'];
      final group = (rawGroup != null && rawGroup.toString().isNotEmpty)
          ? _getGroupName(rawGroup.toString())
          : 'SIN CATEGORÍA';
      final rawValue = item['valor_saldo_actual'];
      final value = (rawValue is num) ? rawValue.toDouble() : 0;
      groupData[group] = (groupData[group] ?? 0) + value;
      totalValue += value;

      final rotation = item['rotacion']?.toString() ?? 'Activo';
      rotationData[rotation] = (rotationData[rotation] ?? 0) + 1;
    }

    // Paleta corporativa de gráficas
    const List<Color> groupColors = AppColors.chartPalette;

    // Create sorted group data
    final sortedGroupData = groupData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 600;
      final chartHeight = isMobile ? 280.0 : 500.0;

      // Gráfico de distribución por Grupo
      Widget groupCard = Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Distribución por Grupo',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Image.asset('statics/images/logo_geoflora.png', height: 30),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Total productos: $totalProducts | Valor total: ${CurrencyFormatter.format(totalValue)}',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: chartHeight,
                child: SfCircularChart(
                  margin: EdgeInsets.zero,
                  legend: const Legend(
                    isVisible: true,
                    position: LegendPosition.bottom,
                    textStyle: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.w500),
                    overflowMode: LegendItemOverflowMode.wrap,
                    iconHeight: 12,
                    iconWidth: 12,
                  ),
                  series: <CircularSeries>[
                    PieSeries<MapEntry<String, double>, String>(
                      dataSource: sortedGroupData,
                      xValueMapper: (MapEntry<String, double> data, _) =>
                          data.key,
                      yValueMapper: (MapEntry<String, double> data, _) =>
                          data.value,
                      pointColorMapper:
                          (MapEntry<String, double> data, int index) =>
                              groupColors[index % groupColors.length],
                      dataLabelMapper: (MapEntry<String, double> data, _) {
                        final total = groupData.values.reduce((a, b) => a + b);
                        final percentage =
                            (data.value / total * 100).toStringAsFixed(1);
                        final shortName = _getShortGroupName(data.key);
                        return '$shortName\n$percentage%';
                      },
                      radius: '60%',
                      dataLabelSettings: DataLabelSettings(
                        isVisible: true,
                        textStyle: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600),
                        labelPosition: ChartDataLabelPosition.outside,
                        connectorLineSettings: const ConnectorLineSettings(
                          type: ConnectorType.line,
                          length: '10%',
                          color: AppColors.textDisabled,
                          width: 1.2,
                        ),
                        useSeriesColor: false,
                        color: Colors.white,
                        borderRadius: 4,
                        borderWidth: 1,
                        borderColor: AppColors.border,
                        margin: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        labelIntersectAction: LabelIntersectAction.shift,
                      ),
                      explode: true,
                      explodeGesture: ActivationMode.singleTap,
                      explodeOffset: '8%',
                      explodeAll: false,
                      animationDuration: 1200,
                      enableTooltip: true,
                      strokeColor: Colors.white,
                      strokeWidth: 2,
                      selectionBehavior: SelectionBehavior(
                        enable: true,
                        selectedOpacity: 1.0,
                        unselectedOpacity: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      // Gráfico de distribución por Rotación
      Widget rotationCard = Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Distribución por Rotación',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Image.asset('statics/images/logo_geoflora.png', height: 30),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Total productos: $totalProducts',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: chartHeight,
                child: SfCircularChart(
                  legend: const Legend(
                    isVisible: true,
                    position: LegendPosition.bottom,
                    textStyle: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 8,
                        fontWeight: FontWeight.w500),
                    overflowMode: LegendItemOverflowMode.wrap,
                    iconHeight: 12,
                    iconWidth: 12,
                  ),
                  series: <CircularSeries>[
                    PieSeries<MapEntry<String, int>, String>(
                      dataSource: rotationData.entries.toList(),
                      xValueMapper: (MapEntry<String, int> data, _) => data.key,
                      yValueMapper: (MapEntry<String, int> data, _) =>
                          data.value,
                      pointColorMapper:
                          (MapEntry<String, int> data, int index) =>
                              _getRotationColor(data.key),
                      dataLabelMapper: (MapEntry<String, int> data, _) {
                        final total =
                            rotationData.values.reduce((a, b) => a + b);
                        final percentage =
                            (data.value / total * 100).toStringAsFixed(1);
                        return '${data.key}\n${data.value} ($percentage%)';
                      },
                      dataLabelSettings: DataLabelSettings(
                        isVisible: true,
                        textStyle: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600),
                        labelPosition: ChartDataLabelPosition.outside,
                        useSeriesColor: false,
                        color: Colors.white,
                        borderRadius: 6,
                        borderWidth: 1,
                        borderColor: AppColors.border,
                        margin: const EdgeInsets.all(3),
                        labelIntersectAction: LabelIntersectAction.shift,
                      ),
                      explode: true,
                      explodeGesture: ActivationMode.singleTap,
                      explodeOffset: '8%',
                      explodeAll: false,
                      animationDuration: 1500,
                      enableTooltip: true,
                      strokeColor: Colors.white,
                      strokeWidth: 2,
                      selectionBehavior: SelectionBehavior(
                        enable: true,
                        selectedOpacity: 1.0,
                        unselectedOpacity: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      // En mobile: apilados; en desktop: lado a lado
      Widget chartsRow = isMobile
          ? Column(
              children: [groupCard, const SizedBox(height: 16), rotationCard])
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: groupCard),
                  const SizedBox(width: 16),
                  Expanded(child: rotationCard),
                ],
              ),
            );

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          chartsRow,
          const SizedBox(height: 16),
          Container(
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
                    Icon(Icons.bar_chart_rounded,
                        size: 18, color: AppColors.primary),
                    SizedBox(width: AppSpacing.sm),
                    Text(
                      'Valor Total por Grupo',
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
                LayoutBuilder(builder: (ctx3, cons3) {
                  final h3 = cons3.maxWidth < 480 ? 280.0 : 380.0;
                  return SizedBox(
                    height: h3,
                    child: SfCartesianChart(
                      primaryXAxis: const CategoryAxis(
                        labelStyle: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                        ),
                        axisLine: AxisLine(width: 0),
                        majorTickLines: MajorTickLines(size: 0),
                        majorGridLines: MajorGridLines(width: 0),
                        labelIntersectAction: AxisLabelIntersectAction.rotate45,
                      ),
                      primaryYAxis: NumericAxis(
                        axisLine: const AxisLine(width: 0),
                        majorTickLines: const MajorTickLines(size: 0),
                        labelStyle: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                        ),
                        majorGridLines: const MajorGridLines(
                          width: 1,
                          color: AppColors.border,
                          dashArray: [4, 4],
                        ),
                        axisLabelFormatter: (AxisLabelRenderDetails details) {
                          final v = details.value.toDouble();
                          String label;
                          if (v.abs() >= 1000000000) {
                            label = '\$${(v / 1000000000).toStringAsFixed(1)}B';
                          } else if (v.abs() >= 1000000) {
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
                      legend: const Legend(isVisible: false),
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
                          color: AppColors.dark,
                          textStyle:
                              TextStyle(color: Colors.white, fontSize: 11),
                          borderWidth: 0,
                        ),
                        builder: (context, details) {
                          final points = details.groupingModeInfo?.points ?? [];
                          if (points.isEmpty) return const SizedBox.shrink();
                          final point = points.first;
                          final xLabel = point.x?.toString() ?? '';
                          final yVal = point.y;
                          final idx = sortedGroupData.indexWhere(
                            (e) => e.key == xLabel,
                          );
                          final barColor = groupColors[
                              (idx >= 0 ? idx : 0) % groupColors.length];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.dark,
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
                                    color: AppColors.textDisabled,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: barColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Valor: ',
                                      style: TextStyle(
                                        color: AppColors.textDisabled,
                                        fontSize: 11,
                                      ),
                                    ),
                                    Text(
                                      yVal != null
                                          ? CurrencyFormatter.format(
                                              yVal.toDouble())
                                          : '—',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      series: <CartesianSeries>[
                        ColumnSeries<MapEntry<String, double>, String>(
                          dataSource: sortedGroupData,
                          xValueMapper: (MapEntry<String, double> data, _) =>
                              data.key,
                          yValueMapper: (MapEntry<String, double> data, _) =>
                              data.value,
                          pointColorMapper:
                              (MapEntry<String, double> data, int index) =>
                                  groupColors[index % groupColors.length]
                                      .withValues(alpha: 0.82),
                          dataLabelSettings: DataLabelSettings(
                            isVisible: true,
                            labelAlignment: ChartDataLabelAlignment.top,
                            textStyle: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                            builder: (dynamic dataPoint,
                                dynamic point,
                                dynamic series,
                                int pointIndex,
                                int seriesIndex) {
                              final entry =
                                  dataPoint as MapEntry<String, double>;
                              final v = entry.value;
                              String label;
                              if (v.abs() >= 1000000000) {
                                label =
                                    '\$${(v / 1000000000).toStringAsFixed(1)}B';
                              } else if (v.abs() >= 1000000) {
                                label =
                                    '\$${(v / 1000000).toStringAsFixed(1)}M';
                              } else if (v.abs() >= 1000) {
                                label = '\$${(v / 1000).toStringAsFixed(0)}K';
                              } else {
                                label = '\$${v.toStringAsFixed(0)}';
                              }
                              return Text(
                                label,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              );
                            },
                          ),
                          width: 0.55,
                          spacing: 0.1,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(5),
                            topRight: Radius.circular(5),
                          ),
                          animationDuration: 1200,
                          enableTooltip: true,
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      );
    }); // LayoutBuilder
  }

  Widget _buildNegativeStockAlerts() {
    final negativeStockItems = filteredAnalysis
        .where((item) => item['negative_stock_alert'] == true)
        .toList();

    if (negativeStockItems.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.report_problem_rounded,
                  size: 18, color: AppColors.error),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Alertas de stock negativo (${negativeStockItems.length})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: AppColors.errorDark, size: 15),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Los siguientes productos tienen saldo negativo y requieren revisión.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.errorDark, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: ListView.builder(
              itemCount: negativeStockItems.length,
              itemBuilder: (context, index) {
                final item = negativeStockItems[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_downward_rounded,
                          color: AppColors.error, size: 15),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['nombre_producto'] ?? '',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.errorDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Código: ${item['codigo'] ?? ''} · ${item['justification'] ?? ''}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _hasActiveFilters() =>
      selectedGroup != null ||
      selectedRotation != null ||
      selectedStagnant != null ||
      selectedHighRotation != null ||
      selectedWarehouse != null ||
      (searchQuery != null && searchQuery!.isNotEmpty) ||
      selectedDateFrom != null ||
      selectedDateTo != null;

  Widget _buildActiveFilterChips() {
    final chips = <Widget>[];

    void addChip(IconData icon, String label, VoidCallback onDelete) {
      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border:
                Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onDelete,
                child: const Icon(Icons.close_rounded,
                    size: 12, color: AppColors.primaryDark),
              ),
            ],
          ),
        ),
      );
    }

    if (selectedGroup != null) {
      addChip(Icons.category_rounded, 'Grupo: $selectedGroup', () {
        setState(() => selectedGroup = null);
        _loadAnalysisData();
      });
    }
    if (selectedRotation != null) {
      addChip(Icons.autorenew_rounded, 'Rotación: $selectedRotation', () {
        setState(() => selectedRotation = null);
        _loadAnalysisData();
      });
    }
    if (selectedStagnant != null) {
      addChip(Icons.hourglass_empty_rounded, 'Estancado: $selectedStagnant',
          () {
        setState(() => selectedStagnant = null);
        _loadAnalysisData();
      });
    }
    if (selectedHighRotation != null) {
      addChip(Icons.trending_up_rounded, 'Alta Rot.: $selectedHighRotation',
          () {
        setState(() => selectedHighRotation = null);
        _loadAnalysisData();
      });
    }
    if (selectedWarehouse != null) {
      addChip(Icons.warehouse_rounded, 'Almacén: $selectedWarehouse', () {
        setState(() => selectedWarehouse = null);
        _loadAnalysisData();
      });
    }
    if (searchQuery != null && searchQuery!.isNotEmpty) {
      addChip(Icons.search_rounded, 'Búsqueda: $searchQuery', () {
        setState(() => searchQuery = null);
        _loadAnalysisData();
      });
    }
    if (selectedDateFrom != null) {
      final dateStr =
          DateFormat('dd/MM/yyyy', 'es_CO').format(selectedDateFrom!);
      addChip(Icons.calendar_today_rounded, 'Desde: $dateStr', () {
        setState(() => selectedDateFrom = null);
        _loadAnalysisData();
      });
    }
    if (selectedDateTo != null) {
      final dateStr = DateFormat('dd/MM/yyyy', 'es_CO').format(selectedDateTo!);
      addChip(Icons.event_rounded, 'Hasta: $dateStr', () {
        setState(() => selectedDateTo = null);
        _loadAnalysisData();
      });
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...chips,
          TextButton.icon(
            onPressed: () {
              setState(() {
                selectedGroup = null;
                selectedRotation = null;
                selectedStagnant = null;
                selectedHighRotation = null;
                selectedWarehouse = null;
                searchQuery = null;
                selectedDateFrom = null;
                selectedDateTo = null;
              });
              _loadAnalysisData();
            },
            icon: const Icon(Icons.filter_list_off_rounded, size: 14),
            label: const Text('Limpiar todo', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisTable() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(Icons.analytics_outlined,
                      color: AppColors.primaryDark, size: 18),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Text(
                  'Catálogo de Productos',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_isRangeMode) _buildRangeModeInfoBanner(),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 600,
              child: PaginatedDataTable2(
                columnSpacing: 12,
                horizontalMargin: 12,
                minWidth: 1000,
                scrollController: ScrollController(),
                isHorizontalScrollBarVisible: true,
                columns: const [
                  DataColumn2(
                    label: Text('Código'),
                    size: ColumnSize.S,
                  ),
                  DataColumn2(
                    label: Text('Nombre Producto'),
                    size: ColumnSize.M,
                  ),
                  DataColumn2(
                    label: Text('Grupo'),
                    size: ColumnSize.S,
                  ),
                  DataColumn2(
                    label: Text('Cantidad Saldo Actual'),
                    size: ColumnSize.S,
                  ),
                  DataColumn2(
                    label: Text('Valor Saldo Actual'),
                    size: ColumnSize.S,
                  ),
                  DataColumn2(
                    label: Text('Costo Unitario'),
                    size: ColumnSize.S,
                    numeric: true,
                  ),
                  DataColumn2(
                    label: Text('Estancado'),
                    size: ColumnSize.S,
                  ),
                  DataColumn2(
                    label: Text('Rotación'),
                    size: ColumnSize.S,
                  ),
                  DataColumn2(
                    label: Text('Alta Rotación'),
                    size: ColumnSize.S,
                  ),
                ],
                source: AnalysisDataSource(filteredAnalysis),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void showFiltersDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogCtx) {
        // Variables locales en el scope del showDialog (no dentro del
        // StatefulBuilder.builder) para que no se reinicien en cada rebuild.
        DateTime? localDateFrom = selectedDateFrom;
        DateTime? localDateTo = selectedDateTo;
        String? localGroup = selectedGroup;
        String? localRotation = selectedRotation;
        String? localStagnant = selectedStagnant;
        String? localHighRotation = selectedHighRotation;
        String? localSearch = searchQuery;

        final fmt = DateFormat('dd/MM/yyyy', 'es_CO');
        final groups = {'Todos', ..._getUniqueValues('grupo')}.toList();

        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            Widget dateRow(
              String label,
              DateTime? value,
              VoidCallback onTap,
              VoidCallback onClear,
            ) {
              return GestureDetector(
                onTap: onTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color:
                          value != null ? AppColors.primary : AppColors.border,
                      width: value != null ? 1.8 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 16,
                          color: value != null
                              ? AppColors.primary
                              : AppColors.textDisabled),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          value != null ? fmt.format(value) : label,
                          style: TextStyle(
                            fontSize: 14,
                            color: value != null
                                ? AppColors.textPrimary
                                : AppColors.textDisabled,
                          ),
                        ),
                      ),
                      if (value != null)
                        GestureDetector(
                          onTap: onClear,
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: AppColors.textMuted),
                        ),
                    ],
                  ),
                ),
              );
            }

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
                    child: const Icon(Icons.filter_alt_rounded,
                        color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Text(
                    'Filtros — Análisis',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Grupo ──────────────────────────────────────────
                      const Text('Grupo',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted)),
                      const SizedBox(height: AppSpacing.xs),
                      DropdownButtonFormField<String>(
                        initialValue:
                            localGroup == null || !groups.contains(localGroup)
                                ? 'Todos'
                                : localGroup,
                        isDense: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.category_rounded, size: 18),
                        ),
                        items: groups
                            .map((v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(v,
                                      style: const TextStyle(fontSize: 14)),
                                ))
                            .toList(),
                        onChanged: (v) => setDlgState(
                            () => localGroup = v == 'Todos' ? null : v),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // ── Rotación ───────────────────────────────────────
                      const Text('Rotación',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted)),
                      const SizedBox(height: AppSpacing.xs),
                      DropdownButtonFormField<String>(
                        initialValue: (localRotation?.isNotEmpty == true)
                            ? localRotation
                            : 'Todos',
                        isDense: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.autorenew_rounded, size: 18),
                        ),
                        items: [
                          'Todos',
                          'Activo',
                          'Estancado',
                          'Obsoleto',
                          'Inactivo'
                        ]
                            .map((v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(v,
                                      style: const TextStyle(fontSize: 14)),
                                ))
                            .toList(),
                        onChanged: (v) => setDlgState(
                            () => localRotation = v == 'Todos' ? null : v),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // ── Estancado ──────────────────────────────────────
                      const Text('Estancado',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted)),
                      const SizedBox(height: AppSpacing.xs),
                      DropdownButtonFormField<String>(
                        initialValue: (localStagnant?.isNotEmpty == true)
                            ? localStagnant
                            : 'Todos',
                        isDense: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon:
                              Icon(Icons.hourglass_bottom_rounded, size: 18),
                        ),
                        items: ['Todos', 'Sí', 'No']
                            .map((v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(v,
                                      style: const TextStyle(fontSize: 14)),
                                ))
                            .toList(),
                        onChanged: (v) => setDlgState(
                            () => localStagnant = v == 'Todos' ? null : v),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // ── Alta Rotación ──────────────────────────────────
                      const Text('Alta Rotación',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted)),
                      const SizedBox(height: AppSpacing.xs),
                      DropdownButtonFormField<String>(
                        initialValue: (localHighRotation?.isNotEmpty == true)
                            ? localHighRotation
                            : 'Todos',
                        isDense: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.trending_up_rounded, size: 18),
                        ),
                        items: ['Todos', 'Sí', 'No']
                            .map((v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(v,
                                      style: const TextStyle(fontSize: 14)),
                                ))
                            .toList(),
                        onChanged: (v) => setDlgState(
                            () => localHighRotation = v == 'Todos' ? null : v),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // ── Búsqueda ───────────────────────────────────────
                      const Text('Producto (código o descripción)',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted)),
                      const SizedBox(height: AppSpacing.xs),
                      TextFormField(
                        initialValue: localSearch,
                        decoration: const InputDecoration(
                          hintText: 'Ingrese código o descripción',
                          prefixIcon: Icon(Icons.search_rounded, size: 18),
                          isDense: true,
                        ),
                        onChanged: (v) => setDlgState(
                            () => localSearch = v.isEmpty ? null : v),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // ── Rango de fechas ───────────────────────────────
                      const Text(
                        'Rango de fechas',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Desde',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textDisabled)),
                                const SizedBox(height: 4),
                                dateRow(
                                  'dd/mm/aaaa',
                                  localDateFrom,
                                  () async {
                                    final picked = await showDatePicker(
                                      context: ctx,
                                      firstDate: DateTime(2020),
                                      lastDate: localDateTo ?? DateTime.now(),
                                      initialDate:
                                          localDateFrom ?? DateTime.now(),
                                      locale: const Locale('es', 'CO'),
                                    );
                                    if (picked != null) {
                                      setDlgState(() => localDateFrom = picked);
                                    }
                                  },
                                  () => setDlgState(() => localDateFrom = null),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Hasta',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textDisabled)),
                                const SizedBox(height: 4),
                                dateRow(
                                  'dd/mm/aaaa',
                                  localDateTo,
                                  () async {
                                    final picked = await showDatePicker(
                                      context: ctx,
                                      firstDate:
                                          localDateFrom ?? DateTime(2020),
                                      lastDate: DateTime.now(),
                                      initialDate:
                                          localDateTo ?? DateTime.now(),
                                      locale: const Locale('es', 'CO'),
                                    );
                                    if (picked != null) {
                                      setDlgState(() => localDateTo = picked);
                                    }
                                  },
                                  () => setDlgState(() => localDateTo = null),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  onPressed: () {
                    setState(() {
                      selectedGroup = null;
                      selectedRotation = null;
                      selectedStagnant = null;
                      selectedHighRotation = null;
                      selectedDateFrom = null;
                      selectedDateTo = null;
                      searchQuery = null;
                    });
                    Navigator.of(dialogCtx).pop();
                    _loadAnalysisData();
                  },
                  child: const Text('Limpiar'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      selectedGroup = localGroup;
                      selectedRotation = localRotation;
                      selectedStagnant = localStagnant;
                      selectedHighRotation = localHighRotation;
                      selectedDateFrom = localDateFrom;
                      selectedDateTo = localDateTo;
                      searchQuery = localSearch;
                    });
                    Navigator.of(dialogCtx).pop();
                    _loadAnalysisData();
                  },
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<String> _getUniqueValues(String field) {
    return AnalisisCatalogoService.obtenerValoresUnicos(analysis, field);
  }

  String _getGroupName(String groupCodeOrName) {
    return AnalisisCatalogoService.normalizarNombreGrupo(groupCodeOrName);
  }

  String _getShortGroupName(String fullName) {
    return AnalisisCatalogoService.nombreGrupoCorto(fullName);
  }

  Color _getRotationColor(String rotation) {
    return AnalisisCatalogoService.colorRotacion(rotation);
  }

  Widget _buildRangeModeInfoBanner() {
    if (selectedDateFrom == null || selectedDateTo == null) {
      return const SizedBox.shrink();
    }
    final fmt = DateFormat('dd/MM/yyyy', 'es_CO');
    final label =
        '${fmt.format(selectedDateFrom!)}  →  ${fmt.format(selectedDateTo!)}';
    final daysCount = selectedDateTo!.difference(selectedDateFrom!).inDays + 1;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.date_range_rounded,
              size: 15, color: AppColors.primaryDark),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Promedio diario del rango $label  ·  $daysCount día${daysCount != 1 ? "s" : ""}'
              '  —  Cantidad y valor representan el saldo promedio diario'
              ' (mismo cálculo que cortes mensuales).',
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w500),
            ),
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
              const Text('Exportar Análisis',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          content: const Text(
            '¿En qué formato desea exportar el análisis de productos?',
          ),
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
                _exportAnalysis('excel');
              },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('PDF'),
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                _exportAnalysis('pdf');
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportAnalysis(String format) async {
    try {
      final response = await _apiService.exportAnalysis(
        format: format,
        warehouse: selectedWarehouse,
        category: selectedGroup,
        rotation: selectedRotation,
        stagnant: selectedStagnant,
        highRotation: selectedHighRotation,
        search: searchQuery,
        dateFrom: selectedDateFrom,
        dateTo: selectedDateTo,
      );

      if (response.statusCode == 200) {
        final Uint8List fileBytes = response.bodyBytes;
        final String timestamp = DateTime.now()
            .toIso8601String()
            .replaceAll(':', '-')
            .replaceAll('.', '-');
        final String extension = format == 'excel' ? 'xlsx' : format;
        final String filename = 'analysis_export_$timestamp.$extension';

        String? path = await FilePicker.platform.saveFile(
          dialogTitle: 'Guardar archivo de análisis',
          fileName: filename,
        );

        if (path != null) {
          final file = File(path);
          await file.writeAsBytes(fileBytes);

          if (!mounted) return;
          context.showSuccessSnackBar('Archivo guardado en: ${file.path}');
        } else {
          if (!mounted) return;
          context.showWarningSnackBar('Guardado cancelado');
        }
      } else {
        throw Exception('Failed to export analysis');
      }
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Error al exportar análisis: ${e.toString()}');
    }
  }
}
