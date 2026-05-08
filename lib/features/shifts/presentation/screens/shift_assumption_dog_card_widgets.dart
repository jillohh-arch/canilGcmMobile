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
              color: _hudCyan.withAlpha(28),
              blurRadius: 24,
              spreadRadius: 1,
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
            Positioned.fill(
              child: DecoratedBox(
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
              ),
            ),
            Positioned(top: 12, left: 12, child: HudCorner(_hudCyan, size: 22)),
            Positioned(
              top: 12,
              right: 12,
              child: HudCorner(_hudCyan, flip: true, size: 22),
            ),
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
                    _ReadinessBar(value: readiness),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _DogMetric(
                            icon: Icons.monitor_weight_outlined,
                            label: 'PESO',
                            value: dog.weight != null
                                ? '${dog.weight!.toStringAsFixed(1)} KG'
                                : '-- KG',
                            color: _hudCyan,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DogMetric(
                            icon: Icons.schedule_rounded,
                            label: 'IDADE',
                            value: '${dog.age} ANOS',
                            color: _hudAmber,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _WideMetric(
                      icon: Icons.track_changes_rounded,
                      label: 'ÚLTIMO TREINO',
                      value: lastTraining,
                    ),
                    const SizedBox(height: 12),
                    _DogIdentity(dog: dog),
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

class _DogBackdrop extends StatelessWidget {
  final Dog dog;

  const _DogBackdrop({required this.dog});

  @override
  Widget build(BuildContext context) {
    if (dog.profileImageUrl == null || dog.profileImageUrl!.isEmpty) {
      return Container(
        color: _hudPanelDeep,
        child: Center(
          child: FaIcon(
            FontAwesomeIcons.dog,
            size: 86,
            color: _hudCyan.withAlpha(80),
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: dog.profileImageUrl!,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      placeholder: (context, url) => const Center(
        child: CircularProgressIndicator(color: _hudCyan, strokeWidth: 2),
      ),
      errorWidget: (context, url, error) => Container(
        color: _hudPanelDeep,
        child: Center(
          child: FaIcon(
            FontAwesomeIcons.dog,
            size: 72,
            color: _hudCyan.withAlpha(80),
          ),
        ),
      ),
    );
  }
}

class _DogIdentity extends StatelessWidget {
  final Dog dog;

  const _DogIdentity({required this.dog});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hudBackground.withAlpha(185),
            border: Border.all(color: _hudCyan.withAlpha(80)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dog.name.toUpperCase(),
                softWrap: true,
                style: GoogleFonts.oxanium(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                dog.breed.toUpperCase(),
                softWrap: true,
                style: GoogleFonts.robotoMono(
                  color: _hudCyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadinessBar extends StatelessWidget {
  final int value;

  const _ReadinessBar({required this.value});

  @override
  Widget build(BuildContext context) {
    final color = value >= 75
        ? _hudGreen
        : value >= 45
        ? _hudAmber
        : _hudRed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'PRONTIDÃO OPERACIONAL',
              style: GoogleFonts.robotoMono(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
            const Spacer(),
            Text(
              '$value%',
              style: GoogleFonts.oxanium(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: _hudBackground,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white12),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0, 100) / 100,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(color: color.withAlpha(120), blurRadius: 8),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DogMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DogMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(226),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(110)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            softWrap: true,
            style: GoogleFonts.oxanium(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.robotoMono(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _WideMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _WideMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _hudBackground.withAlpha(205),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(70)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _hudCyan, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.robotoMono(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.oxanium(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
