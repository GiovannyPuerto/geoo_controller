import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geo_inventario/services/api_service.dart';
import 'package:geo_inventario/services/refresh_notifier.dart';
import 'package:geo_inventario/tabs/tops/tops_calculo_service.dart';
import 'package:geo_inventario/theme/app_theme.dart';
import 'package:geo_inventario/utils/currency_formatter.dart';
import 'package:geo_inventario/widgets/info_tooltip.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:universal_html/html.dart' as html
  if (dart.library.io) 'package:geo_inventario/stubs/html_stub.dart';

class TopsTabPage extends StatefulWidget {
  const TopsTabPage({super.key});

  @override
  State<TopsTabPage> createState() => _TopsTabPageState();
}

class _TopsTabPageState extends State<TopsTabPage>
    with AutomaticKeepAliveClientMixin {
  final ApiService _apiService = ApiService();

  @override
  bool get wantKeepAlive => true;

  bool isLoading = true;
  List<Map<String, dynamic>> analysisCutoff = [];
  List<Map<String, dynamic>> analysisRange = [];

  int topsLimit = 30;
  String? topsGroup;
  String? topsRotation;
  String? topsSearch;
  DateTime? movementDateFrom;
  DateTime? movementDateTo;

  Map<String, List<Map<String, dynamic>>> _cachedTopLists = const {};
  List<Map<String, dynamic>>? _lastCutoffRef;
  List<Map<String, dynamic>>? _lastRangeRef;
  int? _lastTopLimit;
  String? _lastTopGroup;
  String? _lastTopRotation;
  String? _lastTopSearch;

  @override
  void initState() {
    super.initState();
    inventoryRefreshNotifier.addListener(_onExternalRefresh);
    _loadData();
  }

  @override
  void dispose() {
    inventoryRefreshNotifier.removeListener(_onExternalRefresh);
    super.dispose();
  }

  void _onExternalRefresh() => _loadData();

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final hasMovementRange =
          movementDateFrom != null && movementDateTo != null;
      final analysisData = hasMovementRange
          ? await _apiService.getAnalysis(
              dateFrom: movementDateFrom,
              dateTo: movementDateTo,
            )
          : await _apiService.getAnalysis();
      if (!mounted) return;
      setState(() {
        analysisCutoff = analysisData;
        analysisRange = analysisData;
        isLoading = false;
        _lastCutoffRef = null;
        _lastRangeRef = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => isLoading = false);
      context.showErrorSnackBar('Error al cargar datos de tops');
    }
  }

  double _asDouble(dynamic raw) {
    return TopsCalculoService.toDouble(raw);
  }

  Future<void> _pickMovementDateRange() async {
    DateTime? localFrom = movementDateFrom;
    DateTime? localTo = movementDateTo;
    final fmt = DateFormat('dd/MM/yyyy', 'es_CO');

    Widget dateRow(
      BuildContext ctx,
      String label,
      DateTime? value,
      VoidCallback onTap,
      VoidCallback onClear,
    ) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: value != null ? AppColors.info : AppColors.border,
              width: value != null ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded,
                  size: 16,
                  color: value != null
                      ? AppColors.info
                      : AppColors.textDisabled),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value != null ? fmt.format(value) : label,
                  style: TextStyle(
                    fontSize: 14,
                    color: value != null
                        ? AppColors.textPrimary
                        : AppColors.textDisabled,
                  ),
                ),
              ),
              if (value != null)
                GestureDetector(
                  onTap: onClear,
                  child: const Icon(Icons.close_rounded,
                      size: 16, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
      );
    }

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.timeline_rounded,
                    color: AppColors.info, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text('Rango de movimientos',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Desde',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted),
                ),
                const SizedBox(height: AppSpacing.xs),
                dateRow(
                  ctx,
                  'Fecha desde (opcional)',
                  localFrom,
                  () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate: DateTime(2020),
                      lastDate: localTo ?? DateTime.now(),
                      initialDate: localFrom ??
                          DateTime.now()
                              .subtract(const Duration(days: 30)),
                      locale: const Locale('es', 'CO'),
                    );
                    if (picked != null) {
                      setDlgState(() => localFrom = picked);
                    }
                  },
                  () => setDlgState(() => localFrom = null),
                ),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Hasta',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted),
                ),
                const SizedBox(height: AppSpacing.xs),
                dateRow(
                  ctx,
                  'Fecha hasta (opcional)',
                  localTo,
                  () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      firstDate: localFrom ?? DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDate: localTo ?? DateTime.now(),
                      locale: const Locale('es', 'CO'),
                    );
                    if (picked != null) {
                      setDlgState(() => localTo = picked);
                    }
                  },
                  () => setDlgState(() => localTo = null),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  movementDateFrom = null;
                  movementDateTo = null;
                });
                Navigator.of(dialogCtx).pop();
                _loadData();
              },
              child: const Text('Limpiar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  movementDateFrom = localFrom;
                  movementDateTo = localTo;
                });
                Navigator.of(dialogCtx).pop();
                _loadData();
              },
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }

  void _clearMovementDateRange() {
    setState(() {
      movementDateFrom = null;
      movementDateTo = null;
    });
    _loadData();
  }

  String _formatDate(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  double _movementValueFor(
    Map<String, dynamic> item,
    String qtyKey,
    String valueKey,
  ) {
    return TopsCalculoService.valorMovimiento(item, qtyKey, valueKey);
  }

  Map<String, List<Map<String, dynamic>>> _computeTopLists() {
    return TopsCalculoService.computeTopLists(
      analysisCutoff: analysisCutoff,
      analysisRange: analysisRange,
      topLimit: topsLimit,
      group: topsGroup,
      rotation: topsRotation,
      search: topsSearch,
    );
  }

  void _refreshTopListsCacheIfNeeded() {
    final normalizedSearch = (topsSearch ?? '').trim();
    final hasChanges =
        !identical(_lastCutoffRef, analysisCutoff) ||
        !identical(_lastRangeRef, analysisRange) ||
        _lastTopLimit != topsLimit ||
        _lastTopGroup != topsGroup ||
        _lastTopRotation != topsRotation ||
        _lastTopSearch != normalizedSearch;

    if (!hasChanges) return;

    _cachedTopLists = _computeTopLists();
    _lastCutoffRef = analysisCutoff;
    _lastRangeRef = analysisRange;
    _lastTopLimit = topsLimit;
    _lastTopGroup = topsGroup;
    _lastTopRotation = topsRotation;
    _lastTopSearch = normalizedSearch;
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Icon(Icons.download_outlined,
                  color: AppColors.primaryDark, size: 18),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Text('Exportar Tops',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text('Selecciona el formato del informe.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.table_chart_outlined, size: 16),
            label: const Text('Excel'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _exportTops('excel');
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text('PDF'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _exportTops('pdf');
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveBytes({
    required Uint8List bytes,
    required String fileName,
    required String extension,
  }) async {
    if (kIsWeb) {
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
      return;
    }

    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar informe de tops',
      fileName: fileName,
      allowedExtensions: [extension],
      type: FileType.custom,
    );
    if (path == null) return;
    await io.File(path).writeAsBytes(bytes);
  }

  Future<void> _exportTops(String format) async {
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final response = await _apiService.exportTops(
        format: format,
        top: topsLimit,
        group: topsGroup,
        rotation: topsRotation,
        search: topsSearch,
        movementDateFrom: movementDateFrom,
        movementDateTo: movementDateTo,
      );

      if (response.statusCode != 200) {
        throw Exception('Error del servidor (${response.statusCode})');
      }

      await _saveBytes(
        bytes: response.bodyBytes,
        fileName: format == 'excel' ? 'tops_$timestamp.xlsx' : 'tops_$timestamp.pdf',
        extension: format == 'excel' ? 'xlsx' : 'pdf',
      );

      if (!mounted) return;
      context.showSuccessSnackBar('Informe de tops exportado correctamente');
    } catch (e) {
      if (!mounted) return;
      context.showErrorSnackBar('Error al exportar tops: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // requerido por AutomaticKeepAliveClientMixin
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: AppSpacing.sm),
            Text('Cargando tops…',
                style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
      );
    }

    _refreshTopListsCacheIfNeeded();
    final tops = _cachedTopLists;
    final topByEntries = tops['entradas'] ?? const <Map<String, dynamic>>[];
    final topByExits = tops['salidas'] ?? const <Map<String, dynamic>>[];

    final groups = <String>{'Todos'};
    for (final item in [...analysisCutoff, ...analysisRange]) {
      final v = (item['grupo'] ?? '').toString().trim();
      if (v.isNotEmpty) groups.add(v);
    }
    final groupItems = groups.toList()..sort((a, b) => a.compareTo(b));

    final hasMovementRangeFilter =
        movementDateFrom != null && movementDateTo != null;
    final hasAnyFilter = hasMovementRangeFilter ||
        topsGroup != null ||
        topsRotation != null ||
        (topsSearch ?? '').isNotEmpty;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                gradient: AppGradients.hero,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: AppShadows.elevated,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: const Icon(
                      Icons.leaderboard_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tops de valor, entradas y salidas',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        Text(
                          hasMovementRangeFilter
                              ? 'Rango: ${_formatDate(movementDateFrom!)} — ${_formatDate(movementDateTo!)}'
                              : 'Últimos 12 meses',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasAnyFilter)
                    Container(
                      margin: const EdgeInsets.only(right: AppSpacing.xs),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: const Text(
                        'Filtros activos',
                        style: TextStyle(
                          color: AppColors.primaryDark,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.filter_list_rounded,
                        size: 20, color: Colors.white),
                    tooltip: 'Filtros',
                    onPressed: () => _showFilterDialog(groupItems),
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    icon: const Icon(Icons.download_outlined,
                        size: 20, color: Colors.white),
                    tooltip: 'Exportar',
                    onPressed: _showExportDialog,
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // ── Chips de filtros activos ─────────────────────────────────────
            if (hasAnyFilter)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (topsGroup != null)
                      _ActiveFilterChip(
                        icon: Icons.category_rounded,
                        label: topsGroup!,
                        onDelete: () => setState(() => topsGroup = null),
                      ),
                    if (topsRotation != null)
                      _ActiveFilterChip(
                        icon: Icons.autorenew_rounded,
                        label: topsRotation!,
                        onDelete: () => setState(() => topsRotation = null),
                      ),
                    if ((topsSearch ?? '').isNotEmpty)
                      _ActiveFilterChip(
                        icon: Icons.search_rounded,
                        label: '"$topsSearch"',
                        onDelete: () => setState(() => topsSearch = null),
                      ),
                    if (hasMovementRangeFilter)
                      _ActiveFilterChip(
                        icon: Icons.calendar_month_rounded,
                        label:
                            '${_formatDate(movementDateFrom!)} — ${_formatDate(movementDateTo!)}',
                        onDelete: _clearMovementDateRange,
                      ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          topsGroup = null;
                          topsRotation = null;
                          topsSearch = null;
                          movementDateFrom = null;
                          movementDateTo = null;
                        });
                        _loadData();
                      },
                      icon: const Icon(Icons.filter_list_off_rounded, size: 14),
                      label: const Text('Limpiar todo',
                          style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: AppSpacing.md),

            // ── Gráfica top productos ─────────────────────────────────────────
            _buildTopsChart(topByEntries, topByExits),

            const SizedBox(height: AppSpacing.md),

            // ── Tablas de tops ───────────────────────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                final twoCol = constraints.maxWidth >= 580;

                final cards = [
                  _TopMetricCard(
                    title: 'Top entradas — valor',
                    icon: Icons.arrow_downward_rounded,
                    accentColor: AppColors.success,
                    helpText: 'Los productos con mayor dinero en entradas durante el período.\nFórmula: suma de los valores que registró Siesa en cada entrada del producto.\nLa barra de cada producto es proporcional al valor del primero del ranking.',
                    items: topByEntries,
                    valueSelector: (item) => _movementValueFor(
                        item, 'entradas_periodo', 'valor_entradas_periodo'),
                    valueLabel: (item) => CurrencyFormatter.format(
                        _movementValueFor(
                            item, 'entradas_periodo', 'valor_entradas_periodo')),
                  ),
                  _TopMetricCard(
                    title: 'Top salidas — valor',
                    icon: Icons.arrow_upward_rounded,
                    accentColor: AppColors.brandPink,
                    helpText: 'Los productos con mayor dinero en salidas durante el período.\nFórmula: suma de los valores que registró Siesa en cada salida del producto (se toma el valor absoluto porque las salidas son negativas).\nLos primeros son los de mayor consumo o demanda.',
                    items: topByExits,
                    valueSelector: (item) => _movementValueFor(
                        item, 'salidas_periodo', 'valor_salidas_periodo'),
                    valueLabel: (item) => CurrencyFormatter.format(
                        _movementValueFor(
                            item, 'salidas_periodo', 'valor_salidas_periodo')),
                  ),
                ];

                if (twoCol) {
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: cards[1]),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    cards[0],
                    const SizedBox(height: AppSpacing.md),
                    cards[1],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Diálogo de filtros ─────────────────────────────────────────────────

  void _showFilterDialog(List<String> groupItems) {
    int localLimit = topsLimit;
    String? localGroup = topsGroup;
    String? localRotation = topsRotation;
    String localSearch = topsSearch ?? '';
    DateTime? localFrom = movementDateFrom;
    DateTime? localTo = movementDateTo;
    final fmt = DateFormat('dd/MM/yyyy', 'es_CO');

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.tune_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Text('Filtros — Tops',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top N
                  const Text('Mostrar',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<int>(
                    value: localLimit,
                    isDense: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(
                          Icons.format_list_numbered_rounded,
                          size: 16),
                    ),
                    items: const [10, 20, 30, 50]
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text('Top $v',
                                  style:
                                      const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDlgState(() => localLimit = v);
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Grupo
                  const Text('Grupo',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: (localGroup != null &&
                            groupItems.contains(localGroup))
                        ? localGroup
                        : 'Todos',
                    isDense: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon:
                          Icon(Icons.category_rounded, size: 16),
                    ),
                    items: groupItems
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text(v,
                                  style:
                                      const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) => setDlgState(
                        () => localGroup =
                            (v == null || v == 'Todos') ? null : v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Rotación
                  const Text('Rotación',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: (topsRotation?.isNotEmpty == true)
                        ? topsRotation
                        : 'Todos',
                    isDense: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon:
                          Icon(Icons.autorenew_rounded, size: 16),
                    ),
                    items: const [
                      'Todos',
                      'Activo',
                      'Estancado',
                      'Obsoleto',
                      'Inactivo',
                    ]
                        .map((v) => DropdownMenuItem(
                              value: v,
                              child: Text(v,
                                  style:
                                      const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) => setDlgState(() =>
                        localRotation = v == 'Todos' ? null : v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Búsqueda
                  const Text('Buscar por código o nombre',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted)),
                  const SizedBox(height: 4),
                  TextFormField(
                    initialValue: localSearch,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search_rounded, size: 16),
                      hintText: 'Ej: NITRATO, 320…',
                    ),
                    onChanged: (v) => setDlgState(() => localSearch = v),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Rango de movimientos',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted)),
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Desde',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  const SizedBox(height: AppSpacing.xs),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime(2020),
                        lastDate: localTo ?? DateTime.now(),
                        initialDate: localFrom ?? DateTime.now().subtract(const Duration(days: 30)),
                        locale: const Locale('es', 'CO'),
                      );
                      if (picked != null) setDlgState(() => localFrom = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: localFrom != null ? AppColors.primary : AppColors.border,
                          width: localFrom != null ? 1.8 : 1,
                        ),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today_rounded, size: 16,
                            color: localFrom != null ? AppColors.primary : AppColors.textDisabled),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          localFrom != null ? fmt.format(localFrom!) : 'Fecha desde (opcional)',
                          style: TextStyle(fontSize: 14,
                              color: localFrom != null ? AppColors.textPrimary : AppColors.textDisabled),
                        )),
                        if (localFrom != null)
                          GestureDetector(
                            onTap: () => setDlgState(() => localFrom = null),
                            child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Hasta',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                  const SizedBox(height: AppSpacing.xs),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        firstDate: localFrom ?? DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDate: localTo ?? DateTime.now(),
                        locale: const Locale('es', 'CO'),
                      );
                      if (picked != null) setDlgState(() => localTo = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: localTo != null ? AppColors.primary : AppColors.border,
                          width: localTo != null ? 1.8 : 1,
                        ),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today_rounded, size: 16,
                            color: localTo != null ? AppColors.primary : AppColors.textDisabled),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          localTo != null ? fmt.format(localTo!) : 'Fecha hasta (opcional)',
                          style: TextStyle(fontSize: 14,
                              color: localTo != null ? AppColors.textPrimary : AppColors.textDisabled),
                        )),
                        if (localTo != null)
                          GestureDetector(
                            onTap: () => setDlgState(() => localTo = null),
                            child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
                          ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  topsGroup = null;
                  topsRotation = null;
                  topsSearch = null;
                  movementDateFrom = null;
                  movementDateTo = null;
                  topsLimit = 30;
                });
                Navigator.of(dialogCtx).pop();
                _loadData();
              },
              child: const Text('Limpiar todo',
                  style: TextStyle(color: AppColors.error)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  topsLimit = localLimit;
                  topsGroup = localGroup;
                  topsRotation = localRotation;
                  topsSearch =
                      localSearch.trim().isEmpty ? null : localSearch.trim();
                  movementDateFrom = localFrom;
                  movementDateTo = localTo;
                });
                Navigator.of(dialogCtx).pop();
                _loadData();
              },
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Gráfica top productos ────────────────────────────────────────────────

  Widget _buildTopsChart(
    List<Map<String, dynamic>> topByEntries,
    List<Map<String, dynamic>> topByExits,
  ) {
    final chartLimit = topsLimit.clamp(3, 15);
    final bool byGroup = topsGroup == null;

    // ── Modo por GRUPO: agrega TODOS los productos (sin límite topN) ─────
    if (byGroup) {
      // Usa la lista completa filtrada, no la ya limitada a topN
      final allFiltered = TopsCalculoService.filtrarBase(
        analysisRange,
        rotation: topsRotation,
        search: topsSearch,
      );

      final entryByGroup = <String, double>{};
      final exitByGroup = <String, double>{};

      for (final item in allFiltered) {
        final g = (item['grupo'] ?? 'Sin grupo').toString().trim();
        if (g.isEmpty) continue;
        entryByGroup[g] = (entryByGroup[g] ?? 0) +
            _movementValueFor(item, 'entradas_periodo', 'valor_entradas_periodo');
        exitByGroup[g] = (exitByGroup[g] ?? 0) +
            _movementValueFor(item, 'salidas_periodo', 'valor_salidas_periodo');
      }

      final allGroups = <String>{...entryByGroup.keys, ...exitByGroup.keys};
      if (allGroups.isEmpty) return const SizedBox.shrink();

      final chartData = allGroups
          .map((g) => _TopsChartPoint(
                code: g,
                name: g,
                entradas: entryByGroup[g] ?? 0,
                salidas: exitByGroup[g] ?? 0,
              ))
          .toList()
        ..sort((a, b) =>
            (b.entradas + b.salidas).compareTo(a.entradas + a.salidas));

      return _buildChartWidget(
        chartData: chartData, // sin límite — muestra todos los grupos
        tooltipTitle: (pt) => pt.name,
        tooltipSubtitle: null,
        chartTitle: 'Todos los grupos — Entradas vs Salidas',
      );
    }

    // ── Modo por PRODUCTO: dentro del grupo seleccionado ──────────────────
    final allKeys = <String>{};
    for (final item in topByEntries.take(chartLimit)) {
      allKeys.add((item['codigo'] ?? '').toString());
    }
    for (final item in topByExits.take(chartLimit)) {
      allKeys.add((item['codigo'] ?? '').toString());
    }
    if (allKeys.isEmpty) return const SizedBox.shrink();

    final entryMap = <String, double>{};
    for (final item in topByEntries) {
      entryMap[(item['codigo'] ?? '').toString()] =
          _movementValueFor(item, 'entradas_periodo', 'valor_entradas_periodo');
    }
    final exitMap = <String, double>{};
    for (final item in topByExits) {
      exitMap[(item['codigo'] ?? '').toString()] =
          _movementValueFor(item, 'salidas_periodo', 'valor_salidas_periodo');
    }
    final nameMap = <String, String>{};
    for (final item in [...topByEntries, ...topByExits]) {
      final code = (item['codigo'] ?? '').toString();
      if (code.isNotEmpty && !nameMap.containsKey(code)) {
        nameMap[code] = (item['nombre_producto'] ?? '').toString();
      }
    }

    final chartData = allKeys
        .map((code) => _TopsChartPoint(
              code: code,
              name: nameMap[code] ?? code,
              entradas: entryMap[code] ?? 0,
              salidas: exitMap[code] ?? 0,
            ))
        .toList()
      ..sort((a, b) =>
          (b.entradas + b.salidas).compareTo(a.entradas + a.salidas));

    return _buildChartWidget(
      chartData: chartData,
      tooltipTitle: (pt) => pt.code,
      tooltipSubtitle: (pt) => pt.name,
      chartTitle: 'Top productos (${topsGroup!}) — Entradas vs Salidas',
    );
  }

  Widget _buildChartWidget({
    required List<_TopsChartPoint> chartData,
    required String Function(_TopsChartPoint) tooltipTitle,
    String Function(_TopsChartPoint)? tooltipSubtitle,
    required String chartTitle,
  }) {

    String fmtAxis(num v) {
      final abs = v.abs();
      if (abs >= 1e9) return '\$${(v / 1e9).toStringAsFixed(1)}B';
      if (abs >= 1e6) return '\$${(v / 1e6).toStringAsFixed(1)}M';
      if (abs >= 1e3) return '\$${(v / 1e3).toStringAsFixed(0)}K';
      return '\$${v.toStringAsFixed(0)}';
    }

    String fmtVal(num? v) {
      if (v == null) return '—';
      return CurrencyFormatter.format(v.toDouble());
    }

    const seriesColors = [AppColors.chartPositive, AppColors.chartNegative];
    const seriesNames = ['Entradas', 'Salidas'];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  chartTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              const InfoTooltip(
                title: 'Entradas vs Salidas',
                message: 'Entradas y salidas por grupo o producto para comparar en una sola vista.\nFórmula: el valor de cada movimiento lo registra Siesa; el tablero los suma por producto o grupo.\n• Sin filtro de grupo: una barra por cada categoría\n• Con grupo seleccionado: una barra por cada producto del grupo\nToca una barra para ver el valor exacto.',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(builder: (ctx, cons) {
            final baseH = cons.maxWidth < 480 ? 220.0 : 300.0;
            final chartH = (chartData.length * 38.0).clamp(baseH, 600.0);
            return SizedBox(
            height: chartH,
            child: SfCartesianChart(
              plotAreaBorderWidth: 0,
              primaryXAxis: CategoryAxis(
                labelStyle: const TextStyle(
                    color: AppColors.textMuted, fontSize: 10),
                axisLine: const AxisLine(width: 0),
                majorTickLines: const MajorTickLines(size: 0),
                majorGridLines: const MajorGridLines(width: 0),
                labelIntersectAction: AxisLabelIntersectAction.rotate45,
              ),
              primaryYAxis: NumericAxis(
                axisLine: const AxisLine(width: 0),
                majorTickLines: const MajorTickLines(size: 0),
                labelStyle: const TextStyle(
                    color: AppColors.textMuted, fontSize: 10),
                majorGridLines: const MajorGridLines(
                  width: 1,
                  color: AppColors.border,
                  dashArray: [4, 4],
                ),
                axisLabelFormatter: (AxisLabelRenderDetails details) =>
                    ChartAxisLabel(
                        fmtAxis(details.value), details.textStyle),
              ),
              legend: const Legend(
                isVisible: true,
                position: LegendPosition.bottom,
                textStyle: TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
                overflowMode: LegendItemOverflowMode.wrap,
              ),
              trackballBehavior: TrackballBehavior(
                enable: true,
                activationMode: ActivationMode.singleTap,
                lineType: TrackballLineType.vertical,
                lineColor: AppColors.textMuted,
                lineWidth: 1,
                lineDashArray: const [4, 3],
                tooltipDisplayMode:
                    TrackballDisplayMode.groupAllPoints,
                tooltipSettings:
                    const InteractiveTooltip(enable: false),
                builder: (context, details) {
                  final points =
                      details.groupingModeInfo?.points ?? [];
                  if (points.isEmpty) return const SizedBox.shrink();
                  final xKey = points.first.x?.toString() ?? '';
                  // Busca el punto en chartData para obtener título/subtítulo
                  final pt = chartData.firstWhere(
                    (d) => d.code == xKey,
                    orElse: () => _TopsChartPoint(
                        code: xKey, name: xKey,
                        entradas: 0, salidas: 0),
                  );
                  final title = tooltipTitle(pt);
                  final subtitle = tooltipSubtitle?.call(pt) ?? '';
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.dark,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              subtitle,
                              style: const TextStyle(
                                color: AppColors.textDisabled,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        ...points.asMap().entries.map((e) {
                          final idx = e.key;
                          final yVal = e.value.y;
                          final dotColor = idx < seriesColors.length
                              ? seriesColors[idx]
                              : Colors.white;
                          final label = idx < seriesNames.length
                              ? seriesNames[idx]
                              : 'Serie ${idx + 1}';
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: dotColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$label: ',
                                  style: const TextStyle(
                                    color: AppColors.textDisabled,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  fmtVal(yVal),
                                  style: TextStyle(
                                    color: dotColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
              series: <CartesianSeries>[
                ColumnSeries<_TopsChartPoint, String>(
                  name: 'Entradas',
                  dataSource: chartData,
                  xValueMapper: (d, _) => d.code,
                  yValueMapper: (d, _) => d.entradas,
                  color: AppColors.chartPositive.withValues(alpha: 0.75),
                  width: 0.55,
                  spacing: 0.1,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                  animationDuration: 900,
                ),
                ColumnSeries<_TopsChartPoint, String>(
                  name: 'Salidas',
                  dataSource: chartData,
                  xValueMapper: (d, _) => d.code,
                  yValueMapper: (d, _) => d.salidas,
                  color: AppColors.chartNegative.withValues(alpha: 0.75),
                  width: 0.55,
                  spacing: 0.1,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                  animationDuration: 900,
                ),
              ],
            ),
          );
          }),
        ],
      ),
    );
  }
}

// ── Chip de filtro activo ─────────────────────────────────────────────────────
class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({
    required this.icon,
    required this.label,
    required this.onDelete,
  });

  final IconData icon;
  final String label;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDelete,
            child: const Icon(Icons.close_rounded,
                size: 12, color: AppColors.primaryDark),
          ),
        ],
      ),
    );
  }
}

