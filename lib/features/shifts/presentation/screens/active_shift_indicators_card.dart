part of 'active_shift_dashboard_screen.dart';

/// Card "RESUMO DO TURNO" com 4 colunas: Tempo, Ocorrências, Treinos, Saúde.
class _ShiftSummaryCard extends StatelessWidget {
  final Dog dog;

  const _ShiftSummaryCard({required this.dog});

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);
    final incidentVM = Provider.of<IncidentViewModel>(context);

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final elapsed = _formatElapsed(shiftVM.shiftStartTime);
    final startTime = _formatStartTime(shiftVM.shiftStartTime);

    final todayIncidents = incidentVM.incidents
        .where((i) => i.date.isAfter(startOfDay))
        .length;
    final todayTrainings = trainingVM.trainings
        .where((t) => t.date.isAfter(startOfDay))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(text: 'RESUMO DO TURNO'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kBorder),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _SummaryColumn(
                    icon: Icons.schedule_rounded,
                    iconColor: AppTheme.primary,
                    value: elapsed,
                    label: 'Início $startTime',
                  ),
                ),
                _verticalDivider(),
                Expanded(
                  child: _SummaryColumn(
                    icon: Icons.local_police_outlined,
                    iconColor: AppTheme.error,
                    value: '$todayIncidents',
                    label: 'Hoje',
                  ),
                ),
                _verticalDivider(),
                Expanded(
                  child: _SummaryColumn(
                    icon: Icons.fitness_center_rounded,
                    iconColor: AppTheme.primary,
                    value: '$todayTrainings',
                    label: 'Hoje',
                  ),
                ),
                _verticalDivider(),
                Expanded(
                  child: _SummaryColumn(
                    icon: Icons.favorite_outline_rounded,
                    iconColor: AppTheme.success,
                    value: 'OK',
                    label: 'Status do cão',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _verticalDivider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: _kBorder,
    );
  }

  String _formatElapsed(DateTime? startTime) {
    if (startTime == null) return '0h 00m';
    final diff = DateTime.now().difference(startTime);
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  String _formatStartTime(DateTime? start) {
    if (start == null) return '--:--';
    return '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
  }
}

/// Coluna individual do resumo.
class _SummaryColumn extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _SummaryColumn({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: _kTextPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: _kTextMuted,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Label de seção reutilizável.
class _SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const _SectionLabel({required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(height: 1, color: AppTheme.primary.withAlpha(25)),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ],
      ],
    );
  }
}
