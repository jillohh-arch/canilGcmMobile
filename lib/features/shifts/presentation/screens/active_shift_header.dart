part of 'active_shift_dashboard_screen.dart';

const Color _kBorder = AppTheme.surfaceWhiteBorder;
const Color _kBorderSubtle = AppTheme.surfaceWhiteBorderSubtle;
const Color _kTextPrimary = AppTheme.textPrimary;
const Color _kTextSecondary = AppTheme.textSecondary;
const Color _kTextMuted = AppTheme.textMuted;

class _SectionLabel extends StatelessWidget {
  final String emoji;
  final String text;

  const _SectionLabel({required this.emoji, required this.text});

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
        ],
      ),
    );
  }
}

class _ShiftHeader extends StatelessWidget {
  final Dog dog;
  final String? currentRa;
  final String? conductorPhotoUrl;
  final VoidCallback onSwitchDog;
  final VoidCallback? onDogHealth;
  final VoidCallback? onProfile;

  const _ShiftHeader({
    required this.dog,
    this.currentRa,
    this.conductorPhotoUrl,
    required this.onSwitchDog,
    this.onDogHealth,
    this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final elapsed = _formatElapsed(shiftVM.shiftStartTime);
    final vehicleLabel = shiftVM.vehicleLabel?.trim();

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
        subtitle: 'Turno ativo · $elapsed',
        subtitleColor: AppTheme.success,
        statusDotColor: AppTheme.success,
        showStatusDot: true,
        withBackground: false,
        conductorPhotoUrl: conductorPhotoUrl,
        notificationUserId: currentRa,
        trailing: vehicleLabel?.isNotEmpty == true
            ? _VehicleHeaderChip(label: vehicleLabel!)
            : null,
        onSwitchDog: onSwitchDog,
        onProfileTap: onProfile,
        onDogHealthTap: onDogHealth,
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

class _VehicleHeaderChip extends StatelessWidget {
  final String label;

  const _VehicleHeaderChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withAlpha(45)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          color: AppTheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
