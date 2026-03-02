import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geo_inventario/services/api_service.dart';
import 'package:geo_inventario/services/refresh_notifier.dart';
import 'package:geo_inventario/tabs/tops/tops_calculo_service.dart';
import 'package:geo_inventario/theme/app_theme.dart';
import 'package:geo_inventario/utils/currency_formatter.dart';
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html
  if (dart.library.io) 'package:geo_inventario/stubs/html_stub.dart';

class TopsTabPage extends StatefulWidget {
  const TopsTabPage({super.key});

  @override
  State<TopsTabPage> createState() => _TopsTabPageState();
}

class _TopsTabPageState extends State<TopsTabPage> {
  final ApiService _apiService = ApiService();

  bool isLoading = true;
  List<Map<String, dynamic>> analysisCutoff = [];
  List<Map<String, dynamic>> analysisRange = [];

  int topsLimit = 30;
  String? topsGroup;
  String? topsRotation;
  String? topsSearch;
  DateTime? selectedDate;
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
      final hasCutoff = selectedDate != null;
      final hasMovementRange = movementDateFrom != null && movementDateTo != null;

      List<Map<String, dynamic>> cutoffData;
      List<Map<String, dynamic>> rangeData;

      if (!hasCutoff && !hasMovementRange) {
        final allData = await _apiService.getAnalysis();
        cutoffData = allData;
        rangeData = allData;
      } else {
        final results = await Future.wait([
          _apiService.getAnalysis(specificDate: selectedDate),
          _apiService.getAnalysis(
            dateFrom: movementDateFrom,
            dateTo: movementDateTo,
          ),
        ]);
        cutoffData = results[0];
        rangeData = results[1];
      }

      if (!mounted) return;
      setState(() {
        analysisCutoff = cutoffData;
        analysisRange = rangeData;
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

  Future<void> _pickCutoffDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDate: selectedDate ?? now,
      locale: const Locale('es', 'CO'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: AppColors.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => selectedDate = picked);
      _loadData();
    }
  }

  void _clearCutoffDate() {
    setState(() => selectedDate = null);
    _loadData();
  }

