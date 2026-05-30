part of 'active_shift_dashboard_screen.dart';

// ── Design tokens (mockup 10_dashboard) ──────────────────────────────────────
const Color _kBorder = Color(0x14FFFFFF); // white 8%
const Color _kBorderSubtle = Color(0x0FFFFFFF); // white 6%
const Color _kTextPrimary = Color(0xFFFFFFFF);
const Color _kTextSecondary = Color(0xFFB0C4CC);
const Color _kTextMuted = Color(0xFF5A7280);

/// Section label estilo mockup: "⚠ ALERTAS ────────────"
class _SectionLabel extends StatelessWidget {
  final String emoji;
  final String text;
  final Widget? trailing;

  const _SectionLabel({required this.emoji, required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            '$emoji $text',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(height: 1, color: AppTheme.primary.withAlpha(38)),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// Header compacto fiel ao mockup 10_dashboard.
class _ShiftHeader extends StatelessWidget {
  final Dog dog;
  final String? currentRa;
  final String? conductorPhotoUrl;
  final VoidCallback onSwitchDog;
  final VoidCallback? onProfile;

  const _ShiftHeader({
    required this.dog,
    this.currentRa,
    this.conductorPhotoUrl,
    required this.onSwitchDog,
    this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final elapsed = _formatElapsed(shiftVM.shiftStartTime);
    final vehicleLabel = shiftVM.vehicleLabel;
    final subtitle = [
      'Turno ativo',
      elapsed,
      if (vehicleLabel?.trim().isNotEmpty == true) vehicleLabel!.trim(),
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(10),
        border: Border(
          bottom: BorderSide(color: AppTheme.primary.withAlpha(30)),
        ),
      ),
      child: BinomioHeader(
        dog: dog,
        subtitle: subtitle,
        subtitleColor: AppTheme.success,
        statusDotColor: AppTheme.success,
        showStatusDot: true,
        withBackground: false,
        conductorPhotoUrl: conductorPhotoUrl,
        notificationUserId: currentRa,
        onSwitchDog: onSwitchDog,
        onProfileTap: onProfile,
      ),
    );
  }

  String _formatElapsed(DateTime? start) {
    if (start == null) return 'agora';
    final diff = DateTime.now().difference(start);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    return 'há ${diff.inDays}d';
  }
}
