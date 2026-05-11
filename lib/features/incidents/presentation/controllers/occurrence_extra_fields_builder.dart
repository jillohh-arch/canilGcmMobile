import 'occurrence_form_controller.dart';
import 'occurrence_nature_extra_fields_writer.dart';
import 'occurrence_payload_field_writer.dart';
import 'occurrence_payload_final_details_builder.dart';

class OccurrenceExtraFieldsBuilder {
  const OccurrenceExtraFieldsBuilder._();

  static Map<String, dynamic> build({
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

    OccurrenceNatureExtraFieldsWriter.write(
      extraFields: extraFields,
      normalizedNature: normalizedNature,
      formData: formData,
      team: team,
      bo: bo,
      supportedTeam: supportedTeam,
      situation: situation,
      interventionOutcome: interventionOutcome,
      odorSource: odorSource,
      missingTime: missingTime,
      searchDuration: searchDuration,
      terrainCondition: terrainCondition,
      serviceOrderNumber: serviceOrderNumber,
      drugRows: drugRows,
      publicEstimate: publicEstimate,
      eventTheme: eventTheme,
    );

    _writeNatureIdentity(extraFields, normalizedNature, manualNature);
    OccurrencePayloadFieldWriter.putIfNotEmpty(extraFields, 'bo', bo);
    _writeLocation(extraFields, locationLat, locationLng);
    _writeFinalDetails(
      extraFields: extraFields,
      drugRows: drugRows,
      detainedIndividuals: detainedIndividuals,
      seizedObjects: seizedObjects,
      detainedVehicles: detainedVehicles,
    );

    return extraFields;
  }

  static void _writeNatureIdentity(
    Map<String, dynamic> extraFields,
    String normalizedNature,
    String manualNature,
  ) {
    if (normalizedNature == OccurrenceFormController.natureOther &&
        manualNature.trim().isNotEmpty) {
      extraFields['natureza_manual'] = manualNature.trim();
    }

    extraFields['natureza'] =
        normalizedNature == OccurrenceFormController.natureOther
        ? manualNature.trim()
        : normalizedNature;
  }

  static void _writeLocation(
    Map<String, dynamic> extraFields,
    double? locationLat,
    double? locationLng,
  ) {
    if (locationLat != null && locationLng != null) {
      extraFields['locationLat'] = locationLat;
      extraFields['locationLng'] = locationLng;
    }
  }

  static void _writeFinalDetails({
    required Map<String, dynamic> extraFields,
    required List<Map<String, dynamic>> drugRows,
    required List<Map<String, dynamic>> detainedIndividuals,
    required List<Map<String, dynamic>> seizedObjects,
    required List<Map<String, dynamic>> detainedVehicles,
  }) {
    final finalDetails = OccurrencePayloadFinalDetailsBuilder.build(
      drugRows: drugRows,
      detainedIndividuals: detainedIndividuals,
      seizedObjects: seizedObjects,
      detainedVehicles: detainedVehicles,
    );
    if (finalDetails.isEmpty) return;

    extraFields['resultadosDetalhados'] = finalDetails;
    if (finalDetails['drogasApreendidas'] != null) {
      extraFields['drogas'] = finalDetails['drogasApreendidas'];
    }
  }
}
