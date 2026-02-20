import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:geo_inventario/platform_file_picker.dart';
import 'package:geo_inventario/services/api_service.dart';

class UploadOperationResult {
  final bool ok;
  final String message;
  final String? error;
  final int? statusCode;
  final Map<String, dynamic>? summary;

  const UploadOperationResult({
    required this.ok,
    required this.message,
    this.error,
    this.statusCode,
    this.summary,
  });
}

class ExcelUploadService {
  final ApiService _apiService;
  final PlatformFilePicker _picker;

  ExcelUploadService({
    ApiService? apiService,
    PlatformFilePicker? picker,
  })  : _apiService = apiService ?? ApiService(),
        _picker = picker ?? getPlatformFilePicker();

  String _buildBaseSuccessMessage(Map<String, dynamic> jsonResponse) {
    final summary = (jsonResponse['summary'] is Map<String, dynamic>)
        ? jsonResponse['summary'] as Map<String, dynamic>
        : <String, dynamic>{};

    final registered = (summary['base_records'] ?? summary['total_processed'] ?? 0)
        .toString();
    final repeated = (summary['duplicates_base'] ?? 0).toString();

    return 'Carga base completada: $registered registrados, '
        '$repeated repetidos.';
  }

  String _buildUpdateSuccessMessage(Map<String, dynamic> jsonResponse) {
    final summary = (jsonResponse['summary'] is Map<String, dynamic>)
        ? jsonResponse['summary'] as Map<String, dynamic>
        : <String, dynamic>{};

    final registered =
        (summary['update_registered_records'] ?? summary['update_records'] ?? 0)
            .toString();
    final repeated =
        (summary['update_repeated_records'] ?? summary['duplicates_update'] ?? 0)
            .toString();

    final files = (summary['update_files'] is List)
        ? summary['update_files'] as List
        : const [];

    if (files.isNotEmpty) {
      return 'Actualización completada: $registered registrados, '
          '$repeated repetidos (${files.length} archivo(s)).';
    }

    return 'Actualización completada: $registered registrados, '
        '$repeated repetidos.';
  }

  Future<FilePickerResult?> pickBaseFile() {
    return _picker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
  }

  Future<FilePickerResult?> pickUpdateFiles() {
    return _picker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      allowMultiple: true,
    );
  }

  Future<UploadOperationResult> uploadBaseFile(PlatformFile file) async {
    try {
      final fileBytes = file.bytes?.toList() ?? await getFileBytes(file);
      if (fileBytes == null || fileBytes.isEmpty) {
        return const UploadOperationResult(
          ok: false,
          message: '',
          error: 'No se pudo leer el archivo seleccionado.',
        );
      }

      final response = await _apiService.uploadBaseFile(fileBytes, file.name);
      final ok = response['ok'] == true;
      final summary = response['summary'] is Map<String, dynamic>
          ? response['summary'] as Map<String, dynamic>
          : null;
      final fallbackMessage = ok
          ? _buildBaseSuccessMessage({
              'summary': summary,
            })
          : 'Error al cargar el archivo';

      final rawMessage = (response['message'] ?? '').toString().trim();

      return UploadOperationResult(
        ok: ok,
        message: rawMessage.isNotEmpty ? rawMessage : (ok ? fallbackMessage : ''),
        error: ok
            ? null
            : (response['error'] ?? 'Error al cargar el archivo').toString(),
        statusCode: response['statusCode'] as int?,
        summary: summary,
      );
    } catch (e) {
      return UploadOperationResult(
        ok: false,
        message: '',
        error: 'Error de conexión: $e',
      );
    }
  }

  Future<UploadOperationResult> uploadUpdateFiles(
      List<PlatformFile> files) async {
    try {
      if (files.isEmpty) {
        return const UploadOperationResult(
          ok: false,
          message: '',
          error: 'No se seleccionaron archivos de actualización.',
        );
      }

      final filesBytes = <List<int>>[];
      final fileNames = <String>[];

      for (final file in files) {
        final bytes = file.bytes?.toList() ?? await getFileBytes(file);
        if (bytes == null || bytes.isEmpty) {
          return UploadOperationResult(
            ok: false,
            message: '',
            error: 'No se pudo leer el archivo ${file.name}.',
          );
        }
        filesBytes.add(bytes);
        fileNames.add(file.name);
      }

      final response =
          await _apiService.uploadUpdateFiles(filesBytes, fileNames);
      final rawBody = (response['body'] ?? '').toString();

      try {
        final jsonResponse = json.decode(rawBody) as Map<String, dynamic>;
        final ok = jsonResponse['ok'] == true;
        final successMessage = _buildUpdateSuccessMessage(jsonResponse);
        final summary = jsonResponse['summary'] is Map<String, dynamic>
            ? jsonResponse['summary'] as Map<String, dynamic>
            : null;
        final rawMessage = (jsonResponse['message'] ?? '').toString().trim();
        return UploadOperationResult(
          ok: ok,
          message: rawMessage.isNotEmpty
              ? rawMessage
              : (ok ? successMessage : 'Error al procesar archivos'),
          error: ok
              ? null
              : (jsonResponse['error'] ?? 'Error al procesar archivos')
                  .toString(),
          statusCode: response['statusCode'] as int?,
          summary: summary,
        );
      } catch (_) {
        final statusCode = response['statusCode'] as int?;
        final ok = statusCode == 200;
        return UploadOperationResult(
          ok: ok,
          message: ok ? rawBody : '',
          error: ok
              ? null
              : (rawBody.isNotEmpty ? rawBody : 'Error al procesar archivos'),
          statusCode: statusCode,
          summary: null,
        );
      }
    } catch (e) {
      return UploadOperationResult(
        ok: false,
        message: '',
        error: 'Error de conexión: $e',
      );
    }
  }
}
