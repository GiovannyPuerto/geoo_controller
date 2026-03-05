import 'package:flutter/material.dart';
import 'package:geo_inventario/theme/app_theme.dart';

/// Ícono de ayuda `?` con tooltip enriquecido.
///
/// Al hacer hover (escritorio) o pulsación larga (móvil) muestra
/// un panel oscuro y redondeado con [title] en negrita y [message]
/// como cuerpo explicativo.
///
/// Uso básico:
/// ```dart
/// Row(
///   children: [
///     Text('Distribución por Grupo', ...),
///     const SizedBox(width: 6),
///     const InfoTooltip(
///       title: 'Distribución por Grupo',
///       message: 'Muestra el % del valor...',
///     ),
///   ],
/// )
/// ```
class InfoTooltip extends StatefulWidget {
  const InfoTooltip({
    super.key,
    required this.title,
    required this.message,
    this.iconSize = 15.0,

    /// Color del ícono en reposo. Null → AppColors.primary.
    this.baseColor,
  });

  final String title;
  final String message;
  final double iconSize;
  final Color? baseColor;

  @override
  State<InfoTooltip> createState() => _InfoTooltipState();
}

class _InfoTooltipState extends State<InfoTooltip>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onEnter(_) {
    _ctrl.forward();
    setState(() => _hovered = true);
  }

  void _onExit(_) {
    _ctrl.reverse();
    setState(() => _hovered = false);
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.baseColor ?? AppColors.primary;

    return Tooltip(
      richMessage: TextSpan(
        children: [
          TextSpan(
            text: '${widget.title}\n',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: Colors.white,
              height: 1.6,
            ),
          ),
          TextSpan(
            text: widget.message,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFFCBD5E1), // slate-300
              height: 1.5,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // slate-900
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF334155), // slate-700
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            spreadRadius: 1,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      preferBelow: false,
      verticalOffset: 10,
      waitDuration: const Duration(milliseconds: 180),
      showDuration: const Duration(seconds: 6),
      // Ancho máximo cómodo para leer
      constraints: const BoxConstraints(maxWidth: 290),
      child: MouseRegion(
        cursor: SystemMouseCursors.help,
        onEnter: _onEnter,
        onExit: _onExit,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: widget.iconSize + 6,
            height: widget.iconSize + 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hovered
                  ? base.withValues(alpha: 0.18)
                  : base.withValues(alpha: 0.09),
              border: Border.all(
                color: _hovered
                    ? base.withValues(alpha: 0.55)
                    : base.withValues(alpha: 0.25),
                width: 1.2,
              ),
            ),
            child: Center(
              child: Text(
                '?',
                style: TextStyle(
                  fontSize: widget.iconSize - 1,
                  fontWeight: FontWeight.w700,
                  color: _hovered ? base : base.withValues(alpha: 0.65),
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
