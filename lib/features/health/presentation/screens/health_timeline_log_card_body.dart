part of 'health_dashboard_screen.dart';

class _HealthLogCardBody extends StatelessWidget {
  final HealthLogModel log;
  final Color accentColor;
  final bool isExam;
  final bool hasAttachments;
  final ValueChanged<String?> onOpenAttachment;

  const _HealthLogCardBody({
    required this.log,
    required this.accentColor,
    required this.isExam,
    required this.hasAttachments,
    required this.onOpenAttachment,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.healthObservations.isNotEmpty
                      ? log.healthObservations
                      : 'Registro operacional documentado.',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                if (log.vetName != null && log.vetName!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _HealthVetBadge(vetName: log.vetName!),
                ],
                if (isExam && hasAttachments) ...[
                  const SizedBox(height: 16),
                  _ExamAttachmentButton(
                    accentColor: accentColor,
                    onPressed: () =>
                        onOpenAttachment(log.mediaAttachments!.first['url']),
                  ),
                ],
              ],
            ),
          ),
          if (hasAttachments && !isExam) ...[
            const SizedBox(width: 16),
            _TacticalHealthThumbnail(
              url: log.mediaAttachments!.first['url'],
              accentColor: accentColor,
            ),
          ],
        ],
      ),
    );
  }
}

class _HealthVetBadge extends StatelessWidget {
  final String vetName;

  const _HealthVetBadge({required this.vetName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.background.withAlpha(97),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.textPrimary.withAlpha(26)),
      ),
      child: Text(
        'VET/RESP: ${vetName.toUpperCase()}',
        style: GoogleFonts.shareTechMono(
          color: AppTheme.textPrimary.withAlpha(138),
          fontSize: 10,
        ),
      ),
    );
  }
}
