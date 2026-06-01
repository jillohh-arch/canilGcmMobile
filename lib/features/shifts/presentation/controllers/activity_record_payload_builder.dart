import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';

abstract final class ActivityRecordPayloadBuilder {
  static HealthLogModel healthLog({
    required String? documentId,
    required String dogId,
    required String dogName,
    required DateTime date,
    required String logType,
    required String observations,
    required String returnDate,
    required String vetName,
    required List<String> vaccines,
    required List<Map<String, dynamic>> mediaAttachments,
  }) {
    return HealthLogModel(
      id: documentId,
      dogId: dogId,
      dogName: dogName,
      date: date,
      type: HealthLogModel.mapLegacyLogType(logType),
      subtype: vaccines.isNotEmpty
          ? vaccines.first
          : (logType == 'Pesagem' ? 'Pesagem' : null),
      healthObservations: observations + _returnDateSuffix(returnDate),
      vetName: _optionalText(vetName),
      mediaAttachments: _optionalMedia(mediaAttachments),
    );
  }

  static TrainingSessionModel trainingSession({
    required String? documentId,
    required String dogId,
    required String dogName,
    required String currentRa,
    required DateTime date,
    required String trainingType,
    required String location,
    required String notes,
    required String durationMinutes,
    required List<Map<String, dynamic>> mediaAttachments,
    required Map<String, dynamic> metadata,
  }) {
    return TrainingSessionModel(
      id: documentId,
      dogId: dogId,
      dogName: dogName,
      handlerId: currentRa,
      date: date,
      trainingType: trainingType,
      location: location.isNotEmpty ? location : 'Base GCM',
      weather: 'Limpo',
      handlerNotes: notes,
      searchDuration: _durationMinutesAsSeconds(durationMinutes),
      mediaAttachments: _optionalMedia(mediaAttachments),
      metadata: metadata,
    );
  }

  static List<Map<String, dynamic>>? _optionalMedia(
    List<Map<String, dynamic>> media,
  ) {
    return media.isNotEmpty ? media : null;
  }

  static String? _optionalText(String value) {
    return value.isNotEmpty ? value : null;
  }

  static int? _durationMinutesAsSeconds(String value) {
    if (value.isEmpty) return null;
    final mins = int.tryParse(value) ?? 0;
    return mins * 60;
  }

  static String _returnDateSuffix(String returnDate) {
    return returnDate.isNotEmpty ? '\nRetorno agendado: $returnDate' : '';
  }
}
