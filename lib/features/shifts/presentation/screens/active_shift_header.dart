part of 'active_shift_dashboard_screen.dart';

/// Cabeçalho do turno: cão + condutor, status, tempo ativo, botão troca.
class _ShiftHeader extends StatelessWidget {
  final Dog dog;
  final String callsign;
  final VoidCallback onSwitchDog;

  const _ShiftHeader({
    required this.dog,
    required this.callsign,
    required this.onSwitchDog,
  });

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final elapsed = _formatElapsed(shiftVM.shiftStartTime);
    final status = shiftVM.hasActiveShift ? 'Turno ativo' : 'Sem turno';
    final statusColor = shiftVM.hasActiveShift ? _hudGreen : Colors.white38;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          // Avatares sobrepostos (cão + condutor)
          SizedBox(
            width: 72,
            height: 44,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  child: _CircleAvatar(
                    imageUrl: dog.profileImageUrl,
                    fallbackIcon: Icons.pets_rounded,
                    borderColor: _hudCyan,
                    size: 40,
                  ),
                ),
                Positioned(
                  left: 28,
                  child: _CircleAvatar(
                    imageUrl: null,
                    fallbackIcon: Icons.person,
                    borderColor: Colors.white38,
                    size: 40,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Texto dinâmico
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${dog.name} • $callsign',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status,
                      style: GoogleFonts.inter(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      ' • $elapsed',
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Botão troca de cão
          InkWell(
            onTap: onSwitchDog,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _hudCyan.withAlpha(120)),
                color: _hudPanel.withAlpha(200),
              ),
              child: const Icon(
                Icons.swap_horiz_rounded,
                color: _hudCyan,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatElapsed(DateTime? startTime) {
    if (startTime == null) return '';
    final diff = DateTime.now().difference(startTime);
    if (diff.inHours > 0) {
      return 'há ${diff.inHours}h${diff.inMinutes.remainder(60)}min';
    }
    return 'há ${diff.inMinutes}min';
  }
}

class _CircleAvatar extends StatelessWidget {
  final String? imageUrl;
  final IconData fallbackIcon;
  final Color borderColor;
  final double size;

  const _CircleAvatar({
    required this.imageUrl,
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
        border: Border.all(color: borderColor, width: 1.5),
        color: _hudPanel,
      ),
      child: ClipOval(
        child: imageUrl != null
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                placeholder: (context, url) => Icon(
                  fallbackIcon,
                  color: borderColor,
                  size: size * 0.45,
                ),
                errorWidget: (context, url, error) => Icon(
                  fallbackIcon,
                  color: borderColor,
                  size: size * 0.45,
                ),
              )
            : Center(
                child: Icon(
                  fallbackIcon,
                  color: borderColor,
                  size: size * 0.45,
                ),
              ),
      ),
    );
  }
}
