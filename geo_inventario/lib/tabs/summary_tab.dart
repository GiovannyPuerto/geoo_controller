import 'package:flutter/material.dart';
import 'package:geo_inventario/services/api_service.dart';
import 'package:geo_inventario/services/refresh_notifier.dart';
import 'package:geo_inventario/tabs/summary/resumen_analisis_service.dart';
import 'package:geo_inventario/theme/app_theme.dart';
import 'package:geo_inventario/utils/currency_formatter.dart';

class SummaryTabPage extends StatefulWidget {
  /// Callback que abre el selector de archivo base desde el Dashboard.
  final VoidCallback onPickFile;

  const SummaryTabPage({super.key, required this.onPickFile});

  @override
  State<SummaryTabPage> createState() => _SummaryTabPageState();
}

class _SummaryTabPageState extends State<SummaryTabPage>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();

  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _analysis = [];
  String? _welcomeMessage;
  bool _isLoading = true;
  bool _isAnalysisLoading = false;
  int _analysisRequestEpoch = 0;
  ResumenAnalisisMetricas _metricas = const ResumenAnalisisMetricas();

  // Controlador para animar las barras de progreso al aparecer
  late AnimationController _progressCtrl;

  // ─── Ciclo de vida ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    inventoryRefreshNotifier.addListener(_onExternalRefresh);
    _loadData();
  }

  @override
  void dispose() {
    inventoryRefreshNotifier.removeListener(_onExternalRefresh);
    _progressCtrl.dispose();
    super.dispose();
  }

  /// Se llama cuando el Dashboard sube un Excel exitosamente.
  void _onExternalRefresh() => _loadData();

  // ─── Carga de datos ────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    if (!mounted) return;
    final requestEpoch = ++_analysisRequestEpoch;
    setState(() {
      _isLoading = true;
      _isAnalysisLoading = true;
    });
    _progressCtrl.reset();

    try {
      final results = await Future.wait([
        _apiService.getSummary(),
        _apiService.getWelcomeMessage(),
      ]);

      if (!mounted) return;
      setState(() {
        _summary = results[0] as Map<String, dynamic>?;
        _welcomeMessage = results[1] as String?;
        _isLoading = false;
      });
      _progressCtrl.forward();

      final analysisData = await _apiService.getAnalysis();
      if (!mounted || requestEpoch != _analysisRequestEpoch) return;
      setState(() {
        _analysis = analysisData;
        _metricas = ResumenAnalisisService.calcular(analysisData);
        _isAnalysisLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isAnalysisLoading = false;
      });
      context.showErrorSnackBar('Error al cargar el resumen: ${e.toString()}');
    }
  }

  // ─── Datos calculados ──────────────────────────────────────────────────────

  int get _totalProducts => ResumenAnalisisService.totalProductos(_summary);
  double get _totalValue => ResumenAnalisisService.valorTotal(_summary);
  bool get _hasData => ResumenAnalisisService.tieneDatos(_summary);

  int get _activeCount => _metricas.activos;
  int get _stagnantCount => _metricas.estancados;
  int get _obsoleteCount => _metricas.obsoletos;
  int get _inactivoCount => _metricas.inactivos;
  int get _highRotationCount => _metricas.altaRotacion;
  int get _stagnantProductCount => _metricas.estancadoFlag;

  List<Map<String, dynamic>> get _topValueProducts => _metricas.topValor;

  List<Map<String, dynamic>> get _negativeStockProducts =>
      _metricas.stockNegativo;

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
            SizedBox(height: AppSpacing.md),
            Text(
              'Cargando resumen…',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: !_hasData
            ? _buildEmptyState()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Banner corporativo de sección ──────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.md),
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
                          child: const Icon(Icons.dashboard_rounded,
                              color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Resumen del Inventario',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                            Text(
                              'Estado general, rotación y alertas',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xCCFFFFFF)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Banner de bienvenida (opcional)
                  if (_welcomeMessage != null &&
                      _welcomeMessage!.isNotEmpty) ...[
                    _WelcomeBanner(message: _welcomeMessage!),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // ── Fila 1: KPIs principales ──────────────────────────────
                  _buildKpiRow(),
                  const SizedBox(height: AppSpacing.md),

                  if (_isAnalysisLoading) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          children: const [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: AppSpacing.sm),
                            Text(
                              'Cargando análisis detallado…',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // ── Fila 2: Estado + Alertas rápidas ─────────────────────
                  if (!_isAnalysisLoading && _analysis.isNotEmpty) ...[
                    _buildMiddleRow(),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // ── Fila 3: Top productos por valor ──────────────────────
                  if (!_isAnalysisLoading && _topValueProducts.isNotEmpty) ...[
                    _buildTopProductsCard(),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // ── Fila 4: Alertas de stock negativo ────────────────────
                  if (!_isAnalysisLoading && _negativeStockProducts.isNotEmpty)
                    _buildNegativeStockCard(),
                ],
              ),
      ),
    );
  }

  // ─── Estado vacío ──────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
        child: Column(
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: const Icon(Icons.inventory_2_outlined,
                  size: 44, color: AppColors.textDisabled),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Sin datos de inventario',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Carga un archivo base para comenzar a ver\nel estado de tu inventario.',
              style: TextStyle(
                  fontSize: 14, color: AppColors.textMuted, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton.icon(
              onPressed: widget.onPickFile,
              icon: const Icon(Icons.upload_file_rounded, size: 20),
              label: const Text('Cargar archivo base'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Fila 1: KPIs ─────────────────────────────────────────────────────────

  Widget _buildKpiRow() {
    return LayoutBuilder(builder: (context, constraints) {
      // En pantallas anchas: 4 cards en una fila; en angostas: 2×2
      final twoColumns = constraints.maxWidth < 600;
      final cards = [
        _KpiCard(
          label: 'Total productos',
          value: _totalProducts.toString(),
          icon: Icons.inventory_2_rounded,
          gradient: AppGradients.infoCard,
          subtitle: '${_analysis.length} productos únicos',
        ),
        _KpiCard(
          label: 'Valor del inventario',
          value: CurrencyFormatter.format(_totalValue),
          icon: Icons.payments_rounded,
          gradient: AppGradients.successCard,
          subtitle: 'Saldo valorizado actual',
        ),
        _KpiCard(
          label: 'Alta rotación',
          value: _highRotationCount.toString(),
          icon: Icons.trending_up_rounded,
          gradient: AppGradients.warningCard,
          subtitle: 'Productos de alta demanda',
        ),
        _KpiCard(
          label: 'Estancados',
          value: _stagnantProductCount.toString(),
          icon: Icons.hourglass_bottom_rounded,
          gradient: AppGradients.errorCard,
          subtitle: 'Requieren atención',
        ),
      ];

      if (twoColumns) {
        return Column(
          children: [
            Row(children: [
              Expanded(child: cards[0]),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: cards[1]),
            ]),
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              Expanded(child: cards[2]),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: cards[3]),
            ]),
          ],
        );
      }

      return Row(
        children: cards
            .expand((c) =>
                [Expanded(child: c), const SizedBox(width: AppSpacing.sm)])
            .toList()
          ..removeLast(),
      );
    });
  }

  // ─── Fila 2: Solo Rotación rápida ─────────────────────────────────────

  Widget _buildMiddleRow() {
    return _buildRotationQuickView();
  }

  // ─── Vista rápida de rotación (tres chips grandes) ─────────────────────────

  Widget _buildRotationQuickView() {
    final total = _analysis.length;
    double pct(int n) => ResumenAnalisisService.porcentaje(n, total);

    return _SectionCard(
      title: 'Rotación',
      icon: Icons.pie_chart_rounded,
      child: Column(
        children: [
          _RotationTile(
            label: 'Activos',
            count: _activeCount,
            percentage: pct(_activeCount),
            color: AppColors.success,
            bgColor: AppColors.successLight,
            icon: Icons.check_circle_rounded,
          ),
          const SizedBox(height: AppSpacing.sm),
          _RotationTile(
            label: 'Estancados',
            count: _stagnantCount,
            percentage: pct(_stagnantCount),
            color: AppColors.warning,
            bgColor: AppColors.warningLight,
            icon: Icons.warning_rounded,
          ),
          const SizedBox(height: AppSpacing.sm),
          _RotationTile(
            label: 'Obsoletos',
            count: _obsoleteCount,
            percentage: pct(_obsoleteCount),
            color: AppColors.error,
            bgColor: AppColors.errorLight,
            icon: Icons.cancel_rounded,
          ),
          const SizedBox(height: AppSpacing.sm),
          _RotationTile(
            label: 'Inactivos',
            count: _inactivoCount,
            percentage: pct(_inactivoCount),
            color: AppColors.textMuted,
            bgColor: AppColors.surfaceVariant,
            icon: Icons.remove_circle_outline_rounded,
          ),
        ],
      ),
    );
  }

  // ─── Top 5 productos por valor ─────────────────────────────────────────────

  Widget _buildTopProductsCard() {
    return _SectionCard(
      title: 'Top 5 productos por valor',
      icon: Icons.emoji_events_rounded,
      child: Column(
        children: [
          // Encabezado de columnas
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: 4),
            child: Row(
              children: const [
                Expanded(
                  flex: 3,
                  child: Text('Producto',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textMuted)),
                ),
                Expanded(
                  child: Text('Saldo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textMuted)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Valor',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textMuted)),
                ),
              ],
            ),
          ),
          const Divider(height: AppSpacing.sm),
          ..._topValueProducts.asMap().entries.map((e) {
            final index = e.key;
            final item = e.value;
            final name = (item['nombre_producto'] ?? item['descripcion'] ?? '-')
                .toString();
            final qty = (item['cantidad_saldo_actual'] ?? 0.0) as num;
            final val = (item['valor_saldo_actual'] ?? 0.0) as num;
            return _TopProductRow(
              rank: index + 1,
              name: name,
              quantity: qty.toDouble(),
              value: val.toDouble(),
            );
          }),
        ],
      ),
    );
  }

  // ─── Alertas: stock negativo ───────────────────────────────────────────────

  Widget _buildNegativeStockCard() {
    return _SectionCard(
      title: 'Alertas de stock negativo (${_negativeStockProducts.length})',
      icon: Icons.report_problem_rounded,
      iconColor: AppColors.error,
      titleColor: AppColors.error,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: AppColors.errorDark, size: 16),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Los siguientes productos tienen saldo negativo y requieren revisión.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.errorDark, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          ..._negativeStockProducts.take(8).map((item) {
            final name = (item['nombre_producto'] ?? item['descripcion'] ?? '–')
                .toString();
            final code = (item['codigo'] ?? '').toString();
            final qty = (item['cantidad_saldo_actual'] ?? 0.0) as num;
            return _AlertRow(
              code: code,
              name: name,
              quantity: qty.toDouble(),
            );
          }),
          if (_negativeStockProducts.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                '… y ${_negativeStockProducts.length - 8} más. Ve a "Análisis" para verlos todos.',
                style:
                    const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Sub-widgets reutilizables
// ═══════════════════════════════════════════════════════════════════════════════

/// Banner de bienvenida dinámico.
class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.waving_hand_rounded,
              color: AppColors.info, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.infoDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta KPI con degradado, ícono, valor grande y subtítulo.
class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.gradient,
    required this.subtitle,
  });

  final String label;
  final String value;
  final IconData icon;
  final LinearGradient gradient;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      constraints: const BoxConstraints(minHeight: 130),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.75),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Contenedor de sección con encabezado, borde y sombra sutil.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.iconColor = AppColors.primary,
    this.titleColor = AppColors.textPrimary,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Color iconColor;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.lg),
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
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// Fila compacta de rotación con ícono, nombre, conteo y porcentaje.
class _RotationTile extends StatelessWidget {
  const _RotationTile({
    required this.label,
    required this.count,
    required this.percentage,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  final String label;
  final int count;
  final double percentage;
  final Color color;
  final Color bgColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                  height: 1.1,
                ),
              ),
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 11,
                  color: color.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fila de un producto en el top 5 por valor.
class _TopProductRow extends StatelessWidget {
  const _TopProductRow({
    required this.rank,
    required this.name,
    required this.quantity,
    required this.value,
  });

  final int rank;
  final String name;
  final double quantity;
  final double value;

  @override
  Widget build(BuildContext context) {
    // Los primeros tres puestos tienen medalla de color
    final medalColors = [
      const Color(0xFFFFC107), // oro
      const Color(0xFF9E9E9E), // plata
      const Color(0xFF8D6E63), // bronce
    ];
    final medalColor =
        rank <= 3 ? medalColors[rank - 1] : AppColors.textDisabled;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // Posición / medalla
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: medalColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: medalColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Nombre del producto
          Expanded(
            flex: 3,
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Cantidad
          Expanded(
            child: Text(
              quantity.toStringAsFixed(0),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          // Valor monetario
          Expanded(
            flex: 2,
            child: Text(
              CurrencyFormatter.format(value),
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de alerta para un producto con saldo negativo.
class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.code,
    required this.name,
    required this.quantity,
  });

  final String code;
  final String name;
  final double quantity;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.arrow_downward_rounded,
              color: AppColors.error, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.errorDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (code.isNotEmpty)
                  Text(
                    code,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          Text(
            quantity.toStringAsFixed(2),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}
