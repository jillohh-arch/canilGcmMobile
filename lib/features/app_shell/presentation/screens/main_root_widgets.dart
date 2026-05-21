part of 'main_root_screen.dart';

class _ActiveOccurrenceBanner extends StatelessWidget {
  final Occurrence occurrence;
  final String dogName;
  final VoidCallback onTap;

  const _ActiveOccurrenceBanner({
    required this.occurrence,
    required this.dogName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = occurrence.typeName.trim().isEmpty
        ? 'Ocorrência'
        : occurrence.typeName;
    final location = occurrence.locationAddress?.trim().isNotEmpty == true
        ? occurrence.locationAddress!.trim()
        : 'Local não informado';

    return _ActiveOperationBannerFrame(
      label: 'OCORRÊNCIA EM ANDAMENTO',
      title: title,
      subtitle: '$dogName • $location',
      onTap: onTap,
    );
  }
}

class _ActiveOperationBannerFrame extends StatelessWidget {
  final String label;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActiveOperationBannerFrame({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1A1F).withAlpha(244),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppTheme.warning.withAlpha(190),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.warning.withAlpha(46),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
                const BoxShadow(
                  color: Colors.black54,
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withAlpha(24),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.warning.withAlpha(150)),
                  ),
                  child: const Icon(
                    Icons.pending_actions_rounded,
                    color: AppTheme.warning,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          color: AppTheme.warning,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: Colors.white60,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warning,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'CONTINUAR',
                    style: GoogleFonts.inter(
                      color: AppTheme.background,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
