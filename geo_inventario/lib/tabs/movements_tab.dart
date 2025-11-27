import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:geo_inventario/models/monthly_movement.dart';
import 'package:geo_inventario/services/api_service.dart';
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
    _loadAllMovementsData();
  }

  Future<void> _loadAllMovementsData() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
    });

    try {
      // Load all movements for filter options
      final allMovementsData = await _apiService.getMovements();

      // Load monthly movements for chart
      final monthlyMovementsData = await _apiService.getMonthlyMovements();

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar movimientos: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadMovementsData() async {
    if (!mounted) return;

    try {
      final filteredMovementsData = await _apiService.getMovements(
        warehouse: selectedWarehouse,
        category: selectedGroup,
        search: searchQuery,
        dateFrom: selectedDateRange?.start,
        dateTo: selectedDateRange?.end,
      );

      final filteredMonthlyMovementsData =
          await _apiService.getMonthlyMovements(
        warehouse: selectedWarehouse,
        category: selectedGroup,
        search: searchQuery,
        dateFrom: selectedDateRange?.start,
        dateTo: selectedDateRange?.end,
      );

      if (mounted) {
        setState(() {
          movements = filteredMovementsData;
          filteredMovements = movements;
          monthlyMovements = filteredMonthlyMovementsData;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar movimientos: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAllMovementsData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Historial de Movimientos',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Vista detallada de todas las entradas y salidas de inventario',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    _buildMovementsChart(),
                    const SizedBox(height: 24),
                    _buildChartDataTable(),
                    const SizedBox(height: 24),
                    _buildMovementsTable(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMovementsChart() {
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
                tooltipBehavior: TooltipBehavior(enable: true),
                series: <CartesianSeries>[
                  ColumnSeries<MonthlyMovement, String>(
                    dataSource: monthlyMovements,
                    xValueMapper: (MonthlyMovement data, _) =>
                        DateFormat('MMM yyyy')
                            .format(DateTime.parse('${data.month}-01')),
                    yValueMapper: (MonthlyMovement data, _) =>
                        data.totalEntries,
                    name: 'Entradas',
                    color: Colors.green,
                  ),
                  ColumnSeries<MonthlyMovement, String>(
                    dataSource: monthlyMovements,
                    xValueMapper: (MonthlyMovement data, _) =>
                        DateFormat('MMM yyyy')
                            .format(DateTime.parse('${data.month}-01')),
                    yValueMapper: (MonthlyMovement data, _) => data.totalExits,
                    name: 'Salidas',
                    color: Colors.red,
                  ),
                  LineSeries<MonthlyMovement, String>(
                    dataSource: monthlyMovements,
                    xValueMapper: (MonthlyMovement data, _) =>
                        DateFormat('MMM yyyy')
                            .format(DateTime.parse('${data.month}-01')),
                    yValueMapper: (MonthlyMovement data, _) =>
                        data.closingBalance,
                    name: 'Saldo',
                    color: Colors.blue,
                    markerSettings: const MarkerSettings(isVisible: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartDataTable() {
    if (monthlyMovements.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resumen de Movimientos por Mes',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: DataTable2(
                columnSpacing: 12,
                horizontalMargin: 12,
                minWidth: 600,
                columns: const [
                  DataColumn2(
                    label: Text('Mes'),
                    size: ColumnSize.M,
                  ),
                  DataColumn2(
                    label: Text('Entradas'),
                    size: ColumnSize.M,
                    numeric: true,
                  ),
                  DataColumn2(
                    label: Text('Salidas'),
                    size: ColumnSize.M,
                    numeric: true,
                  ),
                  DataColumn2(
                    label: Text('Saldo Final del mes'),
                    size: ColumnSize.M,
                    numeric: true,
                  ),
                ],
                rows: monthlyMovements.map((movement) {
                  final monthName = DateFormat('MMMM yyyy')
                      .format(DateTime.parse('${movement.month}-01'));
                  return DataRow(cells: [
                    DataCell(Text(monthName)),
                    DataCell(
                        Text(CurrencyFormatter.format(movement.totalEntries))),
                    DataCell(
                        Text(CurrencyFormatter.format(movement.totalExits))),
                    DataCell(Text(
                        CurrencyFormatter.format(movement.closingBalance))),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovementsTable() {
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
                  'Todos los Movimientos',
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
                      label: const Text('Exportar Excel'),
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
            if (filteredMovements.isEmpty)
              const SizedBox(
                height: 400,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_rounded, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No hay movimientos para mostrar',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
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
                child: PaginatedDataTable2(
                  columnSpacing: 12,
                  horizontalMargin: 12,
                  minWidth: 800,
                  scrollController: ScrollController(),
                  isHorizontalScrollBarVisible: true,
                  columns: [
                    DataColumn2(label: Text('Fecha'), size: ColumnSize.S),
                    DataColumn2(label: Text('Producto'), size: ColumnSize.M),
                    DataColumn2(label: Text('Almacén'), size: ColumnSize.S),
                    DataColumn2(label: Text('Tipo Doc.'), size: ColumnSize.S),
                    DataColumn2(label: Text('Documento'), size: ColumnSize.S),
                    DataColumn2(
                        label: Text('Cantidad'),
                        size: ColumnSize.S,
                        numeric: true),
                    DataColumn2(
                        label: Text('Costo Unit.'),
                        size: ColumnSize.S,
                        numeric: true),
                    DataColumn2(
                        label: Text('Total'),
                        size: ColumnSize.S,
                        numeric: true),
                  ],
                  source: MovementsDataSource(filteredMovements),
                ),
              ),
          ],
        ),
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
    try {
      final response = await _apiService.exportMovements(
        format: format,
        warehouse: selectedWarehouse,
        category: selectedGroup,
        search: searchQuery,
        dateFrom: selectedDateRange?.start,
        dateTo: selectedDateRange?.end,
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        if (kIsWeb) {
          final blob = html.Blob([response.bodyBytes]);
          final url = html.Url.createObjectUrlFromBlob(blob);
          final fileName = format == 'excel'
              ? 'movimientos_inventario.xlsx'
              : 'movimientos_inventario.pdf';
          html.AnchorElement(href: url)
            ..setAttribute('download', fileName)
            ..click();
          html.Url.revokeObjectUrl(url);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exportado a ${format.toUpperCase()} exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: ${response.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al exportar: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
                        setState(() => this.selectedWarehouse =
                            value == 'Todos' ? null : value);
                      },
                    ),
                    DropdownButtonFormField<String>(
                      value: selectedGroup == null ||
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

  List<MonthlyMovement> _computeMonthlyMovements(
      List<Map<String, dynamic>> movements) {
    final Map<String, Map<String, double>> monthlyData = {};

    for (var movement in movements) {
      final dateStr = movement['fecha']?.toString();
      if (dateStr == null) continue;

      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;

      final monthKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      final cantidad = (movement['cantidad'] as num?)?.toDouble() ?? 0.0;

      monthlyData.putIfAbsent(
          monthKey,
          () => {
                'totalEntries': 0.0,
                'totalExits': 0.0,
                'closingBalance': 0.0,
              });

      // Positive quantity = entry, negative = exit
      if (cantidad > 0) {
        monthlyData[monthKey]!['totalEntries'] =
            (monthlyData[monthKey]!['totalEntries'] ?? 0) + cantidad;
      } else if (cantidad < 0) {
        monthlyData[monthKey]!['totalExits'] =
            (monthlyData[monthKey]!['totalExits'] ?? 0) + cantidad.abs();
      }

      // Calculate closing balance (entries - exits)
      monthlyData[monthKey]!['closingBalance'] =
          (monthlyData[monthKey]!['totalEntries'] ?? 0) -
              (monthlyData[monthKey]!['totalExits'] ?? 0);
    }

    final sortedMonths = monthlyData.keys.toList()..sort();

    return sortedMonths.map((month) {
      final data = monthlyData[month]!;
      return MonthlyMovement(
        month: month,
        totalEntries: data['totalEntries'] ?? 0.0,
        totalExits: data['totalExits'] ?? 0.0,
        closingBalance: data['closingBalance'] ?? 0.0,
      );
    }).toList();
  }
}