  Future<void> _pickMovementDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: (movementDateFrom != null && movementDateTo != null)
          ? DateTimeRange(start: movementDateFrom!, end: movementDateTo!)
          : null,
      locale: const Locale('es', 'CO'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: AppColors.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        movementDateFrom = picked.start;
        movementDateTo = picked.end;
      });
      _loadData();
    }
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
        title: const Text('Exportar Tops'),
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
        cutoffDate: selectedDate,
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
    final topByValue = tops['valor'] ?? const <Map<String, dynamic>>[];
    final topByEntries = tops['entradas'] ?? const <Map<String, dynamic>>[];
    final topByExits = tops['salidas'] ?? const <Map<String, dynamic>>[];

    final groups = <String>{'Todos'};
    for (final item in [...analysisCutoff, ...analysisRange]) {
      final v = (item['grupo'] ?? '').toString().trim();
      if (v.isNotEmpty) groups.add(v);
    }
    final groupItems = groups.toList()..sort((a, b) => a.compareTo(b));

    final hasCutoffDateFilter = selectedDate != null;
    final hasMovementRangeFilter =
        movementDateFrom != null && movementDateTo != null;

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
                gradient: const LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
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
                          'Corte valor: '
                          '${hasCutoffDateFilter ? _formatDate(selectedDate!) : 'sin fecha'}'
                          '  ·  '
                          'Rango ent/sal.: '
                          '${hasMovementRangeFilter ? '${_formatDate(movementDateFrom!)} — ${_formatDate(movementDateTo!)}' : 'sin rango'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasCutoffDateFilter || hasMovementRangeFilter)
                    Chip(
                      label: const Text(
                        'Filtro activo',
                        style: TextStyle(
                          color: AppColors.primaryDark,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // ── Filtros ──────────────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.tune_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const Text(
                          'Filtros',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        OutlinedButton.icon(
                          onPressed: _showExportDialog,
                          icon: const Icon(Icons.download_outlined, size: 16),
                          label: const Text('Exportar'),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const Spacer(),
                        if (hasCutoffDateFilter ||
                            hasMovementRangeFilter ||
                            topsGroup != null ||
                            topsRotation != null ||
                            (topsSearch ?? '').isNotEmpty)
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                topsGroup = null;
                                topsRotation = null;
                                topsSearch = null;
                                selectedDate = null;
                                movementDateFrom = null;
                                movementDateTo = null;
                              });
                              _loadData();
                            },
                            icon: const Icon(Icons.clear_all_rounded, size: 16),
                            label: const Text('Limpiar'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.error,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        // Top N
                        SizedBox(
                          width: 150,
                          child: DropdownButtonFormField<int>(
                            initialValue: topsLimit,
                            decoration: const InputDecoration(
                              labelText: 'Mostrar',
                              prefixIcon: Icon(
                                Icons.format_list_numbered_rounded,
                                size: 18,
                              ),
                            ),
                            items: const [10, 20, 30, 50]
                                .map((v) => DropdownMenuItem(
                                      value: v,
                                      child: Text('Top $v'),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => topsLimit = v);
                            },
                          ),
                        ),

                        // Grupo
                        SizedBox(
                          width: 210,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue:
                                (topsGroup != null && topsGroup!.isNotEmpty)
                                    ? topsGroup
                                    : 'Todos',
                            decoration: const InputDecoration(
                              labelText: 'Grupo',
                              prefixIcon: Icon(
                                Icons.category_rounded,
                                size: 18,
                              ),
                            ),
                            selectedItemBuilder: (context) => groupItems
                                .map((v) => Text(
                                      v,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ))
                                .toList(),
                            items: groupItems
                                .map((v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(
                                        v,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(
                              () => topsGroup = v == 'Todos' ? null : v,
                            ),
                          ),
                        ),

                        // Rotación
                        SizedBox(
                          width: 190,
                          child: DropdownButtonFormField<String>(
                            initialValue: (topsRotation != null &&
                                    topsRotation!.isNotEmpty)
                                ? topsRotation
                                : 'Todos',
                            decoration: const InputDecoration(
                              labelText: 'Rotación',
                              prefixIcon: Icon(
                                Icons.autorenew_rounded,
                                size: 18,
                              ),
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
                                      child: Text(v),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(
                              () => topsRotation = v == 'Todos' ? null : v,
                            ),
                          ),
                        ),
                        

                        // Fecha de corte (solo valor inventario)
                        _DateRangeButton(
                          selectedDate: selectedDate,
                          onTap: _pickCutoffDate,
                          onClear:
                              hasCutoffDateFilter ? _clearCutoffDate : null,
                        ),

                        // Rango de fechas (solo movimientos/entradas/salidas)
                        _MovementRangeButton(
                          dateFrom: movementDateFrom,
                          dateTo: movementDateTo,
                          onTap: _pickMovementDateRange,
                          onClear: hasMovementRangeFilter
                              ? _clearMovementDateRange
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // ── Tablas de tops ───────────────────────────────────────────────
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth < 1100
                    ? constraints.maxWidth
                    : (constraints.maxWidth - AppSpacing.sm) / 2;

                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _TopMetricCard(
                        title: 'Top valor en inventario',
                        icon: Icons.attach_money_rounded,
                        accentColor: AppColors.primary,
                        items: topByValue,
                        valueSelector: (item) =>
                            _asDouble(item['valor_saldo_actual']),
                        valueLabel: (item) =>
                            'Valor: ${CurrencyFormatter.format(item['valor_saldo_actual'] ?? 0)}',
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _TopMetricCard(
                        title: 'Más valor entradas en período',
                        icon: Icons.arrow_downward_rounded,
                        accentColor: AppColors.success,
                        items: topByEntries,
                        valueSelector: (item) =>
                          _movementValueFor(item, 'entradas_periodo', 'valor_entradas_periodo'),
                        valueLabel: (item) =>
                            'Valor ent.: ${CurrencyFormatter.format(_movementValueFor(item, 'entradas_periodo', 'valor_entradas_periodo'))}',
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _TopMetricCard(
                        title: 'Más valor salidas en período',
                        icon: Icons.arrow_upward_rounded,
                        accentColor: AppColors.warning,
                        items: topByExits,
                        valueSelector: (item) =>
                          _movementValueFor(item, 'salidas_periodo', 'valor_salidas_periodo'),
                        valueLabel: (item) =>
                            'Valor sal.: ${CurrencyFormatter.format(_movementValueFor(item, 'salidas_periodo', 'valor_salidas_periodo'))}',
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Botón de rango de fechas ─────────────────────────────────────────────────
class _DateRangeButton extends StatelessWidget {
  const _DateRangeButton({
    required this.selectedDate,
    required this.onTap,
    this.onClear,
  });

  final DateTime? selectedDate;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  String _fmt(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    final hasRange = selectedDate != null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 11,
        ),
        decoration: BoxDecoration(
          color: hasRange ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: hasRange ? AppColors.primary : AppColors.border,
            width: hasRange ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.date_range_rounded,
              size: 18,
              color: hasRange ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              hasRange ? _fmt(selectedDate!) : 'Fecha de corte valor inventario',
              style: TextStyle(
                fontSize: 14,
                color: hasRange ? AppColors.primary : AppColors.textMuted,
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
                  color: AppColors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final List<Map<String, dynamic>> items;
  final double Function(Map<String, dynamic>) valueSelector;
  final String Function(Map<String, dynamic>) valueLabel;

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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
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
