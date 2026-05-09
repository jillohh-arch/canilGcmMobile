part of 'dog_details_screen.dart';

extension _DogDetailsHeader on _DogDetailsScreenState {
  Widget _buildHeroHeader(Dog dog) {
    final opStatus = dog.operationalStatus;
    final gradient = AppTheme.statusGradient(opStatus);
    final statusColor = AppTheme.statusColor(opStatus);

    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      stretch: true,
      backgroundColor: AppTheme.statusBg(opStatus),
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [
          StretchMode.zoomBackground,
          StretchMode.blurBackground,
        ],
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(decoration: BoxDecoration(gradient: gradient)),
            Positioned(
              right: -60,
              top: -40,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(12),
                ),
              ),
            ),
            Positioned(
              left: -30,
              bottom: -30,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withAlpha(25),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _DogHeroAvatar(dog: dog),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _DogHeroIdentity(
                        dog: dog,
                        statusColor: statusColor,
                      ),
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

  Widget _buildQuickActions(Dog dog) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(
          children: [
            _QuickActionButton(
              icon: Icons.track_changes_rounded,
              label: 'Faro',
              color: const Color(0xFFFFB300),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      TrainingLogScreen(dogId: dog.id, dogName: dog.name),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _QuickActionButton(
              icon: Icons.medical_services_rounded,
              label: 'Saúde',
              color: const Color(0xFFEF5350),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HealthLogScreen(dogId: dog.id),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _QuickActionButton(
              icon: Icons.report_rounded,
              label: 'Ocorrência',
              color: const Color(0xFF4ECDE4),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      OccurrenceFlowScreen(dogId: dog.id, dogName: dog.name),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DogHeroAvatar extends StatelessWidget {
  final Dog dog;

  const _DogHeroAvatar({required this.dog});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: CircleAvatar(
        radius: 56,
        backgroundColor: Colors.white24,
        backgroundImage: dog.profileImageUrl != null
            ? NetworkImage(dog.profileImageUrl!)
            : null,
        child: dog.profileImageUrl == null
            ? const FaIcon(FontAwesomeIcons.dog, size: 40, color: Colors.white)
            : null,
      ),
    );
  }
}

class _DogHeroIdentity extends StatelessWidget {
  final Dog dog;
  final Color statusColor;

  const _DogHeroIdentity({required this.dog, required this.statusColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AgentStatusPill(status: dog.operationalStatus, color: statusColor),
        const SizedBox(height: 8),
        Text(
          dog.name.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 0.5,
            height: 1.0,
          ),
        ),
        Row(
          children: [
            Text(
              dog.breed,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              dog.sex == 'F' ? Icons.female_rounded : Icons.male_rounded,
              size: 16,
              color: dog.sex == 'F'
                  ? const Color(0xFFFF80AB)
                  : const Color(0xFF82B1FF),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${dog.age} anos · ID: ${dog.id.substring(0, 8).toUpperCase()}',
          style: GoogleFonts.poppins(
            fontSize: 10,
            color: Colors.white38,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
