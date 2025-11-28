import 'dart:convert';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geo_inventario/services/api_service.dart';
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
      return const Center(child: CircularProgressIndicator());
    }

    if (filteredAnalysis.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics_sharp, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 20),
            const Text(
              'No hay datos de análisis disponibles',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Carga archivos de inventario para ver el análisis',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAnalysisData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Análisis de Productos',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            // Charts
            _buildAnalysisCharts(),
            const SizedBox(height: 24),
            // Table
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                        height: 400,
                        child: SfCircularChart(
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
                                final valueFormatted =
                                    data.value.toStringAsFixed(0);
                                final shortName = _getShortGroupName(data.key);
                                return '$shortName\n$valueFormatted (${percentage}%)';
                              },
                              dataLabelSettings: DataLabelSettings(
                                isVisible: true,
                                textStyle: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                                labelPosition: ChartDataLabelPosition.outside,
                                connectorLineSettings: ConnectorLineSettings(
                                  type: ConnectorType.curve,
                                  length: '25%',
                                  color: Colors.grey.shade600,
                                  width: 1.5,
                                ),
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
                              explodeOffset: '3%',
                              explodeAll: false,
                              animationDuration: 1500,
                              enableTooltip: true,
                              strokeColor: Colors.white,
                              strokeWidth: 2,
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
                        height: 400,
                        child: SfCircularChart(
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
                                return '${data.key}\n${data.value} (${percentage}%)';
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
                              explodeOffset: '3%',
                              explodeAll: false,
                              animationDuration: 1500,
                              enableTooltip: true,
                              strokeColor: Colors.white,
                              strokeWidth: 2,
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
                  height: 300,
                  child: SfCartesianChart(
                    primaryXAxis: const CategoryAxis(
                      labelStyle: TextStyle(
                        color: Colors.black87,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      axisLine: AxisLine(width: 1, color: Colors.grey),
                      majorTickLines: MajorTickLines(size: 0),
                      majorGridLines: MajorGridLines(width: 0),
                      labelRotation: 45,
                    ),
                    primaryYAxis: NumericAxis(
                      numberFormat: NumberFormat.currency(
                        locale: 'es_CO',
                        symbol: '\$',
                      ),
                      labelStyle: const TextStyle(
                        color: Colors.black87,
                        fontSize: 11,
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
                      format: 'point.x: point.y',
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
                        dataSource: groupData.entries.toList(),
                        xValueMapper: (MapEntry<String, double> data, _) =>
                            _getShortGroupName(data.key),
                        yValueMapper: (MapEntry<String, double> data, _) =>
                            data.value,
                        pointColorMapper:
                            (MapEntry<String, double> data, int index) =>
                                groupColors[index % groupColors.length],
                        dataLabelSettings: const DataLabelSettings(
                          isVisible: true,
                          textStyle: TextStyle(
                            color: Colors.black87,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                          labelAlignment: ChartDataLabelAlignment.top,
                          useSeriesColor: false,
                        ),
                        width: 0.7,
                        spacing: 0.1,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
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
                ['Todos', ..._getUniqueValues('grupo')].toSet().toList();

            return AlertDialog(
              title: const Text('Filtros - Análisis de Productos'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedGroup == null ||
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
                        setState(() => this.selectedGroup =
                            value == 'Todos' ? null : value);
                      },
                    ),
                    DropdownButtonFormField<String>(
                      value: (selectedRotation != null &&
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
                      value: (selectedStagnant != null &&
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
                      value: (selectedHighRotation != null &&
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
    final localContext = context;
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
        final String? path = await FileSaver.instance.saveAs(
            name:
                'analysis_export_${DateTime.now().toIso8601String()}.$format',
            bytes: fileBytes,
            ext: format,
            mimeType:
                format == 'excel' ? MimeType.microsoftExcel : MimeType.pdf);

        if (mounted) {
          ScaffoldMessenger.of(localContext).showSnackBar(
            SnackBar(
              content: Text('Análisis exportado a $path'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Failed to export analysis');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(localContext).showSnackBar(
          SnackBar(
            content: Text('Error al exportar análisis: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
