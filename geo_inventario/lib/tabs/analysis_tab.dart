import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geo_inventario/services/api_service.dart';
import 'package:geo_inventario/services/refresh_notifier.dart';
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

  // Filters
  DateTimeRange? selectedDateRange;
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
      selectedDateRange = null;
      searchQuery = null;
      selectedGroup = null;
      selectedRotation = null;
      selectedStagnant = null;
      selectedHighRotation = null;
      selectedWarehouse = null;
    });
    _loadAnalysisData();
  }

  Future<void> _loadAnalysisData() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
    });

    try {
      final data = await _apiService.getAnalysis(
        warehouse: selectedWarehouse,
        category: selectedGroup,
        rotation: selectedRotation,
        stagnant: selectedStagnant,
        highRotation: selectedHighRotation,
        search: searchQuery,
        dateFrom: selectedDateRange?.start,
        dateTo: selectedDateRange?.end,
      );

      if (mounted) {
        setState(() {
          analysis = data;
          filteredAnalysis = data;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
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

    if (filteredAnalysis.isEmpty) {
      return Center(
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
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadAnalysisData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Análisis de Productos',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _buildAnalysisCharts(),
            const SizedBox(height: AppSpacing.lg),
            _buildNegativeStockAlerts(),
            const SizedBox(height: AppSpacing.lg),
            _buildAnalysisTable(),
          ],
        ),
      ),
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

    // Colors for groups
    final List<Color> groupColors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.red,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
    ];

    // Create sorted group data
    final sortedGroupData = groupData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IntrinsicHeight(
         child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Card(
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
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Image.asset(
                            'statics/images/logo_geoflora.png',
                            height: 30,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total productos: $totalProducts | Valor total: ${CurrencyFormatter.format(totalValue)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 500,
                        child: SfCircularChart(
                          margin: EdgeInsets.zero,
                          legend: const Legend(
                            isVisible: true,
                            position: LegendPosition.bottom,
                            textStyle: TextStyle(
                              color: Colors.black87,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                            overflowMode: LegendItemOverflowMode.wrap,
                            iconHeight: 12,
                            iconWidth: 12,
                          ),
                          series: <CircularSeries>[
                            PieSeries<MapEntry<String, double>, String>(
                              dataSource: sortedGroupData,
                              xValueMapper:
                                  (MapEntry<String, double> data, _) =>
                                      data.key,
                              yValueMapper:
                                  (MapEntry<String, double> data, _) =>
                                      data.value,
                              pointColorMapper:
                                  (MapEntry<String, double> data, int index) =>
                                      groupColors[index % groupColors.length],
                              dataLabelMapper:
                                  (MapEntry<String, double> data, _) {
                                final total =
                                    groupData.values.reduce((a, b) => a + b);
                                final percentage = (data.value / total * 100)
                                    .toStringAsFixed(1);
                                final shortName = _getShortGroupName(data.key);
                                return '$shortName\n$percentage%';
                              },
                              radius: '60%',
                              dataLabelSettings: DataLabelSettings(
                                isVisible: true,
                                textStyle: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                                labelPosition: ChartDataLabelPosition.outside,
                                connectorLineSettings: ConnectorLineSettings(
                                  type: ConnectorType.line,
                                  length: '10%',
                                  color: Colors.grey.shade500,
                                  width: 1.2,
                                ),
                                useSeriesColor: false,
                                color: Colors.white,
                                borderRadius: 4,
                                borderWidth: 1,
                                borderColor: Colors.grey.shade300,
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                labelIntersectAction:
                                    LabelIntersectAction.shift,
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
                      )
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Card(
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
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Image.asset(
                            'statics/images/logo_geoflora.png',
                            height: 30,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total productos: $totalProducts',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 500,
                        child: SfCircularChart(
                          legend: const Legend(
                            isVisible: true,
                            position: LegendPosition.bottom,
                            textStyle: TextStyle(
                              color: Colors.black87,
                              fontSize: 8,
                              fontWeight: FontWeight.w500,
                            ),
                            overflowMode: LegendItemOverflowMode.wrap,
                            iconHeight: 12,
                            iconWidth: 12,
                          ),
                          series: <CircularSeries>[
                            PieSeries<MapEntry<String, int>, String>(
                              dataSource: rotationData.entries.toList(),
                              xValueMapper: (MapEntry<String, int> data, _) =>
                                  data.key,
                              yValueMapper: (MapEntry<String, int> data, _) =>
                                  data.value,
                              pointColorMapper:
                                  (MapEntry<String, int> data, int index) =>
                                      _getRotationColor(data.key),
                              dataLabelMapper: (MapEntry<String, int> data, _) {
                                final total =
                                    rotationData.values.reduce((a, b) => a + b);
                                final percentage = (data.value / total * 100)
                                    .toStringAsFixed(1);
                                return '${data.key}\n${data.value} ($percentage%)';
                              },
                              dataLabelSettings: DataLabelSettings(
                                isVisible: true,
                                textStyle: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                                labelPosition: ChartDataLabelPosition.outside,
                                useSeriesColor: false,
                                color: Colors.white,
                                borderRadius: 6,
                                borderWidth: 1,
                                borderColor: Colors.grey.shade300,
                                margin: const EdgeInsets.all(3),
                                labelIntersectAction:
                                    LabelIntersectAction.shift,
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
              ),
            ),
          ],
        ),
       ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Valor Total por Grupo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 380,
                  child: SfCartesianChart(
                    primaryXAxis: const CategoryAxis(
                      labelStyle: TextStyle(
                        color: Colors.black87,
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                      axisLine: AxisLine(width: 1, color: Colors.grey),
                      majorTickLines: MajorTickLines(size: 0),
                      majorGridLines: MajorGridLines(width: 0),
                      labelRotation: 20,
                    ),
                    primaryYAxis: NumericAxis(
                      numberFormat: NumberFormat.compactCurrency(
                        locale: 'es_CO',
                        symbol: '\$',
                      ),
                      labelStyle: const TextStyle(
                        color: Colors.black87,
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                      ),
                      axisLine: const AxisLine(width: 1, color: Colors.grey),
                      majorTickLines: const MajorTickLines(size: 0),
                      majorGridLines: MajorGridLines(
                        width: 0.5,
                        color: Colors.grey.shade200,
                        dashArray: const [5, 5],
                      ),
                      title: const AxisTitle(
                        text: 'Valor (\$)',
                        textStyle: TextStyle(
                          color: Colors.black87,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    plotAreaBorderWidth: 0,
                    legend: const Legend(isVisible: false),
                    tooltipBehavior: TooltipBehavior(
                      enable: true,
                      header: '',
                      format: 'point.x\nTotal: \$point.y',
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                      color: Colors.black87,
                      borderColor: Colors.grey,
                      borderWidth: 1,
                    ),
                    series: <CartesianSeries>[
                      ColumnSeries<MapEntry<String, double>, String>(
                        dataSource: sortedGroupData,
                        xValueMapper: (MapEntry<String, double> data, _) =>
                            _getShortGroupName(data.key),
                        yValueMapper: (MapEntry<String, double> data, _) =>
                            data.value,
                        pointColorMapper:
                            (MapEntry<String, double> data, int index) =>
                                groupColors[index % groupColors.length],
                        dataLabelSettings: DataLabelSettings(
                          isVisible: true,
                          builder: (dynamic dataPoint,
                              dynamic point,
                              dynamic series,
                              int pointIndex,
                              int seriesIndex) {
                            final entry =
                                dataPoint as MapEntry<String, double>;
                            final formatted =
                                CurrencyFormatter.format(entry.value);
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: Colors.grey.shade300, width: 1),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Text(
                                formatted,
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          },
                          labelAlignment: ChartDataLabelAlignment.top,
                          useSeriesColor: false,
                        ),
                        width: 0.65,
                        spacing: 0.1,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(5),
                          topRight: Radius.circular(5),
                        ),
                        animationDuration: 1500,
                        enableTooltip: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
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

  Widget _buildAnalysisTable() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Análisis de Productos',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _showExportDialog,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Exportar'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.filter_list),
                      onPressed: showFiltersDialog,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
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
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            DateTimeRange? selectedDateRange = this.selectedDateRange;
            String dateRangeText = 'Seleccionar rango de fechas (opcional)';

            if (selectedDateRange != null) {
              final dateFormat = DateFormat('dd/MM/yyyy');
              final startDate = dateFormat.format(selectedDateRange.start);
              final endDate = dateFormat.format(selectedDateRange.end);
              dateRangeText = '$startDate - $endDate';
            }

            final groups =
                {'Todos', ..._getUniqueValues('grupo')}.toList();

            return AlertDialog(
              title: const Text('Filtros - Análisis de Productos'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedGroup == null ||
                              !groups.contains(selectedGroup)
                          ? 'Todos'
                          : selectedGroup,
                      decoration: const InputDecoration(labelText: 'Grupo'),
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
                    DropdownButtonFormField<String>(
                      initialValue: (selectedRotation != null &&
                              selectedRotation!.isNotEmpty)
                          ? selectedRotation
                          : 'Todos',
                      decoration: const InputDecoration(labelText: 'Rotación'),
                      items: ['Todos', 'Activo', 'Estancado', 'Obsoleto']
                          .map((value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() =>
                            selectedRotation = value == 'Todos' ? null : value);
                      },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: (selectedStagnant != null &&
                              selectedStagnant!.isNotEmpty)
                          ? selectedStagnant
                          : 'Todos',
                      decoration: const InputDecoration(labelText: 'Estancado'),
                      items: ['Todos', 'Sí', 'No'].map((value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() =>
                            selectedStagnant = value == 'Todos' ? null : value);
                      },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: (selectedHighRotation != null &&
                              selectedHighRotation!.isNotEmpty)
                          ? selectedHighRotation
                          : 'Todos',
                      decoration:
                          const InputDecoration(labelText: 'Alta Rotación'),
                      items: ['Todos', 'Sí', 'No'].map((value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => selectedHighRotation =
                            value == 'Todos' ? null : value);
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
                      selectedGroup = null;
                      selectedRotation = null;
                      selectedStagnant = null;
                      selectedHighRotation = null;
                      selectedDateRange = null;
                      searchQuery = null;
                    });
                    Navigator.of(context).pop();
                    _loadAnalysisData();
                  },
                  child: const Text('Limpiar'),
                ),
                TextButton(
                  onPressed: () {
                    _loadAnalysisData();
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
    var values = analysis
        .map((item) => item[field]?.toString() ?? '')
        .where((value) => value.isNotEmpty);

    if (field == 'grupo') {
      values = values.map(_getGroupName);
    }

    return values.toSet().toList()..sort();
  }

  String _getGroupName(String groupCodeOrName) {
    const knownGroups = <String>{
      'AGROQUIMICOS-FERTILIZANTES Y ABONOS',
      'DOTACION Y SEGURIDAD',
      'MANTENIMIENTO',
      'MATERIAL DE EMPAQUE',
      'PAPELERIA Y ASEO'
    };
    if (knownGroups.contains(groupCodeOrName)) {
      return groupCodeOrName;
    }

    switch (groupCodeOrName) {
      case '1':
        return 'AGROQUIMICOS-FERTILIZZANTES Y ABONOS';
      case '2':
        return 'DOTACION Y SEGURIDAD';
      case '3':
        return 'MANTENIMIENTO';
      case '4':
        return 'MATERIAL DE EMPAQUE';
      case '5':
        return 'PAPELERIA Y ASEO';
      default:
        if (groupCodeOrName.isNotEmpty) {
          return groupCodeOrName;
        }
        return 'SIN CATEGORÍA';
    }
  }

  String _getShortGroupName(String fullName) {
    switch (fullName) {
      case 'AGROQUIMICOS-FERTILIZANTES Y ABONOS':
        return 'AGROQUIMICOS';
      case 'DOTACION Y SEGURIDAD':
        return 'DOTACION';
      case 'MANTENIMIENTO':
        return 'MANTENIMIENTO';
      case 'MATERIAL DE EMPAQUE':
        return 'EMPAQUE';
      case 'PAPELERIA Y ASEO':
        return 'PAPELERIA';
      default:
        return fullName;
    }
  }

  Color _getRotationColor(String rotation) {
    switch (rotation) {
      case 'Activo':
        return Colors.green.shade400;
      case 'Estancado':
        return Colors.orange.shade400;
      case 'Obsoleto':
        return Colors.red.shade400;
      default:
        return Colors.grey.shade400;
    }
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Exportar Análisis'),
          content: const Text('¿Desea exportar el análisis de productos?'),
          actions: [
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Excel'),
              onPressed: () {
                _exportAnalysis('excel');
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('PDF'),
              onPressed: () {
                _exportAnalysis('pdf');
                Navigator.of(context).pop();
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
        dateFrom: selectedDateRange?.start,
        dateTo: selectedDateRange?.end,
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Archivo guardado en: ${file.path}'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Guardado cancelado'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        throw Exception('Failed to export analysis');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al exportar análisis: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
