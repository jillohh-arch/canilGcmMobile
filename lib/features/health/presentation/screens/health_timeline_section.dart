part of 'health_dashboard_screen.dart';

extension _HealthDashboardTimelineSection on _HealthDashboardScreenState {
  Widget _buildTimelineHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      child: Row(
        children: [
          Container(width: 4, height: 14, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(
            'PRONTUÁRIO DE COMBATE / HISTÓRICO',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary.withAlpha(138),
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
              color: AppTheme.textPrimary.withAlpha(61),
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _TacticalHealthLogCard(
          log: logs[index],
          onOpenAttachment: _openAttachment,
        ),
        childCount: logs.length,
      ),
    );
  }

  Future<void> _openAttachment(String? url) async {
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
