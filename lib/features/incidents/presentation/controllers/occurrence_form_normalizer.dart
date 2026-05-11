import 'occurrence_form_labels.dart';
import 'occurrence_text_normalizer.dart';

class OccurrenceFormNormalizer {
  const OccurrenceFormNormalizer._();

  static String normalizeStatus(String? value) {
    final raw = value?.trim() ?? '';
    final normalized = OccurrenceTextNormalizer.normalize(raw);

    if (normalized.contains('andamento')) {
      return OccurrenceFormLabels.statusInProgress;
    }
    if (normalized.contains('cancel')) {
      return OccurrenceFormLabels.statusCanceled;
    }
    if (normalized.contains('conclu')) {
      return OccurrenceFormLabels.statusCompleted;
    }

    return raw.isEmpty ? OccurrenceFormLabels.statusCompleted : raw;
  }

  static String normalizeNature(String? value) {
    final raw = value?.trim() ?? '';
    final normalized = OccurrenceTextNormalizer.normalize(raw);

    if (normalized.contains('entorpec')) {
      return OccurrenceFormLabels.natureNarcoticsSearch;
    }
    if (normalized.contains('detec')) {
      return OccurrenceFormLabels.natureDetection;
    }
    if (normalized.contains('apoio')) {
      return OccurrenceFormLabels.natureSupportVehicle;
    }
    if (normalized.contains('pessoa')) {
      return OccurrenceFormLabels.natureMissingPerson;
    }
    if (normalized.contains('ordem')) {
      return OccurrenceFormLabels.natureServiceOrder;
    }
    if (normalized.contains('palestra') || normalized.contains('evento')) {
      return OccurrenceFormLabels.natureEvent;
    }
    if (normalized.contains('outro')) {
      return OccurrenceFormLabels.natureOther;
    }

    return raw;
  }

  static String normalizeOutcome(String value) {
    final normalized = OccurrenceTextNormalizer.normalize(value);

    if (normalized.contains('droga')) return 'Droga apreendida';
    if (normalized.contains('objeto')) return 'Objetos apreendidos';
    if (normalized.contains('detido') &&
        (normalized.contains('veiculo') || normalized.contains('veiculos'))) {
      return 'Veículos detidos';
    }
    if (normalized.contains('detido')) return 'Indivíduo detido';
    if (normalized.contains('apoio')) return 'Apoio prestado';
    if (normalized.contains('bo')) return 'BO elaborado';
    if (normalized.contains('medico')) return 'Encaminhamento médico';
    if (normalized.contains('constata')) return 'Sem constatação';
    if (normalized.contains('localizada')) return 'Pessoa localizada';
    if (normalized.contains('educativa')) return 'Ação educativa concluída';
    if (normalized.contains('preservado')) return 'Local preservado';
    if (normalized.contains('transito')) return 'Trânsito sinalizado';
    if (normalized.contains('vitima')) return 'Vítima socorrida';

    return value;
  }
}
