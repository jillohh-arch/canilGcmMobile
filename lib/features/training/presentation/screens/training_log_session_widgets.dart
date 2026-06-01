part of 'training_log_screen.dart';

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  const _SectionHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: _hudCyan.withAlpha(210),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.amber.withAlpha(40),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _hudCyan,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: _hudCyan.withAlpha(55))),
      ],
    );
  }
}

class _SessionCard extends StatefulWidget {
  final TrainingSessionModel session;
  const _SessionCard({required this.session});

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _expanded = false;

  (IconData, Color) _typeStyle(String type) {
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

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final (icon, color) = _typeStyle(session.trainingType);
    final dateText =
        '${session.date.day.toString().padLeft(2, '0')}/${session.date.month.toString().padLeft(2, '0')}/${session.date.year}';

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfacePanel,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _expanded ? color.withAlpha(210) : color.withAlpha(90),
            width: _expanded ? 1 : 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(_expanded ? 55 : 22),
              blurRadius: _expanded ? 22 : 12,
              offset: const Offset(0, 8),
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withAlpha(_expanded ? 36 : 22),
              AppTheme.surfacePanelSoft,
              AppTheme.background,
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SessionCardHeader(
              session: session,
              icon: icon,
              color: color,
              dateText: dateText,
              expanded: _expanded,
            ),
            _SessionStateLine(expanded: _expanded, color: color),
            if (_expanded)
              _SessionExpandedDetails(session: session, color: color),
          ],
        ),
      ),
    );
  }
}

class _EmptyTraining extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _hudPanel.withAlpha(220),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _hudCyan.withAlpha(55)),
          ),
          child: Column(
            children: [
              Icon(Icons.track_changes_rounded, size: 56, color: _hudCyan),
              const SizedBox(height: 12),
              Text(
                'Nenhum treino registrado',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Toque em + para adicionar uma sessão.',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// New Training Form
