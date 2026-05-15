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
        // Header universal (avatar + binômio + turno)
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(10),
            border: Border(
              bottom: BorderSide(color: AppTheme.primary.withAlpha(30)),
            ),
          ),
          child: Row(
            children: [
              // Avatar do cão (foto real)
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.primary, width: 2),
                ),
                child: ClipOval(
                  child: dog.profileImageUrl != null && dog.profileImageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: dog.profileImageUrl!,
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: const Color(0xFF1A2A30),
                            child: Center(
                              child: Text(
                                dog.name.isNotEmpty ? dog.name[0] : 'K',
                                style: GoogleFonts.inter(
                                  color: AppTheme.primary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: const Color(0xFF1A2A30),
                            child: Center(
                              child: Text(
                                dog.name.isNotEmpty ? dog.name[0] : 'K',
                                style: GoogleFonts.inter(
                                  color: AppTheme.primary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        )
                      : Container(
                          color: const Color(0xFF1A2A30),
                          child: Center(
                            child: Text(
                              dog.name.isNotEmpty ? dog.name[0] : 'K',
                              style: GoogleFonts.inter(
                                color: AppTheme.primary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              // Info binômio
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${dog.name} · ${dog.breed}',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (isShiftActive) ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppTheme.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Turno ativo',
                            style: GoogleFonts.inter(
                              color: AppTheme.success,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else
                          Text(
                            'Sem turno ativo',
                            style: GoogleFonts.inter(
                              color: AppTheme.textTertiary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Action buttons
              Row(
                children: [
                  _headerActionBtn(context, '⇄'),
                  const SizedBox(width: 6),
                  _headerActionBtn(context, '👤'),
                ],
              ),
            ],
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

  Widget _headerActionBtn(BuildContext context, String label) {
    return Container(
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
    );
  }
}
