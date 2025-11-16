import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

Future<List<int>?> getFileBytesWeb(PlatformFile platformFile) async {
  return platformFile.bytes;
}

Future<http.MultipartFile> createMultipartFileWeb(
    String field, PlatformFile platformFile) async {
  if (platformFile.bytes == null) {
    throw Exception('File bytes are null for web platform.');
  }
  return http.MultipartFile.fromBytes(
    field,
    platformFile.bytes!,
    filename: platformFile.name,
  );
}
