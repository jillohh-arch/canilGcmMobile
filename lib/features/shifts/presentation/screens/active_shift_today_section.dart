part of 'active_shift_dashboard_screen.dart';

/// Card compacto "ATIVIDADE DO TURNO" — mostra estado vazio ou resumo.
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
      trainingVM, healthVM, incidentVM, routineVM, nutritionVM, startOfDay,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(text: 'ATIVIDADE DO TURNO'),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kBorder),
          ),
          child: totalToday == 0
              ? _buildEmpty(context)
              : _buildSummary(context, totalToday),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.event_note_outlined,
          color: _kTextMuted,
          size: 28,
        ),
        const SizedBox(height: 10),
        Text(
          'Nenhuma atividade registrada hoje.',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _kTextSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        _OutlineButton(
          label: 'Registrar atividade',
          onTap: () {
            HapticFeedback.mediumImpact();
            final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
            final activeDogId = shiftVM.activeDogId;
            if (activeDogId != null) {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => DynamicActivitySheet(
                  category: 'Treino',
                  dogId: activeDogId,
                  dogName: '',
                ),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context, int total) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.success.withAlpha(15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              '$total',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.success,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$total atividade${total > 1 ? 's' : ''} registrada${total > 1 ? 's' : ''} hoje',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _kTextPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Veja o histórico abaixo',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: _kTextMuted,
                ),
              ),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: _kTextMuted, size: 20),
      ],
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
    int count = 0;
    count += trainingVM.trainings.where((t) => t.date.isAfter(startOfDay)).length;
    count += healthVM.healthLogs.where((h) => h.date.isAfter(startOfDay)).length;
    count += incidentVM.incidents.where((i) => i.date.isAfter(startOfDay)).length;
    count += routineVM.routines.where((r) => r.timestamp.isAfter(startOfDay)).length;
    count += nutritionVM.todayFeedings.length;
    return count;
  }
}

/// Botão outline institucional.
class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _OutlineButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primary.withAlpha(80)),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.primary,
          ),
        ),
      ),
    );
  }
}

/// Timeline de atividades recentes com "Ver todas".
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
      trainingVM, healthVM, incidentVM, routineVM, nutritionVM,
    );

    if (entries.isEmpty) return const SizedBox.shrink();

    final displayEntries = entries.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          text: 'ATIVIDADES RECENTES',
          trailing: GestureDetector(
            onTap: () {
              // TODO: navegar para histórico completo
            },
            child: Text(
              'Ver todas',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _kSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kBorder),
          ),
          child: Column(
            children: [
              for (int i = 0; i < displayEntries.length; i++) ...[
                _TimelineItem(entry: displayEntries[i]),
                if (i < displayEntries.length - 1)
                  Divider(
                    height: 1,
                    color: _kBorder,
                    indent: 16,
                    endIndent: 16,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
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

    for (final t in trainingVM.trainings) {
      if (t.date.isAfter(startOfDay)) {
        entries.add(_ActivityEntry(
          type: 'treino',
          title: 'Treino · ${t.trainingType}',
          subtitle: 'Sessão registrada',
          time: t.date,
          icon: Icons.fitness_center_rounded,
          color: AppTheme.primary,
        ));
      }
    }

    for (final h in healthVM.healthLogs) {
      if (h.date.isAfter(startOfDay)) {
        entries.add(_ActivityEntry(
          type: 'saude',
          title: '${h.logType} registrada',
          subtitle: h.healthObservations,
          time: h.date,
          icon: Icons.medical_services_outlined,
          color: AppTheme.success,
        ));
      }
    }

    for (final i in incidentVM.incidents) {
      if (i.date.isAfter(startOfDay)) {
        entries.add(_ActivityEntry(
          type: 'ocorrencia',
          title: 'Ocorrência · ${i.type ?? 'Registro'}',
          subtitle: i.location.isNotEmpty ? i.location : '',
          time: i.date,
          icon: Icons.local_police_outlined,
          color: AppTheme.error,
          badge: 'VOCÊ',
        ));
      }
    }

    for (final r in routineVM.routines) {
      if (r.timestamp.isAfter(startOfDay)) {
        entries.add(_ActivityEntry(
          type: 'rotina',
          title: r.activityType,
          subtitle: '',
          time: r.timestamp,
          icon: Icons.schedule_rounded,
          color: AppTheme.attention,
        ));
      }
    }

    for (final f in nutritionVM.todayFeedings) {
      entries.add(_ActivityEntry(
        type: 'nutricao',
        title: 'Alimentação · ${f.amountGrams}g',
        subtitle: '',
        time: f.fedAt,
        icon: Icons.restaurant_outlined,
        color: AppTheme.attention,
      ));
    }

    entries.sort((a, b) => b.time.compareTo(a.time));
    return entries;
  }
}

/// Item individual da timeline.
class _TimelineItem extends StatelessWidget {
  final _ActivityEntry entry;

  const _TimelineItem({required this.entry});

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Ícone
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: entry.color.withAlpha(12),
              shape: BoxShape.circle,
              border: Border.all(color: entry.color.withAlpha(50)),
            ),
            child: Icon(entry.icon, color: entry.color, size: 14),
          ),
          const SizedBox(width: 12),

          // Conteúdo
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      timeStr,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _kTextMuted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.title,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _kTextPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (entry.subtitle != null && entry.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.subtitle!,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: _kTextMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            entry.badge!,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Chevron
          Icon(Icons.chevron_right_rounded, color: _kTextMuted, size: 18),
        ],
      ),
    );
  }
}

/// Modelo de entrada de atividade.
class _ActivityEntry {
  final String type;
  final String title;
  final String? subtitle;
  final DateTime time;
  final IconData icon;
  final Color color;
  final String? badge;

  _ActivityEntry({
    required this.type,
    required this.title,
    this.subtitle,
    required this.time,
    required this.icon,
    required this.color,
    this.badge,
  });
}
