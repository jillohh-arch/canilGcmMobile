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
                  color: AppTheme.textPrimary.withAlpha(12),
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
                  color: AppTheme.background.withAlpha(25),
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
              color: AppTheme.amber,
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
              color: AppTheme.errorStrong,
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
              color: AppTheme.primary,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StartOccurrenceScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
