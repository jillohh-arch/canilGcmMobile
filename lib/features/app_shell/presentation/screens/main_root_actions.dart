part of 'main_root_screen.dart';

extension _MainRootActions on _MainRootScreenState {
  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return MaterialButton(
      minWidth: 56,
      onPressed: () => _onTabTapped(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isSelected ? AppTheme.primary : const Color(0xFF5A7280),
            size: 26,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              color: isSelected ? AppTheme.primary : const Color(0xFF5A7280),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Incident? _activeIncidentForDog(List<Incident> incidents, String dogId) {
    final openIncidents =
        incidents
            .where(
              (incident) => incident.dogId == dogId && incident.isInProgress,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (openIncidents.isEmpty) return null;
    return openIncidents.first;
  }

  String _dogNameFor(BuildContext context, String dogId) {
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    for (final dog in dogVM.dogs) {
      if (dog.id == dogId) return dog.name;
    }
    return dogVM.dogs.isNotEmpty ? dogVM.dogs.first.name : 'K9';
  }

  void _continueActiveIncident(
    BuildContext context, {
    required String dogId,
    required Incident incident,
  }) {
    HapticFeedback.lightImpact();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => OccurrenceFlowScreen(
          dogId: dogId,
          dogName: _dogNameFor(context, dogId),
          incident: incident,
        ),
      ),
    );
  }
}
