import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:geo_inventario/services/api_service.dart';
import 'package:geo_inventario/services/excel_upload_service.dart';
import 'package:geo_inventario/tabs/analysis_tab.dart';
import 'package:geo_inventario/tabs/movements_tab.dart';
import 'package:geo_inventario/tabs/summary_tab.dart';
import 'package:geo_inventario/services/refresh_notifier.dart';
import 'package:geo_inventario/theme/app_theme.dart';
import 'package:intl/intl.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ApiService _apiService = ApiService();
  final ExcelUploadService _uploadService = ExcelUploadService();

  String? _lastUpdateTime;
  bool _hasBaseData = false;

  // ─── Ciclo de vida ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDashboardState();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── Carga de datos iniciales ──────────────────────────────────────────────

  Future<void> _loadDashboardState() async {
    await Future.wait([
      _loadLastUpdateTime(),
      _loadBaseDataStatus(),
    ]);
  }

  Future<void> _loadLastUpdateTime() async {
    try {
      final data = await _apiService.getLastUpdateTime();
      if (!mounted) return;
      setState(() {
        if (data == null || data == 'Error' || data == 'No se ha actualizado') {
          _lastUpdateTime = null;
          return;
        }
        try {
          final dt = DateTime.parse(data);
          _lastUpdateTime =
              DateFormat("dd/MM/yyyy 'a las' HH:mm").format(dt.toLocal());
        } catch (_) {
          _lastUpdateTime = data;
        }
      });
    } catch (_) {
      // No se muestra error crítico si no hay última actualización.
    }
  }

  Future<void> _loadBaseDataStatus() async {
    try {
      final summary = await _apiService.getSummary();
      if (!mounted) return;
      setState(() {
        _hasBaseData = (summary?['total_products'] ?? 0) > 0;
      });
    } catch (_) {
      // Conserva el estado previo en caso de fallo.
    }
  }

  // ─── Operaciones de carga de archivos ─────────────────────────────────────

  /// Selecciona y sube un archivo base de inventario.
  Future<void> _pickAndUploadBaseFile() async {
    final result = await _uploadService.pickBaseFile();
    if (result == null || result.files.isEmpty || !mounted) return;
    await _uploadBaseFile(result.files.single);
  }

  Future<void> _uploadBaseFile(PlatformFile file) async {
    if (!mounted) return;
    _showLoadingDialog('Cargando archivo base…');

    try {
      final result = await _uploadService.uploadBaseFile(file);
      if (!mounted) return;
      Navigator.of(context).pop(); // cierra diálogo de carga

      if (result.ok) {
        setState(() => _hasBaseData = true);
        _loadLastUpdateTime();
        _loadBaseDataStatus();
        inventoryRefreshNotifier.refresh(); // notifica a todas las tabs
        context.showSuccessSnackBar(
          result.message.isNotEmpty
              ? result.message
              : 'Archivo cargado exitosamente.',
        );
        _showUploadResultDialog(
          title: 'Resultado de carga base',
          result: result,
        );
      } else {
        context.showErrorSnackBar(
            result.error ?? 'Error al cargar el archivo.');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      context.showErrorSnackBar('Error de conexión: ${e.toString()}');
    }
  }

  /// Selecciona y sube archivos de actualización de inventario.
  Future<void> _pickAndUploadUpdateFiles() async {
    final result = await _uploadService.pickUpdateFiles();
    if (result == null || result.files.isEmpty || !mounted) return;

    _showLoadingDialog('Procesando archivos de actualización…');

    try {
      final uploadResult = await _uploadService.uploadUpdateFiles(result.files);
      if (!mounted) return;
      Navigator.of(context).pop();

      if (uploadResult.ok) {
        setState(() => _hasBaseData = true);
        _loadLastUpdateTime();
        inventoryRefreshNotifier.refresh(); // notifica a todas las tabs
        context.showSuccessSnackBar(
          uploadResult.message.isNotEmpty
              ? uploadResult.message
              : 'Archivos procesados exitosamente.',
        );
        _showUploadResultDialog(
          title: 'Resultado de actualización',
          result: uploadResult,
        );
      } else {
        context.showErrorSnackBar(
            uploadResult.error ?? 'Error al procesar los archivos.');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      context.showErrorSnackBar('Error de conexión: ${e.toString()}');
    }
  }

  /// Muestra un diálogo de carga no cancelable mientras se procesa un archivo.
  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        contentPadding: const EdgeInsets.all(AppSpacing.xl),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Esto puede tardar unos segundos…',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showUploadResultDialog({
    required String title,
    required UploadOperationResult result,
  }) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => _UploadResultDialog(title: title, result: result),
    );
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: TabBarView(
        controller: _tabController,
        children: [
          SummaryTabPage(onPickFile: _pickAndUploadBaseFile),
          const AnalysisTabPage(),
          const MovementsTabPage(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(112),
      child: Container(
        decoration: const BoxDecoration(
          gradient: AppGradients.primary,
          boxShadow: AppShadows.elevated,
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            tooltip: 'Volver al inicio',
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(
            children: [
              Image.asset('statics/images/logo_geoflora.png', height: 36),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dashboard de Inventario',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (_lastUpdateTime != null)
                      Text(
                        'Actualizado el $_lastUpdateTime',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            _UploadMenu(
              hasBaseData: _hasBaseData,
              onUploadBase: _pickAndUploadBaseFile,
              onUploadUpdate: _pickAndUploadUpdateFiles,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.summarize_rounded, size: 16),
                    SizedBox(width: 6),
                    Text('Resumen'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.analytics_rounded, size: 16),
                    SizedBox(width: 6),
                    Text('Análisis'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_horiz_rounded, size: 16),
                    SizedBox(width: 6),
                    Text('Movimientos'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Widget del menú de carga de archivos
// ═══════════════════════════════════════════════════════════════════════════════

/// Botón de menú desplegable para seleccionar el tipo de carga.
class _UploadMenu extends StatelessWidget {
  const _UploadMenu({
    required this.hasBaseData,
    required this.onUploadBase,
    required this.onUploadUpdate,
  });

  final bool hasBaseData;
  final VoidCallback onUploadBase;
  final VoidCallback onUploadUpdate;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Cargar archivos',
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      onSelected: (value) {
        if (value == 'base') {
          onUploadBase();
        } else if (value == 'update') {
          onUploadUpdate();
        }
      },
      itemBuilder: (_) => [
        if (!hasBaseData)
          const PopupMenuItem(
            value: 'base',
            child: ListTile(
              leading: Icon(Icons.upload_file_rounded, color: AppColors.primary),
              title: Text('Cargar archivo base',
                  style: TextStyle(fontSize: 14)),
              subtitle: Text('Inventario inicial',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        if (hasBaseData)
          const PopupMenuItem(
            value: 'update',
            child: ListTile(
              leading:
                  Icon(Icons.cloud_sync_rounded, color: AppColors.primary),
              title: Text('Cargar actualización',
                  style: TextStyle(fontSize: 14)),
              subtitle: Text('Movimientos nuevos',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
      ],
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_upload_outlined, color: Colors.white, size: 20),
            SizedBox(width: 6),
            Text('Cargar',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Diálogo de resultado de carga
// ═══════════════════════════════════════════════════════════════════════════════

/// Diálogo que muestra el resultado detallado de una carga de archivo.
/// Presenta métricas de registros en filas visuales con íconos y colores,
/// y lista los archivos individuales cuando hay una actualización múltiple.
class _UploadResultDialog extends StatelessWidget {
  const _UploadResultDialog({
    required this.title,
    required this.result,
  });

  final String title;
  final UploadOperationResult result;

  @override
  Widget build(BuildContext context) {
    final summary = result.summary ?? const <String, dynamic>{};

    // Métricas de archivo base
    final baseRegistered = summary['base_records'] as int?;
    final baseRepeated = summary['duplicates_base'] as int?;

    // Métricas de actualización
    final updateRegistered = (summary['update_registered_records'] ??
        summary['update_records']) as int?;
    final updateRepeated = (summary['update_repeated_records'] ??
        summary['duplicates_update']) as int?;
    final totalProcessed = summary['total_processed'] as int?;

    // Lista de archivos individuales (actualizaciones múltiples)
    final updateFiles = summary['update_files'] is List
        ? (summary['update_files'] as List).whereType<Map>().toList()
        : const <Map>[];

    final hasMetrics = baseRegistered != null ||
        baseRepeated != null ||
        updateRegistered != null ||
        updateRepeated != null ||
        totalProcessed != null;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Encabezado con color según resultado ──────────────────────
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                gradient: result.ok
                    ? AppGradients.successCard
                    : AppGradients.errorCard,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.xl),
                  topRight: Radius.circular(AppRadius.xl),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      result.ok
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          result.ok
                              ? 'Procesado exitosamente'
                              : 'Se encontraron errores',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Cuerpo scrollable ─────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Métricas de archivo base
                    if (baseRegistered != null || baseRepeated != null)
                      _MetricSection(
                        label: 'Archivo base',
                        icon: Icons.upload_file_rounded,
                        color: AppColors.info,
                        rows: [
                          if (baseRegistered != null)
                            _MetricRow(
                              icon: Icons.check_circle_outline_rounded,
                              label: 'Registros importados',
                              value: '$baseRegistered',
                              valueColor: AppColors.success,
                            ),
                          if (baseRepeated != null)
                            _MetricRow(
                              icon: Icons.content_copy_rounded,
                              label: 'Registros duplicados',
                              value: '$baseRepeated',
                              valueColor: AppColors.warning,
                            ),
                        ],
                      ),

                    // Métricas de actualización
                    if (updateRegistered != null || updateRepeated != null)
                      _MetricSection(
                        label: 'Actualización',
                        icon: Icons.cloud_sync_rounded,
                        color: AppColors.primaryDark,
                        rows: [
                          if (updateRegistered != null)
                            _MetricRow(
                              icon: Icons.check_circle_outline_rounded,
                              label: 'Registros importados',
                              value: '$updateRegistered',
                              valueColor: AppColors.success,
                            ),
                          if (updateRepeated != null)
                            _MetricRow(
                              icon: Icons.content_copy_rounded,
                              label: 'Registros duplicados',
                              value: '$updateRepeated',
                              valueColor: AppColors.warning,
                            ),
                        ],
                      ),

                    // Total global
                    if (totalProcessed != null)
                      _MetricRow(
                        icon: Icons.summarize_rounded,
                        label: 'Total procesados',
                        value: '$totalProcessed',
                        valueColor: AppColors.textPrimary,
                        bold: true,
                      ),

                    // Detalle por archivo (actualizaciones múltiples)
                    if (updateFiles.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      const Divider(),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'Detalle por archivo',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ...updateFiles.map((entry) => _FileDetailRow(
                            fileName:
                                (entry['file_name'] ?? 'archivo').toString(),
                            registered: (entry['rows_registered'] ?? 0) as int,
                            repeated: (entry['rows_repeated'] ?? 0) as int,
                          )),
                    ],

                    // Mensaje fallback cuando no hay métricas estructuradas
                    if (!hasMetrics && updateFiles.isEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.only(top: AppSpacing.sm),
                        child: Text(
                          result.ok
                              ? (result.message.isNotEmpty
                                  ? result.message
                                  : 'El archivo fue procesado correctamente.')
                              : (result.error?.isNotEmpty == true
                                  ? result.error!
                                  : result.message.isNotEmpty
                                      ? result.message
                                      : 'Ocurrió un error al procesar el archivo.'),
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Botón de cierre ───────────────────────────────────────────
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets del diálogo ────────────────────────────────────────────────

/// Sección agrupada de métricas con encabezado coloreado.
class _MetricSection extends StatelessWidget {
  const _MetricSection({
    required this.label,
    required this.icon,
    required this.color,
    required this.rows,
  });

  final String label;
  final IconData icon;
  final Color color;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Encabezado de la sección
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.md),
                topRight: Radius.circular(AppRadius.md),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          // Filas de métricas
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                for (int i = 0; i < rows.length; i++) ...[
                  rows[i],
                  if (i < rows.length - 1) const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila individual de métrica: ícono + etiqueta + valor en badge.
class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
    this.bold = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: valueColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// Fila de resumen por archivo individual en una actualización múltiple.
class _FileDetailRow extends StatelessWidget {
  const _FileDetailRow({
    required this.fileName,
    required this.registered,
    required this.repeated,
  });

  final String fileName;
  final int registered;
  final int repeated;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insert_drive_file_rounded,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  fileName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _SmallBadge(
                  label: '$registered registrados',
                  color: AppColors.success),
              const SizedBox(width: AppSpacing.sm),
              _SmallBadge(
                label: '$repeated duplicados',
                color: repeated > 0 ? AppColors.warning : AppColors.textDisabled,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Badge compacto para conteos en filas de archivo.
class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
