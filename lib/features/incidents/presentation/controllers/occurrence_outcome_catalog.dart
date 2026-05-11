import 'occurrence_form_labels.dart';
import 'occurrence_form_normalizer.dart';

class OccurrenceOutcomeCatalog {
  const OccurrenceOutcomeCatalog._();

  static List<String> optionsForNature(String? nature) {
    switch (OccurrenceFormNormalizer.normalizeNature(nature)) {
      case OccurrenceFormLabels.natureDetection:
      case OccurrenceFormLabels.natureNarcoticsSearch:
        return const [
          'Droga apreendida',
          'Objetos apreendidos',
          'Veículos detidos',
          'Indivíduo detido',
          'Apoio prestado',
          'BO elaborado',
          'Encaminhamento médico',
          'Sem constatação',
        ];
      case OccurrenceFormLabels.natureSupportVehicle:
        return const [
          'Apoio prestado',
          'Droga apreendida',
          'Objetos apreendidos',
          'Veículos detidos',
          'Indivíduo detido',
          'Encaminhamento médico',
          'BO elaborado',
          'Local preservado',
          'Sem constatação',
        ];
      case OccurrenceFormLabels.natureMissingPerson:
        return const [
          'Pessoa localizada',
          'Objeto localizado',
          'Droga apreendida',
          'Objetos apreendidos',
          'Veículos detidos',
          'Apoio prestado',
          'Encaminhamento médico',
          'BO elaborado',
          'Sem constatação',
        ];
      case OccurrenceFormLabels.natureServiceOrder:
        return const [
          'Apoio prestado',
          'Droga apreendida',
          'Objetos apreendidos',
          'Veículos detidos',
          'BO elaborado',
          'Local preservado',
          'Encaminhamento médico',
          'Sem constatação',
        ];
      case OccurrenceFormLabels.natureEvent:
        return const [
          'Apoio prestado',
          'Droga apreendida',
          'Objetos apreendidos',
          'Ação educativa concluída',
          'BO elaborado',
          'Sem constatação',
        ];
      case OccurrenceFormLabels.natureOther:
        return const [
          'Apoio prestado',
          'Droga apreendida',
          'Objetos apreendidos',
          'Veículos detidos',
          'Vítima socorrida',
          'Encaminhamento médico',
          'Trânsito sinalizado',
          'Local preservado',
          'Indivíduo detido',
          'BO elaborado',
          'Sem constatação',
        ];
      default:
        return const [
          'Apoio prestado',
          'Droga apreendida',
          'Objetos apreendidos',
          'Veículos detidos',
          'Indivíduo detido',
          'BO elaborado',
          'Sem constatação',
        ];
    }
  }

  static Set<String> defaultsForNature(String? nature) {
    switch (OccurrenceFormNormalizer.normalizeNature(nature)) {
      case OccurrenceFormLabels.natureSupportVehicle:
      case OccurrenceFormLabels.natureServiceOrder:
      case OccurrenceFormLabels.natureEvent:
      case OccurrenceFormLabels.natureOther:
        return {'Apoio prestado'};
      default:
        return <String>{};
    }
  }
}
