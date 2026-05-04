import 'package:flutter/material.dart';

abstract final class OccurrenceDynamicRows {
  static Map<String, dynamic> drug({
    String type = 'Maconha',
    String amount = '',
    String specify = '',
  }) {
    return {
      'tipo': type,
      'quantidade': TextEditingController(text: amount),
      'especificar': TextEditingController(text: specify),
    };
  }

  static Map<String, dynamic> detainedIndividual({String amount = ''}) {
    return {'quantidade': TextEditingController(text: amount)};
  }

  static Map<String, dynamic> seizedObject({
    String description = '',
    String amount = '',
  }) {
    return {
      'descricao': TextEditingController(text: description),
      'quantidade': TextEditingController(text: amount),
    };
  }

  static Map<String, dynamic> detainedVehicle({
    String type = '',
    String plate = '',
  }) {
    return {
      'tipo': TextEditingController(text: type),
      'placa': TextEditingController(text: plate),
    };
  }

  static List<Map<String, dynamic>> hydrateDetainedIndividuals(dynamic rows) {
    return _asList(rows)
        .map(
          (data) =>
              detainedIndividual(amount: data['quantidade']?.toString() ?? ''),
        )
        .toList();
  }

  static List<Map<String, dynamic>> hydrateSeizedObjects(dynamic rows) {
    return _asList(rows)
        .map(
          (data) => seizedObject(
            description: data['descricao']?.toString() ?? '',
            amount: data['quantidade']?.toString() ?? '',
          ),
        )
        .toList();
  }

  static List<Map<String, dynamic>> hydrateDrugs(
    dynamic rows, {
    required List<String> knownOptions,
  }) {
    return _asList(rows).map((data) {
      final rawType = data['tipo']?.toString() ?? '';
      final knownType = knownOptions.contains(rawType);
      return drug(
        type: knownType ? rawType : 'Outros',
        amount: data['quantidade']?.toString() ?? '',
        specify: knownType ? '' : rawType,
      );
    }).toList();
  }

  static List<Map<String, dynamic>> hydrateDetainedVehicles(dynamic rows) {
    return _asList(rows)
        .map(
          (data) => detainedVehicle(
            type: data['tipo']?.toString() ?? '',
            plate: data['placa']?.toString() ?? '',
          ),
        )
        .toList();
  }

  static void disposeRows(
    List<Map<String, dynamic>> rows,
    List<String> controllerKeys,
  ) {
    for (final row in rows) {
      for (final key in controllerKeys) {
        row[key]?.dispose();
      }
    }
  }

  static void disposeDrugs(List<Map<String, dynamic>> rows) {
    disposeRows(rows, ['quantidade', 'especificar']);
  }

  static List<Map<String, dynamic>> _asList(dynamic rows) {
    if (rows is! List) return const [];
    return rows
        .map<Map<String, dynamic>>(
          (row) => row is Map ? Map<String, dynamic>.from(row) : {},
        )
        .toList();
  }
}
