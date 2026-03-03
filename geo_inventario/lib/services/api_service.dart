import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geo_inventario/models/monthly_cut.dart';
import 'package:geo_inventario/models/monthly_product_cut.dart';
import 'package:geo_inventario/models/monthly_movement.dart';
import 'package:geo_inventario/services/config_service.dart';

class ApiService {
  /// URL base dinámica: se obtiene de ConfigService en cada llamada.
  static String get baseUrl => ConfigService.instance.baseUrl;
  static const Duration _analysisCacheTtl = Duration(seconds: 20);
  static const int _analysisCacheMaxEntries = 64;
  static final http.Client _httpClient = http.Client();
  static final Map<String, _AnalysisCacheEntry> _analysisCache = {};
  static final Map<String, Future<List<Map<String, dynamic>>>>
      _analysisInFlight = {};

  String _toIsoDate(DateTime date) => date.toIso8601String().split('T')[0];

  String _buildAnalysisCacheKey(Map<String, String> params) {
    final ordered = params.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final qp = ordered.map((e) => '${e.key}=${e.value}').join('&');
    return '$baseUrl/analisis-producto/?$qp';
  }

  List<Map<String, dynamic>> _cloneAnalysisData(
      List<Map<String, dynamic>> data) {
    return data.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void _pruneAnalysisCache() {
    final now = DateTime.now();
    _analysisCache.removeWhere((_, entry) => entry.expiresAt.isBefore(now));

    if (_analysisCache.length <= _analysisCacheMaxEntries) return;

    final entries = _analysisCache.entries.toList()
      ..sort((a, b) => a.value.createdAt.compareTo(b.value.createdAt));
    final removeCount = _analysisCache.length - _analysisCacheMaxEntries;
    for (var i = 0; i < removeCount; i++) {
      _analysisCache.remove(entries[i].key);
    }
  }

  void _invalidateLocalCaches() {
    _analysisCache.clear();
    _analysisInFlight.clear();
  }

  // Suamtoria endpoints
  Future<Map<String, dynamic>?> getSummary() async {
    try {
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/resumen/'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      throw Exception('Error al cargar el resumen: $e');
    }
  }

  // Endpoints de análisis y movimientos
  Future<List<Map<String, dynamic>>> getAnalysis({
    String? warehouse,
    String? category,
    String? rotation,
    String? stagnant,
    String? highRotation,
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
    DateTime? specificDate,
  }) async {
    String cacheKey = '';
    try {
      final params = <String, String>{};
      if (warehouse != null && warehouse.isNotEmpty) {
        params['warehouse'] = warehouse;
      }
      if (category != null && category.isNotEmpty) {
        params['category'] = category;
      }
      if (rotation != null && rotation.isNotEmpty) {
        params['rotation'] = rotation;
      }
      if (stagnant != null && stagnant.isNotEmpty) {
        params['stagnant'] = stagnant;
      }
      if (highRotation != null && highRotation.isNotEmpty) {
        params['high_rotation'] = highRotation;
      }
      if (search != null && search.isNotEmpty) {
        params['search'] = search;
      }
      if (specificDate != null) {
        params['date'] = _toIsoDate(specificDate);
      } else {
        if (dateFrom != null) {
          params['date_from'] = _toIsoDate(dateFrom);
        }
        if (dateTo != null) {
          params['date_to'] = _toIsoDate(dateTo);
        }
      }

      cacheKey = _buildAnalysisCacheKey(params);
      _pruneAnalysisCache();
      final now = DateTime.now();
      final cached = _analysisCache[cacheKey];
      if (cached != null && cached.expiresAt.isAfter(now)) {
        return _cloneAnalysisData(cached.data);
      }

      final inFlight = _analysisInFlight[cacheKey];
      if (inFlight != null) {
        final shared = await inFlight;
        return _cloneAnalysisData(shared);
      }

      final uri = Uri.parse('$baseUrl/analisis-producto/')
          .replace(queryParameters: params);
      final requestFuture = () async {
        final response = await _httpClient.get(
          uri,
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body);
          final parsed = List<Map<String, dynamic>>.from(data);
          _analysisCache[cacheKey] = _AnalysisCacheEntry(
            data: parsed,
            createdAt: DateTime.now(),
            expiresAt: DateTime.now().add(_analysisCacheTtl),
          );
          _pruneAnalysisCache();
          return parsed;
        }
        return <Map<String, dynamic>>[];
      }();

      _analysisInFlight[cacheKey] = requestFuture;
      final resolved = await requestFuture;
      return _cloneAnalysisData(resolved);
    } catch (e) {
      throw Exception('Error al obtener análisis: $e');
    } finally {
      if (cacheKey.isNotEmpty) {
        _analysisInFlight.remove(cacheKey);
      }
    }
  }

