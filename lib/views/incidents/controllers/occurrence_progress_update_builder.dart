import '../../../models/incident.dart';
import 'occurrence_form_controller.dart';

abstract final class OccurrenceProgressUpdateBuilder {
  static List<IncidentProgressUpdate> build({
    required List<IncidentProgressUpdate> timeline,
    required bool isNewRecord,
    required bool isEditingExistingRecord,
    required DateTime timestamp,
    required String description,
    required String location,
    required String status,
    required String? selectedUpdateTitle,
    required String updateNote,
    required String authorId,
    required String authorName,
  }) {
    final updates = List<IncidentProgressUpdate>.from(timeline);
    final cleanDescription = description.trim();
    final cleanLocation = location.trim();
    final cleanNote = updateNote.trim();

    if (updates.isEmpty && isNewRecord) {
      updates.add(
        IncidentProgressUpdate(
          title: 'Registro inicial',
          description: cleanDescription.isNotEmpty
              ? cleanDescription
              : 'Ocorrência registrada pela equipe.',
          timestamp: timestamp,
          location: cleanLocation,
          authorId: authorId,
          authorName: authorName,
        ),
      );
    }

    if (cleanNote.isNotEmpty) {
      updates.add(
        IncidentProgressUpdate(
          title: selectedUpdateTitle ?? _progressTitleForStatus(status),
          description: cleanNote,
          timestamp: timestamp,
          location: cleanLocation,
          authorId: authorId,
          authorName: authorName,
        ),
      );
    } else if (isEditingExistingRecord) {
      updates.add(
        IncidentProgressUpdate(
          title: 'Registro atualizado',
          description: 'Dados da ocorrência atualizados.',
          timestamp: timestamp,
          location: cleanLocation,
          authorId: authorId,
          authorName: authorName,
        ),
      );
    }

    return updates;
  }

  static String _progressTitleForStatus(String status) {
    return status == OccurrenceFormController.statusInProgress
        ? 'Atualização operacional'
        : 'Encerramento da ocorrência';
  }
}
