import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dashboard.dart';
import 'package:geo_inventario/services/excel_upload_service.dart';
import 'package:geo_inventario/theme/app_theme.dart';

void main() {
  runApp(const GeoInventarioApp());
}

/// Raíz de la aplicación. Configura el tema global y la ruta inicial.
class GeoInventarioApp extends StatelessWidget {
  const GeoInventarioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sistema de Inventario – Geoflora',
      theme: AppTheme.theme,
      home: const WelcomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage>
    with SingleTickerProviderStateMixin {
  PlatformFile? _selectedFile;
  final ExcelUploadService _uploadService = ExcelUploadService();

  String? _mensaje;
  bool _isSuccess = false;
  bool _isLoading = false;
  List<Map<String, dynamic>> _historial = [];

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // ─── Ciclo de vida ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );
    _animCtrl.forward();
    _loadHistorial();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ─── Lógica ────────────────────────────────────────────────────────────────

  /// Carga el historial de importaciones recientes desde la API.
  Future<void> _loadHistorial() async {
    try {
      final response = await http
          .get(Uri.parse('http://127.0.0.1:8000/api/inventory/batches/'));
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _historial =
              List<Map<String, dynamic>>.from(json.decode(response.body));
        });
      }
    } catch (_) {
      // El historial es opcional; si falla no se bloquea la pantalla.
    }
  }

  /// Abre el selector de archivos y guarda el archivo elegido.
  Future<void> _pickFile() async {
    final result = await _uploadService.pickBaseFile();
    if (result != null && mounted) {
      setState(() {
        _selectedFile = result.files.first;
        _mensaje = null;
      });
    }
  }

  /// Sube el archivo seleccionado al servidor y muestra el resultado.
  Future<void> _uploadFile() async {
    if (_selectedFile == null) return;
    setState(() {
      _isLoading = true;
      _mensaje = null;
    });

    try {
      final result = await _uploadService.uploadBaseFile(_selectedFile!);
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _isSuccess = result.ok;
        _mensaje = result.ok
            ? (result.message.isNotEmpty
                ? result.message
                : 'Archivo procesado correctamente.')
            : (result.error ??
                'El archivo contiene errores o ya fue procesado. '
                    'Verifique la fecha o formato.');
      });

      if (result.ok) _loadHistorial();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isSuccess = false;
        _mensaje = 'Error al procesar el archivo. Intente nuevamente.';
      });
    }
  }

  /// Limpia la selección actual y el mensaje de resultado.
  void _clearSelection() {
    setState(() {
      _selectedFile = null;
      _mensaje = null;
    });
  }

  /// Navega al dashboard con una transición de deslizamiento.
  void _goToDashboard() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const DashboardPage(),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeInOutCubic)).animate(animation),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  // ─── Construcción de la UI ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildHeroSection(),
                  if (_selectedFile != null || _isLoading || _mensaje != null)
                    _buildUploadSection(),
                  _buildFeaturesSection(),
                  _buildHowItWorksSection(),
                  if (_historial.isNotEmpty) _buildHistorialSection(),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(70),
      child: Container(
        decoration: const BoxDecoration(
          gradient: AppGradients.primary,
          boxShadow: AppShadows.elevated,
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Image.asset('statics/images/logo_geoflora.png',
                    height: 30),
              ),
              const SizedBox(width: AppSpacing.md),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Sistema de Inventario',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Geoflora SAS',
                    style: TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            _AppBarButton(
              icon: Icons.dashboard_rounded,
              label: 'Dashboard',
              onTap: _goToDashboard,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  // ─── Hero section ──────────────────────────────────────────────────────────

  Widget _buildHeroSection() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final heroIconSize = isMobile ? 72.0 : 96.0;
    final heroIconInner = isMobile ? 36.0 : 48.0;
    final heroTitleSize = isMobile ? 26.0 : 40.0;
    final heroSubtitleSize = isMobile ? 14.0 : 17.0;
    final heroPaddingV = isMobile ? AppSpacing.xl : AppSpacing.xxxl;
    final heroPaddingH = isMobile ? AppSpacing.md : AppSpacing.xxl;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: heroPaddingV, horizontal: heroPaddingH),
      child: Column(
        children: [
          // Ícono principal con fondo degradado
          Container(
            width: heroIconSize,
            height: heroIconSize,
            decoration: BoxDecoration(
              gradient: AppGradients.primary,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              boxShadow: AppShadows.colored(AppColors.primary),
            ),
            child: Icon(Icons.inventory_2_rounded,
                size: heroIconInner, color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Gestión de Inventario',
            style: TextStyle(
              fontSize: heroTitleSize,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              height: 1.1,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            isMobile
                ? 'Procesa Excel, analiza movimientos y visualiza tu inventario.'
                : 'Procesa archivos Excel, analiza movimientos\ny visualiza el estado de tu inventario en tiempo real.',
            style: TextStyle(
              fontSize: heroSubtitleSize,
              color: AppColors.textMuted,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          // Botones de acción
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.upload_file_rounded, size: 20),
                label: const Text('Seleccionar archivo Excel'),
              ),
              OutlinedButton.icon(
                onPressed: _goToDashboard,
                icon: const Icon(Icons.bar_chart_rounded, size: 20),
                label: const Text('Ver Dashboard'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Sección de carga de archivo ───────────────────────────────────────────

  Widget _buildUploadSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          vertical: AppSpacing.xl,
          horizontal: isMobile ? AppSpacing.md : AppSpacing.xxl),
      color: AppColors.surface,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.card,
            ),
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Encabezado de sección
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: const Icon(Icons.cloud_upload_outlined,
                          color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Procesamiento de archivo',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Carga tu archivo Excel base de inventario',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),

                if (_selectedFile != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  // Archivo seleccionado
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.sm + 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLighter,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.description_outlined,
                            color: AppColors.primary, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            _selectedFile!.name,
                            style: const TextStyle(
                              color: AppColors.primaryDarker,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              size: 18, color: AppColors.textMuted),
                          onPressed: _clearSelection,
                          tooltip: 'Quitar archivo',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.lg),

                // Botones de acción
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _selectedFile != null && !_isLoading
                            ? _uploadFile
                            : null,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.upload_rounded, size: 20),
                        label: Text(_isLoading ? 'Procesando…' : 'Subir y procesar'),
                      ),
                    ),
                    if (_selectedFile != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      OutlinedButton(
                        onPressed: _clearSelection,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.border),
                          foregroundColor: AppColors.textSecondary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                        ),
                        child: const Text('Limpiar'),
                      ),
                    ],
                  ],
                ),

                // Mensaje de resultado
                if (_mensaje != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ResultBanner(message: _mensaje!, isSuccess: _isSuccess),
                  if (_isSuccess) ...[
                    const SizedBox(height: AppSpacing.md),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: _goToDashboard,
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Ver inventario'),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Sección de características ────────────────────────────────────────────

  Widget _buildFeaturesSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    const features = [
      (Icons.upload_file_rounded, 'Carga rápida',
          'Selecciona archivos Excel y procésalos en segundos de forma automática.'),
      (Icons.analytics_rounded, 'Análisis completo',
          'Gráficos, estadísticas y reportes detallados del estado de tu inventario.'),
      (Icons.history_rounded, 'Historial de importaciones',
          'Registro completo de todas las cargas realizadas con trazabilidad total.'),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          vertical: isMobile ? AppSpacing.xl : AppSpacing.xxxl,
          horizontal: isMobile ? AppSpacing.md : AppSpacing.xxl),
      color: AppColors.surface,
      child: Column(
        children: [
          const _SectionHeader(
            title: '¿Qué puedes hacer?',
            subtitle:
                'Todas las herramientas que necesitas para gestionar tu inventario en un solo lugar.',
          ),
          const SizedBox(height: AppSpacing.xxxl),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.lg,
            alignment: WrapAlignment.center,
            children: features
                .map((f) => _FeatureCard(icon: f.$1, title: f.$2, body: f.$3))
                .toList(),
          ),
        ],
      ),
    );
  }

  // ─── Sección "Cómo funciona" ───────────────────────────────────────────────

  Widget _buildHowItWorksSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    const steps = [
      ('1', 'Prepara tu Excel',
          'Asegúrate de incluir las columnas: CODIGO, DESCRIPCION, LOCALIZACION, CATEGORIA, FECHA, DOCUMENTO, SALIDA, UNITARIO, TOTAL.'),
      ('2', 'Sube el archivo',
          'Haz clic en "Seleccionar archivo Excel", elige tu archivo y presiona "Subir y procesar".'),
      ('3', 'Revisa los resultados',
          'El sistema procesará los datos automáticamente y podrás visualizarlos en el Dashboard.'),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          vertical: isMobile ? AppSpacing.xl : AppSpacing.xxxl,
          horizontal: isMobile ? AppSpacing.md : AppSpacing.xxl),
      child: Column(
        children: [
          const _SectionHeader(
            title: '¿Cómo funciona?',
            subtitle: 'Tres pasos sencillos para tener tu inventario actualizado.',
          ),
          const SizedBox(height: AppSpacing.xxxl),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xxl,
            alignment: WrapAlignment.center,
            children: steps
                .map((s) => _StepCard(number: s.$1, title: s.$2, body: s.$3))
                .toList(),
          ),
        ],
      ),
    );
  }

  // ─── Historial reciente ────────────────────────────────────────────────────

  Widget _buildHistorialSection() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          vertical: isMobile ? AppSpacing.xl : AppSpacing.xxxl,
          horizontal: isMobile ? AppSpacing.md : AppSpacing.xxl),
      color: AppColors.surface,
      child: Column(
        children: [
          const _SectionHeader(
            title: 'Actividad reciente',
            subtitle: 'Últimas importaciones realizadas al sistema.',
          ),
          const SizedBox(height: AppSpacing.xl),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.border),
                boxShadow: AppShadows.card,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                      AppColors.surfaceVariant),
                  headingTextStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                  dataTextStyle: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                  columnSpacing: AppSpacing.xl,
                  columns: const [
                    DataColumn(label: Text('Fecha')),
                    DataColumn(label: Text('Archivo')),
                    DataColumn(label: Text('Registros')),
                    DataColumn(label: Text('Estado')),
                  ],
                  rows: _historial.take(5).map((batch) {
                    final ok = (batch['rows_imported'] ?? 0) > 0;
                    return DataRow(cells: [
                      DataCell(Text(
                          (batch['started_at'] as String).substring(0, 10))),
                      DataCell(
                        Text(
                          batch['file_name'] ?? '',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DataCell(Text(
                          '${batch['rows_imported']}/${batch['rows_total']}')),
                      DataCell(_StatusChip(ok: ok)),
                    ]);
                  }).toList(),
                ),
                ), // SingleChildScrollView horizontal
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Footer ────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          vertical: AppSpacing.xl,
          horizontal: isMobile ? AppSpacing.md : AppSpacing.xxl),
      color: AppColors.dark,
      child: Column(
        children: [
          // Tres columnas informativas
          Wrap(
            spacing: AppSpacing.xxl,
            runSpacing: AppSpacing.xl,
            alignment: WrapAlignment.spaceEvenly,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              // Contacto
              _FooterColumn(
                title: 'Contáctenos',
                children: const [
                  Text('info@geoflora.co',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 13)),
                  SizedBox(height: 4),
                  Text('Km 4 Vía el Corzo, Bojacá',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('Cundinamarca, Colombia',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
              // Logo
              _FooterColumn(
                title: 'Nuestro grupo empresarial',
                children: [
                  Image.asset('statics/images/logo_geoflora.png',
                      width: 160),
                ],
              ),
              // Certificaciones
              _FooterColumn(
                title: 'Comprometidos con el medio ambiente',
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('statics/images/rainforest.png', width: 72),
                      const SizedBox(width: AppSpacing.md),
                      Image.asset('statics/images/florverde.png', width: 110),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          const Divider(color: Colors.white12, thickness: 1),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Diseñado por Geoflora  ·  © 2025 Geoflora SAS  ·  Todos los derechos reservados',
            style: TextStyle(color: Colors.white54, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Widgets reutilizables de la WelcomePage
// ═══════════════════════════════════════════════════════════════════════════════

/// Botón de icono + etiqueta para el AppBar.
class _AppBarButton extends StatelessWidget {
  const _AppBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white, size: 20),
      label: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 13)),
      style: TextButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.15),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }
}

/// Encabezado estándar de sección (título + subtítulo centrado).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: isMobile ? 22.0 : 28.0,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          subtitle,
          style: TextStyle(fontSize: isMobile ? 14.0 : 16.0, color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Tarjeta de característica con ícono, título y descripción.
class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final cardWidth = isMobile ? screenWidth - AppSpacing.md * 2 : 280.0;

    return SizedBox(
      width: cardWidth,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(icon, size: 32, color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              body,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta numerada del flujo "Cómo funciona".
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final cardWidth = isMobile ? screenWidth - AppSpacing.md * 2 : 260.0;

    return SizedBox(
      width: cardWidth,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: AppGradients.primary,
              shape: BoxShape.circle,
              boxShadow: AppShadows.colored(AppColors.primary),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textMuted, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Banner de resultado de la carga (éxito / error).
class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.message, required this.isSuccess});

  final String message;
  final bool isSuccess;

  @override
  Widget build(BuildContext context) {
    final bg = isSuccess ? AppColors.successLight : AppColors.errorLight;
    final fg = isSuccess ? AppColors.successDark : AppColors.errorDark;
    final icon = isSuccess ? Icons.check_circle_outline : Icons.error_outline;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: TextStyle(color: fg, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

/// Chip de estado en la tabla del historial.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.ok});

  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ok ? AppColors.successLight : AppColors.warningLight,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.warning_amber,
            size: 13,
            color: ok ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 4),
          Text(
            ok ? 'Éxito' : 'Advertencia',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ok ? AppColors.successDark : AppColors.warningDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Columna de información en el footer.
class _FooterColumn extends StatelessWidget {
  const _FooterColumn({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        ...children,
      ],
    );
  }
}
