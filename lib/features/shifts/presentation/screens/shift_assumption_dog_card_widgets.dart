part of 'shift_assumption_screen.dart';

class _HudDogSelectionCard extends StatelessWidget {
  final Dog dog;
  final bool isStarting;
  final VoidCallback onSelect;

  const _HudDogSelectionCard({
    required this.dog,
    required this.isStarting,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final readiness = dog.calculateReadiness();
    final statusColor = _statusColor(dog.operationalStatus);
    final lastTraining = _formatLastTraining(dog.lastTrainingDate);

    return GestureDetector(
      onTap: isStarting ? null : onSelect,
      child: Container(
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(236),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _hudCyan.withAlpha(125), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: _hudCyan.withAlpha(18),
              blurRadius: 14,
              spreadRadius: 0,
            ),
            const BoxShadow(
              color: Colors.black54,
              blurRadius: 18,
              offset: Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(child: _DogBackdrop(dog: dog)),
            const Positioned.fill(child: _DogCardScrim()),
            Positioned(
              top: 18,
              right: 18,
              child: _StatusBadge(
                label: dog.operationalStatus,
                color: statusColor,
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 26, 18, 18),
                child: Column(
                  children: [
                    const Spacer(),
                    _DogIdentity(dog: dog),
                    const SizedBox(height: 14),
                    _ReadinessBar(value: readiness),
                    const SizedBox(height: 14),
                    _DogMetricRow(dog: dog),
                    const SizedBox(height: 10),
                    _WideMetric(
                      icon: Icons.track_changes_rounded,
                      label: 'ÚLTIMO TREINO',
                      value: lastTraining,
                    ),
                    const SizedBox(height: 16),
                    _StartShiftButton(isStarting: isStarting),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _statusColor(String status) {
    final normalized = status.toLowerCase();
    if (normalized.contains('ativo') || normalized.contains('treino')) {
      return _hudGreen;
    }
    if (normalized.contains('licen')) {
      return _hudAmber;
    }
    return _hudRed;
  }

  static String _formatLastTraining(DateTime? date) {
    if (date == null) return 'Sem registro';
    final days = DateTime.now().difference(date).inDays;
    if (days <= 0) return 'Hoje';
    if (days == 1) return 'Ontem';
    return 'Há $days dias';
  }
}

class _DogCardScrim extends StatelessWidget {
  const _DogCardScrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _hudBackground.withAlpha(20),
            _hudBackground.withAlpha(90),
            _hudBackground.withAlpha(245),
          ],
        ),
      ),
    );
  }
}
