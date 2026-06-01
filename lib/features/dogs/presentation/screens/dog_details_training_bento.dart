part of 'dog_details_screen.dart';

class _TrainingSummaryBento extends StatelessWidget {
  final TrainingSessionModel? lastTraining;
  final int scentCount;

  const _TrainingSummaryBento({
    required this.lastTraining,
    required this.scentCount,
  });

  @override
  Widget build(BuildContext context) {
    return _BentoBlock(
      height: 110,
      accent: _trainingAccent,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _trainingAccent.withAlpha(30),
              border: Border.all(color: _trainingAccent.withAlpha(100)),
            ),
            child: const Icon(
              Icons.track_changes_rounded,
              color: _trainingAccent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: _TrainingSummaryText(lastTraining: lastTraining)),
          _SessionCounter(count: scentCount),
        ],
      ),
    );
  }
}

class _TrainingSummaryText extends StatelessWidget {
  final TrainingSessionModel? lastTraining;

  const _TrainingSummaryText({required this.lastTraining});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          lastTraining != null
              ? 'ÚLTIMO TREINO DE ${lastTraining!.trainingType.toUpperCase()}'
              : 'ÚLTIMO TREINO DE FARO',
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: _trainingAccent,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        if (lastTraining != null) ...[
          Text(
            '${lastTraining!.trainingType}${lastTraining!.substanceUsed != null ? " · ${lastTraining!.substanceUsed}" : ""}',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          Text(
            lastTraining!.location,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppTheme.textPrimary.withAlpha(138),
              fontWeight: FontWeight.w500,
            ),
          ),
        ] else
          Text(
            'Nenhum treino registrado',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textPrimary.withAlpha(97),
            ),
          ),
      ],
    );
  }
}

class _SessionCounter extends StatelessWidget {
  final int count;

  const _SessionCounter({required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$count',
          style: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: _trainingAccent,
          ),
        ),
        Text(
          'SESSÕES',
          style: GoogleFonts.inter(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary.withAlpha(97),
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}
