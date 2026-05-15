part of 'training_hub_screen.dart';

class _TrainingHubHeader extends StatelessWidget {
  final Dog dog;
  const _TrainingHubHeader({required this.dog});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TREINOS',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Hub de Treinos',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.pets_rounded, size: 14, color: AppTheme.textTertiary),
              const SizedBox(width: 6),
              Text(
                dog.name,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.textTertiary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                dog.breed,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}