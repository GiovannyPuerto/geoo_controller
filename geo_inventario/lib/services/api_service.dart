import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geo_inventario/models/monthly_cut.dart';
import 'package:geo_inventario/models/monthly_product_cut.dart';
import 'package:geo_inventario/models/monthly_movement.dart';

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000/api/inventory';
  String _toIsoDate(DateTime date) => date.toIso8601String().split('T')[0];

  // Suamtoria endpoints
  Future<Map<String, dynamic>?> getSummary() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/summary/'),
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

      final uri =
          Uri.parse('$baseUrl/analysis/').replace(queryParameters: params);
      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      throw Exception('Error al obtener análisis: $e');
    }
  }

  // Endpoints de movimientos de inventario
  Future<List<Map<String, dynamic>>> getMovements({
    String? inventoryName,
    String? warehouse,
    String? category,
    String? search,
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
          Uri.parse('$baseUrl/records/').replace(queryParameters: params);
      final response = await http.get(
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

      final uri = Uri.parse('$baseUrl/monthly-movements/')
          .replace(queryParameters: params);
      final response = await http.get(
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

      final uri =
          Uri.parse('$baseUrl/monthly-cuts/').replace(queryParameters: params);
      final response = await http.get(
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

      final uri = Uri.parse('$baseUrl/monthly-cuts-products/')
          .replace(queryParameters: params);
      final response = await http.get(
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
      final response = await http.get(
        Uri.parse('$baseUrl/last-update/'),
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
      final response = await http.get(
        Uri.parse('$baseUrl/welcome/'),
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
          http.MultipartRequest('POST', Uri.parse('$baseUrl/upload-base/'));

      request.files.add(http.MultipartFile.fromBytes('base_file', fileBytes,
          filename: fileName));

      var streamedResponse =
          await request.send().timeout(const Duration(seconds: 60));
      var responseData = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
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
          http.MultipartRequest('POST', Uri.parse('$baseUrl/update/'));

      for (int i = 0; i < filesBytes.length; i++) {
        request.files.add(http.MultipartFile.fromBytes(
            'update_files', filesBytes[i],
            filename: fileNames[i]));
      }

      var response = await request.send();
      var responseData = await response.stream.bytesToString();

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

      final uri = Uri.parse('$baseUrl/export-analysis/')
          .replace(queryParameters: params);
      final response = await http.get(
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

      final uri = Uri.parse('$baseUrl/export-movements/')
          .replace(queryParameters: params);
      final response = await http.get(
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

      final uri = Uri.parse('$baseUrl/export-monthly-cuts/')
          .replace(queryParameters: params);
      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 60));

      return response;
    } catch (e) {
      throw Exception('Error al exportar cortes mensuales: $e');
    }
  }

  // Revertir último lote de actualización
  Future<Map<String, dynamic>> rollbackBatch({int? batchId}) async {
    try {
      final payload = <String, dynamic>{};
      if (batchId != null) {
        payload['batch_id'] = batchId;
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/rollback/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 30));

      final data = json.decode(response.body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      return {'ok': false, 'error': 'Error al revertir lote: $e'};
    }
  }

  // Obtener lotes de importación
  Future<List<Map<String, dynamic>>> getBatches() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/batches/'),
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
      final response = await http.get(
        Uri.parse('$baseUrl/products/'),
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
      final response = await http
          .post(
            Uri.parse('$baseUrl/create-inventory/'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'inventory_name': inventoryName}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
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
      final response = await http.get(
        Uri.parse('$baseUrl/product-history/$productCode/'),
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
      final response = await http.get(
        Uri.parse('$baseUrl/list-inventories/'),
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

      final uri = Uri.parse('$baseUrl/inventory-at-date/')
          .replace(queryParameters: params);
      final response = await http.get(
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
