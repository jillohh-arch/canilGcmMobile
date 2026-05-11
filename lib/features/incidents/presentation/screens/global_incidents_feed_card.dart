part of 'global_incidents_screen.dart';

class _GlobalIncidentFeedCard extends StatefulWidget {
  final Incident incident;

  const _GlobalIncidentFeedCard({required this.incident});

  @override
  State<_GlobalIncidentFeedCard> createState() =>
      _GlobalIncidentFeedCardState();
}

class _GlobalIncidentFeedCardState extends State<_GlobalIncidentFeedCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final inc = widget.incident;
    final cs = Theme.of(context).colorScheme;
    final resultColor = _globalIncidentResultColor(inc.result);
    final timeAgo = _globalIncidentTimeAgo(inc.date);

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: cs.outlineVariant, width: 0.8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GlobalIncidentCardHeader(
                incident: inc,
                resultColor: resultColor,
                expanded: _expanded,
              ),
              const SizedBox(height: 10),
              _GlobalIncidentCardTags(incident: inc),
              const SizedBox(height: 8),
              _GlobalIncidentTimestamp(label: timeAgo),
              if (inc.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                _GlobalIncidentDescription(description: inc.description),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _globalIncidentTimeAgo(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);

  if (diff.inDays > 0) return '${diff.inDays}d atrás';
  if (diff.inHours > 0) return '${diff.inHours}h atrás';
  return 'Agora';
}
