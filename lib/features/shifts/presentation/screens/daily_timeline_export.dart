part of 'daily_timeline_screen.dart';

extension _DailyTimelineExport on _DailyTimelineScreenState {
  Future<void> _exportPdf(BuildContext ctx, String dogId) async {
    final tVM = Provider.of<TrainingViewModel>(ctx, listen: false);
    final iVM = Provider.of<IncidentViewModel>(ctx, listen: false);
    final hVM = Provider.of<HealthViewModel>(ctx, listen: false);
    final rVM = Provider.of<RoutineViewModel>(ctx, listen: false);
    final authVM = Provider.of<AuthViewModel>(ctx, listen: false);
    final userVM = Provider.of<UserViewModel>(ctx, listen: false);
    final dogVM = Provider.of<DogViewModel>(ctx, listen: false);

    final dog = dogVM.dogs.firstWhere(
      (d) => d.id == dogId,
      orElse: () => dogVM.dogs.first,
    );
    final fbUser = authVM.user;
    final currentRa = HandlerIdentityService.raFromUser(fbUser);
    final userModel = userVM.users.cast<dynamic>().firstWhere(
      (u) => u?.ra == currentRa,
      orElse: () => null,
    );
    final callsign = userModel?.callsign ?? fbUser?.displayName ?? 'GCM';

    final entries = <ReportEntry>[
      ...tVM.trainings
          .where((training) => training.dogId == dogId)
          .map(
            (training) => ReportEntry(
              date: training.date,
              type: training.trainingType,
              location: training.location,
              observations: training.handlerNotes,
            ),
          ),
      ...rVM.routines
          .where((routine) => routine.dogId == dogId)
          .map(
            (routine) => ReportEntry(
              date: routine.timestamp,
              type: routine.activityType,
              location: routine.dogName,
              observations: routine.notes ?? '',
            ),
          ),
      ...hVM.healthLogs
          .where((healthLog) => healthLog.dogId == dogId)
          .map(
            (healthLog) => ReportEntry(
              date: healthLog.date,
              type: healthLog.logType,
              location: healthLog.dogName,
              observations: healthLog.healthObservations,
            ),
          ),
      ...iVM.incidents
          .where((incident) => incident.dogId == dogId)
          .map(
            (incident) => ReportEntry(
              date: incident.date,
              type: incident.type ?? 'Ocorrência',
              location: incident.location,
              observations: incident.description,
            ),
          ),
    ];

    final pdfBytes = await ReportService.generateActivityReport(
      dog: dog,
      conductorCallsign: callsign,
      entries: entries,
    );

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'relatorio_k9_${dog.name.toLowerCase()}.pdf',
    );
  }
}
