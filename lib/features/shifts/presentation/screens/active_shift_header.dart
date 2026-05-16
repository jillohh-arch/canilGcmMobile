part of 'active_shift_dashboard_screen.dart';

// ─── Design tokens locais ───────────────────────────────────────────────────
const Color _kSurface = Color(0xFF0B171C);
const Color _kSurfaceElevated = Color(0xFF0F2026);
const Color _kBorder = Color(0x294DD0E1); // rgba(77,208,225,0.16)
const Color _kTextPrimary = Color(0xFFF4F7F8);
const Color _kTextSecondary = Color(0xFFA7B4BA);
const Color _kTextMuted = Color(0xFF5F7078);

/// Header operacional: avatares sobrepostos, nome do binômio, status, botões.
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
    final startTime = _formatStartTime(shiftVM.shiftStartTime);
    final isActive = shiftVM.hasActiveShift;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          // Avatares sobrepostos
          SizedBox(
            width: 72,
            height: 48,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  child: _HeaderAvatar(
                    imageUrl: dog.profileImageUrl,
                    fallbackText: dog.name.isNotEmpty ? dog.name[0] : 'K',
                    borderColor: AppTheme.primary,
                    size: 44,
                  ),
                ),
                Positioned(
                  left: 28,
                  child: _HeaderAvatar(
                    imageUrl: conductorPhotoUrl,
                    fallbackIcon: Icons.person_rounded,
                    borderColor: AppTheme.success,
                    size: 44,
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${dog.name} · ${callsign.split(' ').last}',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _kTextPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive ? AppTheme.success : _kTextMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isActive
                            ? 'Turno ativo desde $startTime'
                            : 'Sem turno ativo',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _kTextSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'K9 Operacional',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _kTextMuted,
                  ),
                ),
              ],
            ),
          ),

          // Botões à direita
          const SizedBox(width: 8),
          _HeaderIconButton(
            icon: Icons.swap_horiz_rounded,
            onTap: () {
              HapticFeedback.lightImpact();
              onSwitchDog();
            },
          ),
          const SizedBox(width: 6),
          _HeaderIconButton(
            icon: Icons.person_outline_rounded,
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
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
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  String _formatStartTime(DateTime? start) {
    if (start == null) return '--:--';
    return '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
  }
}

/// Botão de ícone compacto para o header.
class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.primary.withAlpha(15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.primary.withAlpha(40)),
        ),
        child: Center(
          child: Icon(icon, size: 18, color: AppTheme.primary),
        ),
      ),
    );
  }
}

/// Avatar circular para o header.
class _HeaderAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? fallbackText;
  final IconData? fallbackIcon;
  final Color borderColor;
  final double size;

  const _HeaderAvatar({
    this.imageUrl,
    this.fallbackText,
    this.fallbackIcon,
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
        border: Border.all(color: borderColor, width: 2),
      ),
      child: ClipOval(
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, __) => _buildFallback(),
                errorWidget: (_, __, ___) => _buildFallback(),
              )
            : _buildFallback(),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      color: const Color(0xFF0F2026),
      child: Center(
        child: fallbackText != null
            ? Text(
                fallbackText!,
                style: GoogleFonts.inter(
                  color: borderColor,
                  fontSize: size * 0.32,
                  fontWeight: FontWeight.w800,
                ),
              )
            : Icon(
                fallbackIcon ?? Icons.person_rounded,
                color: borderColor.withAlpha(180),
                size: size * 0.4,
              ),
      ),
    );
  }
}
