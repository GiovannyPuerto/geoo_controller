import 'dart:io' as io;
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

Future<List<int>?> getFileBytes(PlatformFile platformFile) async {
  if (platformFile.path != null) {
    final file = io.File(platformFile.path!);
    return await file.readAsBytes();
  }
  return null;
}

Future<http.MultipartFile> createMultipartFile(
    String field, PlatformFile platformFile) async {
  if (platformFile.path != null) {
    final file = io.File(platformFile.path!);
    return await http.MultipartFile.fromPath(
      field,
      file.path,
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
