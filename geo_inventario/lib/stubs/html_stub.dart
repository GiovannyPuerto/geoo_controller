// Stub para plataformas no-web (Android, iOS, desktop).
// Las clases aquí nunca se ejecutan porque el código que las usa
// está siempre protegido por `if (kIsWeb)`.

class Blob {
  Blob(List<dynamic> parts, [dynamic options]);
}

class Url {
  static String createObjectUrlFromBlob(Blob blob) => '';
  static void revokeObjectUrl(String url) {}
}

class AnchorElement {
  AnchorElement({String? href});
  void setAttribute(String name, String value) {}
  void click() {}
}
