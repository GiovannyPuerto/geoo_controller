import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product.dart';
import '../models/inventory_record.dart';
import '../models/analysis_item.dart';

class ApiService {
  static const String baseUrl =
      'http://localhost:8000'; // Ajustar según la configuración

  // Product Analysis
  static Future<List<AnalysisItem>> getProductAnalysis({
    String inventoryName = 'default',
    String? warehouse,
    String? category,
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      final queryParams = {
        'inventory_name': inventoryName,
        if (warehouse != null && warehouse.isNotEmpty) 'warehouse': warehouse,
        if (category != null && category.isNotEmpty) 'category': category,
        if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
        if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
      };

      final uri = Uri.parse('$baseUrl/inventory/analysis/')
          .replace(queryParameters: queryParams);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => AnalysisItem.fromJson(item)).toList();
      } else {
        throw Exception(
            'Failed to load product analysis: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching product analysis: $e');
    }
  }

  // Summary
  static Future<Map<String, dynamic>> getSummary(
      {String inventoryName = 'default'}) async {
    try {
      final uri =
          Uri.parse('$baseUrl/inventory/summary/').replace(queryParameters: {
        'inventory_name': inventoryName,
      });
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load summary: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching summary: $e');
    }
  }

  // Batches
  static Future<List<Map<String, dynamic>>> getBatches(
      {String inventoryName = 'default'}) async {
    try {
      final uri =
          Uri.parse('$baseUrl/inventory/batches/').replace(queryParameters: {
        'inventory_name': inventoryName,
      });
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => item as Map<String, dynamic>).toList();
      } else {
        throw Exception('Failed to load batches: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching batches: $e');
    }
  }

  // Products
  static Future<List<Product>> getProducts(
      {String inventoryName = 'default'}) async {
    try {
      final uri =
          Uri.parse('$baseUrl/inventory/products/').replace(queryParameters: {
        'inventory_name': inventoryName,
      });
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => Product.fromJson(item)).toList();
      } else {
        throw Exception('Failed to load products: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching products: $e');
    }
  }

  // Records
  static Future<List<InventoryRecord>> getRecords({
    String inventoryName = 'default',
    String? warehouse,
    String? category,
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      final queryParams = {
        'inventory_name': inventoryName,
        if (warehouse != null && warehouse.isNotEmpty) 'warehouse': warehouse,
        if (category != null && category.isNotEmpty) 'category': category,
        if (dateFrom != null && dateFrom.isNotEmpty) 'date_from': dateFrom,
        if (dateTo != null && dateTo.isNotEmpty) 'date_to': dateTo,
      };

      final uri = Uri.parse('$baseUrl/inventory/records/')
          .replace(queryParameters: queryParams);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => InventoryRecord.fromJson(item)).toList();
      } else {
        throw Exception('Failed to load records: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching records: $e');
    }
  }

  // Product History
  static Future<List<Map<String, dynamic>>> getProductHistory(
    String productCode, {
    String inventoryName = 'default',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/inventory/products/$productCode/history/')
          .replace(queryParameters: {
        'inventory_name': inventoryName,
      });
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => item as Map<String, dynamic>).toList();
      } else {
        throw Exception(
            'Failed to load product history: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching product history: $e');
    }
  }

  // Create Inventory
  static Future<Map<String, dynamic>> createInventory() async {
    try {
      final uri = Uri.parse('$baseUrl/inventory/create/');
      final response = await http.post(uri);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to create inventory: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error creating inventory: $e');
    }
  }

  // List Inventories
  static Future<List<Map<String, dynamic>>> listInventories() async {
    try {
      final uri = Uri.parse('$baseUrl/inventory/list/');
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => item as Map<String, dynamic>).toList();
      } else {
        throw Exception('Failed to list inventories: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error listing inventories: $e');
    }
  }

  // Filter Options
  static Future<Map<String, dynamic>> getFilterOptions(
      {String inventoryName = 'default'}) async {
    try {
      final uri =
          Uri.parse('$baseUrl/inventory/filters/').replace(queryParameters: {
        'inventory_name': inventoryName,
      });
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(
            'Failed to load filter options: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching filter options: $e');
    }
  }

  // Upload Base File
  static Future<Map<String, dynamic>> uploadBaseFile(
    List<int> fileBytes,
    String fileName, {
    String inventoryName = 'default',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/inventory/upload-base/')
          .replace(queryParameters: {
        'inventory_name': inventoryName,
      });

      final request = http.MultipartRequest('POST', uri)
        ..files.add(http.MultipartFile.fromBytes('base_file', fileBytes,
            filename: fileName));

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        return json.decode(responseBody);
      } else {
        throw Exception(
            'Failed to upload base file: ${response.statusCode} - $responseBody');
      }
    } catch (e) {
      throw Exception('Error uploading base file: $e');
    }
  }

  // Update Inventory (Upload files)
  static Future<Map<String, dynamic>> updateInventory({
    List<int>? baseFileBytes,
    String? baseFileName,
    List<int>? updateFileBytes,
    String? updateFileName,
    String inventoryName = 'default',
  }) async {
    try {
      final uri =
          Uri.parse('$baseUrl/inventory/update/').replace(queryParameters: {
        'inventory_name': inventoryName,
      });

      final request = http.MultipartRequest('POST', uri);

      if (baseFileBytes != null && baseFileName != null) {
        request.files.add(http.MultipartFile.fromBytes(
            'base_file', baseFileBytes,
            filename: baseFileName));
      }

      if (updateFileBytes != null && updateFileName != null) {
        request.files.add(http.MultipartFile.fromBytes(
            'update_file', updateFileBytes,
            filename: updateFileName));
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        return json.decode(responseBody);
      } else {
        throw Exception(
            'Failed to update inventory: ${response.statusCode} - $responseBody');
      }
    } catch (e) {
      throw Exception('Error updating inventory: $e');
    }
  }
}