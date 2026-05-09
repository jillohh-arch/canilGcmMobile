part of 'dashboard_screen.dart';

class _BentoDogGrid extends StatelessWidget {
  final List<Dog> dogs;
  final DogViewModel dogVM;
  const _BentoDogGrid({required this.dogs, required this.dogVM});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FeaturedDogCard(dog: dogs.first, dogVM: dogVM),
        const SizedBox(height: 10),
        if (dogs.length > 1) _buildGrid(context, dogs.sublist(1)),
      ],
    );
  }

  Widget _buildGrid(BuildContext context, List<Dog> remaining) {
    final rows = <Widget>[];
    for (int i = 0; i < remaining.length; i += 2) {
      final left = remaining[i];
      final right = i + 1 < remaining.length ? remaining[i + 1] : null;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SmallDogCard(dog: left, dogVM: dogVM),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: right != null
                  ? _SmallDogCard(dog: right, dogVM: dogVM)
                  : const SizedBox(),
            ),
          ],
        ),
      );
      if (i + 2 < remaining.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }
}

class _FeaturedDogCard extends StatelessWidget {
  final Dog dog;
  final DogViewModel dogVM;
  const _FeaturedDogCard({required this.dog, required this.dogVM});

  @override
  Widget build(BuildContext context) {
    final opStatus = dog.operationalStatus;
    final sColor = AppTheme.statusColor(opStatus);
    final sLabel = AppTheme.statusLabel(opStatus);
    final sIcon = AppTheme.statusIcon(opStatus);
    final hasTraining = dogVM.hasTrainingAlert(dog);
    final hasHealth = dogVM.hasHealthAlert(dog);

    String lastTrainingStr = '--';
    if (dog.lastTrainingDate != null) {
      final diff = DateTime.now().difference(dog.lastTrainingDate!).inDays;
      lastTrainingStr = diff == 0 ? 'Hoje' : '${diff}d';
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DogDetailsScreen(dog: dog)),
      ),
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
              child: dog.profileImageUrl != null
                  ? Image.network(dog.profileImageUrl!, fit: BoxFit.cover)
                  : Container(
                      color: _hudPanelAlt,
                      child: Center(
                        child: FaIcon(
                          FontAwesomeIcons.dog,
                          size: 40,
                          color: _hudCyan.withAlpha(160),
                        ),
                      ),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _InlineStatusPill(
                          label: sLabel,
                          color: sColor,
                          icon: sIcon,
                        ),
                        const Spacer(),
                        if (hasHealth)
                          _TinyAlert(
                            icon: Icons.vaccines_rounded,
                            color: Colors.redAccent,
                          ),
                        if (hasTraining) ...[
                          const SizedBox(width: 4),
                          _TinyAlert(
                            icon: Icons.fitness_center_rounded,
                            color: Colors.orangeAccent,
                          ),
                        ],
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dog.name.toUpperCase(),
                          style: GoogleFonts.oxanium(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 1.0,
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
                    ),
                    Row(
                      children: [
                        _MicroStat(label: 'Idade', value: '${dog.age}a'),
                        const SizedBox(width: 14),
                        _MicroStat(
                          label: 'Treino',
                          value: lastTrainingStr,
                          highlight: hasTraining,
                        ),
                        const SizedBox(width: 14),
                        Icon(
                          dog.sex == 'F'
                              ? Icons.female_rounded
                              : Icons.male_rounded,
                          size: 16,
                          color: dog.sex == 'F'
                              ? const Color(0xFFFF80AB)
                              : const Color(0xFF82B1FF),
                        ),
                      ],
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

class _SmallDogCard extends StatelessWidget {
  final Dog dog;
  final DogViewModel dogVM;
  const _SmallDogCard({required this.dog, required this.dogVM});

  @override
  Widget build(BuildContext context) {
    final opStatus = dog.operationalStatus;
    final sColor = AppTheme.statusColor(opStatus);
    final sLabel = AppTheme.statusLabel(opStatus);
    final sIcon = AppTheme.statusIcon(opStatus);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DogDetailsScreen(dog: dog)),
      ),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(230),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _hudCyan.withAlpha(65), width: 1),
          boxShadow: [BoxShadow(color: _hudCyan.withAlpha(16), blurRadius: 14)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dog.name.toUpperCase(),
                    style: GoogleFonts.oxanium(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.7,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          dog.breed,
                          style: GoogleFonts.robotoMono(
                            fontSize: 10,
                            color: Colors.white54,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _InlineStatusPill(
                        label: sLabel,
                        color: sColor,
                        icon: sIcon,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: dog.profileImageUrl != null
                    ? Image.network(
                        dog.profileImageUrl!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      )
                    : Container(
                        color: _hudPanelAlt,
                        child: Center(
                          child: FaIcon(
                            FontAwesomeIcons.dog,
                            size: 32,
                            color: _hudCyan.withAlpha(145),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
