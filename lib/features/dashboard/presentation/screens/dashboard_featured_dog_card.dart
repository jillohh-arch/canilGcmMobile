part of 'dashboard_screen.dart';

class _FeaturedDogCard extends StatelessWidget {
  final Dog dog;
  final DogViewModel dogVM;

  const _FeaturedDogCard({required this.dog, required this.dogVM});

  @override
  Widget build(BuildContext context) {
    final opStatus = dog.operationalStatus;
    final statusColor = AppTheme.statusColor(opStatus);
    final statusLabel = AppTheme.statusLabel(opStatus);
    final statusIcon = AppTheme.statusIcon(opStatus);
    final hasTraining = dogVM.hasTrainingAlert(dog);
    final hasHealth = dogVM.hasHealthAlert(dog);

    return GestureDetector(
      onTap: () => _openDogDetails(context, dog),
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(235),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _hudCyan.withAlpha(90), width: 1),
          boxShadow: [BoxShadow(color: _hudCyan.withAlpha(24), blurRadius: 18)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 130,
              child: _DogCardImage(
                imageUrl: dog.profileImageUrl,
                iconSize: 40,
                iconAlpha: 160,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _FeaturedDogStatusRow(
                      statusLabel: statusLabel,
                      statusColor: statusColor,
                      statusIcon: statusIcon,
                      hasHealth: hasHealth,
                      hasTraining: hasTraining,
                    ),
                    _FeaturedDogIdentity(dog: dog),
                    _FeaturedDogStats(
                      dog: dog,
                      lastTrainingLabel: _lastTrainingLabel(dog),
                      hasTraining: hasTraining,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturedDogStatusRow extends StatelessWidget {
  final String statusLabel;
  final Color statusColor;
  final IconData statusIcon;
  final bool hasHealth;
  final bool hasTraining;

  const _FeaturedDogStatusRow({
    required this.statusLabel,
    required this.statusColor,
    required this.statusIcon,
    required this.hasHealth,
    required this.hasTraining,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _InlineStatusPill(
          label: statusLabel,
          color: statusColor,
          icon: statusIcon,
        ),
        const Spacer(),
        if (hasHealth)
          _TinyAlert(icon: Icons.vaccines_rounded, color: Colors.redAccent),
        if (hasTraining) ...[
          const SizedBox(width: 4),
          _TinyAlert(
            icon: Icons.fitness_center_rounded,
            color: Colors.orangeAccent,
          ),
        ],
      ],
    );
  }
}

class _FeaturedDogIdentity extends StatelessWidget {
  final Dog dog;

  const _FeaturedDogIdentity({required this.dog});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dog.name.toUpperCase(),
          style: GoogleFonts.oxanium(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
        Text(
          dog.breed,
          style: GoogleFonts.robotoMono(
            fontSize: 11,
            color: Colors.white54,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _FeaturedDogStats extends StatelessWidget {
  final Dog dog;
  final String lastTrainingLabel;
  final bool hasTraining;

  const _FeaturedDogStats({
    required this.dog,
    required this.lastTrainingLabel,
    required this.hasTraining,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MicroStat(label: 'Idade', value: '${dog.age}a'),
        const SizedBox(width: 14),
        _MicroStat(
          label: 'Treino',
          value: lastTrainingLabel,
          highlight: hasTraining,
        ),
        const SizedBox(width: 14),
        Icon(
          dog.sex == 'F' ? Icons.female_rounded : Icons.male_rounded,
          size: 16,
          color: dog.sex == 'F'
              ? const Color(0xFFFF80AB)
              : const Color(0xFF82B1FF),
        ),
      ],
    );
  }
}

String _lastTrainingLabel(Dog dog) {
  if (dog.lastTrainingDate == null) return '--';
  final diff = DateTime.now().difference(dog.lastTrainingDate!).inDays;
  return diff == 0 ? 'Hoje' : '${diff}d';
}
