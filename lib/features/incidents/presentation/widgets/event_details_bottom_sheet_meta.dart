part of 'event_details_bottom_sheet.dart';

class _EventDetailsMetaList extends StatelessWidget {
  final IncidentProgressUpdate update;
  final String timestampLabel;
  final String eventLocation;
  final Color accentColor;
  final Color successColor;
  final Color warningColor;

  const _EventDetailsMetaList({
    required this.update,
    required this.timestampLabel,
    required this.eventLocation,
    required this.accentColor,
    required this.successColor,
    required this.warningColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _EventDetailLine(
          icon: Icons.schedule_rounded,
          label: 'Data e hora',
          value: timestampLabel,
          color: accentColor,
        ),
        if ((update.authorName ?? '').isNotEmpty)
          _EventDetailLine(
            icon: Icons.person_rounded,
            label: 'Operador',
            value: update.authorName!,
            color: successColor,
          ),
        if (eventLocation.isNotEmpty)
          _EventDetailLine(
            icon: Icons.location_on_rounded,
            label: 'Local',
            value: eventLocation,
            color: warningColor,
          ),
      ],
    );
  }
}
