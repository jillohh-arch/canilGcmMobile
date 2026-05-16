part of 'active_shift_dashboard_screen.dart';

/// Monta o layout principal do dashboard operacional institucional.
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
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header operacional
          _ShiftHeader(
            dog: dog,
            callsign: callsign,
            conductorPhotoUrl: conductorPhoto,
            onSwitchDog: () => _showDogSwitcher(context),
          ),
          const SizedBox(height: 20),

          // 2. Resumo do turno (4 colunas)
          _ShiftSummaryCard(dog: dog),
          const SizedBox(height: 20),

          // 3. Alertas (se houver)
          if (state._alerts.isNotEmpty) ...[
            _AlertsSection(
              alerts: state._alerts,
              totalAlerts: state._totalAlerts,
            ),
            const SizedBox(height: 20),
          ],

          // 4. Atividade do turno (card compacto)
          _ShiftActivityCard(dogId: dog.id),
          const SizedBox(height: 20),

          // 5. Registrar (grid 2x2)
          _QuickActionsSection(
            dog: dog,
            actions: state._quickActions,
          ),
          const SizedBox(height: 20),

          // 6. Atividades recentes (timeline)
          _RecentActivityTimeline(dogId: dog.id),
          const SizedBox(height: 20),

          // 7. Status do binômio (K9)
          _K9StatusCard(dog: dog),
        ],
      ),
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
