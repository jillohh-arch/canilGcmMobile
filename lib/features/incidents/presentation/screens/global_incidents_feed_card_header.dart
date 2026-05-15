part of 'global_incidents_screen.dart';

class _GlobalIncidentCardHeader extends StatelessWidget {
  final Incident incident;
  final Color resultColor;
  final bool expanded;

  const _GlobalIncidentCardHeader({
    required this.incident,
    required this.resultColor,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: resultColor.withAlpha(30),
            border: Border.all(color: resultColor.withAlpha(100), width: 1),
          ),
          child: Icon(
            _globalIncidentTypeIcon(incident.type),
            size: 18,
            color: resultColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (incident.type != null)
                Text(
                  incident.type!.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: resultColor,
                    letterSpacing: 0.6,
                  ),
                ),
              Text(
                incident.result,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
        Icon(
          expanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          size: 20,
          color: Colors.white30,
        ),
      ],
    );
  }
}
