part of 'global_incidents_screen.dart';

class _GlobalIncidentsBody extends StatelessWidget {
  final bool isLoading;
  final List<Incident> incidents;

  const _GlobalIncidentsBody({
    required this.isLoading,
    required this.incidents,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (incidents.isEmpty) {
      return const _GlobalIncidentsEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: incidents.length,
      itemBuilder: (context, index) =>
          _GlobalIncidentFeedCard(incident: incidents[index]),
    );
  }
}
