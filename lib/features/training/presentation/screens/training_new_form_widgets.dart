part of 'training_log_screen.dart';

class _TrainingSectionLabel extends StatelessWidget {
  final String title;

  const _TrainingSectionLabel(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          color: AppTheme.textMuted,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

String? _requiredField(String? value) {
  return value == null || value.isEmpty ? 'Obrigatório' : null;
}

(IconData, Color) _trainingSessionStyle(String type) {
  switch (type) {
    case 'Faro':
      return (Icons.track_changes_rounded, AppTheme.amber);
    case 'Proteção':
      return (Icons.shield_rounded, AppTheme.errorStrong);
    case 'Obediência':
      return (Icons.school_rounded, AppTheme.info);
    default:
      return (Icons.fitness_center_rounded, AppTheme.amber);
  }
}
