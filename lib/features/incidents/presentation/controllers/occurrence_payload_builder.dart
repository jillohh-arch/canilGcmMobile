import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'occurrence_extra_fields_builder.dart';
import 'occurrence_form_controller.dart';
import 'occurrence_payload_final_details_builder.dart';

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
    final normalizedDocumentId = documentId?.trim();

    return Incident(
      id: normalizedDocumentId == null || normalizedDocumentId.isEmpty
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : normalizedDocumentId,
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
    return OccurrenceExtraFieldsBuilder.build(
      nature: nature,
      manualNature: manualNature,
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
      detainedIndividuals: detainedIndividuals,
      seizedObjects: seizedObjects,
      detainedVehicles: detainedVehicles,
      existingExtraFields: existingExtraFields,
      publicEstimate: publicEstimate,
      eventTheme: eventTheme,
      locationLat: locationLat,
      locationLng: locationLng,
    );
  }

  static Map<String, dynamic> buildFinalOutcomeDetails({
    required List<Map<String, dynamic>> drugRows,
    required List<Map<String, dynamic>> detainedIndividuals,
    required List<Map<String, dynamic>> seizedObjects,
    required List<Map<String, dynamic>> detainedVehicles,
  }) {
    return OccurrencePayloadFinalDetailsBuilder.build(
      drugRows: drugRows,
      detainedIndividuals: detainedIndividuals,
      seizedObjects: seizedObjects,
      detainedVehicles: detainedVehicles,
    );
  }

  static List<Map<String, dynamic>> buildDrugDetails(
    List<Map<String, dynamic>> drugRows,
  ) {
    return OccurrencePayloadFinalDetailsBuilder.buildDrugDetails(drugRows);
  }
}
