part of 'active_shift_dashboard_screen.dart';

/// Seção "Registrar" fiel ao mockup: quatro ações rápidas em uma linha.
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

    final cards = _dashboardCards(
      context,
      trainingVM,
      healthVM,
      incidentVM,
      nutritionVM,
    );

    return _DashboardPanel(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        children: [
          const _PanelTitle(icon: Icons.edit_outlined, label: 'REGISTRAR'),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 390) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 8),
                        Expanded(child: cards[1]),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: cards[2]),
                        const SizedBox(width: 8),
                        Expanded(child: cards[3]),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  for (int i = 0; i < cards.length; i++) ...[
                    Expanded(child: cards[i]),
                    if (i < cards.length - 1) const SizedBox(width: 7),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _dashboardCards(
    BuildContext context,
    TrainingViewModel trainingVM,
    HealthViewModel healthVM,
    IncidentViewModel incidentVM,
    NutritionViewModel nutritionVM,
  ) {
    if (actions.isNotEmpty) {
      return actions.take(4).map((action) {
        return _QuickActionCard(
          label: action.nome,
          sublabel: 'Último',
          lastAgo: '—',
          icon: _resolveIcon(action.icone),
          color: _resolveColor(action.cor),
          onTap: () => _openSheet(context, action.nome),
        );
      }).toList();
    }

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
    final lastIncident = _lastAgo(
      incidentVM.incidents.isNotEmpty ? incidentVM.incidents.first.date : null,
    );

    return [
      _QuickActionCard(
        label: 'Nutrição',
        sublabel: 'Última',
        lastAgo: lastNutrition.isNotEmpty ? lastNutrition : '—',
        icon: Icons.rice_bowl_rounded,
        color: AppTheme.warning,
        onTap: () => _openNutrition(context),
      ),
      _QuickActionCard(
        label: 'Saúde',
        sublabel: 'Último',
        lastAgo: lastHealth.isNotEmpty ? lastHealth : '—',
        icon: Icons.local_hospital_rounded,
        color: const Color(0xFF8BE36D),
        onTap: () => _openSheet(context, 'Saúde'),
      ),
      _QuickActionCard(
        label: 'Treino',
        sublabel: 'Último',
        lastAgo: lastTraining.isNotEmpty ? lastTraining : '—',
        icon: Icons.fitness_center_rounded,
        color: AppTheme.primary,
        onTap: () => _openSheet(context, 'Treino'),
      ),
      _QuickActionCard(
        label: 'Ocorrência',
        sublabel: 'Última',
        lastAgo: lastIncident.isNotEmpty ? lastIncident : '—',
        icon: Icons.emergency_share_rounded,
        color: AppTheme.error,
        onTap: () => _openSheet(context, 'Ocorrência'),
      ),
    ];
  }

  String _lastAgo(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    if (diff.inDays == 1) return 'há 1 dia';
    return 'há ${diff.inDays}d';
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

  IconData _resolveIcon(String? iconName) {
    switch (iconName) {
      case 'assignment':
        return Icons.assignment_outlined;
      case 'fitness_center':
        return Icons.fitness_center_rounded;
      case 'medical_services':
        return Icons.local_hospital_rounded;
      case 'schedule':
        return Icons.schedule_rounded;
      case 'pets':
        return Icons.pets_rounded;
      case 'local_police':
        return Icons.emergency_share_rounded;
      case 'restaurant':
        return Icons.rice_bowl_rounded;
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
        return const Color(0xFF8BE36D);
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth > 120;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Container(
              height: compact ? 70 : 116,
              padding: compact
                  ? const EdgeInsets.fromLTRB(10, 9, 10, 9)
                  : const EdgeInsets.fromLTRB(6, 12, 6, 9),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(7),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kBorder),
              ),
              child: compact ? _compactContent() : _regularContent(),
            ),
          ),
        );
      },
    );
  }

  Widget _compactContent() {
    return Row(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AutoFitText(
                label,
                alignment: Alignment.centerLeft,
                textAlign: TextAlign.left,
                style: GoogleFonts.inter(
                  color: _kTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '$sublabel $lastAgo',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: _kTextSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _regularContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 29),
        const SizedBox(height: 10),
        _AutoFitText(
          label,
          style: GoogleFonts.inter(
            color: _kTextPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          sublabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: _kTextSecondary,
            fontSize: 10.5,
            height: 1.08,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        _AutoFitText(
          lastAgo,
          style: GoogleFonts.inter(
            color: _kTextSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
