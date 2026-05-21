part of 'active_shift_dashboard_screen.dart';

/// SeÃ§Ã£o "Registrar" fiel ao mockup: grid 2x2 com Ã­cone + nome + meta.
class _QuickActionsSection extends StatelessWidget {
  final Dog dog;
  final List<QuickAction> actions;

  const _QuickActionsSection({required this.dog, required this.actions});

  @override
  Widget build(BuildContext context) {
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);
    final occurrenceVM = Provider.of<OccurrenceViewModel>(context);
    final nutritionVM = Provider.of<NutritionViewModel>(context);

    final cards = _buildCards(
      context,
      trainingVM,
      healthVM,
      occurrenceVM,
      nutritionVM,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(emoji: 'âš¡', text: 'REGISTRAR'),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cards,
        ),
      ],
    );
  }

  List<Widget> _buildCards(
    BuildContext context,
    TrainingViewModel trainingVM,
    HealthViewModel healthVM,
    OccurrenceViewModel occurrenceVM,
    NutritionViewModel nutritionVM,
  ) {
    final lastNutrition = _lastAgo(
      nutritionVM.todayFeedings.isNotEmpty
          ? nutritionVM.todayFeedings.first.fedAt
          : null,
    );
    final lastHealth = _lastAgo(
      healthVM.healthLogs.isNotEmpty ? healthVM.healthLogs.first.date : null,
    );
    final lastTraining = _lastAgo(
      trainingVM.trainings.isNotEmpty ? trainingVM.trainings.first.date : null,
    );
    final lastOccurrence = _lastAgo(
      occurrenceVM.occurrences.isNotEmpty
          ? occurrenceVM.occurrences.first.startedAt
          : null,
    );

    return [
      _QuickCard(
        icon: Icons.restaurant_rounded,
        color: const Color(0xFFE67E22),
        label: 'NutriÃ§Ã£o',
        meta: lastNutrition.isNotEmpty
            ? 'Ãºltima $lastNutrition'
            : 'sem registro',
        onTap: () => _openNutrition(context),
      ),
      _QuickCard(
        icon: Icons.local_hospital_rounded,
        color: AppTheme.error,
        label: 'SaÃºde',
        meta: lastHealth.isNotEmpty ? 'Ãºltima $lastHealth' : 'sem registro',
        onTap: () => _openSheet(context, 'SaÃºde'),
      ),
      _QuickCard(
        icon: Icons.fitness_center_rounded,
        color: AppTheme.warning,
        label: 'Treino',
        meta: lastTraining.isNotEmpty
            ? 'Ãºltima $lastTraining'
            : 'sem registro',
        onTap: () => _openSheet(context, 'Treino'),
      ),
      _QuickCard(
        icon: Icons.shield_rounded,
        color: AppTheme.primary,
        label: 'OcorrÃªncia',
        meta: lastOccurrence.isNotEmpty
            ? 'Ãºltima $lastOccurrence'
            : 'sem registro',
        onTap: () => _openOccurrence(context),
      ),
    ];
  }

  String _lastAgo(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'hÃ¡ ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'hÃ¡ ${diff.inHours}h';
    if (diff.inDays == 1) return 'hÃ¡ 1d';
    return 'hÃ¡ ${diff.inDays}d';
  }

  void _openNutrition(BuildContext context) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            FeedingRegistrationScreen(dogId: dog.id, dogName: dog.name),
      ),
    );
  }

  void _openSheet(BuildContext context, String nome) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DynamicActivitySheet(
        category: nome,
        dogId: dog.id,
        dogName: dog.name,
      ),
    );
  }

  void _openOccurrence(BuildContext context) {
    HapticFeedback.mediumImpact();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StartOccurrenceScreen()));
  }
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String meta;
  final VoidCallback onTap;

  const _QuickCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.meta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          border: Border.all(color: _kBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: _kTextPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: GoogleFonts.inter(color: _kTextMuted, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
