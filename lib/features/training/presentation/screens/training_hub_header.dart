part of 'training_hub_screen.dart';

class _TrainingHubHeader extends StatelessWidget {
  final Dog dog;
  const _TrainingHubHeader({required this.dog});

  @override
  Widget build(BuildContext context) {
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final weekCount = _countThisWeek(trainingVM);
    final isShiftActive = shiftVM.hasActiveShift;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Binômio universal
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: BinomioHeader(
            dog: dog,
            subtitle: isShiftActive ? 'Turno ativo' : 'Sem turno ativo',
            subtitleColor: isShiftActive ? AppTheme.success : AppTheme.textTertiary,
            showStatusDot: true,
            statusDotColor: isShiftActive ? AppTheme.success : AppTheme.textTertiary,
            avatarSize: 46,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _headerActionBtn(context, '⇄', null),
              ],
            ),
          ),
        ),

        // Título da página
        Padding(
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
            ],
          ),
        ),
      ],
    );
  }

  int _countThisWeek(TrainingViewModel vm) {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final start = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    return vm.trainings.where((t) => t.date.isAfter(start)).length;
  }

  Widget _headerActionBtn(BuildContext context, String label, VoidCallback? onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap?.call();
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppTheme.primary.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primary.withAlpha(50)),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppTheme.primary),
          ),
        ),
      ),
    );
  }
}