  // Cortes promedio por producto en un rango libre de fechas
  Future<Map<String, dynamic>> getRangeProductCuts({
    required DateTime dateFrom,
    required DateTime dateTo,
    String? warehouse,
    String? category,
    String? search,
    String? inventoryName,
  }) async {
    try {
      final params = <String, String>{
        'date_from': _toIsoDate(dateFrom),
        'date_to': _toIsoDate(dateTo),
      };
      if (inventoryName != null && inventoryName.isNotEmpty) {
        params['inventory_name'] = inventoryName;
      }
      if (warehouse != null && warehouse.isNotEmpty) {
        params['warehouse'] = warehouse;
      }
      if (category != null && category.isNotEmpty) {
        params['category'] = category;
      }
      if (search != null && search.isNotEmpty) {
        params['search'] = search;
      }
      final uri = Uri.parse('$baseUrl/cortes-rango-productos/')
          .replace(queryParameters: params);
      final response = await _httpClient.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 45));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
        return {};
      }
      return {};
    } catch (e) {
      throw Exception('Error al obtener cortes de rango: $e');
    }
  }

  // Endpoints de movimientos de inventario
  Future<List<Map<String, dynamic>>> getMovements({
    String? inventoryName,
    String? warehouse,
    String? category,
    String? search,
    String? documentNumber,
    String? documentType,
    DateTime? dateFrom,
    DateTime? dateTo,
    DateTime? specificDate,
  }) async {
    try {
      final params = <String, String>{};
      if (inventoryName != null && inventoryName.isNotEmpty) {
        params['inventory_name'] = inventoryName;
      }
      if (warehouse != null && warehouse.isNotEmpty) {
        params['warehouse'] = warehouse;
      }
      if (category != null && category.isNotEmpty) {
        params['category'] = category;
      }
      if (search != null && search.isNotEmpty) {
        params['search'] = search;
      }
      if (documentNumber != null && documentNumber.isNotEmpty) {
        params['document_number'] = documentNumber;
      }
      if (documentType != null && documentType.isNotEmpty) {
        params['document_type'] = documentType;
      }
      if (specificDate != null) {
        params['date'] = _toIsoDate(specificDate);
      } else {
        if (dateFrom != null) {
          params['date_from'] = _toIsoDate(dateFrom);
        }
        if (dateTo != null) {
          params['date_to'] = _toIsoDate(dateTo);
        }
      }
      final uri =
          Uri.parse('$baseUrl/registros/').replace(queryParameters: params);
      final response = await _httpClient.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      throw Exception('Error al obtener movimientos: $e');
    }
  }

  // Movimientos mensuales para gráfica
  Future<List<MonthlyMovement>> getMonthlyMovements({
    String? warehouse,
    String? category,
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
    DateTime? specificDate,
  }) async {
    try {
      final params = <String, String>{};
      if (warehouse != null && warehouse.isNotEmpty) {
        params['warehouse'] = warehouse;
      }
      if (category != null && category.isNotEmpty) {
        params['category'] = category;
      }
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (specificDate != null) {
        params['date'] = _toIsoDate(specificDate);
      } else {
        if (dateFrom != null) {
          params['date_from'] = _toIsoDate(dateFrom);
        }
        if (dateTo != null) {
          params['date_to'] = _toIsoDate(dateTo);
        }
      }

      final uri = Uri.parse('$baseUrl/movimientos-mensuales/')
          .replace(queryParameters: params);
      final response = await _httpClient.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => MonthlyMovement.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      throw Exception('Error al obtener movimientos mensuales: $e');
    }
  }

  // Cortes mensuales promediados
  Future<Map<String, dynamic>> getMonthlyCuts({
    String? warehouse,
    String? category,
    String? search,
    int months = 12,
  }) async {
    try {
      final params = <String, String>{'months': months.toString()};
      if (warehouse != null && warehouse.isNotEmpty) {
        params['warehouse'] = warehouse;
      }
      if (category != null && category.isNotEmpty) {
        params['category'] = category;
      }
      if (search != null && search.isNotEmpty) {
        params['search'] = search;
      }

      final uri = Uri.parse('$baseUrl/cortes-mensuales/')
          .replace(queryParameters: params);
      final response = await _httpClient.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final raw = json.decode(response.body) as Map<String, dynamic>;
        final rows = (raw['months'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MonthlyCut.fromJson)
            .toList();
        return {
          'months': rows,
          'period_average_general':
              ((raw['period_average_general'] as num?) ?? 0).toDouble(),
          'period_average_per_product':
              ((raw['period_average_per_product'] as num?) ?? 0).toDouble(),
          'products_count': (raw['products_count'] as int?) ?? 0,
          'months_count': (raw['months_count'] as int?) ?? rows.length,
        };
      }

      return {
        'months': <MonthlyCut>[],
        'period_average_general': 0.0,
        'period_average_per_product': 0.0,
        'products_count': 0,
        'months_count': 0,
      };
    } catch (e) {
      throw Exception('Error al obtener cortes mensuales: $e');
    }
  }

  // Corte mensual promedio por producto (inventario del mes)
  Future<Map<String, dynamic>> getMonthlyProductCuts({
    String? warehouse,
    String? category,
    String? search,
    String? month,
    int limit = 5000,
  }) async {
    try {
      final params = <String, String>{'limit': limit.toString()};
      if (warehouse != null && warehouse.isNotEmpty) {
        params['warehouse'] = warehouse;
      }
      if (category != null && category.isNotEmpty) {
        params['category'] = category;
      }
      if (search != null && search.isNotEmpty) {
        params['search'] = search;
      }
      if (month != null && month.isNotEmpty) {
        params['month'] = month;
      }

      final uri = Uri.parse('$baseUrl/cortes-mensuales-productos/')
          .replace(queryParameters: params);
      final response = await _httpClient.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final raw = json.decode(response.body) as Map<String, dynamic>;
        final products = (raw['products'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MonthlyProductCut.fromJson)
            .toList();
        final rawTotals = (raw['totals'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};

        return {
          'month': (raw['month'] ?? '').toString(),
          'month_start': (raw['month_start'] ?? '').toString(),
          'month_end': (raw['month_end'] ?? '').toString(),
          'products': products,
          'products_count':
              ((raw['products_count'] as num?) ?? products.length).toInt(),
          'totals': {
            'opening_quantity':
                ((rawTotals['opening_quantity'] as num?) ?? 0).toDouble(),
            'closing_quantity':
                ((rawTotals['closing_quantity'] as num?) ?? 0).toDouble(),
            'average_quantity':
                ((rawTotals['average_quantity'] as num?) ?? 0).toDouble(),
            'opening_value':
                ((rawTotals['opening_value'] as num?) ?? 0).toDouble(),
            'closing_value':
                ((rawTotals['closing_value'] as num?) ?? 0).toDouble(),
            'average_value':
                ((rawTotals['average_value'] as num?) ?? 0).toDouble(),
          },
          'truncated': raw['truncated'] == true,
          'limit': ((raw['limit'] as num?) ?? limit).toInt(),
        };
      }

      return {
        'month': '',
        'month_start': '',
        'month_end': '',
        'products': <MonthlyProductCut>[],
        'products_count': 0,
        'totals': {
          'opening_quantity': 0.0,
          'closing_quantity': 0.0,
          'average_quantity': 0.0,
          'opening_value': 0.0,
          'closing_value': 0.0,
          'average_value': 0.0,
        },
        'truncated': false,
        'limit': limit,
      };
    } catch (e) {
      throw Exception('Error al obtener corte mensual por producto: $e');
    }
  }

  // Última actualización
  Future<String?> getLastUpdateTime() async {
    try {
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/ultima-actualizacion/'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['last_update'] != null) {
          final dateTime = DateTime.parse(data['last_update']);
          return dateTime.toLocal().toString();
        }
      }
      return 'No se ha actualizado';
    } catch (e) {
      return 'Error';
    }
  }

  // Mensaje de bienvenida para pruebas de conexion
  Future<String?> getWelcomeMessage() async {
    try {
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/bienvenida/'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['message'] ?? 'Bienvenido al dashboard de inventario!';
      }
      return 'Bienvenido al dashboard de inventario!';
    } catch (e) {
      return 'Bienvenido al dashboard de inventario!';
    }
  }

  // Endpoint de importacion de archivos de actualizacion y base, exportacion de analisis y movimientos
  Future<Map<String, dynamic>> uploadBaseFile(
      List<int> fileBytes, String fileName) async {
    try {
      var request =
          http.MultipartRequest('POST', Uri.parse('$baseUrl/subir-base/'));

      request.files.add(http.MultipartFile.fromBytes('base_file', fileBytes,
          filename: fileName));

      var streamedResponse =
          await request.send().timeout(const Duration(seconds: 60));
      var responseData = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        _invalidateLocalCaches();
        try {
          final jsonResponse = json.decode(responseData);
          return {
            'statusCode': streamedResponse.statusCode,
            'body': responseData,
            'ok': jsonResponse['ok'] ?? false,
            'message': jsonResponse['message'] ?? '',
            'error': jsonResponse['error'] ?? '',
            'summary': jsonResponse['summary'],
          };
        } catch (e) {
          // Si la respuesta no es en json o no tiene el formato esperado, devolvemos un error genérico
          return {
            'statusCode': streamedResponse.statusCode,
            'body': responseData,
            'ok': false,
            'message': responseData,
            'error': 'Formato de respuesta inválido',
          };
        }
      } else {
        try {
          final jsonResponse = json.decode(responseData);
          return {
            'statusCode': streamedResponse.statusCode,
            'body': responseData,
            'ok': jsonResponse['ok'] ?? false,
            'message': jsonResponse['message'] ?? '',
            'error': jsonResponse['error'] ?? 'Error del servidor',
            'summary': jsonResponse['summary'],
          };
        } catch (e) {
          return {
            'statusCode': streamedResponse.statusCode,
            'body': responseData,
            'ok': false,
            'message': '',
            'error': 'Error: ${streamedResponse.statusCode}',
          };
        }
      }
    } catch (e) {
      return {
        'statusCode': 0,
        'body': '',
        'ok': false,
        'message': '',
        'error': 'Error de conexión: $e',
      };
    }
  }

  Future<Map<String, dynamic>> uploadUpdateFiles(
      List<List<int>> filesBytes, List<String> fileNames) async {
    try {
      var request =
          http.MultipartRequest('POST', Uri.parse('$baseUrl/actualizar/'));

      for (int i = 0; i < filesBytes.length; i++) {
        request.files.add(http.MultipartFile.fromBytes(
            'update_files', filesBytes[i],
            filename: fileNames[i]));
      }

      var response = await request.send();
      var responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        _invalidateLocalCaches();
      }

      return {
        'statusCode': response.statusCode,
        'body': responseData,
      };
    } catch (e) {
      throw Exception('Error al subir archivos de actualización: $e');
    }
  }

  // Exportar análisis
  Future<http.Response> exportAnalysis({
    String format = 'excel',
    String? warehouse,
    String? category,
    String? rotation,
    String? stagnant,
    String? highRotation,
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
    DateTime? specificDate,
  }) async {
    try {
      final params = <String, String>{'format': format};
      if (warehouse != null && warehouse.isNotEmpty) {
        params['warehouse'] = warehouse;
      }

      if (category != null && category.isNotEmpty) {
        params['category'] = category;
      }
      if (rotation != null && rotation.isNotEmpty) {
        params['rotation'] = rotation;
      }
      if (stagnant != null && stagnant.isNotEmpty) {
        params['stagnant'] = stagnant;
      }
      if (highRotation != null && highRotation.isNotEmpty) {
        params['high_rotation'] = highRotation;
      }
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (specificDate != null) {
        params['date'] = _toIsoDate(specificDate);
      } else {
        if (dateFrom != null) {
          params['date_from'] = _toIsoDate(dateFrom);
        }

        if (dateTo != null) {
          params['date_to'] = _toIsoDate(dateTo);
        }
      }

      final uri = Uri.parse('$baseUrl/exportar-analisis/')
          .replace(queryParameters: params);
      final response = await _httpClient.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 60));

      return response;
    } catch (e) {
      throw Exception('Error al exportar análisis: $e');
    }
  }

  // Exportar movimientos
  Future<http.Response> exportMovements({
    String format = 'excel',
    String? warehouse,
    String? category,
    String? search,
    String? documentType,
    DateTime? dateFrom,
    DateTime? dateTo,
    DateTime? specificDate,
  }) async {
    try {
      final params = <String, String>{'format': format};
      if (warehouse != null && warehouse.isNotEmpty) {
        params['warehouse'] = warehouse;
      }
      if (category != null && category.isNotEmpty) {
        params['category'] = category;
      }
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (documentType != null && documentType.isNotEmpty) {
        params['document_type'] = documentType;
      }
      if (specificDate != null) {
        params['date'] = _toIsoDate(specificDate);
      } else {
        if (dateFrom != null) {
          params['date_from'] = _toIsoDate(dateFrom);
        }
        if (dateTo != null) {
          params['date_to'] = _toIsoDate(dateTo);
        }
      }

      final uri = Uri.parse('$baseUrl/exportar-movimientos/')
          .replace(queryParameters: params);
      final response = await _httpClient.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 60));

      return response;
    } catch (e) {
      throw Exception('Error al exportar movimientos: $e');
    }
  }

  // Exportar cortes mensuales
  Future<http.Response> exportMonthlyCuts({
    String format = 'excel',
    String? warehouse,
    String? category,
    String? search,
    int months = 12,
    String? month,
    int productLimit = 5000,
  }) async {
    try {
      final params = <String, String>{
        'format': format,
        'months': months.toString(),
        'product_limit': productLimit.toString(),
      };
      if (warehouse != null && warehouse.isNotEmpty) {
        params['warehouse'] = warehouse;
      }
      if (category != null && category.isNotEmpty) {
        params['category'] = category;
      }
      if (search != null && search.isNotEmpty) {
        params['search'] = search;
      }
      if (month != null && month.isNotEmpty) {
        params['month'] = month;
      }

      final uri = Uri.parse('$baseUrl/exportar-cortes-mensuales/')
          .replace(queryParameters: params);
      final response = await _httpClient.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 60));

      return response;
    } catch (e) {
      throw Exception('Error al exportar cortes mensuales: $e');
    }
  }

  // Exportar tops
  Future<http.Response> exportTops({
    String format = 'excel',
    String? warehouse,
    String? category,
    String? rotation,
    String? group,
    String? search,
    int top = 30,
    DateTime? cutoffDate,
    DateTime? movementDateFrom,
    DateTime? movementDateTo,
  }) async {
    try {
      final params = <String, String>{
        'format': format,
        'top': top.toString(),
      };
      if (warehouse != null && warehouse.isNotEmpty) {
        params['warehouse'] = warehouse;
      }
      if (category != null && category.isNotEmpty) {
        params['category'] = category;
      }
      if (rotation != null && rotation.isNotEmpty) {
        params['rotation'] = rotation;
      }
      if (group != null && group.isNotEmpty) {
        params['group'] = group;
      }
      if (search != null && search.isNotEmpty) {
        params['search'] = search;
      }
      if (cutoffDate != null) {
        params['date'] = _toIsoDate(cutoffDate);
      }
      if (movementDateFrom != null) {
        params['movement_date_from'] = _toIsoDate(movementDateFrom);
      }
      if (movementDateTo != null) {
        params['movement_date_to'] = _toIsoDate(movementDateTo);
      }

      final uri =
          Uri.parse('$baseUrl/exportar-tops/').replace(queryParameters: params);
      final response = await _httpClient.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 60));

      return response;
    } catch (e) {
      throw Exception('Error al exportar tops: $e');
    }
  }

  // Revertir último lote de actualización
  Future<Map<String, dynamic>> rollbackBatch({int? batchId}) async {
    try {
      final payload = <String, dynamic>{};
      if (batchId != null) {
        payload['batch_id'] = batchId;
      }

      final response = await _httpClient
          .post(
            Uri.parse('$baseUrl/revertir-lote/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 30));

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _invalidateLocalCaches();
      }
      return data;
    } catch (e) {
      return {'ok': false, 'error': 'Error al revertir lote: $e'};
    }
  }

  // Obtener lotes de importación
  Future<List<Map<String, dynamic>>> getBatches() async {
    try {
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/lotes/'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      throw Exception('Error al obtener lotes de importación: $e');
    }
  }

  // Obtenemos productos
  Future<List<Map<String, dynamic>>> getProducts() async {
    try {
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/productos/'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      throw Exception('Error loading products: $e');
    }
  }

  // Crear inventario
  Future<Map<String, dynamic>> createInventory(String inventoryName) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$baseUrl/crear-inventario/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'inventory_name': inventoryName}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        _invalidateLocalCaches();
        return json.decode(response.body);
      }
      return {'ok': false, 'error': 'Failed to create inventory'};
    } catch (e) {
      return {'ok': false, 'error': 'Connection error: $e'};
    }
  }

  // Obtener historial de producto
  Future<List<Map<String, dynamic>>> getProductHistory(
      String productCode) async {
    try {
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/producto/$productCode/historial/'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      throw Exception('Error al obtener historial de producto: $e');
    }
  }

  // Listar inventarios
  Future<List<String>> listInventories() async {
    try {
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/inventarios/'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return List<String>.from(data);
      }
      return [];
    } catch (e) {
      throw Exception('Error al listar inventarios de base de datos: $e');
    }
  }

  // Obtener inventario en una fecha específica
  Future<List<Map<String, dynamic>>> getInventoryAtDate(DateTime date) async {
    try {
      final params = <String, String>{'date': _toIsoDate(date)};

      final uri = Uri.parse('$baseUrl/inventario-a-fecha/')
          .replace(queryParameters: params);
      final response = await _httpClient.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> products = data['products'] ?? [];
        return List<Map<String, dynamic>>.from(products);
      }
      return [];
    } catch (e) {
      throw Exception(
          'Error al obtener inventario en una fecha específica: $e');
    }
  }
}

class _AnalysisCacheEntry {
  _AnalysisCacheEntry({
    required this.data,
    required this.createdAt,
    required this.expiresAt,
  });

  final List<Map<String, dynamic>> data;
  final DateTime createdAt;
  final DateTime expiresAt;
}
