part of 'active_shift_dashboard_screen.dart';

/// Monta o dashboard inicial do turno logo após assumir o binômio.
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

  return Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF061017), Color(0xFF050D10), Color(0xFF050D10)],
      ),
    ),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShiftHeader(
              dog: dog,
              callsign: callsign,
              conductorPhotoUrl: conductorPhoto,
              onSwitchDog: () => _showDogSwitcher(context),
            ),
            const SizedBox(height: 14),
            _ShiftSummaryCard(dog: dog),
            const SizedBox(height: 14),
            if (state._alerts.isNotEmpty) ...[
              _AlertsSection(
                alerts: state._alerts,
                totalAlerts: state._totalAlerts,
              ),
              const SizedBox(height: 14),
            ],
            _ShiftActivityCard(dogId: dog.id),
            const SizedBox(height: 14),
            _QuickActionsSection(dog: dog, actions: state._quickActions),
            const SizedBox(height: 14),
            _RecentActivityTimeline(dogId: dog.id),
            const SizedBox(height: 14),
            _K9StatusCard(dog: dog),
          ],
        ),
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
