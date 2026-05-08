part of 'daily_timeline_screen.dart';

extension _DailyTimelineTextHelpers on _DailyTimelineScreenState {
  String _resolveHealthTimelineTitle(dynamic healthLog) {
    final logType = (healthLog.logType ?? '').toString().trim();
    if (logType.isNotEmpty && logType.toLowerCase() != 'rotina') {
      return logType;
    }

    final vaccines = healthLog.vaccines is List
        ? List<String>.from(healthLog.vaccines as List)
        : const <String>[];
    if (vaccines.isNotEmpty) {
      return vaccines.first;
    }

    final observations = (healthLog.healthObservations ?? '').toString().trim();
    if (observations.isNotEmpty) {
      final firstSentence = observations.split(RegExp(r'[.!?\n]')).first.trim();
      if (firstSentence.isNotEmpty) {
        return firstSentence;
      }
    }

    return 'Registro de saúde';
  }

  String _resolveIncidentTimelineTitle(Incident incident) {
    final type = (incident.type ?? '').trim();
    if (type.isNotEmpty) {
      return type;
    }

    if (incident.outcomes.isNotEmpty) {
      return incident.outcomes.first;
    }

    final latestUpdate = incident.progressUpdates.isNotEmpty
        ? incident.progressUpdates.last.title.trim()
        : '';
    if (latestUpdate.isNotEmpty) {
      return latestUpdate;
    }

    return 'Registro operacional';
  }

  String _cleanTimelineTitle(_TimelineEntry entry) {
    final rawTitle = entry.title.trim();
    final normalized = rawTitle
        .replaceAll('TREINO: ', '')
        .replaceAll('ROTINA: ', '')
        .replaceAll('OCORRÊNCIA: ', '')
        .replaceAll('SAÚDE: ', '')
        .trim();

    if (normalized.isNotEmpty) {
      return normalized;
    }

    switch (entry.type) {
      case 'Treino':
        return 'Treino';
      case 'Rotina':
        return 'Rotina';
      case 'Ocorrência':
        return 'Ocorrência';
      case 'Saude':
        return 'Saúde';
      default:
        return 'Registro';
    }
  }

  String _buildTimelineSubtitle(_TimelineEntry entry, String timeStr) {
    final location = entry.location.trim();
    if (location.isEmpty) {
      return timeStr;
    }
    return '$timeStr \u2022 $location';
  }
}
