part of 'health_log_screen.dart';

class _HealthTimeline extends StatefulWidget {
  final String dogId;

  const _HealthTimeline({required this.dogId});

  @override
  State<_HealthTimeline> createState() => _HealthTimelineState();
}

class _HealthTimelineState extends State<_HealthTimeline> {
  static const _filters = [
    'Todos',
    'Vacina',
    'Consulta',
    'Exame',
    'Medicação',
    'Banho',
  ];

  String _filter = 'Todos';

  @override
  Widget build(BuildContext context) {
    final healthVM = Provider.of<HealthViewModel>(context);
    final logs =
        healthVM.healthLogs
            .where((log) => _filter == 'Todos' || log.logType == _filter)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    return Column(
      children: [
        _HealthFilterBar(
          filters: _filters,
          selectedFilter: _filter,
          onSelected: (filter) => setState(() => _filter = filter),
        ),
        Expanded(
          child: _HealthTimelineList(
            isLoading: healthVM.isLoading,
            logs: logs,
            filter: _filter,
          ),
        ),
      ],
    );
  }
}
