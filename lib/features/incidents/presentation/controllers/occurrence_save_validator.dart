import 'occurrence_form_controller.dart';

abstract final class OccurrenceSaveValidator {
  static void validate({
    required String status,
    required String description,
    required Set<String> outcomes,
    required String? subtype,
    required String natureText,
  }) {
    final finalizing = status != OccurrenceFormController.statusInProgress;
    if (finalizing && description.trim().isEmpty) {
      throw Exception(
        'Preencha a descrição final antes de encerrar a ocorrência.',
      );
    }
    if (finalizing && outcomes.isEmpty) {
      throw Exception(
        'Selecione ao menos um resultado final antes de encerrar.',
      );
    }
    if ((subtype?.trim().isEmpty ?? true) || natureText.trim().isEmpty) {
      throw Exception('Informe a natureza da ocorrência.');
    }
  }
}
