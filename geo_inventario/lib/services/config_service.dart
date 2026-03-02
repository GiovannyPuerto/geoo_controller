/// Servicio de configuración de conexión al servidor.
/// Persiste IP y puerto usando shared_preferences para que sobrevivan
/// reinicios de la aplicación.
library;

import 'package:shared_preferences/shared_preferences.dart';

class ConfigService {
  ConfigService._();
  static final ConfigService instance = ConfigService._();

  static const String _keyHost = 'server_host';
  static const String _keyPort = 'server_port';

  static const String _defaultHost = '127.0.0.1';
  static const int _defaultPort = 8000;

  String _host = _defaultHost;
  int _port = _defaultPort;
  bool _loaded = false;

  /// URL base actual, usada por ApiService.
  String get baseUrl => 'http://$_host:$_port/api/inventory';

  /// URL raíz, usada para el historial de lotes en WelcomePage.
  String get rootUrl => 'http://$_host:$_port';

  String get host => _host;
  int get port => _port;

  /// Carga configuración almacenada.  Llamar una vez en main() antes de runApp.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _host = prefs.getString(_keyHost) ?? _defaultHost;
    _port = prefs.getInt(_keyPort) ?? _defaultPort;
    _loaded = true;
  }

  /// Persiste nueva configuración y actualiza los valores en memoria.
  Future<void> save({required String host, required int port}) async {
    _host = host.trim().isEmpty ? _defaultHost : host.trim();
    _port = (port < 1 || port > 65535) ? _defaultPort : port;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyHost, _host);
    await prefs.setInt(_keyPort, _port);
  }

  /// Devuelve a los valores por defecto.
  Future<void> reset() async {
    await save(host: _defaultHost, port: _defaultPort);
  }
}
