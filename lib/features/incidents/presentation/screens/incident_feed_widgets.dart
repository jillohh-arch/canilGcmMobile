part of 'incident_form_screen.dart';

class _IncidentFeed extends StatelessWidget {
  final String dogId;

  const _IncidentFeed({required this.dogId});

  @override
  Widget build(BuildContext context) {
    final iVM = Provider.of<IncidentViewModel>(context);

    if (iVM.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final incidents = [...iVM.incidents]
      ..sort((a, b) => b.date.compareTo(a.date));

    if (incidents.isEmpty) {
      return const _IncidentFeedEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: incidents.length,
      itemBuilder: (context, index) =>
          _IncidentFeedCard(incident: incidents[index]),
    );
  }
}
