part of 'active_shift_dashboard_screen.dart';

extension _ActiveShiftCockpit on _ActiveShiftDashboardScreenState {
  Widget _buildCockpit(BuildContext context, Dog dog, String callsign) {
    return CustomScrollView(
      slivers: [
        _buildHeroHeader(context, dog, callsign),
        const _CockpitSectionHeader(),
        _HealthAlertBanner(dogId: dog.id),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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

class _CockpitSectionHeader extends StatelessWidget {
  const _CockpitSectionHeader();

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Row(
          children: [
            Text(
              'PAINEL DE COMANDO',
              style: GoogleFonts.robotoMono(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: _hudCyan.withAlpha(220),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(height: 1, color: _hudCyan.withAlpha(70)),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroDogBackdrop extends StatelessWidget {
  final Dog dog;

  const _HeroDogBackdrop({required this.dog});

  @override
  Widget build(BuildContext context) {
    if (dog.profileImageUrl != null) {
      return Hero(
        tag: 'dog_profile_${dog.id}',
        child: CachedNetworkImage(
          imageUrl: dog.profileImageUrl!,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      );
    }

    return Container(
      color: _hudPanel,
      child: const Center(
        child: FaIcon(FontAwesomeIcons.dog, size: 64, color: Colors.white24),
      ),
    );
  }
}

class _HeroDogScrim extends StatelessWidget {
  const _HeroDogScrim();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black54,
                Colors.black.withAlpha(50),
                _hudBackground.withAlpha(170),
                _hudBackground,
              ],
              stops: const [0, 0.3, 0.6, 1],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroDogIdentity extends StatelessWidget {
  final Dog dog;
  final String callsign;
  final VoidCallback onTap;

  const _HeroDogIdentity({
    required this.dog,
    required this.callsign,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          _HeroDogAvatar(dog: dog),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onTap,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    '$callsign & ${dog.name}'.toUpperCase(),
                    style: GoogleFonts.oxanium(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.6,
                      height: 1.1,
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 8),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.swap_horiz_rounded, color: _hudCyan, size: 20),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const _ActiveShiftPill(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _HeroDogAvatar extends StatelessWidget {
  final Dog dog;

  const _HeroDogAvatar({required this.dog});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _hudCyan, width: 3),
        boxShadow: [
          BoxShadow(
            color: _hudCyan.withAlpha(110),
            blurRadius: 34,
            spreadRadius: 4,
          ),
        ],
      ),
      child: CircleAvatar(
        radius: 48,
        backgroundColor: _hudPanelAlt,
        backgroundImage: dog.profileImageUrl != null
            ? CachedNetworkImageProvider(dog.profileImageUrl!)
            : null,
        child: dog.profileImageUrl == null
            ? const FaIcon(
                FontAwesomeIcons.dog,
                size: 36,
                color: Colors.white54,
              )
            : null,
      ),
    );
  }
}

class _ActiveShiftPill extends StatelessWidget {
  const _ActiveShiftPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(220),
        borderRadius: BorderRadius.circular(6),
        border: const Border(left: BorderSide(color: _hudGreen, width: 3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _hudGreen,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'TURNO ATIVO',
            style: GoogleFonts.robotoMono(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: _hudGreen,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
