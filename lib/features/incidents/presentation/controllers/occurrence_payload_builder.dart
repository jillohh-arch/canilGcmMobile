import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'occurrence_form_controller.dart';

class OccurrencePayloadBuilder {
  static Incident buildIncident({
    required String? documentId,
    required String dogId,
    required String dogName,
    required String handlerId,
    required DateTime startedAt,
    required DateTime updatedAt,
    required String location,
    required String description,
    required String result,
    required String? type,
    required Map<String, dynamic> extraFields,
    required List<Map<String, dynamic>> mediaAttachments,
    required String status,
    required bool? operationalSuccess,
    required List<String> outcomes,
    required List<IncidentProgressUpdate> progressUpdates,
  }) {
    return Incident(
      id: documentId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      dogId: dogId,
      dogName: dogName,
      handlerId: handlerId,
      date: startedAt,
      location: location.trim().isNotEmpty ? location.trim() : 'GCM',
      description: description.trim(),
      result: result,
      type: type,
      extraFields: extraFields.isNotEmpty ? extraFields : null,
      mediaAttachments: mediaAttachments.isNotEmpty ? mediaAttachments : null,
      status: status,
      operationalSuccess: operationalSuccess,
      outcomes: outcomes,
      startedAt: startedAt,
      endedAt:
          status == OccurrenceFormController.statusCompleted ||
              status == OccurrenceFormController.statusCanceled
          ? updatedAt
          : null,
      updatedAt: updatedAt,
      progressUpdates: progressUpdates,
    );
  }

  static Map<String, dynamic> buildExtraFields({
    required String? nature,
    required String manualNature,
    required Map<String, dynamic> formData,
    required String team,
    required String bo,
    required String supportedTeam,
    required String situation,
    required String interventionOutcome,
    required String odorSource,
    required String missingTime,
    required String searchDuration,
    required String terrainCondition,
    required String serviceOrderNumber,
    required List<Map<String, dynamic>> drugRows,
    required List<Map<String, dynamic>> detainedIndividuals,
    required List<Map<String, dynamic>> seizedObjects,
    required List<Map<String, dynamic>> detainedVehicles,
    Map<String, dynamic>? existingExtraFields,
    String publicEstimate = '',
    String eventTheme = '',
    double? locationLat,
    double? locationLng,
  }) {
    final extraFields = existingExtraFields != null
        ? Map<String, dynamic>.from(existingExtraFields)
        : <String, dynamic>{};
    final normalizedNature = OccurrenceFormController.normalizeNature(nature);

    if (normalizedNature == OccurrenceFormController.natureDetection ||
        normalizedNature == OccurrenceFormController.natureNarcoticsSearch) {
      final drugs = buildDrugDetails(drugRows);
      if (drugs.isNotEmpty) extraFields['drogas'] = drugs;
      _putIfNotEmpty(extraFields, 'equipe', team);
      _putIfNotEmpty(extraFields, 'bo', bo);
    } else if (normalizedNature ==
        OccurrenceFormController.natureSupportVehicle) {
      _putIfNotEmpty(extraFields, 'guarnicao', supportedTeam);
      _putIfNotEmpty(extraFields, 'situacao', situation);
      _putIfNotEmpty(extraFields, 'desfecho', interventionOutcome);
    } else if (normalizedNature ==
        OccurrenceFormController.natureMissingPerson) {
      extraFields['tipo_busca'] =
          formData['Tipo de Busca'] ?? 'Busca & Captura';
      _putIfNotEmpty(extraFields, 'odor_inicial', odorSource);
      _putIfNotEmpty(extraFields, 'tempo_desaparecimento', missingTime);
      _putIfNotEmpty(extraFields, 'duracao_busca', searchDuration);
      _putIfNotEmpty(extraFields, 'condicao_terreno', terrainCondition);
    } else if (normalizedNature ==
        OccurrenceFormController.natureServiceOrder) {
      _putIfNotEmpty(extraFields, 'numero_os', serviceOrderNumber);
    } else if (normalizedNature == OccurrenceFormController.natureEvent) {
      _putIfNotEmpty(extraFields, 'publico_estimado', publicEstimate);
      _putIfNotEmpty(extraFields, 'tema', eventTheme);
    }

    if (normalizedNature == OccurrenceFormController.natureOther &&
        manualNature.trim().isNotEmpty) {
      extraFields['natureza_manual'] = manualNature.trim();
    }

    extraFields['natureza'] =
        normalizedNature == OccurrenceFormController.natureOther
        ? manualNature.trim()
        : normalizedNature;

    _putIfNotEmpty(extraFields, 'bo', bo);

    if (locationLat != null && locationLng != null) {
      extraFields['locationLat'] = locationLat;
      extraFields['locationLng'] = locationLng;
    }

    final finalDetails = buildFinalOutcomeDetails(
      drugRows: drugRows,
      detainedIndividuals: detainedIndividuals,
      seizedObjects: seizedObjects,
      detainedVehicles: detainedVehicles,
    );
    if (finalDetails.isNotEmpty) {
      extraFields['resultadosDetalhados'] = finalDetails;
      if (finalDetails['drogasApreendidas'] != null) {
        extraFields['drogas'] = finalDetails['drogasApreendidas'];
      }
    }

    return extraFields;
  }

