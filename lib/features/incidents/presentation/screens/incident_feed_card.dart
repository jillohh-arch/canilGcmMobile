part of 'incident_form_screen.dart';

class _IncidentFeedCard extends StatefulWidget {
  final Incident incident;

  const _IncidentFeedCard({required this.incident});

  @override
  State<_IncidentFeedCard> createState() => _IncidentFeedCardState();
}

class _IncidentFeedCardState extends State<_IncidentFeedCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final inc = widget.incident;
    final cs = Theme.of(context).colorScheme;
    final resultColor = _incidentFeedResultColor(inc.displayResult);
    final dateLabel = _incidentFeedDateLabel(inc.date);

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(color: resultColor, width: 3),
            top: BorderSide(color: cs.outlineVariant, width: 0.5),
            right: BorderSide(color: cs.outlineVariant, width: 0.5),
            bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IncidentFeedCardHeader(
                incident: inc,
                resultColor: resultColor,
                expanded: _expanded,
              ),
              const SizedBox(height: 10),
              _IncidentFeedCardTags(incident: inc),
              const SizedBox(height: 8),
              _IncidentFeedTimestamp(label: dateLabel),
              if (_expanded && inc.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                _IncidentFeedDescription(description: inc.description),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _incidentFeedDateLabel(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  final timeAgo = diff.inDays > 0
      ? '${diff.inDays}d atrás'
      : diff.inHours > 0
      ? '${diff.inHours}h atrás'
      : 'Agora';
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');

  return '$day/$month/${date.year} · $timeAgo';
}
