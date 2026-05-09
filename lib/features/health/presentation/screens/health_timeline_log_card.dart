part of 'health_dashboard_screen.dart';

class _TacticalHealthLogCard extends StatelessWidget {
  final HealthLogModel log;
  final ValueChanged<String?> onOpenAttachment;

  const _TacticalHealthLogCard({
    required this.log,
    required this.onOpenAttachment,
  });

  @override
  Widget build(BuildContext context) {
    final isExam = log.logType == 'Exame';
    final hasAttachments =
        log.mediaAttachments != null && log.mediaAttachments!.isNotEmpty;
    final accentColor = _healthLogColor(log.logType);
    final iconData = _healthLogIcon(log.logType);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: ShapeDecoration(
          color: const Color(0xFF0F172A),
          shape: BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: accentColor.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          shadows: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HealthLogCardHeader(
              log: log,
              accentColor: accentColor,
              iconData: iconData,
            ),
            _HealthLogCardBody(
              log: log,
              accentColor: accentColor,
              isExam: isExam,
              hasAttachments: hasAttachments,
              onOpenAttachment: onOpenAttachment,
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthLogCardHeader extends StatelessWidget {
  final HealthLogModel log;
  final Color accentColor;
  final IconData iconData;

  const _HealthLogCardHeader({
    required this.log,
    required this.accentColor,
    required this.iconData,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.15),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(6),
          topRight: Radius.circular(6),
        ),
      ),
      child: Row(
        children: [
          Icon(iconData, size: 16, color: accentColor),
          const SizedBox(width: 8),
          Text(
            log.logType.toUpperCase(),
            style: GoogleFonts.shareTechMono(
              color: accentColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            _formatMilitaryDate(log.date),
            style: GoogleFonts.shareTechMono(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

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
                    color: Colors.white,
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
        color: Colors.black38,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(
        'VET/RESP: ${vetName.toUpperCase()}',
        style: GoogleFonts.shareTechMono(color: Colors.white54, fontSize: 10),
      ),
    );
  }
}

class _ExamAttachmentButton extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onPressed;

  const _ExamAttachmentButton({
    required this.accentColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: accentColor, width: 1.5),
        foregroundColor: accentColor,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.document_scanner_rounded, size: 18),
      label: Text(
        'ACESSAR LAUDO PDF',
        style: GoogleFonts.oxanium(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _TacticalHealthThumbnail extends StatelessWidget {
  final String? url;
  final Color accentColor;

  const _TacticalHealthThumbnail({
    required this.url,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    if (url == null) return const SizedBox.shrink();

    return Container(
      width: 75,
      height: 75,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFF030712),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.8),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: url!,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: Colors.white10),
          errorWidget: (context, url, error) => const Icon(
            Icons.image_not_supported,
            color: Colors.white24,
            size: 24,
          ),
        ),
      ),
    );
  }
}

Color _healthLogColor(String type) {
  switch (type) {
    case 'Vacina':
      return const Color(0xFFFF00FF);
    case 'Exame':
      return Colors.cyanAccent;
    case 'Banho':
      return const Color(0xFF00BFFF);
    case 'Consulta':
      return Colors.orangeAccent;
    default:
      return Colors.cyan;
  }
}

IconData _healthLogIcon(String type) {
  switch (type) {
    case 'Vacina':
      return Icons.vaccines;
    case 'Exame':
      return Icons.biotech;
    case 'Banho':
      return Icons.water_drop;
    case 'Consulta':
      return Icons.medical_services;
    default:
      return Icons.fact_check;
  }
}
