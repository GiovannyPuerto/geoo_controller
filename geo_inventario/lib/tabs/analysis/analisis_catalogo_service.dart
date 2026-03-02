import 'package:flutter/material.dart';
import 'package:geo_inventario/theme/app_theme.dart';

class AnalisisCatalogoService {
  static const Set<String> _gruposConocidos = {
    'AGROQUIMICOS-FERTILIZANTES Y ABONOS',
    'DOTACION Y SEGURIDAD',
    'MANTENIMIENTO',
    'MATERIAL DE EMPAQUE',
    'PAPELERIA Y ASEO',
  };

  static List<String> obtenerValoresUnicos(
    List<Map<String, dynamic>> analysis,
    String field,
  ) {
    Iterable<String> values = analysis
        .map((item) => item[field]?.toString() ?? '')
        .where((value) => value.isNotEmpty);

    if (field == 'grupo') {
      values = values.map(normalizarNombreGrupo);
    }

    return values.toSet().toList()..sort();
  }

  static String normalizarNombreGrupo(String groupCodeOrName) {
    if (_gruposConocidos.contains(groupCodeOrName)) {
      return groupCodeOrName;
    }

    switch (groupCodeOrName) {
      case '1':
        return 'AGROQUIMICOS-FERTILIZZANTES Y ABONOS';
      case '2':
        return 'DOTACION Y SEGURIDAD';
      case '3':
        return 'MANTENIMIENTO';
      case '4':
        return 'MATERIAL DE EMPAQUE';
      case '5':
        return 'PAPELERIA Y ASEO';
      default:
        if (groupCodeOrName.isNotEmpty) {
          return groupCodeOrName;
        }
        return 'SIN CATEGORÍA';
    }
  }

  static String nombreGrupoCorto(String fullName) {
    switch (fullName) {
      case 'AGROQUIMICOS-FERTILIZANTES Y ABONOS':
        return 'AGROQUIMICOS';
      case 'DOTACION Y SEGURIDAD':
        return 'DOTACION';
      case 'MANTENIMIENTO':
        return 'MANTENIMIENTO';
      case 'MATERIAL DE EMPAQUE':
        return 'EMPAQUE';
      case 'PAPELERIA Y ASEO':
        return 'PAPELERIA';
      default:
        return fullName;
    }
  }

  static Color colorRotacion(String rotation) {
    switch (rotation) {
      case 'Activo':
        return AppColors.chartPositive;
      case 'Estancado':
        return AppColors.chartCutFinal;
      case 'Obsoleto':
        return AppColors.chartNegative;
      case 'Inactivo':
        return AppColors.textMuted;
      default:
        return AppColors.textDisabled;
    }
  }
}
