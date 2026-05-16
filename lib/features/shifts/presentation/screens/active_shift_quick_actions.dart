part of 'active_shift_dashboard_screen.dart';

/// Seção "REGISTRAR" com grid 2x2 compacto institucional.
class _QuickActionsSection extends StatelessWidget {
  final Dog dog;
  final List<QuickAction> actions;

  const _QuickActionsSection({required this.dog, required this.actions});

  @override
  Widget build(BuildContext context) {
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);
    final incidentVM = Provider.of<IncidentViewModel>(context);
    final nutritionVM = Provider.of<NutritionViewModel>(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(text: 'REGISTRAR'),
        const SizedBox(height: 12),
        _buildGrid(context, trainingVM, healthVM, incidentVM, nutritionVM),
      ],
    );
  }

  Widget _buildGrid(
    BuildContext context,
    TrainingViewModel trainingVM,
    HealthViewModel healthVM,
    IncidentViewModel incidentVM,
    NutritionViewModel nutritionVM,
  ) {
    final lastTraining = _lastAgo(trainingVM.trainings.isNotEmpty
        ? trainingVM.trainings.first.date
        : null);
    final lastHealth = _lastAgo(healthVM.healthLogs.isNotEmpty
        ? healthVM.healthLogs.first.date
        : null);
    final lastIncident = _lastAgo(incidentVM.incidents.isNotEmpty
        ? incidentVM.incidents.first.date
        : null);
    final lastNutrition = _lastAgo(nutritionVM.todayFeedings.isNotEmpty
        ? nutritionVM.todayFeedings.first.fedAt
        : null);

    if (actions.isNotEmpty) {
      final items = actions.map((a) => _QuickActionCard(
        label: a.nome,
        sublabel: 'Último registro',
        lastAgo: '',
        icon: _resolveIcon(a.icone),
        color: _resolveColor(a.cor),
        onTap: () => _openSheet(context, a.tipo, a.nome),
      )).toList();
      return _buildGridLayout(items);
    }

    return _buildGridLayout([
      _QuickActionCard(
        label: 'Nutrição',
        sublabel: 'Última refeição',
        lastAgo: lastNutrition.isNotEmpty ? lastNutrition : '—',
        icon: Icons.restaurant_outlined,
        color: AppTheme.attention,
        onTap: () => _openNutrition(context),
      ),
      _QuickActionCard(
        label: 'Saúde',
        sublabel: 'Último registro',
        lastAgo: lastHealth.isNotEmpty ? lastHealth : '—',
        icon: Icons.medical_services_outlined,
        color: AppTheme.success,
        onTap: () => _openSheet(context, 'saude', 'Saúde'),
      ),
      _QuickActionCard(
        label: 'Treino',
        sublabel: 'Último treino',
        lastAgo: lastTraining.isNotEmpty ? lastTraining : '—',
        icon: Icons.fitness_center_rounded,
        color: AppTheme.primary,
        onTap: () => _openSheet(context, 'treino', 'Treino'),
      ),
      _QuickActionCard(
        label: 'Ocorrência',
        sublabel: 'Última ocorrência',
        lastAgo: lastIncident.isNotEmpty ? lastIncident : '—',
        icon: Icons.local_police_outlined,
        color: AppTheme.error,
        onTap: () => _openSheet(context, 'ocorrencia', 'Ocorrência'),
      ),
    ]);
  }

  Widget _buildGridLayout(List<Widget> items) {
    final rows = <Widget>[];
    for (int i = 0; i < items.length; i += 2) {
      rows.add(Row(
        children: [
          Expanded(child: items[i]),
          const SizedBox(width: 10),
          Expanded(child: i + 1 < items.length ? items[i + 1] : const SizedBox()),
        ],
      ));
      if (i + 2 < items.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }

  String _lastAgo(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    if (diff.inDays == 1) return 'há 1 dia';
    return 'há ${diff.inDays}d';
  }

  void _openNutrition(BuildContext context) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeedingRegistrationScreen(
          dogId: dog.id,
          dogName: dog.name,
        ),
      ),
    );
  }

  void _openSheet(BuildContext context, String tipo, String nome) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DynamicActivitySheet(
        category: nome,
        dogId: dog.id,
        dogName: dog.name,
      ),
    );
  }

  IconData _resolveIcon(String? iconName) {
    switch (iconName) {
      case 'assignment':
        return Icons.assignment_outlined;
      case 'fitness_center':
        return Icons.fitness_center_rounded;
      case 'medical_services':
        return Icons.medical_services_outlined;
      case 'schedule':
        return Icons.schedule_rounded;
      case 'pets':
        return Icons.pets_rounded;
      case 'local_police':
        return Icons.local_police_outlined;
      default:
        return Icons.radio_button_checked;
    }
  }

  Color _resolveColor(String? colorName) {
    switch (colorName) {
      case 'red':
      case 'danger':
        return AppTheme.error;
      case 'green':
      case 'success':
        return AppTheme.success;
      case 'amber':
      case 'warning':
        return AppTheme.warning;
      case 'orange':
      case 'attention':
        return AppTheme.attention;
      default:
        return AppTheme.primary;
    }
  }
}

/// Card individual do grid "Registrar".
class _QuickActionCard extends StatelessWidget {
  final String label;
  final String sublabel;
  final String lastAgo;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.label,
    required this.sublabel,
    required this.lastAgo,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withAlpha(15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const Spacer(),
                Icon(Icons.add_rounded, color: color.withAlpha(100), size: 16),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _kTextPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: _kTextMuted,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              lastAgo,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _kTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
