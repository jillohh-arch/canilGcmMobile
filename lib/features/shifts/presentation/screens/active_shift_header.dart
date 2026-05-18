part of 'active_shift_dashboard_screen.dart';

// ── Design tokens (mockup 10_dashboard) ──────────────────────────────────────
const Color _kSurface = Color(0xFF0E1A1F);
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

  const _SectionLabel({
    required this.emoji,
    required this.text,
    this.trailing,
  });

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
            child: Container(
              height: 1,
              color: AppTheme.primary.withAlpha(38),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}


/// Header compacto fiel ao mockup 10_dashboard.
class _ShiftHeader extends StatelessWidget {
  final Dog dog;
  final String callsign;
  final String? conductorPhotoUrl;
  final VoidCallback onSwitchDog;
  final VoidCallback? onProfile;

  const _ShiftHeader({
    required this.dog,
    required this.callsign,
    this.conductorPhotoUrl,
    required this.onSwitchDog,
    this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final elapsed = _formatElapsed(shiftVM.shiftStartTime);
    final conductorName = _shortName(callsign);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(10),
        border: Border(
          bottom: BorderSide(color: AppTheme.primary.withAlpha(30)),
        ),
      ),
      child: Row(
        children: [
          // Avatares sobrepostos
          SizedBox(
            width: 60,
            height: 38,
            child: Stack(
              children: [
                _SmallAvatar(
                  imageUrl: dog.profileImageUrl,
                  fallbackText: dog.name.isNotEmpty
                      ? dog.name.substring(0, dog.name.length.clamp(0, 4)).toUpperCase()
                      : 'K9',
                  borderColor: AppTheme.primary,
                ),
                Positioned(
                  left: 28,
                  child: _SmallAvatar(
                    imageUrl: conductorPhotoUrl,
                    fallbackText: conductorName.length >= 3
                        ? conductorName.substring(0, 3).toUpperCase()
                        : conductorName.toUpperCase(),
                    borderColor: AppTheme.primary.withAlpha(128),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${dog.name} · GCM $conductorName',
                  style: GoogleFonts.inter(
                    color: _kTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.success,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Turno ativo',
                      style: GoogleFonts.inter(
                        color: AppTheme.success,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '· $elapsed',
                      style: GoogleFonts.inter(
                        color: _kTextSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Botão trocar cão
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onSwitchDog();
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary.withAlpha(51)),
              ),
              child: const Center(
                child: Icon(
                  Icons.compare_arrows_rounded,
                  color: AppTheme.primary,
                  size: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Botão perfil do condutor
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              if (onProfile != null) onProfile!();
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary.withAlpha(51)),
              ),
              child: const Center(
                child: Icon(
                  Icons.person_outline_rounded,
                  color: AppTheme.primary,
                  size: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _shortName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Condutor';
    final pieces = trimmed.split(RegExp(r'\s+'));
    return pieces.length <= 1 ? pieces.first : pieces.last;
  }

  String _formatElapsed(DateTime? start) {
    if (start == null) return '--';
    final diff = DateTime.now().difference(start);
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    return 'há ${diff.inHours}h';
  }
}

/// Avatar circular 38px para o header compacto.
class _SmallAvatar extends StatelessWidget {
  final String? imageUrl;
  final String fallbackText;
  final Color borderColor;

  const _SmallAvatar({
    this.imageUrl,
    required this.fallbackText,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1A2A30),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: ClipOval(
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                placeholder: (_, __) => _fallbackWidget(),
                errorWidget: (_, __, ___) => _fallbackWidget(),
              )
            : _fallbackWidget(),
      ),
    );
  }

  Widget _fallbackWidget() {
    return Container(
      color: const Color(0xFF1A2A30),
      alignment: Alignment.center,
      child: Text(
        fallbackText,
        style: GoogleFonts.inter(
          color: AppTheme.primary,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
