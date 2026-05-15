part of 'dog_details_screen.dart';

class _MissionLog extends StatelessWidget {
  final Dog dog;

  const _MissionLog({required this.dog});

  @override
  Widget build(BuildContext context) {
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);
    final incidentVM = Provider.of<IncidentViewModel>(context);

    final items = [
      ...trainingVM.trainings.map(_timelineItemFromTraining),
      ...healthVM.healthLogs.map(_timelineItemFromHealthLog),
      ...incidentVM.incidents.map(_timelineItemFromIncident),
    ]..sort((a, b) => b.date.compareTo(a.date));

    final visibleItems = items.take(12).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _MissionLogHeader(),
        const SizedBox(height: 16),
        if (visibleItems.isEmpty)
          const _MissionLogEmptyState()
        else
          ...List.generate(visibleItems.length, (index) {
            final item = visibleItems[index];
            final isLast = index == visibleItems.length - 1;
            return _MissionTimelineRow(item: item, isLast: isLast);
          }),
      ],
    );
  }

  _MissionTimelineItem _timelineItemFromTraining(
    TrainingSessionModel training,
  ) {
    final isScent = training.trainingType == 'Faro';
    final icon = isScent
        ? Icons.track_changes_rounded
        : (training.trainingType == 'Proteção'
              ? Icons.shield_rounded
              : Icons.school_rounded);
    final substance = training.substanceUsed;
    final title = substance == null || substance.isEmpty
        ? training.trainingType
        : '${training.trainingType} · $substance';

    return _MissionTimelineItem(
      date: training.date,
      title: title,
      subtitle: training.location,
      icon: icon,
      color: const Color(0xFFFFB300),
      tag: 'TREINO',
    );
  }

  _MissionTimelineItem _timelineItemFromHealthLog(HealthLogModel healthLog) {
    final (icon, color) = _healthIconAndColor(healthLog.logType);

    return _MissionTimelineItem(
      date: healthLog.date,
      title: healthLog.logType,
      subtitle: healthLog.vaccines.isNotEmpty
          ? healthLog.vaccines.join(', ')
          : healthLog.healthObservations,
      icon: icon,
      color: color,
      tag: 'SAÚDE',
    );
  }

  _MissionTimelineItem _timelineItemFromIncident(Incident incident) {
    return _MissionTimelineItem(
      date: incident.date,
      title: incident.type ?? 'Ocorrência',
      subtitle: '${incident.result} · ${incident.location}',
      icon: Icons.report_rounded,
      color: AppTheme.primary,
      tag: 'OCORRÊNCIA',
    );
  }

  (IconData, Color) _healthIconAndColor(String logType) {
    switch (logType) {
      case 'Vacina':
        return (Icons.vaccines_rounded, const Color(0xFFEF5350));
      case 'Consulta':
        return (Icons.local_hospital_rounded, const Color(0xFF66BB6A));
      case 'Exame':
        return (Icons.biotech_rounded, const Color(0xFF7E57C2));
      case 'Medicação':
        return (Icons.medication_rounded, const Color(0xFFFF7043));
      case 'Banho':
        return (Icons.water_drop_rounded, const Color(0xFF29B6F6));
      default:
        return (Icons.medical_services_rounded, const Color(0xFFEF5350));
    }
  }
}
