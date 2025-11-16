import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'dart:io';
import 'package:geo_inventario/preview_page.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:data_table_2/data_table_2.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> filteredProducts = [];
  List<Map<String, dynamic>> records = [];
  List<Map<String, dynamic>> analysis = [];
  bool isLoading = true;
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredProducts = products.where((product) {
        final code = product['code'].toLowerCase();
        final description = product['description'].toLowerCase();
        return code.contains(query) || description.contains(query);
      }).toList();
    });
  }

  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
    });
    try {
      final productsResponse = await http
          .get(Uri.parse('http://127.0.0.1:8000/api/inventory/products/'));
      final recordsResponse = await http
          .get(Uri.parse('http://127.0.0.1:8000/api/inventory/records/'));
      final analysisResponse = await http
          .get(Uri.parse('http://127.0.0.1:8000/api/inventory/analysis/'));

      if (productsResponse.statusCode == 200 &&
          recordsResponse.statusCode == 200 &&
          analysisResponse.statusCode == 200) {
        setState(() {
          products = List<Map<String, dynamic>>.from(
              json.decode(productsResponse.body));
          filteredProducts = products;
          records = List<Map<String, dynamic>>.from(
              json.decode(recordsResponse.body));
          analysis = List<Map<String, dynamic>>.from(
              json.decode(analysisResponse.body));
          isLoading = false;
        });
      } else {
        throw Exception('Failed to load data');
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar los datos: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard de Inventario'),
        backgroundColor: const Color(0xFF10B981),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: _uploadFile,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Resumen'),
            Tab(text: 'Productos'),
            Tab(text: 'Análisis'),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Resumen
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Estadísticas rápidas
                        GridView.count(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          shrinkWrap: true,
                          children: [
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    const Text('Total Productos',
                                        style: TextStyle(
                                            fontSize: 14, color: Colors.grey)),
                                    Text('${products.length}',
                                        style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    const Text('Total Registros',
                                        style: TextStyle(
                                            fontSize: 14, color: Colors.grey)),
                                    Text('${records.length}',
                                        style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Gráfico de productos por grupo
                        const Text('Productos por Grupo',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 300,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: _getMaxGroupCount().toDouble(),
                              barTouchData: BarTouchData(enabled: false),
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final groups = _getGroupData();
                                      if (value.toInt() < groups.length) {
                                        return Text(
                                            groups[value.toInt()]['group'],
                                            style:
                                                const TextStyle(fontSize: 10));
                                      }
                                      return const Text('');
                                    },
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: true),
                                ),
                                topTitles: AxisTitles(
                                    sideTitles: SideTitles(showTitles: false)),
                                rightTitles: AxisTitles(
                                    sideTitles: SideTitles(showTitles: false)),
                              ),
                              gridData: FlGridData(show: false),
                              borderData: FlBorderData(show: false),
                              barGroups: _getBarGroups(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Tabla de registros recientes
                        const Text('Registros Recientes',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 400,
                          child: Card(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Text('Últimos 10 Registros',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                ),
                                Expanded(
                                  child: DataTable2(
                                    columnSpacing: 12,
                                    horizontalMargin: 12,
                                    minWidth: 800,
                                    columns: const [
                                      DataColumn2(
                                          label: Text('Producto'),
                                          size: ColumnSize.M),
                                      DataColumn2(
                                          label: Text('Almacén'),
                                          size: ColumnSize.M),
                                      DataColumn2(
                                          label: Text('Fecha'),
                                          size: ColumnSize.S),
                                      DataColumn2(
                                          label: Text('Cantidad'),
                                          size: ColumnSize.S),
                                      DataColumn2(
                                          label: Text('Costo Unit.'),
                                          size: ColumnSize.S),
                                      DataColumn2(
                                          label: Text('Total'),
                                          size: ColumnSize.S),
                                    ],
                                    rows: records.take(10).map((record) {
                                      return DataRow(cells: [
                                        DataCell(Text(record['product_code']
                                                ?.toString() ??
                                            'N/A')),
                                        DataCell(Text(
                                            record['warehouse']?.toString() ??
                                                'N/A')),
                                        DataCell(Text(
                                            record['date']?.toString() ??
                                                'N/A')),
                                        DataCell(Text(
                                            record['quantity']?.toString() ??
                                                '0')),
                                        DataCell(Text(
                                            record['unit_cost']?.toString() ??
                                                '0')),
                                        DataCell(Text(
                                            record['total']?.toString() ??
                                                '0')),
                                      ]);
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

                  // Tab 2: Productos
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Lista de Productos',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              labelText: 'Buscar por código o descripción',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: DataTable2(
                              columnSpacing: 12,
                              horizontalMargin: 12,
                              minWidth: 600,
                              columns: const [
                                DataColumn2(
                                    label: Text('Código'), size: ColumnSize.S),
                                DataColumn2(
                                    label: Text('Descripción'),
                                    size: ColumnSize.L),
                                DataColumn2(
                                    label: Text('Grupo'), size: ColumnSize.L),
                              ],
                              rows: filteredProducts.map((product) {
                                return DataRow(cells: [
                                  DataCell(Text(product['code'])),
                                  DataCell(Text(product['description'])),
                                  DataCell(Text(product['group'])),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Tab 3: Análisis de Productos
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Análisis de Productos',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          Card(
                            child: DataTable2(
                              columnSpacing: 12,
                              horizontalMargin: 12,
                              minWidth: 1200,
                              columns: const [
                                DataColumn2(
                                    label: Text('Código'), size: ColumnSize.S),
                                DataColumn2(
                                    label: Text('Descripción'),
                                    size: ColumnSize.M),
                                DataColumn2(
                                    label: Text('Grupo'), size: ColumnSize.S),
                                DataColumn2(
                                    label: Text('Saldo Actual'),
                                    size: ColumnSize.S),
                                DataColumn2(
                                    label: Text('Valor Saldo'),
                                    size: ColumnSize.S),
                                DataColumn2(
                                    label: Text('Costo Unit.'),
                                    size: ColumnSize.S),
                                DataColumn2(
                                    label: Text('Estancado'),
                                    size: ColumnSize.S),
                                DataColumn2(
                                    label: Text('Rotación'),
                                    size: ColumnSize.S),
                                DataColumn2(
                                    label: Text('Alta Rotación'),
                                    size: ColumnSize.S),
                              ],
                              rows: analysis.map((item) {
                                return DataRow(cells: [
                                  DataCell(Text(item['codigo'] ?? '')),
                                  DataCell(Text(item['descripcion'] ?? '')),
                                  DataCell(Text(item['grupo'] ?? '')),
                                  DataCell(Text(
                                      item['saldo_actual']?.toString() ?? '0')),
                                  DataCell(Text(
                                      '${(item['valor_saldo'] as double?)?.toStringAsFixed(2) ?? '0.00'}')),
                                  DataCell(Text(
                                      '${(item['costo_unitario_promedio'] as double?)?.toStringAsFixed(2) ?? '0.00'}')),
                                  DataCell(Text(item['estancado'] ?? 'No')),
                                  DataCell(Text(item['rotacion'] ?? 'Activo')),
                                  DataCell(Text(item['alta_rotacion'] ?? 'No')),
                                ]);
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

  int _getMaxGroupCount() {
    final groupData = _getGroupData();
    if (groupData.isEmpty) return 0;
    return groupData
        .map((e) => e['count'] as int)
        .reduce((a, b) => a > b ? a : b);
  }

  List<BarChartGroupData> _getBarGroups() {
    final groupData = _getGroupData();
    return List.generate(groupData.length, (index) {
      final data = groupData[index];
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: data['count'].toDouble(),
            color: Colors.blue,
            width: 20,
          ),
        ],
      );
    });
  }

  List<Map<String, dynamic>> _getGroupData() {
    Map<String, int> groupCounts = {};
    for (var product in products) {
      String group = product['group'];
      groupCounts[group] = (groupCounts[group] ?? 0) + 1;
    }
    return groupCounts.entries
        .map((e) => {'group': e.key, 'count': e.value})
        .toList();
  }

  Future<void> _uploadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result != null) {
      final path = result.files.single.path;
      if (path != null) {
        var bytes = File(path).readAsBytesSync();
        var excel = Excel.decodeBytes(bytes);
        var sheet = excel.tables[excel.tables.keys.first];
        var data = sheet!.rows
            .map((row) => row.map((cell) => cell?.value).toList())
            .toList();

        final bool? confirmed = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PreviewPage(data: data, filePath: path),
          ),
        );

        if (confirmed == true) {
          var request = http.MultipartRequest(
            'POST',
            Uri.parse('http://127.0.0.1:8000/api/inventory/upload/'),
          );
          request.files.add(await http.MultipartFile.fromPath('file', path));
          var response = await request.send();
          if (response.statusCode == 201) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Archivo subido correctamente.'),
                backgroundColor: Colors.green,
              ),
            );
            _loadData();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('Error al subir el archivo: ${response.reasonPhrase}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }
  }
}
