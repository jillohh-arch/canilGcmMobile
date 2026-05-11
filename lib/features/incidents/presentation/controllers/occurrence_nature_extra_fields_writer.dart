import 'occurrence_form_controller.dart';
import 'occurrence_payload_field_writer.dart';
import 'occurrence_payload_final_details_builder.dart';

class OccurrenceNatureExtraFieldsWriter {
  const OccurrenceNatureExtraFieldsWriter._();

  static void write({
    required Map<String, dynamic> extraFields,
    required String normalizedNature,
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
    required String publicEstimate,
    required String eventTheme,
  }) {
    if (normalizedNature == OccurrenceFormController.natureDetection ||
        normalizedNature == OccurrenceFormController.natureNarcoticsSearch) {
      _writeDetectionFields(extraFields, drugRows, team, bo);
    } else if (normalizedNature ==
        OccurrenceFormController.natureSupportVehicle) {
      _writeSupportVehicleFields(
        extraFields,
        supportedTeam,
        situation,
        interventionOutcome,
      );
    } else if (normalizedNature ==
        OccurrenceFormController.natureMissingPerson) {
      _writeMissingPersonFields(
        extraFields,
        formData,
        odorSource,
        missingTime,
        searchDuration,
        terrainCondition,
      );
    } else if (normalizedNature ==
        OccurrenceFormController.natureServiceOrder) {
      OccurrencePayloadFieldWriter.putIfNotEmpty(
        extraFields,
        'numero_os',
        serviceOrderNumber,
      );
    } else if (normalizedNature == OccurrenceFormController.natureEvent) {
      OccurrencePayloadFieldWriter.putIfNotEmpty(
        extraFields,
        'publico_estimado',
        publicEstimate,
      );
      OccurrencePayloadFieldWriter.putIfNotEmpty(
        extraFields,
        'tema',
        eventTheme,
      );
    }
  }

  static void _writeDetectionFields(
    Map<String, dynamic> extraFields,
    List<Map<String, dynamic>> drugRows,
    String team,
    String bo,
  ) {
    final drugs = OccurrencePayloadFinalDetailsBuilder.buildDrugDetails(
      drugRows,
    );
    if (drugs.isNotEmpty) extraFields['drogas'] = drugs;
    OccurrencePayloadFieldWriter.putIfNotEmpty(extraFields, 'equipe', team);
    OccurrencePayloadFieldWriter.putIfNotEmpty(extraFields, 'bo', bo);
  }

  static void _writeSupportVehicleFields(
    Map<String, dynamic> extraFields,
    String supportedTeam,
    String situation,
    String interventionOutcome,
  ) {
    OccurrencePayloadFieldWriter.putIfNotEmpty(
      extraFields,
      'guarnicao',
      supportedTeam,
    );
    OccurrencePayloadFieldWriter.putIfNotEmpty(
      extraFields,
      'situacao',
      situation,
    );
    OccurrencePayloadFieldWriter.putIfNotEmpty(
      extraFields,
      'desfecho',
      interventionOutcome,
    );
  }

  static void _writeMissingPersonFields(
    Map<String, dynamic> extraFields,
    Map<String, dynamic> formData,
    String odorSource,
    String missingTime,
    String searchDuration,
    String terrainCondition,
  ) {
    extraFields['tipo_busca'] = formData['Tipo de Busca'] ?? 'Busca & Captura';
    OccurrencePayloadFieldWriter.putIfNotEmpty(
      extraFields,
      'odor_inicial',
      odorSource,
    );
    OccurrencePayloadFieldWriter.putIfNotEmpty(
      extraFields,
      'tempo_desaparecimento',
      missingTime,
    );
    OccurrencePayloadFieldWriter.putIfNotEmpty(
      extraFields,
      'duracao_busca',
      searchDuration,
    );
    OccurrencePayloadFieldWriter.putIfNotEmpty(
      extraFields,
      'condicao_terreno',
      terrainCondition,
    );
  }
}
