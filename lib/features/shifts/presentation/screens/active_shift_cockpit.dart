part of 'active_shift_dashboard_screen.dart';

// _buildCockpit foi movido para _ActiveShiftDashboardScreenState
// como método _buildCockpitBody() para permitir uso de _animateSection.

Dog? _localDogFallback(DogViewModel dogVM, String dogId) {
  try {
    return dogVM.dogs.firstWhere((d) => d.id == dogId);
  } catch (_) {
    return null;
  }
}
