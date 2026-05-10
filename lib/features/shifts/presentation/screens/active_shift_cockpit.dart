part of 'active_shift_dashboard_screen.dart';

extension _ActiveShiftCockpit on _ActiveShiftDashboardScreenState {
  Widget _buildCockpit(BuildContext context, Dog dog, String callsign) {
    return CustomScrollView(
      slivers: [
        _buildHeroHeader(context, dog, callsign),
        _HealthAlertBanner(dogId: dog.id),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: [
                _DogInfoCockpitCard(dog: dog),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _WeatherCockpitCard()),
                    const SizedBox(width: 16),
                    Expanded(child: _ShiftMetricsCockpitCard(dog: dog)),
                  ],
                ),
                const SizedBox(height: 16),
                _TodayActivitiesCard(dogId: dog.id),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroHeader(BuildContext context, Dog dog, String callsign) {
    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      backgroundColor: _hudBackground,
      iconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            _HeroDogBackdrop(dog: dog),
            const _HeroDogScrim(),
            _HeroDogIdentity(
              dog: dog,
              callsign: callsign,
              onTap: () => _showDogSwitcher(context, dog),
            ),
          ],
        ),
      ),
    );
  }
}
