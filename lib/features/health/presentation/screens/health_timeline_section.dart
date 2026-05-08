part of 'health_dashboard_screen.dart';

extension _HealthDashboardTimelineSection on _HealthDashboardScreenState {
  Widget _buildTimelineHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      child: Row(
        children: [
          Container(width: 4, height: 14, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          Text(
            'PRONTUÁRIO DE COMBATE / HISTÓRICO',
            style: GoogleFonts.oxanium(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white54,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTacticalLogs(BuildContext context, List<HealthLogModel> logs) {
    if (logs.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            'NENHUM REGISTRO MÉDICO',
            style: GoogleFonts.shareTechMono(
              color: Colors.white24,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final log = logs[index];
        final bool isExam = log.logType == 'Exame';
        final bool hasAttachments =
            log.mediaAttachments != null && log.mediaAttachments!.isNotEmpty;
        final accentColor = _getLogColor(log.logType);
        final iconData = _getLogIcon(log.logType);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            decoration: ShapeDecoration(
              color: const Color(0xFF0F172A),
              shape: BeveledRectangleBorder(
                borderRadius: BorderRadius.circular(
                  12,
                ), // Corte tático nas bordas
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
                // Cabeçalho do Card (Estilo Badge Militar)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
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
                ),

                // Corpo do Card
                Padding(
                  padding: const EdgeInsets.all(16.0),
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
                            if (log.vetName != null &&
                                log.vetName!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black38,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Text(
                                  'VET/RESP: ${log.vetName!.toUpperCase()}',
                                  style: GoogleFonts.shareTechMono(
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                            if (isExam && hasAttachments) ...[
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: accentColor,
                                    width: 1.5,
                                  ),
                                  foregroundColor: accentColor,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                onPressed: () => _openAttachment(
                                  log.mediaAttachments!.first['url'],
                                ),
                                icon: const Icon(
                                  Icons.document_scanner_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  'ACESSAR LAUDO PDF',
                                  style: GoogleFonts.oxanium(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (hasAttachments && !isExam) ...[
                        const SizedBox(width: 16),
                        _buildTacticalThumbnail(
                          log.mediaAttachments!.first['url'],
                          accentColor,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }, childCount: logs.length),
    );
  }

  Widget _buildTacticalThumbnail(String? url, Color accentColor) {
    if (url == null) return const SizedBox.shrink();
    return Container(
      width: 75,
      height: 75,
      padding: const EdgeInsets.all(2), // Espaço para dar efeito de moldura
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
          imageUrl: url,
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

  Color _getLogColor(String type) {
    switch (type) {
      case 'Vacina':
        return const Color(0xFFFF00FF); // Magenta Neon
      case 'Exame':
        return Colors.cyanAccent;
      case 'Banho':
        return const Color(0xFF00BFFF); // Deep Sky Blue Neon
      case 'Consulta':
        return Colors.orangeAccent;
      default:
        return Colors.cyan;
    }
  }

  IconData _getLogIcon(String type) {
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

  Future<void> _openAttachment(String? url) async {
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
