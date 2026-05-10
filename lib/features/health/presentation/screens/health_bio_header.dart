part of 'health_dashboard_screen.dart';

extension _HealthBioHeader on _HealthDashboardScreenState {
  Widget _buildBioHudHeader(
    Dog dog,
    List<HealthLogModel> logs,
    DateTime? lastBath,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        children: [
          _PulsingDogAvatar(dog: dog, animation: _pulseController),
          const SizedBox(height: 16),
          Text(
            dog.name.toUpperCase(),
            style: GoogleFonts.oxanium(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          _ReadinessHudBar(dog: dog, logs: logs, lastBath: lastBath),
        ],
      ),
    );
  }
}
