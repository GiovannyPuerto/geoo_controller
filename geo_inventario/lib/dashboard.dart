import 'dart:convert';
import 'dart:io' as io show File;

import 'package:data_table_2/data_table_2.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:geo_inventario/platform_file_picker.dart';
import 'package:geo_inventario/utils/currency_formatter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:universal_html/html.dart' as html;

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> analysis = [];
  List<Map<String, dynamic>> filteredAnalysis = [];
  List<Map<String, dynamic>> movements = [];
  List<Map<String, dynamic>> filteredMovements = [];
  Map<String, dynamic>? summary;
  bool isLoading = true;
  bool hasBaseData = false; // Track if base data has been uploaded
  final int _tabsCount = 3; // Number of tabs

  // Filtros
  String? selectedWarehouse;
  String? selectedGroup;
  String? selectedRotation;
  String? selectedStagnant;
  String? selectedHighRotation;
  DateTimeRange? selectedDateRange;
  String? searchQuery; // Para búsqueda por código o descripción

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabsCount, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _loadData();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      // Handle tab change if needed
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _uploadBaseFile(PlatformFile platformFile) async {
    if (!mounted) return;

    // Show loading spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Cargando archivo base...'),
            ],
          ),
        );
      },
    );

    setState(() {
      isLoading = true;
    });

    try {
      print('[_uploadBaseFile] Preparing to upload base file.');
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://127.0.0.1:8000/api/inventory/upload-base/'),
      );

      request.files.add(await createMultipartFile('base_file', platformFile));

      print('[_uploadBaseFile] Sending request...');
      var response = await request.send();
      var responseData = await response.stream.bytesToString();

      print('[_uploadBaseFile] Raw response: $responseData');

      if (response.statusCode == 200) {
        try {
          var jsonResponse = json.decode(responseData);
          print(
            '[_uploadBaseFile] Response status: ${response.statusCode}, body: $jsonResponse',
          );

          if (jsonResponse['ok']) {
            if (!mounted) return;
            // Close loading dialog
            Navigator.of(context).pop();
            setState(() {
              hasBaseData = true; // Mark that base data has been uploaded
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  jsonResponse['message'] ?? 'Archivo cargado exitosamente',
                ),
                backgroundColor: Colors.green,
              ),
            );
            await _loadData();
          } else {
            if (!mounted) return;
            // Close loading dialog
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  jsonResponse['error'] ?? 'Error al cargar el archivo',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        } catch (jsonError) {
          print('[_uploadBaseFile] JSON decode error: $jsonError');
          if (!mounted) return;
          // Close loading dialog
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error al procesar respuesta del servidor: $jsonError',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        print('[_uploadBaseFile] HTTP error: ${response.statusCode}');
        if (!mounted) return;
        // Close loading dialog
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error HTTP ${response.statusCode}: $responseData'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('[_uploadBaseFile] Error during upload: $e');
      if (!mounted) return;
      // Close loading dialog
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error de conexión: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadFile() async {
    try {
      print('[_pickAndUploadFile] Attempting to pick files...');
      FilePickerResult? result = await getPlatformFilePicker().pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result != null) {
        PlatformFile platformFile = result.files.single;
        print('[_pickAndUploadFile] File picked: ${platformFile.name}');
        await _uploadBaseFile(platformFile);
      } else {
        print(
          '[_pickAndUploadFile] File picking cancelled or no file selected.',
        );
      }
    } catch (e) {
      print('[_pickAndUploadFile] Error during file picking: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar el archivo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
    });

    try {
      // Load summary data
      final summaryResponse = await http.get(
        Uri.parse('http://127.0.0.1:8000/api/inventory/summary/'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      // Load analysis data
      final analysisResponse = await http.get(
        Uri.parse('http://127.0.0.1:8000/api/inventory/analysis/'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      // Load movements data
      final movementsResponse = await http.get(
        Uri.parse('http://127.0.0.1:8000/api/inventory/records/'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      print('Summary Response Status: ${summaryResponse.statusCode}');
      print('Analysis Response Status: ${analysisResponse.statusCode}');
      print('Analysis Response Body Length: ${analysisResponse.body.length}');
      print('Movements Response Status: ${movementsResponse.statusCode}');
      print('Movements Response Body Length: ${movementsResponse.body.length}');

      if (summaryResponse.statusCode == 200 &&
          analysisResponse.statusCode == 200 &&
          movementsResponse.statusCode == 200) {
        final Map<String, dynamic> summaryData = json.decode(
          summaryResponse.body,
        );
        final List<dynamic> analysisData = json.decode(analysisResponse.body);
        final List<dynamic> movementsData = json.decode(movementsResponse.body);

        print('Summary Data: $summaryData');
        print('Analysis Data Count: ${analysisData.length}');
        print('Movements Data Count: ${movementsData.length}');

        if (!mounted) return;
        setState(() {
          summary = summaryData;
          analysis = List<Map<String, dynamic>>.from(analysisData);
          filteredAnalysis = analysis;
          movements = List<Map<String, dynamic>>.from(movementsData);
          filteredMovements = movements;

          // Process and extract unique products
          final productMap = <String, Map<String, dynamic>>{};

          for (var item in analysis) {
            final code = item['codigo']?.toString() ?? '';
            if (!productMap.containsKey(code)) {
              productMap[code] = {
                'code': code,
                'description':
                    item['nombre_producto']?.toString() ?? 'Sin descripción',
                'group': _getGroupName(item['grupo']?.toString() ?? ''),
                'quantity': item['cantidad_saldo_actual'] ?? 0,
                'unitValue': item['costo_unitario'] ?? 0,
                'totalValue': item['valor_saldo_actual'] ?? 0,
                'rotation': item['rotacion'] ?? 'Activo',
                'stagnant': item['estancado'] ?? 'No',
                'highRotation': item['alta_rotacion'] ?? 'No',
              };
            }
          }

          products = productMap.values.toList();
          isLoading = false;
        });

        print(
          'Data loaded successfully. Summary: ${summary != null}, Analysis: ${analysis.length}, Movements: ${movements.length}, Products: ${products.length}',
        );
      } else {
        print(
          'Error responses: Summary ${summaryResponse.statusCode}: ${summaryResponse.body}',
        );
        print(
          'Analysis ${analysisResponse.statusCode}: ${analysisResponse.body}',
        );
        print(
          'Movements ${movementsResponse.statusCode}: ${movementsResponse.body}',
        );
        throw Exception(
          'Error al cargar los datos: ${summaryResponse.statusCode} / ${analysisResponse.statusCode} / ${movementsResponse.statusCode}',
        );
      }
    } catch (e) {
      print('Error loading data: $e');
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar los datos: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getGroupName(String groupCode) {
    switch (groupCode) {
      case '1':
        return 'AGROQUIMICOS-FERTILIZANTES Y ABONOS';
      case '2':
        return 'DOTACION Y SEGURIDAD';
      case '3':
        return 'MANTENIMIENTO';
      case '4':
        return 'MATERIAL DE EMPAQUE';
      case '5':
        return 'PAPELERIA Y ASEO';
      default:
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

  // Removed unused methods since data comes from backend

  // Build the summary tab
  Widget _buildSummaryTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (summary == null || summary!['total_productos'] == 0)
              _buildEmptyState()
            else ...[
              _buildSummaryCards(),
              const SizedBox(height: 20),
              _buildInventoryStatus(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 60),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'statics/images/logo_geoflora.png',
                height: 50,
              ),
              const SizedBox(width: 10),
              SvgPicture.asset(
                'statics/images/Logo_SBTale.svg',
                height: 50,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 20),
          const Text(
            'No hay datos de inventario disponibles',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text(
            'Sube un archivo base para comenzar',
            style: TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _pickAndUploadFile,
            icon: const Icon(Icons.cloud_upload),
            label: const Text('Cargar archivo base'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  // Build summary cards
  Widget _buildSummaryCards() {
    if (summary == null) {
      return const SizedBox.shrink();
    }

    final totalProducts = summary!['total_productos'] ?? 0;
    final totalValue = summary!['valor_total_inventario'] ?? 0.0;

    return Row(
      children: [
        _buildSummaryCard(
          'Productos',
          totalProducts.toString(),
          Icons.inventory_2,
          Colors.blue,
        ),
        const SizedBox(width: 16),
        _buildSummaryCard(
          'Valor Total',
          CurrencyFormatter.format(totalValue),
          Icons.attach_money,
          Colors.green,
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Build inventory status section
  Widget _buildInventoryStatus() {
    if (analysis.isEmpty) {
      return const SizedBox.shrink();
    }

    // Count items by rotation status
    final activeCount = analysis
        .where((item) => (item['rotacion'] ?? 'Activo') == 'Activo')
        .length;
    final stagnantCount = analysis
        .where((item) => (item['rotacion'] ?? 'Activo') == 'Estancado')
        .length;
    final obsoleteCount = analysis
        .where((item) => (item['rotacion'] ?? 'Activo') == 'Obsoleto')
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estado del Inventario',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildStatusRow('Activos', activeCount, Colors.green),
            _buildStatusRow('Estancados', stagnantCount, Colors.orange),
            _buildStatusRow('Obsoletos', obsoleteCount, Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text('$label:'),
          const Spacer(),
          Text(
            count.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // Build analysis charts
  Widget _buildAnalysisCharts() {
    if (filteredAnalysis.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 20),
            const Text(
              'No hay datos de análisis de productos disponibles',
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

    // Preparar datos para gráficos
    final groupData = <String, double>{};
    final rotationData = <String, int>{};

    for (var item in filteredAnalysis) {
      final group = item['grupo']?.toString() ?? 'SIN CATEGORÍA';
      final quantity = (item['cantidad_saldo_actual'] as num?)?.toDouble() ?? 0;
      groupData[group] = (groupData[group] ?? 0) + quantity;

      final rotation = item['rotacion']?.toString() ?? 'Activo';
      rotationData[rotation] = (rotationData[rotation] ?? 0) + 1;
    }

    // Colores para los grupos
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

    // Crear lista ordenada de datos con colores
    final sortedGroupData = groupData.entries.toList()
      ..sort((a, b) =>
          b.value.compareTo(a.value)); // Ordenar por valor descendente

    return Column(
      children: [
        Row(
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
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 350,
                        child: SfCircularChart(
                          legend: const Legend(
                            isVisible: true,
                            position: LegendPosition.bottom,
                            textStyle: TextStyle(
                              color: Colors.black87,
                              fontSize: 11,
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

                                // Use shorter names for chart labels
                                final shortName = _getShortGroupName(data.key);
                                return '$shortName\n$percentage%';
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
                                borderRadius: 4,
                                borderWidth: 1,
                                borderColor: Colors.grey.shade300,
                                margin: const EdgeInsets.all(2),
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
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 250,
                        child: SfCircularChart(
                          legend: const Legend(
                            isVisible: true,
                            position: LegendPosition.bottom,
                            textStyle: TextStyle(
                              color: Colors.black87,
                              fontSize: 11,
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
                                  (MapEntry<String, int> data, int index) {
                                // Custom colors for rotation status
                                switch (data.key) {
                                  case 'Activo':
                                    return Colors.green.shade400;
                                  case 'Estancado':
                                    return Colors.orange.shade400;
                                  case 'Obsoleto':
                                    return Colors.red.shade400;
                                  default:
                                    return Colors.grey.shade400;
                                }
                              },
                              dataLabelMapper:
                                  (MapEntry<String, int> data, _) =>
                                      '${data.key}\n${data.value}',
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
                                  length: '20%',
                                  color: Colors.grey.shade600,
                                  width: 1.5,
                                ),
                                useSeriesColor: false,
                                color: Colors.white,
                                borderRadius: 4,
                                borderWidth: 1,
                                borderColor: Colors.grey.shade300,
                                margin: const EdgeInsets.all(2),
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
                    legend: const Legend(
                      isVisible: false,
                    ),
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

  // Build the movements tab
  Widget _buildMovementsTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Historial de Movimientos',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Vista detallada de todas las entradas y salidas de inventario',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Gráfica de movimientos por mes
            _buildMovementsChart(),
            const SizedBox(height: 24),

            // Tabla de movimientos
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Todos los Movimientos',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            // Implementar exportación
                          },
                          icon: const Icon(Icons.download),
                          label: const Text('Exportar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (filteredMovements.isEmpty)
                      const SizedBox(
                        height: 400,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No hay movimientos para mostrar',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Carga un archivo de actualización para ver el historial de movimientos',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 800,
                          maxWidth: double.infinity,
                          minHeight: 400,
                          maxHeight: 600,
                        ),
                        child: DataTable2(
                          columnSpacing: 12,
                          horizontalMargin: 12,
                          minWidth: 800,
                          scrollController: ScrollController(),
                          isHorizontalScrollBarVisible: true,
                          columns: const [
                            DataColumn2(
                              label: Text('Fecha'),
                              size: ColumnSize.S,
                            ),
                            DataColumn2(
                              label: Text('Producto'),
                              size: ColumnSize.M,
                            ),
                            DataColumn2(
                              label: Text('Almacén'),
                              size: ColumnSize.S,
                            ),
                            DataColumn2(
                              label: Text('Tipo Doc.'),
                              size: ColumnSize.S,
                            ),
                            DataColumn2(
                              label: Text('Documento'),
                              size: ColumnSize.S,
                            ),
                            DataColumn2(
                              label: Text('Cantidad'),
                              size: ColumnSize.S,
                              numeric: true,
                            ),
                            DataColumn2(
                              label: Text('Costo Unit.'),
                              size: ColumnSize.S,
                              numeric: true,
                            ),
                            DataColumn2(
                              label: Text('Total'),
                              size: ColumnSize.S,
                              numeric: true,
                            ),
                          ],
                          rows: filteredMovements.map((item) {
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
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build movements chart
  Widget _buildMovementsChart() {
    if (filteredMovements.isEmpty) {
      return const SizedBox.shrink();
    }

    // Group by month
    final monthlyData = <String, Map<String, double>>{};
    for (var item in filteredMovements) {
      final date = DateTime.parse(item['date']);
      final monthKey = DateFormat('yyyy-MM').format(date);
      final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
      final total = (item['total'] as num?)?.toDouble() ?? 0;

      if (!monthlyData.containsKey(monthKey)) {
        monthlyData[monthKey] = {
          'entradas': 0,
          'salidas': 0,
          'entradas_valor': 0,
          'salidas_valor': 0,
        };
      }

      if (quantity > 0) {
        monthlyData[monthKey]!['entradas'] =
            (monthlyData[monthKey]!['entradas'] ?? 0) + quantity;
        monthlyData[monthKey]!['entradas_valor'] =
            (monthlyData[monthKey]!['entradas_valor'] ?? 0) + total;
      } else {
        monthlyData[monthKey]!['salidas'] =
            (monthlyData[monthKey]!['salidas'] ?? 0) + quantity.abs();
        monthlyData[monthKey]!['salidas_valor'] =
            (monthlyData[monthKey]!['salidas_valor'] ?? 0) + total.abs();
      }
    }

    final sortedMonths = monthlyData.keys.toList()..sort();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Movimientos por Mes',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: SfCartesianChart(
                primaryXAxis: const CategoryAxis(
                  labelStyle: TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                  ),
                ),
                primaryYAxis: NumericAxis(
                  numberFormat: NumberFormat.currency(
                    locale: 'es_CO',
                    symbol: '\$',
                  ),
                  labelStyle: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                  ),
                  title: const AxisTitle(text: 'Valor (\$)'),
                ),
                legend: const Legend(
                  isVisible: true,
                  textStyle: TextStyle(color: Colors.black, fontSize: 12),
                ),
                series: <CartesianSeries>[
                  ColumnSeries<MapEntry<String, Map<String, double>>, String>(
                    dataSource: sortedMonths
                        .map((month) => MapEntry(month, monthlyData[month]!))
                        .toList(),
                    xValueMapper:
                        (MapEntry<String, Map<String, double>> data, _) =>
                            DateFormat(
                      'MMM yyyy',
                    ).format(DateTime.parse('${data.key}-01')),
                    yValueMapper:
                        (MapEntry<String, Map<String, double>> data, _) =>
                            data.value['entradas_valor'] ?? 0,
                    name: 'Entradas',
                    color: Colors.green,
                    dataLabelSettings: const DataLabelSettings(
                      isVisible: true,
                      textStyle: TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ColumnSeries<MapEntry<String, Map<String, double>>, String>(
                    dataSource: sortedMonths
                        .map((month) => MapEntry(month, monthlyData[month]!))
                        .toList(),
                    xValueMapper:
                        (MapEntry<String, Map<String, double>> data, _) =>
                            DateFormat(
                      'MMM yyyy',
                    ).format(DateTime.parse('${data.key}-01')),
                    yValueMapper:
                        (MapEntry<String, Map<String, double>> data, _) =>
                            data.value['salidas_valor'] ?? 0,
                    name: 'Salidas',
                    color: Colors.red,
                    dataLabelSettings: const DataLabelSettings(
                      isVisible: true,
                      textStyle: TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Summary table
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Mes')),
                  DataColumn(label: Text('Entradas (Cant.)')),
                  DataColumn(label: Text('Entradas (\$)')),
                  DataColumn(label: Text('Salidas (Cant.)')),
                  DataColumn(label: Text('Salidas (\$)')),
                ],
                rows: sortedMonths.map((month) {
                  final data = monthlyData[month]!;
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          DateFormat(
                            'MMM yyyy',
                          ).format(DateTime.parse('$month-01')),
                        ),
                      ),
                      DataCell(
                        Text((data['entradas'] ?? 0).toStringAsFixed(0)),
                      ),
                      DataCell(
                        Text(
                          CurrencyFormatter.format(data['entradas_valor'] ?? 0),
                        ),
                      ),
                      DataCell(Text((data['salidas'] ?? 0).toStringAsFixed(0))),
                      DataCell(
                        Text(
                          CurrencyFormatter.format(data['salidas_valor'] ?? 0),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'statics/images/logo_geoflora.png',
              height: 40,
            ),
            const SizedBox(width: 10),
            SvgPicture.asset(
              'statics/images/Logo_SBTale.svg',
              height: 40,
            ),
            const SizedBox(width: 10),
            const Text('Dashboard de Inventario'),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFiltersDialog,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _showExportDialog,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.cloud_upload),
            onSelected: (value) {
              if (value == 'base') {
                _pickAndUploadFile();
              } else if (value == 'update') {
                _uploadUpdateFile();
              }
            },
            itemBuilder: (BuildContext context) => [
              if (!hasBaseData)
                const PopupMenuItem(
                  value: 'base',
                  child: Text('Cargar archivo base'),
                ),
              const PopupMenuItem(
                value: 'update',
                child: Text('Cargar archivo de actualización'),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Resumen General'),
            Tab(text: 'Análisis de Productos'),
            Tab(text: 'Movimientos'),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: <Widget>[
          // Resumen General Tab
          _buildSummaryTab(),

          // Análisis de Productos Tab
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : filteredAnalysis.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.analytics_outlined,
                            size: 80,
                            color: Colors.grey[400],
                          ),
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
                    )
                  : RefreshIndicator(
                      onRefresh: _loadData,
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
                            // Gráficas
                            _buildAnalysisCharts(),
                            const SizedBox(height: 24),
                            // Tabla
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: 1000,
                                maxWidth: double.infinity,
                                minHeight: 400,
                                maxHeight: 800,
                              ),
                              child: Card(
                                child: DataTable2(
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
                                  rows: filteredAnalysis.map((item) {
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(item['codigo'] ?? '')),
                                        DataCell(
                                          Text(item['nombre_producto'] ?? ''),
                                        ),
                                        DataCell(Text(item['grupo'] ?? '')),
                                        DataCell(
                                          Text(
                                            item['cantidad_saldo_actual']
                                                    ?.toString() ??
                                                '0',
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
                                            Text(item['estancado'] ?? 'No')),
                                        DataCell(
                                          Text(item['rotacion'] ?? 'Activo'),
                                        ),
                                        DataCell(
                                          Text(item['alta_rotacion'] ?? 'No'),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

          // Movements Tab
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : filteredMovements.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history,
                              size: 80, color: Colors.grey[400]),
                          const SizedBox(height: 20),
                          const Text(
                            'No hay movimientos disponibles',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Carga un archivo de actualización para ver el historial de movimientos',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : _buildMovementsTab(),
        ],
      ),
    );
  }

  void _applyFilters() {
    setState(() {
      filteredAnalysis = analysis.where((item) {
        // Filtro por búsqueda (código o descripción)
        if (searchQuery != null && searchQuery!.isNotEmpty) {
          final code = item['codigo']?.toString().toLowerCase() ?? '';
          final description =
              item['nombre_producto']?.toString().toLowerCase() ?? '';
          final query = searchQuery!.toLowerCase();
          if (!code.contains(query) && !description.contains(query)) {
            return false;
          }
        }

        // Filtro por almacén
        if (selectedWarehouse != null && selectedWarehouse!.isNotEmpty) {
          if (item['almacen'] != selectedWarehouse) return false;
        }

        // Filtro por grupo
        if (selectedGroup != null && selectedGroup!.isNotEmpty) {
          if (item['grupo'] != selectedGroup) return false;
        }

        // Filtro por rotación
        if (selectedRotation != null && selectedRotation!.isNotEmpty) {
          if (item['rotacion'] != selectedRotation) return false;
        }

        // Filtro por estancado
        if (selectedStagnant != null && selectedStagnant!.isNotEmpty) {
          if (item['estancado'] != selectedStagnant) return false;
        }

        // Filtro por alta rotación
        if (selectedHighRotation != null && selectedHighRotation!.isNotEmpty) {
          if (item['alta_rotacion'] != selectedHighRotation) return false;
        }

        return true;
      }).toList();

      filteredMovements = movements.where((item) {
        // Filtro por almacén
        if (selectedWarehouse != null && selectedWarehouse!.isNotEmpty) {
          if (item['warehouse'] != selectedWarehouse) return false;
        }

        // Filtro por grupo (usando category)
        if (selectedGroup != null && selectedGroup!.isNotEmpty) {
          if (item['category'] != selectedGroup) return false;
        }

        // Filtro por fecha
        if (selectedDateRange != null) {
          final date = DateTime.parse(item['date']);
          if (date.isBefore(selectedDateRange!.start) ||
              date.isAfter(selectedDateRange!.end)) {
            return false;
          }
        }

        return true;
      }).toList();
    });

    // Recargar datos con filtros aplicados desde el backend
    _loadDataWithFilters();
  }

  Future<void> _loadDataWithFilters() async {
    if (!mounted) return;

    try {
      // Construir parámetros de consulta para análisis
      final analysisParams = <String, String>{};
      if (selectedWarehouse != null && selectedWarehouse!.isNotEmpty) {
        analysisParams['warehouse'] = selectedWarehouse!;
      }
      if (selectedGroup != null && selectedGroup!.isNotEmpty) {
        analysisParams['category'] = selectedGroup!;
      }
      if (selectedDateRange != null) {
        analysisParams['date_from'] =
            selectedDateRange!.start.toIso8601String().split('T')[0];
        analysisParams['date_to'] =
            selectedDateRange!.end.toIso8601String().split('T')[0];
      }

      // Construir parámetros de consulta para movimientos
      final movementsParams = <String, String>{};
      if (selectedWarehouse != null && selectedWarehouse!.isNotEmpty) {
        movementsParams['warehouse'] = selectedWarehouse!;
      }
      if (selectedGroup != null && selectedGroup!.isNotEmpty) {
        movementsParams['category'] = selectedGroup!;
      }
      if (selectedDateRange != null) {
        movementsParams['date_from'] =
            selectedDateRange!.start.toIso8601String().split('T')[0];
        movementsParams['date_to'] =
            selectedDateRange!.end.toIso8601String().split('T')[0];
      }

      final analysisUri = Uri.parse(
        'http://127.0.0.1:8000/api/inventory/analysis/',
      ).replace(queryParameters: analysisParams);
      final analysisResponse = await http.get(
        analysisUri,
        headers: {'Content-Type': 'application/json'},
      );

      final movementsUri = Uri.parse(
        'http://127.0.0.1:8000/api/inventory/records/',
      ).replace(queryParameters: movementsParams);
      final movementsResponse = await http.get(
        movementsUri,
        headers: {'Content-Type': 'application/json'},
      );

      if (analysisResponse.statusCode == 200 &&
          movementsResponse.statusCode == 200) {
        final List<dynamic> analysisData = json.decode(analysisResponse.body);
        final List<dynamic> movementsData = json.decode(movementsResponse.body);

        if (!mounted) return;
        setState(() {
          analysis = List<Map<String, dynamic>>.from(analysisData);
          filteredAnalysis = analysis;
          movements = List<Map<String, dynamic>>.from(movementsData);
          filteredMovements = movements;

          // Process and extract unique products
          final productMap = <String, Map<String, dynamic>>{};

          for (var item in analysis) {
            final code = item['codigo']?.toString() ?? '';
            if (!productMap.containsKey(code)) {
              productMap[code] = {
                'code': code,
                'description':
                    item['nombre_producto']?.toString() ?? 'Sin descripción',
                'group': _getGroupName(item['grupo']?.toString() ?? ''),
                'quantity': item['cantidad'] ?? 0,
                'unitValue': item['costo_unitario'] ?? 0,
                'totalValue': item['valor_total'] ?? 0,
                'rotation': item['rotacion'] ?? 'Activo',
                'stagnant': item['estancado'] ?? 'No',
                'highRotation': item['alta_rotacion'] ?? 'No',
              };
            }
          }

          products = productMap.values.toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al aplicar filtros: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _clearFilters() {
    setState(() {
      selectedWarehouse = null;
      selectedGroup = null;
      selectedRotation = null;
      selectedStagnant = null;
      selectedHighRotation = null;
      selectedDateRange = null;
      searchQuery = null;
      filteredAnalysis = analysis;
      filteredMovements = movements;
    });
  }

  void _showFiltersDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Filtros'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Filtro por almacén
                    DropdownButtonFormField<String>(
                      value: selectedWarehouse,
                      decoration: const InputDecoration(labelText: 'Almacén'),
                      items: _getUniqueValues('almacen').map((value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => selectedWarehouse = value);
                      },
                    ),

                    // Filtro por grupo
                    DropdownButtonFormField<String>(
                      value: selectedGroup,
                      decoration: const InputDecoration(labelText: 'Grupo'),
                      items: _getUniqueValues('grupo').map((value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => selectedGroup = value);
                      },
                    ),

                    // Filtro por rotación
                    DropdownButtonFormField<String>(
                      value: selectedRotation,
                      decoration: const InputDecoration(labelText: 'Rotación'),
                      items: ['Activo', 'Estancado', 'Obsoleto'].map((value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => selectedRotation = value);
                      },
                    ),

                    // Filtro por estancado
                    DropdownButtonFormField<String>(
                      value: selectedStagnant,
                      decoration: const InputDecoration(labelText: 'Estancado'),
                      items: ['Sí', 'No'].map((value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => selectedStagnant = value);
                      },
                    ),

                    // Filtro por alta rotación
                    DropdownButtonFormField<String>(
                      value: selectedHighRotation,
                      decoration: const InputDecoration(
                        labelText: 'Alta Rotación',
                      ),
                      items: ['Sí', 'No'].map((value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => selectedHighRotation = value);
                      },
                    ),

                    // Campo de búsqueda por código o descripción
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: searchQuery,
                      decoration: const InputDecoration(
                        labelText: 'Buscar por código o descripción',
                        hintText: 'Ingrese código o descripción del producto',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        setState(() => searchQuery = value);
                      },
                    ),

                    // Filtro por rango de fechas
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
                          setState(() => selectedDateRange = picked);
                        }
                      },
                      child: Text(
                        selectedDateRange == null
                            ? 'Seleccionar rango de fechas'
                            : '${DateFormat('dd/MM/yyyy').format(selectedDateRange!.start)} - ${DateFormat('dd/MM/yyyy').format(selectedDateRange!.end)}',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _clearFilters();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Limpiar'),
                ),
                TextButton(
                  onPressed: () {
                    _applyFilters();
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
    return analysis
        .map((item) => item[field]?.toString() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Exportar Datos'),
          content: const Text('¿Qué formato desea usar para exportar?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _exportToExcel();
              },
              child: const Text('Excel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _exportToPdf();
              },
              child: const Text('PDF'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportToExcel() async {
    try {
      final excel = Excel.createExcel()
        ..rename('Sheet1', 'Análisis de Productos');
      final sheet = excel['Análisis de Productos'];

      // Headers
      List<String> headers = [
        'Código',
        'Nombre Producto',
        'Grupo',
        'Saldo Actual',
        'Valor Saldo',
        'Costo Unitario',
        'Estancado',
        'Rotación',
        'Alta Rotación',
      ];
      sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

      // Data
      for (var item in filteredAnalysis) {
        List<CellValue?> rowData = [
          TextCellValue(item['codigo'] ?? ''),
          TextCellValue(item['nombre_producto'] ?? ''),
          TextCellValue(item['grupo'] ?? ''),
          TextCellValue(item['cantidad_saldo_actual']?.toString() ?? '0'),
          TextCellValue(
            (item['valor_saldo_actual'] as num?)?.toStringAsFixed(2) ?? '0.00',
          ),
          TextCellValue(
            (item['costo_unitario'] as num?)?.toStringAsFixed(2) ?? '0.00',
          ),
          TextCellValue(item['estancado'] ?? 'No'),
          TextCellValue(item['rotacion'] ?? 'Activo'),
          TextCellValue(item['alta_rotacion'] ?? 'No'),
        ];
        sheet.appendRow(rowData);
      }

      final bytes = excel.encode();
      if (kIsWeb) {
        // Web implementation using dart:html
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', 'analisis_productos.xlsx')
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        // Mobile/Desktop implementation using path_provider and share_plus
        final directory = await getApplicationDocumentsDirectory();
        final file = io.File('${directory.path}/analisis_productos.xlsx');
        await file.writeAsBytes(bytes!);
        await Share.shareXFiles([
          XFile(file.path),
        ], text: 'Análisis de Productos');
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Archivo Excel descargado')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al exportar: $e')));
    }
  }

  Future<void> _exportToPdf() async {
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text(
                'Análisis de Productos',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              headers: [
                'Código',
                'Nombre Producto',
                'Grupo',
                'Saldo Actual',
                'Valor Saldo',
                'Costo Unit.',
                'Estancado',
                'Rotación',
                'Alta Rotación',
              ],
              data: filteredAnalysis
                  .map(
                    (item) => [
                      item['codigo'] ?? '',
                      item['nombre_producto'] ?? '',
                      item['grupo'] ?? '',
                      item['cantidad_saldo_actual']?.toString() ?? '0',
                      (item['valor_saldo_actual'] as double?)?.toStringAsFixed(
                            2,
                          ) ??
                          '0.00',
                      (item['costo_unitario'] as double?)?.toStringAsFixed(2) ??
                          '0.00',
                      item['estancado'] ?? 'No',
                      item['rotacion'] ?? 'Activo',
                      item['alta_rotacion'] ?? 'No',
                    ],
                  )
                  .toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF generado correctamente')),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al generar PDF: $e')));
    }
  }

  Future<void> _uploadUpdateFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: true, // Allow multiple update files
      );

      if (result == null || result.files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Debe seleccionar al menos un archivo de actualización (.xlsx o .xls).',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final files = result.files;

      // Show loading dialog
      bool? confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Procesando archivo(s) de actualización...'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
                child: const Text('Confirmar'),
              ),
            ],
          );
        },
      );

      if (confirmed == true) {
        var request = http.MultipartRequest(
          'POST',
          Uri.parse('http://127.0.0.1:8000/api/inventory/update/'),
        );

        // Send all update files - backend will handle multiple files and add movements
        for (int i = 0; i < files.length; i++) {
          request.files
              .add(await createMultipartFile('update_files', files[i]));
        }

        print(
            '[_uploadUpdateFile] Sending update request with ${files.length} files...');
        var response = await request.send();
        var responseData = await response.stream.bytesToString();

        print('[_uploadUpdateFile] Raw response: $responseData');

        if (response.statusCode == 200) {
          try {
            var jsonResponse = json.decode(responseData);
            print(
              '[_uploadUpdateFile] Response status: ${response.statusCode}, body: $jsonResponse',
            );

            if (jsonResponse['ok']) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${files.length} archivo(s) de actualización procesado(s) correctamente.',
                  ),
                  backgroundColor: Colors.green,
                ),
              );
              await _loadData(); // Reload data after successful upload
            } else {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    jsonResponse['error'] ??
                        'Error al procesar los archivos de actualización.',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
          } catch (jsonError) {
            print('[_uploadUpdateFile] JSON decode error: $jsonError');
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Error al procesar respuesta del servidor: $jsonError',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        } else {
          print('[_uploadUpdateFile] HTTP error: ${response.statusCode}');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error HTTP ${response.statusCode}: $responseData'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Operación cancelada por el usuario.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al procesar el archivo de actualización: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
