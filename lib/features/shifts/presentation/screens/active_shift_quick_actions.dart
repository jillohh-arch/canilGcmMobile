part of 'active_shift_dashboard_screen.dart';

/// Seção de ações rápidas do turno.
class _QuickActionsSection extends StatelessWidget {
  final Dog dog;
  final List<QuickAction> actions;
  final VoidCallback? onOpenTrainingHub;

  const _QuickActionsSection({
    required this.dog,
    required this.actions,
    this.onOpenTrainingHub,
  });

  @override
  Widget build(BuildContext context) {
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
            icon: Icons.flash_on_rounded,
            title: 'Ações rápidas',
            subtitle: 'Registre alimentação, saúde, treino ou ocorrência',
          ),
          const SizedBox(height: 18),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.25,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: _buildCards(context),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCards(BuildContext context) {
    return [
      _QuickCard(
        icon: Icons.restaurant_rounded,
        color: AppTheme.primary,
        label: 'Nutrição',
        onTap: () => _openNutrition(context),
      ),
      _QuickCard(
        icon: Icons.local_hospital_rounded,
        color: AppTheme.success,
        label: 'Saúde',
        onTap: () => _openSheet(context, 'Saúde'),
      ),
      _QuickCard(
        icon: Icons.fitness_center_rounded,
        color: AppTheme.warning,
        label: 'Treino',
        onTap: () => _openTrainingHub(context),
      ),
      _QuickCard(
        icon: Icons.shield_rounded,
        color: AppTheme.attention,
        label: 'Ocorrência',
        onTap: () => _openOccurrence(context),
      ),
    ];
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
      backgroundColor: AppTheme.transparent,
      builder: (_) => DynamicActivitySheet(
        category: nome,
        dogId: dog.id,
        dogName: dog.name,
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
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _QuickCard({
    required this.icon,
    required this.color,
    required this.label,
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: _kBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 9),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: _kTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
