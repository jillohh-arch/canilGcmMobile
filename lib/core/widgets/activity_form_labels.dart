import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_form_controller.dart';

abstract final class ActivityFormLabels {
  static String descriptionLabel({
    required String category,
    required String? subtype,
    required String feedingSubtype,
  }) {
    if (category == 'Treino') return 'Descrição do treino';
    if (category == 'Saude') return 'Detalhes';
    if (category == 'Rotina') {
      return subtype == feedingSubtype
          ? 'Observações da alimentação'
          : 'Detalhes da rotina';
    }
    return 'Descrição da ocorrência';
  }

  static String saveButtonLabel({
    required String category,
    required String occurrenceStatus,
  }) {
    if (category == 'Treino') return 'SALVAR TREINO';
    if (category == 'Saude') return 'SALVAR PRONTUÁRIO';
    if (category == 'Rotina') return 'SALVAR ROTINA';
    return occurrenceStatus == OccurrenceFormController.statusInProgress
        ? 'SALVAR EM ANDAMENTO'
        : 'CONCLUIR OCORRÊNCIA';
  }

  static String successSaveMessage({
    required String category,
    required bool isOccurrenceCategory,
    required String occurrenceStatus,
  }) {
    if (isOccurrenceCategory || category == 'Evento') {
      return occurrenceStatus == OccurrenceFormController.statusInProgress
          ? 'Ocorrência salva em andamento no Firebase.'
          : 'Ocorrência concluída e sincronizada.';
    }

    if (category == 'Treino') return 'Treino salvo no Firebase.';
    if (category == 'Rotina') return 'Rotina salva no Firebase.';
    if (category == 'Saude') return 'Prontuário salvo no Firebase.';

    return 'Registro salvo no Firebase.';
  }

  static String occurrenceModeLabel({required bool isNewRecord}) {
    return isNewRecord ? 'NOVA OCORRÊNCIA' : 'OCORRÊNCIA OPERACIONAL';
  }

  static String occurrenceStatusLabel({
    required String occurrenceStatus,
    required bool isNewRecord,
  }) {
    if (occurrenceStatus == OccurrenceFormController.statusCompleted) {
      return 'FECHADA';
    }
    return isNewRecord ? 'NOVA' : 'ABERTA';
  }
}
