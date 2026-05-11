import 'occurrence_form_labels.dart';
import 'occurrence_form_normalizer.dart';

class OccurrenceOutcomeSummary {
  const OccurrenceOutcomeSummary._();

  static String? resolve(Iterable<String> selectedOutcomes, String? nature) {
    final outcomeSet = selectedOutcomes
        .map(OccurrenceFormNormalizer.normalizeOutcome)
        .toSet();
    final normalizedNature = OccurrenceFormNormalizer.normalizeNature(nature);

    if (outcomeSet.contains('Droga apreendida')) {
      return 'Apreensão positiva';
    }
    if (normalizedNature == OccurrenceFormLabels.natureMissingPerson &&
        outcomeSet.contains('Pessoa localizada')) {
      return 'Sucesso';
    }
    if (outcomeSet.contains('Indivíduo detido')) {
      return 'Indivíduo detido';
    }
    if (outcomeSet.contains('Vítima socorrida')) {
      return 'Vítima socorrida';
    }
    if (outcomeSet.contains('Encaminhamento médico')) {
      return 'Encaminhamento médico';
    }
    if (outcomeSet.contains('Trânsito sinalizado')) {
      return 'Trânsito sinalizado';
    }
    if (outcomeSet.contains('Local preservado')) {
      return 'Local preservado';
    }
    if (outcomeSet.contains('Ação educativa concluída')) {
      return 'Ação educativa concluída';
    }
    if (outcomeSet.contains('Apoio prestado')) {
      return 'Apoio prestado';
    }
    if (outcomeSet.contains('BO elaborado')) {
      return 'BO elaborado';
    }
    if (outcomeSet.contains('Sem constatação')) {
      return 'Sem constatação';
    }

    return null;
  }
}
