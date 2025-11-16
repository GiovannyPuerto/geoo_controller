import 'dart:io' as io;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:geo_inventario/file_platform_web.dart';
import 'package:http/http.dart' as http;

// Conditional imports for platform-specific file handling
import 'file_platform_io.dart' if (dart.library.html) 'file_platform_web.dart';

// Abstract class to define the interface for file picking
abstract class PlatformFilePicker {
  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  });
}

// Web implementation
class WebFilePicker implements PlatformFilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  }) async {
    return await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
    );
  }
}

// Mobile/Desktop implementation
class IOFilePicker implements PlatformFilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  }) async {
    return await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
    );
  }
}

// Factory to get the correct file picker implementation
PlatformFilePicker getPlatformFilePicker() {
  if (kIsWeb) {
    return WebFilePicker();
  } else {
    return IOFilePicker();
  }
}

// Helper function to get file bytes or path based on platform
Future<List<int>?> getFileBytes(PlatformFile platformFile) async {
  if (kIsWeb) {
    return getFileBytesWeb(platformFile);
  } else {
    if (platformFile.path != null) {
      final file = io.File(platformFile.path!);
      return await file.readAsBytes();
    }
    return null;
  }
}

// Helper function to create MultipartFile based on platform
Future<http.MultipartFile> createMultipartFile(
    String field, PlatformFile platformFile) async {
  if (kIsWeb) {
    return createMultipartFileWeb(field, platformFile);
  } else {
    // IO platform implementation
    if (platformFile.path != null) {
      // Use fromPath for better memory efficiency with large files
      return await http.MultipartFile.fromPath(
        field,
        platformFile.path!,
        filename: platformFile.name,
      );
    } else if (platformFile.bytes != null) {
      return http.MultipartFile.fromBytes(
        field,
        platformFile.bytes!,
        filename: platformFile.name,
      );
    } else {
      throw Exception('No file path or bytes available for IO platform.');
    }
  }
}
