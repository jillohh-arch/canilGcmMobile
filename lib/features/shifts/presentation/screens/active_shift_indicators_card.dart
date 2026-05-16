part of 'active_shift_dashboard_screen.dart';

/// Card "Resumo do turno" com os quatro indicadores principais do mockup.
class _ShiftSummaryCard extends StatelessWidget {
  final Dog dog;

  const _ShiftSummaryCard({required this.dog});

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final trainingVM = Provider.of<TrainingViewModel>(context);
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
    final isDogOperational =
        dog.status.toLowerCase().contains('ativo') ||
        dog.status.toLowerCase().contains('operacional');
    final healthColor = isDogOperational
        ? const Color(0xFF8BE36D)
        : AppTheme.warning;

    return _DashboardPanel(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
      child: Column(
        children: [
          _PanelTitle(
            icon: Icons.bar_chart_rounded,
            label: 'RESUMO DO TURNO',
            trailing: Icon(
              Icons.info_outline_rounded,
              color: _kTextSecondary,
              size: 22,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final metrics = [
                _SummaryMetricData(
                  icon: Icons.schedule_rounded,
                  iconColor: AppTheme.primary,
                  label: 'Tempo ativo',
                  value: elapsed,
                  footer: 'Início $startTime',
                ),
                _SummaryMetricData(
                  icon: Icons.assignment_outlined,
                  iconColor: AppTheme.warning,
                  label: 'Ocorrências',
                  value: '$todayIncidents',
                  footer: 'Hoje',
                ),
                _SummaryMetricData(
                  icon: Icons.fitness_center_rounded,
                  iconColor: AppTheme.primary,
                  label: 'Treinos',
                  value: '$todayTrainings',
                  footer: 'Hoje',
                ),
                _SummaryMetricData(
                  icon: Icons.monitor_heart_rounded,
                  iconColor: healthColor,
                  label: 'Saúde',
                  value: isDogOperational ? 'OK' : 'ALERTA',
                  footer: 'Status do cão',
                  valueColor: healthColor,
                ),
              ];

              if (constraints.maxWidth < 390) {
                return _CompactSummaryGrid(metrics: metrics);
              }

              return IntrinsicHeight(
                child: Row(
                  children: [
                    for (int i = 0; i < metrics.length; i++) ...[
                      Expanded(child: _SummaryColumn(data: metrics[i])),
                      if (i < metrics.length - 1) _SummaryDivider(),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
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

class _SummaryMetricData {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String footer;
  final Color? valueColor;

  const _SummaryMetricData({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.footer,
    this.valueColor,
  });
}

class _CompactSummaryGrid extends StatelessWidget {
  final List<_SummaryMetricData> metrics;

  const _CompactSummaryGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _SummaryTile(data: metrics[0])),
            const SizedBox(width: 10),
            Expanded(child: _SummaryTile(data: metrics[1])),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _SummaryTile(data: metrics[2])),
            const SizedBox(width: 10),
            Expanded(child: _SummaryTile(data: metrics[3])),
          ],
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final _SummaryMetricData data;

  const _SummaryTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Icon(data.icon, color: data.iconColor, size: 25),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _AutoFitText(
                  data.label,
                  alignment: Alignment.centerLeft,
                  textAlign: TextAlign.left,
                  style: GoogleFonts.inter(
                    color: _kTextSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                _AutoFitText(
                  data.value,
                  alignment: Alignment.centerLeft,
                  textAlign: TextAlign.left,
                  style: GoogleFonts.inter(
                    color: data.valueColor ?? _kTextPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                _AutoFitText(
                  data.footer,
                  alignment: Alignment.centerLeft,
                  textAlign: TextAlign.left,
                  style: GoogleFonts.inter(
                    color: _kTextMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      color: _kBorderStrong.withAlpha(75),
    );
  }
}

class _SummaryColumn extends StatelessWidget {
  final _SummaryMetricData data;

  const _SummaryColumn({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(data.icon, color: data.iconColor, size: 26),
        const SizedBox(height: 10),
        _AutoFitText(
          data.label,
          style: GoogleFonts.inter(
            color: _kTextPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        _AutoFitText(
          data.value,
          style: GoogleFonts.inter(
            color: data.valueColor ?? _kTextPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 5),
        _AutoFitText(
          data.footer,
          style: GoogleFonts.inter(
            color: _kTextSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
