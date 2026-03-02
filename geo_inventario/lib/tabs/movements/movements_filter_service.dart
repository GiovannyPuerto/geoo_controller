class MovementsFilterService {
  static List<String> obtenerValoresUnicos(
    List<Map<String, dynamic>> source,
    String field,
  ) {
    final values = source
        .map((item) => item[field]?.toString() ?? '')
        .where((value) => value.isNotEmpty);

    return values.toSet().toList()..sort();
  }

  static bool tieneFiltrosActivos({
    String? warehouse,
    String? group,
    String? search,
    DateTime? date,
  }) {
    return warehouse != null ||
        group != null ||
        (search != null && search.isNotEmpty) ||
        date != null;
  }
}
