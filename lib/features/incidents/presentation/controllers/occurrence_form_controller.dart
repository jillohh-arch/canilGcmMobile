import 'occurrence_form_labels.dart';
import 'occurrence_form_normalizer.dart';
import 'occurrence_outcome_catalog.dart';
import 'occurrence_outcome_summary.dart';
import 'occurrence_text_normalizer.dart';

class OccurrenceFormController {
  static const statusInProgress = OccurrenceFormLabels.statusInProgress;
  static const statusCompleted = OccurrenceFormLabels.statusCompleted;
  static const statusCanceled = OccurrenceFormLabels.statusCanceled;

  static const natureDetection = OccurrenceFormLabels.natureDetection;
  static const natureSupportVehicle = OccurrenceFormLabels.natureSupportVehicle;
  static const natureMissingPerson = OccurrenceFormLabels.natureMissingPerson;
  static const natureServiceOrder = OccurrenceFormLabels.natureServiceOrder;
  static const natureEvent = OccurrenceFormLabels.natureEvent;
  static const natureOther = OccurrenceFormLabels.natureOther;
  static const natureNarcoticsSearch =
      OccurrenceFormLabels.natureNarcoticsSearch;

  int step = 0;
  String status = statusCompleted;
  bool? successful = true;
  final Set<String> outcomes = {};

  static String normalizeStatus(String? value) {
    return OccurrenceFormNormalizer.normalizeStatus(value);
  }

  static String normalizeNature(String? value) {
    return OccurrenceFormNormalizer.normalizeNature(value);
  }

  static String normalizeOutcome(String value) {
    return OccurrenceFormNormalizer.normalizeOutcome(value);
  }

  void startNewOccurrence() {
    status = statusInProgress;
    successful = null;
    outcomes.clear();
    step = 0;
  }

  void selectNature(String nature) {
    outcomes
      ..clear()
      ..addAll(defaultOutcomesForNature(nature));
  }

  void setStatus(String value) {
    status = value;
    if (value == statusInProgress) {
      successful = null;
    } else {
      successful ??= true;
    }
  }

  bool toggleOutcome(String option) {
    if (outcomes.contains(option)) {
      outcomes.remove(option);
      return false;
    }

    outcomes.add(option);
    return true;
  }

  bool get isFinalizing => status != statusInProgress;

  String resultSummary({required String? nature, required String fallback}) {
    if (status == statusInProgress) {
      return statusInProgress;
    }

    if (status == statusCanceled) {
      return statusCanceled;
    }

    final summary = prioritizedOutcomeSummary(outcomes, nature);
    if (summary != null) {
      return summary;
    }

    if (successful == true) {
      return 'Êxito';
    }

    if (successful == false) {
      return 'Sem êxito';
    }

    return fallback;
  }

  List<String> outcomeOptionsForNature(String? nature) {
    return OccurrenceOutcomeCatalog.optionsForNature(nature);
  }

  Set<String> defaultOutcomesForNature(String? nature) {
    return OccurrenceOutcomeCatalog.defaultsForNature(nature);
  }

  bool hasOutcomeContaining(String token) {
    final normalizedToken = OccurrenceTextNormalizer.normalize(token);
    return outcomes.any(
      (outcome) =>
          OccurrenceTextNormalizer.normalize(outcome).contains(normalizedToken),
    );
  }

  bool hasVehicleOutcome() {
    return hasOutcomeContaining('veículo');
  }

  bool hasDetainedIndividualOutcome() {
    return hasOutcomeContaining('detido') && !hasVehicleOutcome();
  }

  bool hasObjectOutcome() {
    return hasOutcomeContaining('objeto');
  }

  bool hasDrugOutcome() {
    return hasOutcomeContaining('droga');
  }

  String? prioritizedOutcomeSummary(
    Iterable<String> selectedOutcomes,
    String? nature,
  ) {
    return OccurrenceOutcomeSummary.resolve(selectedOutcomes, nature);
  }
}