// ── Botón de rango de movimientos ───────────────────────────────────────────
class _MovementRangeButton extends StatelessWidget {
  const _MovementRangeButton({
    required this.dateFrom,
    required this.dateTo,
    required this.onTap,
    this.onClear,
  });

  final DateTime? dateFrom;
  final DateTime? dateTo;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  String _fmt(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    final hasRange = dateFrom != null && dateTo != null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 11,
        ),
        decoration: BoxDecoration(
          color: hasRange ? AppColors.infoLight : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: hasRange ? AppColors.info : AppColors.border,
            width: hasRange ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timeline_rounded,
              size: 18,
              color: hasRange ? AppColors.info : AppColors.textMuted,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              hasRange
                  ? '${_fmt(dateFrom!)} — ${_fmt(dateTo!)}'
                  : 'Rango movs.',
              style: TextStyle(
                fontSize: 14,
                color: hasRange ? AppColors.infoDark : AppColors.textMuted,
                fontWeight: hasRange ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: AppSpacing.xs),
              GestureDetector(
                onTap: onClear,
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.info,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Tarjeta de top ───────────────────────────────────────────────────────────
class _TopMetricCard extends StatelessWidget {
  const _TopMetricCard({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.items,
    required this.valueSelector,
    required this.valueLabel,
    this.helpText,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final List<Map<String, dynamic>> items;
  final double Function(Map<String, dynamic>) valueSelector;
  final String Function(Map<String, dynamic>) valueLabel;
  final String? helpText;

  @override
  Widget build(BuildContext context) {
    final maxVal = items.isEmpty
        ? 1.0
        : items.map(valueSelector).reduce((a, b) => a > b ? a : b);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera con color de acento
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.lg),
                topRight: Radius.circular(AppRadius.lg),
              ),
              border: Border(
                bottom: BorderSide(
                  color: accentColor.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, size: 16, color: accentColor),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    '${items.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
                if (helpText != null) ...[  
                  const SizedBox(width: 6),
                  InfoTooltip(
                    title: title,
                    message: helpText!,
                    baseColor: accentColor,
                  ),
                ],
              ],
            ),
          ),

          // Lista
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Icon(
                          Icons.inbox_rounded,
                          size: 16,
                          color: AppColors.textDisabled,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        const Text(
                          'Sin datos para los filtros actuales.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: items.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final ratio = maxVal > 0
                          ? (valueSelector(item) / maxVal).clamp(0.0, 1.0)
                          : 0.0;
                      return _TopRow(
                        index: index,
                        item: item,
                        valueLabel: valueLabel(item),
                        ratio: ratio,
                        accentColor: accentColor,
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Fila individual del ranking ──────────────────────────────────────────────
class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.index,
    required this.item,
    required this.valueLabel,
    required this.ratio,
    required this.accentColor,
  });

  final int index;
  final Map<String, dynamic> item;
  final String valueLabel;
  final double ratio;
  final Color accentColor;

  static const _medals = [
    AppColors.medalGold,
    AppColors.medalSilver,
    AppColors.medalBronze,
  ];

  @override
  Widget build(BuildContext context) {
    final rank = index + 1;
    final isMedal = rank <= 3;
    final medalColor = isMedal ? _medals[index] : null;
    final code = (item['codigo'] ?? '').toString();
    final name = (item['nombre_producto'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: isMedal
              ? medalColor!.withValues(alpha: 0.06)
              : (index.isEven
                  ? AppColors.surfaceVariant.withValues(alpha: 0.5)
                  : Colors.transparent),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Posición / medalla
                SizedBox(
                  width: 28,
                  child: isMedal
                      ? Icon(
                          Icons.emoji_events_rounded,
                          size: 18,
                          color: medalColor,
                        )
                      : Text(
                          '$rank.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                ),
                // Código + nombre
                Expanded(
                  child: Text(
                    '$code — $name',
                    style: TextStyle(
                      fontSize: 12,
                      color: isMedal
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: isMedal ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Valor
                Text(
                  valueLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isMedal ? medalColor : accentColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Barra de progreso relativa
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 3,
                backgroundColor: AppColors.borderLight,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isMedal
                      ? medalColor!.withValues(alpha: 0.8)
                      : accentColor.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Datos para la gráfica de tops ────────────────────────────────────────────

class _TopsChartPoint {
  const _TopsChartPoint({
    required this.code,
    required this.name,
    required this.entradas,
    required this.salidas,
  });

  final String code;
  final String name;
  final double entradas;
  final double salidas;
}
