part of 'active_shift_dashboard_screen.dart';

/// Seção "Atividades de Hoje" fiel ao mockup — timeline com cards ou empty state.
class _TodayActivitiesSection extends StatelessWidget {
  final String dogId;
  final String dogName;

  const _TodayActivitiesSection({required this.dogId, required this.dogName});

  @override
  Widget build(BuildContext context) {
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);
    final incidentVM = Provider.of<IncidentViewModel>(context);
    final nutritionVM = Provider.of<NutritionViewModel>(context);

    final entries = _buildEntries(trainingVM, healthVM, incidentVM, nutritionVM);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          emoji: '📋',
          text: 'ATIVIDADES DE HOJE',
          trailing: entries.isNotEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${entries.length} registro${entries.length > 1 ? 's' : ''}',
                    style: GoogleFonts.inter(
                      color: AppTheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : null,
        ),
        if (entries.isEmpty)
          _EmptyActivitiesState(dogId: dogId, dogName: dogName)
        else
          ...entries.map((e) => _ActivityCard(entry: e)),
      ],
    );
  }

  List<_ActivityEntry> _buildEntries(
    TrainingViewModel trainingVM,
    HealthViewModel healthVM,
    IncidentViewModel incidentVM,
    NutritionViewModel nutritionVM,
  ) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final entries = <_ActivityEntry>[];

    for (final f in nutritionVM.todayFeedings) {
      entries.add(_ActivityEntry(
        title: 'Alimentação · ${f.amountGrams}g',
        subtitle: 'Registrado',
        time: f.fedAt,
        icon: Icons.rice_bowl_rounded,
        color: const Color(0xFF9B59B6),
      ));
    }

    for (final h in healthVM.healthLogs) {
      if (h.date.isAfter(startOfDay)) {
        entries.add(_ActivityEntry(
          title: h.logType,
          subtitle: h.healthObservations.isNotEmpty
              ? h.healthObservations
              : 'Registro de saúde',
          time: h.date,
          icon: Icons.local_hospital_rounded,
          color: AppTheme.error,
        ));
      }
    }

    for (final t in trainingVM.trainings) {
      if (t.date.isAfter(startOfDay)) {
        entries.add(_ActivityEntry(
          title: 'Treino · ${t.trainingType}',
          subtitle: 'Sessão registrada',
          time: t.date,
          icon: Icons.fitness_center_rounded,
          color: AppTheme.warning,
        ));
      }
    }

    for (final i in incidentVM.incidents) {
      if (i.date.isAfter(startOfDay)) {
        entries.add(_ActivityEntry(
          title: 'Ocorrência · ${i.type ?? 'Registro'}',
          subtitle: i.location,
          time: i.date,
          icon: Icons.shield_rounded,
          color: AppTheme.primary,
        ));
      }
    }

    entries.sort((a, b) => b.time.compareTo(a.time));
    return entries.take(5).toList();
  }
}

/// Card de atividade individual — horário + ícone + info.
class _ActivityCard extends StatelessWidget {
  final _ActivityEntry entry;

  const _ActivityCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        border: Border.all(color: _kBorderSubtle),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Horário
          SizedBox(
            width: 42,
            child: Text(
              timeStr,
              style: GoogleFonts.inter(
                color: _kTextMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Ícone
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: entry.color.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(entry.icon, color: entry.color, size: 14),
          ),
          const SizedBox(width: 10),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: GoogleFonts.inter(
                    color: _kTextPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    entry.subtitle,
                    style: GoogleFonts.inter(
                      color: _kTextMuted,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado vazio com chamada à ação (4 atalhos).
class _EmptyActivitiesState extends StatelessWidget {
  final String dogId;
  final String dogName;

  const _EmptyActivitiesState({required this.dogId, required this.dogName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(8),
        border: Border.all(
          color: AppTheme.primary.withAlpha(64),
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: GoogleFonts.inter(
                color: _kTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
              children: [
                TextSpan(
                  text: 'Comece o dia\n',
                  style: GoogleFonts.inter(
                    color: _kTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(
                  text: 'Registre alimentação, treino, saúde ou ocorrência',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _EmptyActionChip(
                icon: Icons.rice_bowl_rounded,
                label: 'Rotina',
                onTap: () => _openSheet(context, 'Nutrição'),
              ),
              const SizedBox(width: 8),
              _EmptyActionChip(
                icon: Icons.local_hospital_rounded,
                label: 'Saúde',
                onTap: () => _openSheet(context, 'Saúde'),
              ),
              const SizedBox(width: 8),
              _EmptyActionChip(
                icon: Icons.fitness_center_rounded,
                label: 'Treino',
                onTap: () => _openSheet(context, 'Treino'),
              ),
              const SizedBox(width: 8),
              _EmptyActionChip(
                icon: Icons.shield_rounded,
                label: 'Ocorr.',
                onTap: () => _openSheet(context, 'Ocorrência'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openSheet(BuildContext context, String category) {
    HapticFeedback.mediumImpact();
    if (category == 'Nutrição') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FeedingRegistrationScreen(dogId: dogId, dogName: dogName),
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DynamicActivitySheet(
        category: category,
        dogId: dogId,
        dogName: dogName,
      ),
    );
  }
}

class _EmptyActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _EmptyActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(10),
            border: Border.all(color: _kBorderSubtle),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: _kTextSecondary),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: _kTextSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityEntry {
  final String title;
  final String subtitle;
  final DateTime time;
  final IconData icon;
  final Color color;

  _ActivityEntry({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.icon,
    required this.color,
  });
}