  static Map<String, dynamic> buildFinalOutcomeDetails({
    required List<Map<String, dynamic>> drugRows,
    required List<Map<String, dynamic>> detainedIndividuals,
    required List<Map<String, dynamic>> seizedObjects,
    required List<Map<String, dynamic>> detainedVehicles,
  }) {
    final details = <String, dynamic>{};

    final detained = detainedIndividuals
        .map((row) => {'quantidade': _text(row['quantidade'])})
        .where((row) => (row['quantidade'] ?? '').isNotEmpty)
        .toList();
    if (detained.isNotEmpty) {
      details['individuosDetidos'] = detained;
    }

    final objects = seizedObjects
        .map(
          (row) => {
            'descricao': _text(row['descricao']),
            'quantidade': _text(row['quantidade']),
          },
        )
        .where(
          (row) =>
              (row['descricao'] ?? '').isNotEmpty ||
              (row['quantidade'] ?? '').isNotEmpty,
        )
        .toList();
    if (objects.isNotEmpty) {
      details['objetosApreendidos'] = objects;
    }

    final drugs = buildDrugDetails(drugRows);
    if (drugs.isNotEmpty) {
      details['drogasApreendidas'] = drugs;
    }

    final vehicles = detainedVehicles
        .map(
          (row) => {'tipo': _text(row['tipo']), 'placa': _text(row['placa'])},
        )
        .where(
          (row) =>
              (row['tipo'] ?? '').isNotEmpty || (row['placa'] ?? '').isNotEmpty,
        )
        .toList();
    if (vehicles.isNotEmpty) {
      details['veiculosDetidos'] = vehicles;
    }

    return details;
  }

  static List<Map<String, dynamic>> buildDrugDetails(
    List<Map<String, dynamic>> drugRows,
  ) {
    return drugRows
        .map(
          (row) => {
            'tipo': row['tipo'] == 'Outros'
                ? _text(row['especificar'])
                : row['tipo'],
            'quantidade': _text(row['quantidade']),
          },
        )
        .where(
          (row) =>
              (row['tipo'] ?? '').toString().isNotEmpty ||
              (row['quantidade'] ?? '').toString().isNotEmpty,
        )
        .toList();
  }

  static void _putIfNotEmpty(
    Map<String, dynamic> target,
    String key,
    String value,
  ) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      target[key] = trimmed;
    }
  }

  static String _text(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    final dynamic dynamicValue = value;
    final Object? text;
    try {
      text = dynamicValue.text;
    } catch (_) {
      return value.toString().trim();
    }
    return text is String ? text.trim() : '';
  }
}
