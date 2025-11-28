import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geo_inventario/models/monthly_movement.dart';

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000/api/inventory';

  // Summary endpoints
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
      throw Exception('Error loading summary: $e');
    }
  }

  // Analysis endpoints
  Future<List<Map<String, dynamic>>> getAnalysis({
    String? warehouse,
    String? category,
    String? rotation,
    String? stagnant,
    String? highRotation,
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      final params = <String, String>{};
      if (warehouse != null && warehouse.isNotEmpty)
        params['warehouse'] = warehouse;
      if (category != null && category.isNotEmpty)
        params['category'] = category;
      if (rotation != null && rotation.isNotEmpty)
        params['rotation'] = rotation;
      if (stagnant != null && stagnant.isNotEmpty)
        params['stagnant'] = stagnant;
      if (highRotation != null && highRotation.isNotEmpty)
        params['high_rotation'] = highRotation;
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (dateFrom != null)
        params['date_from'] = dateFrom.toIso8601String().split('T')[0];
      if (dateTo != null)
        params['date_to'] = dateTo.toIso8601String().split('T')[0];

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
      throw Exception('Error loading analysis: $e');
    }
  }

  // Movements endpoints
  Future<List<Map<String, dynamic>>> getMovements({
    String? inventoryName,
    String? warehouse,
    String? category,
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      final params = <String, String>{};
      if (inventoryName != null && inventoryName.isNotEmpty)
        params['inventory_name'] = inventoryName;
      if (warehouse != null && warehouse.isNotEmpty)
        params['warehouse'] = warehouse;
      if (category != null && category.isNotEmpty)
        params['category'] = category;
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (dateFrom != null)
        params['date_from'] = dateFrom.toIso8601String().split('T')[0];
      if (dateTo != null)
        params['date_to'] = dateTo.toIso8601String().split('T')[0];

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
      throw Exception('Error loading movements: $e');
    }
  }

  // Monthly movements
  Future<List<MonthlyMovement>> getMonthlyMovements({
    String? warehouse,
    String? category,
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      final params = <String, String>{};
      if (warehouse != null && warehouse.isNotEmpty)
        params['warehouse'] = warehouse;
      if (category != null && category.isNotEmpty)
        params['category'] = category;
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (dateFrom != null)
        params['date_from'] = dateFrom.toIso8601String().split('T')[0];
      if (dateTo != null)
        params['date_to'] = dateTo.toIso8601String().split('T')[0];

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
      throw Exception('Error loading monthly movements: $e');
    }
  }

  // Last update time
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

  // Get welcome message
  Future<String?> getWelcomeMessage() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/welcome/'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['message'] ?? 'Welcome to the Inventory Dashboard!';
      }
      return 'Welcome to the Inventory Dashboard!';
    } catch (e) {
      return 'Welcome to the Inventory Dashboard!';
    }
  }

  // File upload endpoints
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
          };
        } catch (e) {
          // If response is not JSON, return raw response
          return {
            'statusCode': streamedResponse.statusCode,
            'body': responseData,
            'ok': false,
            'message': responseData,
            'error': 'Invalid response format',
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
        'error': 'Connection error: $e',
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
      throw Exception('Error uploading update files: $e');
    }
  }

  // Export analysis data
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
  }) async {
    try {
      final params = <String, String>{'format': format};
      if (warehouse != null && warehouse.isNotEmpty)
        params['warehouse'] = warehouse;
      if (category != null && category.isNotEmpty)
        params['category'] = category;
      if (rotation != null && rotation.isNotEmpty)
        params['rotation'] = rotation;
      if (stagnant != null && stagnant.isNotEmpty)
        params['stagnant'] = stagnant;
      if (highRotation != null && highRotation.isNotEmpty)
        params['high_rotation'] = highRotation;
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (dateFrom != null)
        params['date_from'] = dateFrom.toIso8601String().split('T')[0];
      if (dateTo != null)
        params['date_to'] = dateTo.toIso8601String().split('T')[0];

      final uri = Uri.parse('$baseUrl/export-analysis/')
          .replace(queryParameters: params);
      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 60));

      return response;
    } catch (e) {
      throw Exception('Error exporting analysis: $e');
    }
  }

  // Export movements data
  Future<http.Response> exportMovements({
    String format = 'excel',
    String? warehouse,
    String? category,
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      final params = <String, String>{'format': format};
      if (warehouse != null && warehouse.isNotEmpty)
        params['warehouse'] = warehouse;
      if (category != null && category.isNotEmpty)
        params['category'] = category;
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (dateFrom != null)
        params['date_from'] = dateFrom.toIso8601String().split('T')[0];
      if (dateTo != null)
        params['date_to'] = dateTo.toIso8601String().split('T')[0];

      final uri = Uri.parse('$baseUrl/export-movements/')
          .replace(queryParameters: params);
      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 60));

      return response;
    } catch (e) {
      throw Exception('Error exporting movements: $e');
    }
  }

  // Get import batches
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
      throw Exception('Error loading batches: $e');
    }
  }

  // Get products
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

  // Create inventory
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

  // Get product history
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
      throw Exception('Error loading product history: $e');
    }
  }

  // List inventories
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
      throw Exception('Error loading inventories: $e');
    }
  }
}
