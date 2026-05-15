part of 'active_shift_dashboard_screen.dart';

/// Monta o layout principal do dashboard via CustomScrollView.
Widget _buildCockpit(BuildContext context, Dog dog, String callsign) {
  final state = context.findAncestorStateOfType<_ActiveShiftDashboardScreenState>()!;
  final userVM = Provider.of<UserViewModel>(context);
  final authVM = Provider.of<AuthViewModel>(context);
  final currentRa = HandlerIdentityService.raFromUser(authVM.user);
  final userModel = userVM.users.cast<dynamic>().firstWhere(
    (u) => u?.ra == currentRa,
    orElse: () => null,
  );
  final conductorPhoto = userModel?.photoUrl as String?;

  return SafeArea(
    child: CustomScrollView(
      slivers: [
        // Header (binômio)
        SliverToBoxAdapter(
          child: _ShiftHeader(
            dog: dog,
            callsign: callsign,
            conductorPhotoUrl: conductorPhoto,
            onSwitchDog: () => _showDogSwitcher(context),
          ),
        ),

        // Alertas (prioridade visual — aparece primeiro)
        if (state._alerts.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _AlertsSection(
                alerts: state._alerts,
                totalAlerts: state._totalAlerts,
              ),
            ),
          ),

        // Atividades de hoje
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _TodayActivitiesSection(dogId: dog.id),
          ),
        ),

        // Registros rápidos (grid 2x2)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _QuickActionsSection(
              dog: dog,
              actions: state._quickActions,
            ),
          ),
        ),

        // Indicadores compactos
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _ShiftIndicatorsCard(
              dog: dog,
              totalAlerts: state._totalAlerts,
              weatherData: state._weatherData,
            ),
          ),
        ),

        // Perfil do cão (card compacto)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: _DogProfileCard(dog: dog),
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