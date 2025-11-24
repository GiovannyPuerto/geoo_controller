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

class _WelcomePageState extends State<WelcomePage>
    with SingleTickerProviderStateMixin {
  PlatformFile? file;
  String? mensaje;
  bool isLoading = false;
  List<Map<String, dynamic>> historial = [];
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _loadHistorial();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF10B981),
                Color(0xFF059669),
                Color(0xFF047857),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Image.asset(
                    'statics/images/logo_geoflora.png',
                    height: 32,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 16),
                const Text(
                  'Sistema de Inventario',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.inventory,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            const DashboardPage(),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                          const begin = Offset(1.0, 0.0);
                          const end = Offset.zero;
                          const curve = Curves.easeInOutCubic;
                          var tween = Tween(begin: begin, end: end)
                              .chain(CurveTween(curve: curve));
                          return SlideTransition(
                            position: animation.drive(tween),
                            child: child,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Hero Section
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 80, horizontal: 40),
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
                                      builder: (context) =>
                                          const DashboardPage()),
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
                  if (file != null || isLoading || mensaje != null) ...[
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
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: file != null && !isLoading
                                              ? const LinearGradient(
                                                  colors: [
                                                    Color(0xFF10B981),
                                                    Color(0xFF059669)
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                )
                                              : null,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          boxShadow: file != null && !isLoading
                                              ? [
                                                  BoxShadow(
                                                    color:
                                                        const Color(0xFF10B981)
                                                            .withOpacity(0.3),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: ElevatedButton.icon(
                                          onPressed: file != null && !isLoading
                                              ? uploadFile
                                              : null,
                                          icon: const Icon(Icons.upload,
                                              size: 20),
                                          label: const Text('Subir y procesar'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            disabledBackgroundColor:
                                                Colors.grey.shade300,
                                            disabledForegroundColor:
                                                Colors.grey.shade500,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 16),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            textStyle: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (file != null) ...[
                                      const SizedBox(width: 16),
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  Colors.black.withOpacity(0.1),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: OutlinedButton(
                                          onPressed: _clearSelection,
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(
                                                color: Color(0xFFE5E7EB)),
                                            foregroundColor:
                                                const Color(0xFF374151),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 24, vertical: 16),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            textStyle: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          child: const Text('Limpiar'),
                                        ),
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
                                          color:
                                              mensaje!.contains('correctamente')
                                                  ? const Color(0xFF10B981)
                                                  : const Color(0xFFEF4444),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            mensaje!,
                                            style: TextStyle(
                                              color: mensaje!
                                                      .contains('correctamente')
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
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF10B981),
                                              Color(0xFF059669),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF10B981)
                                                  .withOpacity(0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ElevatedButton(
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              PageRouteBuilder(
                                                pageBuilder: (context,
                                                        animation,
                                                        secondaryAnimation) =>
                                                    const DashboardPage(),
                                                transitionsBuilder: (context,
                                                    animation,
                                                    secondaryAnimation,
                                                    child) {
                                                  const begin =
                                                      Offset(1.0, 0.0);
                                                  const end = Offset.zero;
                                                  const curve =
                                                      Curves.easeInOutCubic;
                                                  var tween = Tween(
                                                          begin: begin,
                                                          end: end)
                                                      .chain(CurveTween(
                                                          curve: curve));
                                                  return SlideTransition(
                                                    position:
                                                        animation.drive(tween),
                                                    child: child,
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 32, vertical: 16),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            textStyle: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          child: const Text('Ver Inventario'),
                                        ),
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
                  ],

                  // Features Section
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 60, horizontal: 40),
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
                    padding: const EdgeInsets.symmetric(
                        vertical: 60, horizontal: 40),
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
                  ...(historial.isNotEmpty
                      ? [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 60, horizontal: 40),
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
                                  constraints:
                                      const BoxConstraints(maxWidth: 1000),
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
                                            DataCell(Text(batch['started_at']
                                                .substring(0, 10))),
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
                                                    color:
                                                        batch['rows_imported'] >
                                                                0
                                                            ? Colors.green
                                                            : Colors.orange,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                      batch['rows_imported'] > 0
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
                        ]
                      : []),

                  // Footer
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 40, horizontal: 40),
                    color: const Color(0xFF111827),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // SECCIÓN PRINCIPAL DEL FOOTER (3 columnas)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // --------- Columna 1: Contáctenos ----------
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Contáctenos",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  "info@geoflora.co",
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 14),
                                ),
                                const SizedBox(height: 5),
                                const Text(
                                  "Km 4 Vía el Corzo Bojacá",
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 14),
                                ),
                                const SizedBox(height: 5),
                                const Text(
                                  "Cundinamarca, Colombia",
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 14),
                                ),
                              ],
                            ),

                            // --------- Columna 2: Nuestro grupo empresarial ----------
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text(
                                  "Nuestro grupo empresarial",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Image.asset(
                                  "statics/images/logo_geoflora.png",
                                  width: 180,
                                ),
                              ],
                            ),

                            // --------- Columna 3: Comprometidos con el medio ambiente ----------
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text(
                                  "Comprometidos con el medio ambiente",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Image.asset(
                                      "statics/images/rainforest.png",
                                      width: 80,
                                    ),
                                    const SizedBox(width: 15),
                                    Image.asset(
                                      "statics/images/florverde.png",
                                      width: 120,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 40),

                        // Línea divisoria
                        Container(
                          height: 1,
                          color: Colors.white12,
                          margin: const EdgeInsets.symmetric(vertical: 20),
                        ),

                        // --------- COPYRIGHT FINAL ----------
                        const Text(
                          'Diseñado por Geoflora | Copyright © 2025 Geoflora SAS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
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
