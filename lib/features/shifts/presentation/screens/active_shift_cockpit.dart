part of 'active_shift_dashboard_screen.dart';

/// Monta o dashboard fiel ao mockup 10_dashboard.html.
Widget _buildCockpit(BuildContext context, Dog dog, String callsign) {
  final state = context
      .findAncestorStateOfType<_ActiveShiftDashboardScreenState>()!;
  final userVM = Provider.of<UserViewModel>(context);
  final authVM = Provider.of<AuthViewModel>(context);
  final currentRa = HandlerIdentityService.raFromUser(authVM.user);
  final userModel = userVM.users.cast<dynamic>().firstWhere(
    (u) => u?.ra == currentRa,
    orElse: () => null,
  );
  final conductorPhoto = userModel?.photoUrl as String?;

  return SafeArea(
    child: Column(
      children: [
        // Header compacto (fixo no topo)
        _ShiftHeader(
          dog: dog,
          callsign: callsign,
          conductorPhotoUrl: conductorPhoto,
          onSwitchDog: () => _showDogSwitcher(context),
        ),
        // Scroll area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Alertas (condicional)
                if (state._alerts.isNotEmpty) ...[
                  _AlertsSection(
                    alerts: state._alerts,
                    totalAlerts: state._totalAlerts,
                  ),
                  const SizedBox(height: 16),
                ],
                // Atividades de Hoje
                _TodayActivitiesSection(dogId: dog.id, dogName: dog.name),
                const SizedBox(height: 18),
                // Registrar (quick actions)
                _QuickActionsSection(dog: dog, actions: state._quickActions),
                const SizedBox(height: 18),
                // Resumo do Cão
                _DogSummarySection(dog: dog),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Dog? _localDogFallback(DogViewModel dogVM, String dogId) {
  try {
    return dogVM.dogs.firstWhere((d) => d.id == dogId);
  } catch (_) {
    return null;
  }
}
