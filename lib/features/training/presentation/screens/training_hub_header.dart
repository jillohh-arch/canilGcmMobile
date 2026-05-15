part of 'training_hub_screen.dart';

class _TrainingHubHeader extends StatelessWidget {
  final Dog dog;
  const _TrainingHubHeader({required this.dog});

  @override
  Widget build(BuildContext context) {
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final weekCount = _countThisWeek(trainingVM);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Treinos',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
              children: [
                TextSpan(
                  text: '$weekCount sessões',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
                const TextSpan(text: ' esta semana'),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.pets_rounded, size: 13, color: AppTheme.textTertiary),
              const SizedBox(width: 5),
              Text(
                '${dog.name} · ${dog.breed}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _countThisWeek(TrainingViewModel vm) {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    return vm.trainings.where((t) => t.date.isAfter(start)).length;
  }
}
