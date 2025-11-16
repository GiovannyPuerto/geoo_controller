import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dashboard.dart';
import 'package:flutter_svg/svg.dart';

void main() {
  runApp(MaterialApp(
    title: 'Sistema de Inventario',
    theme: ThemeData(
      primaryColor: const Color.fromARGB(255, 30, 255, 180),
      fontFamily: 'Roboto',
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: const CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        elevation: 4,
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFF10B981)),
          foregroundColor: const Color(0xFF10B981),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    home: const WelcomePage(),
    debugShowCheckedModeBanner: false,
  ));
}

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  PlatformFile? file;
  String? mensaje;
  bool isLoading = false;
  List<Map<String, dynamic>> historial = [];

  @override
  void initState() {
    super.initState();
    _loadHistorial();
  }

  Future<void> _loadHistorial() async {
    try {
      final response = await http
          .get(Uri.parse('http://127.0.0.1:8000/api/inventory/batches/'));
      if (response.statusCode == 200) {
        setState(() {
          historial =
              List<Map<String, dynamic>>.from(json.decode(response.body));
        });
      }
    } catch (e) {
      // Error al cargar historial
    }
  }

  Future<void> pickFile() async {
    var result = await FilePicker.platform
        .pickFiles(allowedExtensions: ['xlsx'], type: FileType.custom);
    if (result != null) {
      setState(() => file = result.files.first);
    }
  }

  Future<void> uploadFile() async {
    if (file == null) return;
    setState(() {
      isLoading = true;
      mensaje = null;
    });

    try {
      var request = http.MultipartRequest('POST',
          Uri.parse('http://127.0.0.1:8000/api/inventory/upload-base/'));
      if (file!.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
            'base_file', file!.bytes!,
            filename: file!.name));
      } else {
        request.files
            .add(await http.MultipartFile.fromPath('base_file', file!.path!));
      }
      var response = await request.send();
      var responseBody = await response.stream.bytesToString();
      var data = json.decode(responseBody);

      setState(() {
        isLoading = false;
        mensaje = data['ok'] == true
            ? 'Archivo procesado correctamente. Se agregaron ${data['importados']} registros nuevos.'
            : 'El archivo contiene errores o ya fue procesado. Verifique la fecha o formato.';
      });

      _loadHistorial(); // Recargar historial
    } catch (e) {
      setState(() {
        isLoading = false;
        mensaje = 'Error al procesar el archivo.';
      });
    }
  }

  void _clearSelection() {
    setState(() {
      file = null;
      mensaje = null;
    });
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
            const Text('Sistema de Inventario'),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DashboardPage()),
              );
            },
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF9FAFB), Color(0xFFF3F4F6)],
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Hero Section
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 80, horizontal: 40),
                child: Column(
                  children: [
                    const Icon(
                      Icons.inventory_2,
                      size: 80,
                      color: Color(0xFF10B981),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Sistema de Gestión de Inventario',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Gestiona tu inventario de manera eficiente con procesamiento automático de archivos Excel',
                      style: TextStyle(
                        fontSize: 20,
                        color: Color(0xFF6B7280),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: pickFile,
                          icon: const Icon(Icons.file_upload),
                          label: const Text('Seleccionar Archivo Excel'),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const DashboardPage()),
                            );
                          },
                          icon: const Icon(Icons.bar_chart),
                          label: const Text('Ver Dashboard'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // File Upload Section
              if (file != null || isLoading || mensaje != null)
                Container(
                  padding: const EdgeInsets.all(40),
                  color: Colors.white,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Procesamiento de Archivo',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF374151),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Tu archivo está siendo procesado. Esto puede tardar unos segundos.',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(height: 32),
                            if (file != null) ...[
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0F2F1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.file_present,
                                        color: Color(0xFF10B981)),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Archivo seleccionado: ${file!.name}',
                                        style: const TextStyle(
                                            color: Color(0xFF065F46)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: file != null && !isLoading
                                        ? uploadFile
                                        : null,
                                    icon: const Icon(Icons.upload),
                                    label: const Text('Subir y procesar'),
                                  ),
                                ),
                                if (file != null) ...[
                                  const SizedBox(width: 16),
                                  OutlinedButton(
                                    onPressed: _clearSelection,
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                          color: Color(0xFFE5E7EB)),
                                      foregroundColor: const Color(0xFF374151),
                                    ),
                                    child: const Text('Limpiar'),
                                  ),
                                ],
                              ],
                            ),
                            if (isLoading) ...[
                              const SizedBox(height: 24),
                              const Center(
                                child: CircularProgressIndicator(),
                              ),
                              const SizedBox(height: 8),
                              const Center(
                                child: Text(
                                  'Procesando archivo… esto puede tardar unos segundos.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                            ],
                            if (mensaje != null) ...[
                              const SizedBox(height: 24),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: mensaje!.contains('correctamente')
                                      ? const Color(0xFFD1FAE5)
                                      : const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      mensaje!.contains('correctamente')
                                          ? Icons.check_circle
                                          : Icons.error,
                                      color: mensaje!.contains('correctamente')
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFEF4444),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        mensaje!,
                                        style: TextStyle(
                                          color:
                                              mensaje!.contains('correctamente')
                                                  ? const Color(0xFF065F46)
                                                  : const Color(0xFF991B1B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (mensaje!.contains('correctamente')) ...[
                                const SizedBox(height: 16),
                                Center(
                                  child: ElevatedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                const DashboardPage()),
                                      );
                                    },
                                    child: const Text('Ver Inventario'),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Features Section
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
                color: Colors.white,
                child: Column(
                  children: [
                    const Text(
                      '¿Qué puedes hacer?',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Nuestra plataforma te permite gestionar tu inventario de forma sencilla y eficiente',
                      style: TextStyle(
                        fontSize: 18,
                        color: Color(0xFF6B7280),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 60),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildFeatureCard(
                          Icons.upload_file,
                          'Subida Rápida',
                          'Arrastra y suelta tus archivos Excel para procesarlos automáticamente',
                        ),
                        const SizedBox(height: 20),
                        _buildFeatureCard(
                          Icons.analytics,
                          'Análisis Completo',
                          'Visualiza estadísticas, gráficos y reportes detallados de tu inventario',
                        ),
                        const SizedBox(height: 20),
                        _buildFeatureCard(
                          Icons.history,
                          'Historial Completo',
                          'Mantén un registro de todas las importaciones realizadas',
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // How it works
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
                child: Column(
                  children: [
                    const Text(
                      '¿Cómo funciona?',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 60),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildStepCard(
                          '1',
                          'Prepara tu Excel',
                          'Asegúrate de que tu archivo Excel contenga las columnas: CODIGO, DESCRIPCION CODIGO, LOCALIZACION, CATEGORIA, FECHA, DOCUMENTO, SALIDA, UNITARIO, TOTAL',
                        ),
                        const SizedBox(height: 40),
                        _buildStepCard(
                          '2',
                          'Sube el Archivo',
                          'Haz clic en "Seleccionar Archivo Excel" o arrastra el archivo a la zona designada',
                        ),
                        const SizedBox(height: 40),
                        _buildStepCard(
                          '3',
                          'Revisa los Resultados',
                          'El sistema procesará automáticamente los datos y podrás verlos en el dashboard',
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Recent Activity
              if (historial.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
                  color: Colors.white,
                  child: Column(
                    children: [
                      const Text(
                        'Actividad Reciente',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 40),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Fecha')),
                                DataColumn(label: Text('Archivo')),
                                DataColumn(label: Text('Registros')),
                                DataColumn(label: Text('Estado')),
                              ],
                              rows: historial.take(5).map((batch) {
                                return DataRow(cells: [
                                  DataCell(Text(
                                      batch['started_at'].substring(0, 10))),
                                  DataCell(Text(batch['file_name'])),
                                  DataCell(Text(
                                      '${batch['rows_imported']}/${batch['rows_total']}')),
                                  DataCell(
                                    Row(
                                      children: [
                                        Icon(
                                          batch['rows_imported'] > 0
                                              ? Icons.check_circle
                                              : Icons.warning,
                                          color: batch['rows_imported'] > 0
                                              ? Colors.green
                                              : Colors.orange,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(batch['rows_imported'] > 0
                                            ? 'Éxito'
                                            : 'Error'),
                                      ],
                                    ),
                                  ),
                                ]);
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Footer
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 40, horizontal: 40),
                color: const Color(0xFF111827),
                child: const Column(
                  children: [
                    Text(
                      'Sistema de Inventario © 2025',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Desarrollado para facilitar la gestión de inventarios empresariales',
                      style: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard(IconData icon, String title, String description) {
    return SizedBox(
      width: 300,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(icon, size: 48, color: const Color(0xFF10B981)),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard(String number, String title, String description) {
    return SizedBox(
      width: 300,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
