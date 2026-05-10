part of 'health_log_screen.dart';

class _HealthTimelineList extends StatelessWidget {
  final bool isLoading;
  final List<HealthLogModel> logs;
  final String filter;

  const _HealthTimelineList({
    required this.isLoading,
    required this.logs,
    required this.filter,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (logs.isEmpty) {
      return _EmptyHealth(filter: filter);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        final isLast = index == logs.length - 1;
        return _HealthTimelineItem(log: log, isLast: isLast);
      },
    );
  }
}
