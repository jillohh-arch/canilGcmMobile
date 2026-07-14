part of 'active_shift_dashboard_screen.dart';

/// Central de ações do turno, com contexto real do binômio.
class _QuickActionsSection extends StatelessWidget {
  final Dog? dog;
  final List<QuickAction> actions;
  final VoidCallback? onOpenTrainingHub;
  final VoidCallback? onOpenHealthTab;

  const _QuickActionsSection({
    required this.dog,
    required this.actions,
    this.onOpenTrainingHub,
    this.onOpenHealthTab,
  });

  @override
  Widget build(BuildContext context) {
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);
    final occurrenceVM = Provider.of<OccurrenceViewModel>(context);
    final nutritionVM = Provider.of<NutritionViewModel>(context);
    final hasK9 = dog != null;
    final now = DateTime.now();
    final trainings7d = trainingVM.trainings
        .where((training) => _isWithinDays(training.date, now, 7))
        .length;
    final health7d = healthVM.healthLogs
        .where((log) => _isWithinDays(log.date, now, 7))
        .length;
    final occurrences7d = occurrenceVM.occurrences
        .where((occurrence) => _isWithinDays(occurrence.startedAt, now, 7))
        .length;
    final todayFeedings = nutritionVM.todayFeedings
        .where((feeding) => _isSameDay(feeding.fedAt, now))
        .length;
    final lastTraining = _latestDate(trainingVM.trainings.map((t) => t.date));
    final lastHealth = _latestDate(healthVM.healthLogs.map((h) => h.date));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DashboardPanelTitle(
            icon: Icons.bolt_rounded,
            title: 'Central de ação',
            subtitle: 'Atalhos com contexto real do turno',
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _CommandCard(
                      icon: Icons.shield_rounded,
                      color: AppTheme.attention,
                      eyebrow: hasK9 ? '$occurrences7d em 7d' : 'K9 necessário',
                      title: 'Operação',
                      subtitle: hasK9
                          ? 'Abrir ocorrência operacional'
                          : 'Associe um K9 para registrar',
                      actionLabel: hasK9 ? 'Registrar' : 'Associar',
                      onTap: () => hasK9
                          ? _openOccurrence(context)
                          : _promptAssociateDog(context),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _CommandCard(
                      icon: Icons.fitness_center_rounded,
                      color: AppTheme.warning,
                      eyebrow: hasK9 ? '$trainings7d em 7d' : 'K9 necessário',
                      title: 'Treino',
                      subtitle: hasK9
                          ? _lastAgo(lastTraining)
                          : 'Associe um K9 para treinar',
                      actionLabel: hasK9 ? 'Abrir hub' : 'Associar',
                      onTap: () => hasK9
                          ? _openTrainingHub(context)
                          : _promptAssociateDog(context),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _CommandCard(
                      icon: Icons.local_hospital_rounded,
                      color: AppTheme.success,
                      eyebrow: hasK9 ? '$health7d em 7d' : 'K9 necessário',
                      title: 'Saúde',
                      subtitle: hasK9
                          ? _lastAgo(lastHealth)
                          : 'Associe um K9 para acessar',
                      actionLabel: hasK9 ? 'Prontuário' : 'Associar',
                      onTap: () => hasK9
                          ? _openHealth(context)
                          : _promptAssociateDog(context),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _CommandCard(
                      icon: Icons.restaurant_rounded,
                      color: AppTheme.primary,
                      eyebrow: hasK9 ? '$todayFeedings hoje' : 'K9 necessário',
                      title: 'Nutrição',
                      subtitle: hasK9
                          ? todayFeedings == 0
                                ? 'Nenhuma refeição registrada hoje'
                                : 'Rotina alimentar em andamento'
                          : 'Associe um K9 para registrar',
                      actionLabel: hasK9 ? 'Registrar' : 'Associar',
                      onTap: () => hasK9
                          ? _openNutrition(context)
                          : _promptAssociateDog(context),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _openNutrition(BuildContext context) {
    final activeDog = dog;
    if (activeDog == null) {
      _promptAssociateDog(context);
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeedingRegistrationScreen(
          dogId: activeDog.id,
          dogName: activeDog.name,
        ),
      ),
    );
  }

  void _openHealth(BuildContext context) {
    final activeDog = dog;
    if (activeDog == null) {
      _promptAssociateDog(context);
      return;
    }
    HapticFeedback.mediumImpact();
    final callback = onOpenHealthTab;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DogHealthProntuarioScreen(dogId: activeDog.id),
      ),
    );
  }

  void _openTrainingHub(BuildContext context) {
    HapticFeedback.mediumImpact();
    final callback = onOpenTrainingHub;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TrainingHubScreen()));
  }

  void _openOccurrence(BuildContext context) {
    HapticFeedback.mediumImpact();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StartOccurrenceScreen()));
  }

  void _promptAssociateDog(BuildContext context) {
    HapticFeedback.lightImpact();
    _showDogSwitcher(context);
  }

  DateTime? _latestDate(Iterable<DateTime> dates) {
    DateTime? latest;
    for (final date in dates) {
      if (latest == null || date.isAfter(latest)) latest = date;
    }
    return latest;
  }

  String _lastAgo(DateTime? date) {
    if (date == null) return 'Sem registro recente';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Última agora';
    if (diff.inMinutes < 60) return 'Última há ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'Última há ${diff.inHours}h';
    if (diff.inDays == 1) return 'Última há 1d';
    return 'Última há ${diff.inDays}d';
  }

  bool _isWithinDays(DateTime date, DateTime now, int days) {
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));
    return !date.isBefore(start);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _CommandCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String eyebrow;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  const _CommandCard({
    required this.icon,
    required this.color,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.textPrimary.withAlpha(6),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 132),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: _kBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withAlpha(22),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: color.withAlpha(55)),
                    ),
                    child: Icon(icon, color: color, size: 19),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      eyebrow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: GoogleFonts.ibmPlexMono(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: GoogleFonts.inter(
                  color: _kTextPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  color: _kTextMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    actionLabel,
                    style: GoogleFonts.inter(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, color: color, size: 14),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
