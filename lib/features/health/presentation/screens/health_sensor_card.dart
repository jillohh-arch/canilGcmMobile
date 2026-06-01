part of 'health_dashboard_screen.dart';

class _SensorCard extends StatelessWidget {
  final String label;
  final String value;
  final Widget icon;
  final bool isSelected;
  final VoidCallback? onTap;

  const _SensorCard({
    required this.label,
    required this.value,
    required this.icon,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.infoStrong.withValues(alpha: 0.3)
              : AppTheme.surfacePanelAlt,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(6),
            topRight: const Radius.circular(6),
            bottomLeft: Radius.circular(isSelected ? 0 : 8),
            bottomRight: Radius.circular(isSelected ? 0 : 8),
          ),
          border: Border.all(
            color: isSelected
                ? AppTheme.primary
                : AppTheme.primary.withValues(alpha: 0.2),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Stack(
          children: [
            if (onTap != null)
              Positioned(
                top: 0,
                right: 6,
                child: Icon(
                  Icons.edit_rounded,
                  size: 14,
                  color: AppTheme.primary.withValues(alpha: 0.85),
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(height: 12),
                Text(
                  value,
                  style: GoogleFonts.shareTechMono(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? AppTheme.primary
                        : AppTheme.primary.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isSelected
                        ? AppTheme.textPrimary
                        : AppTheme.textPrimary.withAlpha(138),
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (onTap != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'TOQUE PARA ALTERAR',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 7,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primary.withValues(alpha: 0.68),
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
