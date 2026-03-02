/// Diálogo de configuración de conexión al servidor backend.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:geo_inventario/services/config_service.dart';
import 'package:geo_inventario/theme/app_theme.dart';

class ServerSettingsDialog extends StatefulWidget {
  const ServerSettingsDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ServerSettingsDialog(),
    );
    return result ?? false;
  }

  @override
  State<ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<ServerSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  bool _saving = false;
  bool _testing = false;
  String? _connectionStatus;
  bool _connectionOk = false;

  @override
  void initState() {
    super.initState();
    final cfg = ConfigService.instance;
    _hostCtrl = TextEditingController(text: cfg.host);
    _portCtrl = TextEditingController(text: cfg.port.toString());
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  String get _previewUrl {
    final h = _hostCtrl.text.trim().isEmpty ? '...' : _hostCtrl.text.trim();
    final p = _portCtrl.text.trim().isEmpty ? '...' : _portCtrl.text.trim();
    return 'http://$h:$p/api/inventory';
  }

  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _connectionStatus = null;
    });
    try {
      final host = _hostCtrl.text.trim();
      final port = int.parse(_portCtrl.text.trim());
      final url = Uri.parse('http://$host:$port/api/inventory/resumen/');
      final response = await http.get(url, headers: {
        'Accept': 'application/json'
      }).timeout(const Duration(seconds: 6));
      if (mounted) {
        setState(() {
          _connectionOk =
              response.statusCode >= 200 && response.statusCode < 300;
          _connectionStatus = _connectionOk
              ? 'Conexion exitosa (HTTP ${response.statusCode}) checked'
              : 'El servidor respondio con codigo ${response.statusCode}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectionOk = false;
          _connectionStatus =
              'Sin respuesta: ${e.toString().replaceAll("Exception: ", "").split("\n").first}';
        });
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await ConfigService.instance.save(
      host: _hostCtrl.text.trim(),
      port: int.parse(_portCtrl.text.trim()),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  void _resetDefaults() {
    _hostCtrl.text = '127.0.0.1';
    _portCtrl.text = '8000';
    setState(() => _connectionStatus = null);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl)),
      clipBehavior: Clip.hardEdge,
      elevation: 8,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, minWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [_buildHeader(), _buildBody()],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(Icons.dns_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Configuracion del servidor',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                Text('IP y puerto del backend Django',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                color: Colors.white70, size: 20),
            onPressed: () => Navigator.of(context).pop(false),
            tooltip: 'Cancelar',
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(Icons.router_rounded, 'Direccion IP / Host'),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _hostCtrl,
              decoration: _inputDeco(
                  hint: 'ej.  192.168.1.100   o   127.0.0.1',
                  suffix: _pasteButton(_hostCtrl)),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'La direccion no puede estar vacia'
                  : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            _label(Icons.settings_ethernet_rounded, 'Puerto'),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _portCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _inputDeco(hint: 'ej.  8000'),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n < 1 || n > 65535) {
                  return 'Puerto invalido (1 - 65535)';
                }
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('URL resultante',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  SelectableText(_previewUrl,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.primary,
                          fontFamily: 'monospace')),
                ],
              ),
            ),
            if (_connectionStatus != null) ...[
              const SizedBox(height: AppSpacing.md),
              _StatusBanner(ok: _connectionOk, message: _connectionStatus!),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _saving ? null : _resetDefaults,
                  icon: const Icon(Icons.restore_rounded, size: 16),
                  label: const Text('Restablecer'),
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.textMuted),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: (_saving || _testing) ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary))
                      : const Icon(Icons.wifi_tethering_rounded, size: 16),
                  label: Text(_testing ? 'Probando...' : 'Probar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, size: 16),
                  label: const Text('Guardar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
        ],
      );

  Widget _pasteButton(TextEditingController ctrl) => IconButton(
        icon: const Icon(Icons.paste_rounded,
            size: 18, color: AppColors.textMuted),
        tooltip: 'Pegar del portapapeles',
        onPressed: () async {
          final data = await Clipboard.getData(Clipboard.kTextPlain);
          if (data?.text != null) ctrl.text = data!.text!.trim();
          setState(() {});
        },
      );

  InputDecoration _inputDeco({required String hint, Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textDisabled, fontSize: 13),
        filled: true,
        fillColor: AppColors.surfaceVariant,
        suffixIcon: suffix,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: const BorderSide(color: AppColors.primary, width: 2)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: const BorderSide(color: AppColors.error)),
      );
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.ok, required this.message});
  final bool ok;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      decoration: BoxDecoration(
        color: ok ? AppColors.successLight : AppColors.errorLight,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
            color: ok ? AppColors.accentLight : AppColors.errorLight),
      ),
      child: Row(
        children: [
          Icon(
              ok
                  ? Icons.check_circle_outline_rounded
                  : Icons.error_outline_rounded,
              size: 16,
              color: ok ? AppColors.accent : AppColors.error),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: TextStyle(
                      fontSize: 13,
                      color:
                          ok ? AppColors.successDark : AppColors.errorDark))),
        ],
      ),
    );
  }
}

/// Chip compacto en el AppBar que muestra la IP y puerto del servidor activo.
class ServerIndicatorChip extends StatelessWidget {
  const ServerIndicatorChip(
      {super.key, required this.host, required this.port});
  final String host;
  final int port;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
                color: AppColors.cyan, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$host:$port',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
