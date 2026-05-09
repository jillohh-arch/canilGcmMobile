part of 'incident_form_screen.dart';

class _IncidentFeed extends StatelessWidget {
  final String dogId;
  const _IncidentFeed({required this.dogId});

  @override
  Widget build(BuildContext context) {
    final iVM = Provider.of<IncidentViewModel>(context);

    if (iVM.isLoading) return const Center(child: CircularProgressIndicator());

    final incidents = [...iVM.incidents]
      ..sort((a, b) => b.date.compareTo(a.date));

    if (incidents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.report_off_rounded,
              size: 56,
              color: Colors.white.withAlpha(30),
            ),
            const SizedBox(height: 12),
            Text(
              'Nenhuma ocorrência registrada',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.white.withAlpha(60),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Toque em "Nova" para registrar',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.white.withAlpha(40),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: incidents.length,
      itemBuilder: (context, i) => _IncidentFeedCard(incident: incidents[i]),
    );
  }
}

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
    final rColor = _incidentFeedResultColor(inc.displayResult);
    final now = DateTime.now();
    final diff = now.difference(inc.date);
    final timeAgo = diff.inDays > 0
        ? '${diff.inDays}d atrás'
        : diff.inHours > 0
        ? '${diff.inHours}h atrás'
        : 'Agora';
    final dateStr =
        '${inc.date.day.toString().padLeft(2, '0')}/${inc.date.month.toString().padLeft(2, '0')}/${inc.date.year} · $timeAgo';

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(color: rColor, width: 3),
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
              // Header row
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: rColor.withAlpha(30),
                      border: Border.all(
                        color: rColor.withAlpha(100),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      _incidentFeedTypeIcon(inc.type),
                      size: 18,
                      color: rColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (inc.type != null)
                          Text(
                            inc.type!.toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: rColor,
                              letterSpacing: 0.6,
                            ),
                          ),
                        Text(
                          inc.displayResult,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: Colors.white30,
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Location tag
              Row(
                children: [
                  _IncidentFeedTag(
                    icon: Icons.location_on_rounded,
                    text: inc.location,
                    iconColor: const Color(0xFF4ECDE4),
                    textColor: cs.onSurface,
                  ),
                  const SizedBox(width: 8),
                  // Handler tag
                  _IncidentFeedTag(
                    icon: Icons.badge_outlined,
                    text: 'RA ${inc.handlerId}',
                    iconColor: cs.onSurfaceVariant,
                    textColor: cs.onSurfaceVariant,
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Timestamp
              Text(
                dateStr,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: Colors.white30,
                  fontWeight: FontWeight.w500,
                ),
              ),

              // Expanded: Description
              if (_expanded && inc.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: cs.outlineVariant, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.description_rounded,
                            size: 12,
                            color: const Color(0xFF4ECDE4),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'RELATÓRIO',
                            style: GoogleFonts.poppins(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF4ECDE4),
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        inc.description,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.white70,
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Novo formulário de ocorrência ----------------------------------------------
