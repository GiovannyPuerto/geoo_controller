import 'package:flutter/material.dart';
import 'package:geo_inventario/services/api_service.dart';
import 'package:geo_inventario/utils/currency_formatter.dart';

class SummaryTabPage extends StatefulWidget {
  final VoidCallback onPickFile;

  const SummaryTabPage({
    super.key,
    required this.onPickFile,
  });

  @override
  State<SummaryTabPage> createState() => _SummaryTabPageState();
}

class _SummaryTabPageState extends State<SummaryTabPage> {
  final ApiService _apiService = ApiService();

  // State
  Map<String, dynamic>? summary;
  List<Map<String, dynamic>> analysis = [];
  String? welcomeMessage;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSummaryData();
  }

  Future<void> _loadSummaryData() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
    });

    try {
      // Load all data in parallel
      final results = await Future.wait([
        _apiService.getSummary(),
        _apiService.getAnalysis(), // Simplified for now
        _apiService.getWelcomeMessage(),
      ]);

      if (mounted) {
        setState(() {
          summary = results[0] as Map<String, dynamic>?;
          analysis = results[1] as List<Map<String, dynamic>>;
          welcomeMessage = results[2] as String?;
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
            content: Text('Error al cargar el resumen: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _loadSummaryData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (welcomeMessage != null && welcomeMessage!.isNotEmpty) ...[
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.waving_hand, color: Colors.blue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          welcomeMessage!,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (summary == null || (summary!['total_products'] ?? 0) == 0)
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
            ],
          ),
          const SizedBox(height: 20),
          const Icon(Icons.inventory_rounded,
              size: 80, color: Color.fromARGB(255, 158, 158, 158)),
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
            onPressed: widget.onPickFile,
            icon: const Icon(Icons.cloud_upload_outlined,
                size: 20, color: Colors.white),
            label: const Text('Cargar archivo base'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    if (summary == null) {
      return const SizedBox.shrink();
    }

    final totalProducts = summary!['total_products'] ?? 0;
    final totalValue = (summary!['total_value'] ?? 0.0).toDouble();

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
}