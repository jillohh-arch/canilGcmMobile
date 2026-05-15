part of 'active_shift_dashboard_screen.dart';

/// Cabeçalho do turno: cão + condutor, status, tempo ativo, botão troca.
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
      child: Row(
        children: [
          // Avatares sobrepostos (cão + condutor)
          SizedBox(
            width: 80,
            height: 50,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  child: _CircleAvatar(
                    imageUrl: dog.profileImageUrl,
                    fallbackIcon: Icons.pets_rounded,
                    borderColor: AppTheme.primary,
                    size: 46,
                  ),
                ),
                Positioned(
                  left: 32,
                  child: _CircleAvatar(
                    imageUrl: conductorPhotoUrl,
                    fallbackIcon: Icons.person,
                    borderColor: AppTheme.textTertiary,
                    size: 46,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${dog.name} · $callsign',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$status · $elapsed',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Botão trocar cão
          IconButton(
            onPressed: onSwitchDog,
            icon: const Icon(Icons.swap_horiz_rounded, size: 22),
            color: AppTheme.primary,
            tooltip: 'Trocar cão',
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.primary.withAlpha(15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatElapsed(DateTime? startTime) {
    if (startTime == null) return '--:--';
    final diff = DateTime.now().difference(startTime);
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    return '${hours}h${minutes.toString().padLeft(2, '0')}';
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
        border: Border.all(color: borderColor.withAlpha(150), width: 2),
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
      color: const Color(0xFF1A2328),
      child: Center(
        child: Icon(fallbackIcon, color: AppTheme.textTertiary, size: size * 0.4),
      ),
    );
  }
}