part of 'active_shift_dashboard_screen.dart';

/// Cabeçalho do turno usando BinomioHeader universal.
class _ShiftHeader extends StatelessWidget {
  final Dog dog;
  final String callsign;
  final String? conductorPhotoUrl;
  final VoidCallback onSwitchDog;

  const _ShiftHeader({
    required this.dog,
    required this.callsign,
    this.conductorPhotoUrl,
    required this.onSwitchDog,
  });

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final elapsed = _formatElapsed(shiftVM.shiftStartTime);
    final status = shiftVM.hasActiveShift ? 'Turno ativo' : 'Sem turno';
    final statusColor = shiftVM.hasActiveShift ? AppTheme.success : AppTheme.textTertiary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: BinomioHeader(
        dog: dog,
        conductorPhotoUrl: conductorPhotoUrl,
        subtitle: '$status · $elapsed',
        subtitleColor: AppTheme.textSecondary,
        showStatusDot: true,
        statusDotColor: statusColor,
        trailing: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onSwitchDog();
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.primary.withAlpha(60)),
            ),
            child: const Center(
              child: Icon(Icons.swap_horiz_rounded, size: 22, color: AppTheme.primary),
            ),
          ),
        ),
      ),
    );
  }

  String _formatElapsed(DateTime? startTime) {
    if (startTime == null) return '--:--';
    final diff = DateTime.now().difference(startTime);
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    if (hours == 0) return 'há ${minutes}min';
    return 'há ${hours}h${minutes > 0 ? minutes.toString().padLeft(2, '0') : ''}';
  }
}

class _CircleAvatar extends StatelessWidget {
  final String? imageUrl;
  final IconData fallbackIcon;
  final Color borderColor;
  final double size;

  const _CircleAvatar({
    this.imageUrl,
    required this.fallbackIcon,
    required this.borderColor,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.background,
        border: Border.all(color: borderColor, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: borderColor.withAlpha(35),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipOval(
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => _fallback(),
                errorWidget: (_, __, ___) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      color: const Color(0xFF1A2A30),
      child: Center(
        child: Icon(fallbackIcon, color: borderColor.withAlpha(180), size: size * 0.4),
      ),
    );
  }
}
