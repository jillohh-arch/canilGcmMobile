import '../../../widgets/activity_card_catalog.dart';

abstract final class OccurrenceDisplayText {
  static String effectiveNature(String? selectedSubtype) {
    return (selectedSubtype?.trim().isNotEmpty ?? false)
        ? selectedSubtype!
        : 'Averiguação';
  }

  static String manualNatureOr({
    required String manualNature,
    required String fallback,
  }) {
    return manualNature.trim().isNotEmpty ? manualNature.trim() : fallback;
  }

  static String headerNatureLabel({
    required String? selectedSubtype,
    required String manualNature,
  }) {
    if (selectedSubtype == ActivitySubtypeIds.other) {
      return manualNatureOr(manualNature: manualNature, fallback: 'Outros');
    }

    return selectedSubtype ?? 'Averiguação';
  }

  static String elapsedLabel(DateTime? startedAt, {DateTime? now}) {
    if (startedAt == null) return 'Não iniciada';
    return formatElapsedDuration((now ?? DateTime.now()).difference(startedAt));
  }

  static String formatElapsedDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    return '${minutes}m';
  }
}
