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
          color: Colors.white38,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

String? _requiredField(String? value) {
  return value == null || value.isEmpty ? 'ObrigatÃ³rio' : null;
}

(IconData, Color) _trainingSessionStyle(String type) {
  switch (type) {
    case 'Faro':
      return (Icons.track_changes_rounded, const Color(0xFFFFB300));
    case 'ProteÃ§Ã£o':
      return (Icons.shield_rounded, const Color(0xFFEF5350));
    case 'ObediÃªncia':
      return (Icons.school_rounded, const Color(0xFF42A5F5));
    default:
      return (Icons.fitness_center_rounded, AppTheme.amber);
  }
}
