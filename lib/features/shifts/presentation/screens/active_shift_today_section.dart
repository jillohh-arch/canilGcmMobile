part of 'active_shift_dashboard_screen.dart';

/// Card compacto "Atividade do turno".
class _ShiftActivityCard extends StatelessWidget {
  final String dogId;
  const _ShiftActivityCard({required this.dogId});

  @override
  Widget build(BuildContext context) {
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);
    final incidentVM = Provider.of<IncidentViewModel>(context);
    final routineVM = Provider.of<RoutineViewModel>(context);
    final nutritionVM = Provider.of<NutritionViewModel>(context);

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final totalToday = _countToday(
      trainingVM,
      healthVM,
      incidentVM,
      routineVM,
      nutritionVM,
      startOfDay,
    );

    final message = totalToday == 0
        ? 'Nenhuma atividade registrada hoje.'
        : '$totalToday atividade${totalToday > 1 ? 's' : ''} registrada${totalToday > 1 ? 's' : ''} hoje.';

    return _DashboardPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 390;

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _PanelTitle(
                  icon: Icons.format_list_bulleted_rounded,
                  label: 'ATIVIDADE DO TURNO',
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: _kTextSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                _OutlineButton(
                  label: 'Registrar atividade',
                  fullWidth: true,
                  onTap: () => _openActivitySheet(context),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _PanelTitle(
                      icon: Icons.format_list_bulleted_rounded,
                      label: 'ATIVIDADE DO TURNO',
                    ),
                    const SizedBox(height: 15),
                    Text(
                      message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: _kTextSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              _OutlineButton(
                label: 'Registrar atividade',
                onTap: () => _openActivitySheet(context),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openActivitySheet(BuildContext context) {
    HapticFeedback.mediumImpact();
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    final activeDogId = shiftVM.activeDogId;
    if (activeDogId == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DynamicActivitySheet(
        category: 'Treino',
        dogId: activeDogId,
        dogName: '',
      ),
    );
  }

  int _countToday(
    TrainingViewModel trainingVM,
    HealthViewModel healthVM,
    IncidentViewModel incidentVM,
    RoutineViewModel routineVM,
    NutritionViewModel nutritionVM,
    DateTime startOfDay,
  ) {
    var count = 0;
    count += trainingVM.trainings
        .where((t) => t.date.isAfter(startOfDay))
        .length;
    count += healthVM.healthLogs
        .where((h) => h.date.isAfter(startOfDay))
        .length;
    count += incidentVM.incidents
        .where((i) => i.date.isAfter(startOfDay))
        .length;
    count += routineVM.routines
        .where((r) => r.timestamp.isAfter(startOfDay))
        .length;
    count += nutritionVM.todayFeedings.length;
    return count;
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool fullWidth;

  const _OutlineButton({
    required this.label,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 42,
          width: fullWidth ? double.infinity : 142,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(10),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.primary.withAlpha(170)),
          ),
          child: _AutoFitText(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Timeline de atividades recentes com o mesmo ritmo visual do mockup.
class _RecentActivityTimeline extends StatelessWidget {
  final String dogId;
  const _RecentActivityTimeline({required this.dogId});

  @override
  Widget build(BuildContext context) {
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);
    final incidentVM = Provider.of<IncidentViewModel>(context);
    final routineVM = Provider.of<RoutineViewModel>(context);
    final nutritionVM = Provider.of<NutritionViewModel>(context);

    final entries = _buildEntries(
      trainingVM,
      healthVM,
      incidentVM,
      routineVM,
      nutritionVM,
    ).take(3).toList();

    return _DashboardPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        children: [
          _PanelTitle(
            icon: Icons.history_rounded,
            label: 'ATIVIDADES RECENTES',
            trailing: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ver todas',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Nenhum registro recente para este turno.',
                  style: GoogleFonts.inter(
                    color: _kTextSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
          else
            Stack(
              children: [
                Positioned(
                  left: 17,
                  top: 18,
                  bottom: 18,
                  child: Container(width: 1.2, color: _kTextSecondary),
                ),
                Column(
                  children: [
                    for (int i = 0; i < entries.length; i++) ...[
                      _TimelineItem(
                        entry: entries[i],
                        railColor: _railColorForIndex(i),
                      ),
                      if (i < entries.length - 1)
                        Divider(height: 1, color: _kBorder, indent: 58),
                    ],
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Color _railColorForIndex(int index) {
    switch (index) {
      case 0:
        return _kTextSecondary;
      case 1:
        return AppTheme.warning;
      default:
        return const Color(0xFF74DB69);
    }
  }

  List<_ActivityEntry> _buildEntries(
    TrainingViewModel trainingVM,
    HealthViewModel healthVM,
    IncidentViewModel incidentVM,
    RoutineViewModel routineVM,
    NutritionViewModel nutritionVM,
  ) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final entries = <_ActivityEntry>[];

    for (final h in healthVM.healthLogs) {
      if (h.date.isAfter(startOfDay) && h.weight != null) {
        entries.add(
          _ActivityEntry(
            title: 'Pesagem operacional registrada',
            subtitle: '',
            trailing: '${h.weight!.toStringAsFixed(1)} kg',
            time: h.date,
            icon: Icons.monitor_weight_outlined,
            color: AppTheme.primary,
          ),
        );
      } else if (h.date.isAfter(startOfDay)) {
        entries.add(
          _ActivityEntry(
            title: '${h.logType} registrado',
            subtitle: h.healthObservations,
            time: h.date,
            icon: Icons.local_hospital_rounded,
            color: const Color(0xFF8BE36D),
          ),
        );
      }
    }

    for (final i in incidentVM.incidents) {
      if (i.date.isAfter(startOfDay)) {
        entries.add(
          _ActivityEntry(
            title: 'Ocorrência • ${i.type ?? 'Registro'}',
            subtitle: i.location,
            badge: 'VOCÊ',
            time: i.date,
            icon: Icons.assignment_outlined,
            color: AppTheme.warning,
          ),
        );
      }
    }

    for (final t in trainingVM.trainings) {
      if (t.date.isAfter(startOfDay)) {
        entries.add(
          _ActivityEntry(
            title: 'Treino • ${t.trainingType}',
            subtitle: 'Sessão registrada',
            time: t.date,
            icon: Icons.fitness_center_rounded,
            color: const Color(0xFF74DB69),
          ),
        );
      }
    }

    for (final r in routineVM.routines) {
      if (r.timestamp.isAfter(startOfDay)) {
        entries.add(
          _ActivityEntry(
            title: r.activityType,
            subtitle: r.notes ?? '',
            time: r.timestamp,
            icon: Icons.format_list_bulleted_rounded,
            color: AppTheme.primary,
          ),
        );
      }
    }

    for (final f in nutritionVM.todayFeedings) {
      entries.add(
        _ActivityEntry(
          title: 'Nutrição • ${f.amountGrams}g',
          subtitle: '',
          time: f.fedAt,
          icon: Icons.rice_bowl_rounded,
          color: AppTheme.warning,
        ),
      );
    }

    entries.sort((a, b) => b.time.compareTo(a.time));
    return entries;
  }
}

class _TimelineItem extends StatelessWidget {
  final _ActivityEntry entry;
  final Color railColor;

  const _TimelineItem({required this.entry, required this.railColor});

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Center(
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: railColor,
                  border: Border.all(color: _kDashboardBackground, width: 1.5),
                ),
              ),
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: entry.color.withAlpha(14),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _kBorder),
            ),
            child: Icon(entry.icon, color: entry.color, size: 21),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 45,
            child: Text(
              timeStr,
              style: GoogleFonts.inter(
                color: _kTextSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: _kTextPrimary,
                    fontSize: 13,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (entry.subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: _kTextSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (entry.trailing != null) ...[
            const SizedBox(width: 8),
            Text(
              entry.trailing!,
              style: GoogleFonts.inter(
                color: _kTextPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (entry.badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: AppTheme.warning.withAlpha(170)),
              ),
              child: Text(
                entry.badge!,
                style: GoogleFonts.inter(
                  color: AppTheme.warning,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
          const SizedBox(width: 5),
          Icon(Icons.chevron_right_rounded, color: _kTextSecondary, size: 21),
        ],
      ),
    );
  }
}

class _ActivityEntry {
  final String title;
  final String subtitle;
  final String? trailing;
  final DateTime time;
  final IconData icon;
  final Color color;
  final String? badge;

  _ActivityEntry({
    required this.title,
    required this.subtitle,
    this.trailing,
    required this.time,
    required this.icon,
    required this.color,
    this.badge,
  });
}
