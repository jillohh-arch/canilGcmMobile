part of 'main_root_screen.dart';

extension _MainRootActions on _MainRootScreenState {
  // ─── Tokens espelhados do Header Universal ─────────────────────────
  static const _navBg = Color(0x0A4DD0E1); // rgba(77,208,225,0.04)
  static const _navBorder = Color(0x1F4DD0E1); // rgba(77,208,225,0.12)
  static const _iconInactive = Color(0xFF5A7280);
  static const _iconActive = Color(0xFF4DD0E1);
  static const _pillBg = Color(0x1A4DD0E1); // rgba(77,208,225,0.10)
  static const _pillBorder = Color(0x384DD0E1); // rgba(77,208,225,0.22)
  static const _fabColor = Color(0xFF4DD0E1);
  static const _fabIconColor = Color(0xFF04181C);
  static const _fabRingColor = Color(0xFF050D10);
  static const _fabSize = 54.0;
  static const _fabElevation = 22.0; // how much FAB rises above bar

  Widget _buildBottomNavigation(BuildContext context, String? activeDogId) {
    return SizedBox(
      // Total height = bar content + safe area padding handled by SafeArea
      // The Stack allows the FAB to overflow upward
      height: 76 + MediaQuery.of(context).padding.bottom,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ─── Bar background ───────────────────────────────────────
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                color: _navBg,
                border: Border(
                  top: BorderSide(color: _navBorder, width: 1),
                ),
              ),
            ),
          ),

          // ─── Nav items row ────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: MediaQuery.of(context).padding.bottom,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  _buildNavItem(0, Icons.home_outlined, 'Turno'),
                  _buildNavItem(1, Icons.history_rounded, 'Histórico'),
                  // Spacer for FAB
                  const SizedBox(width: 72),
                  _buildNavItem(2, Icons.fitness_center_rounded, 'Treino'),
                  _buildNavItem(3, Icons.pets_rounded, 'Cão'),
                ],
              ),
            ),
          ),

          // ─── FAB (elevated above bar) ─────────────────────────────
          Positioned(
            top: -_fabElevation,
            left: 0,
            right: 0,
            child: Center(
              child: _buildCenterFab(context, activeDogId),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;

    return Expanded(
      flex: isSelected ? 3 : 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          _onTabTapped(index);
        },
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: isSelected ? 12 : 10,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: isSelected ? _pillBg : Colors.transparent,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: isSelected ? _pillBorder : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isSelected ? _iconActive : _iconInactive,
                  size: 22,
                ),
                if (isSelected) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        color: _iconActive,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterFab(BuildContext context, String? activeDogId) {
    return GestureDetector(
      onTap: () => _openOccurrenceFromRoot(context, activeDogId),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // FAB circle with ring
          Container(
            width: _fabSize,
            height: _fabSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _fabColor,
              border: Border.all(color: _fabRingColor, width: 4),
              boxShadow: [
                BoxShadow(
                  color: _fabColor.withAlpha(82), // ~0.32 opacity
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: _fabIconColor,
              size: 26,
            ),
          ),
          const SizedBox(height: 3),
          // Label "Nova"
          Text(
            'Nova',
            style: GoogleFonts.inter(
              color: _fabColor,
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Occurrence navigation logic ────────────────────────────────────

  Future<void> _openOccurrenceFromRoot(
    BuildContext context,
    String? dogId,
  ) async {
    HapticFeedback.mediumImpact();
    if (dogId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inicie um turno para registrar ocorrência.'),
        ),
      );
      return;
    }

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final occurrenceVM = Provider.of<OccurrenceViewModel>(
      context,
      listen: false,
    );
    final openOccurrence =
        occurrenceVM.openOccurrence ?? await occurrenceVM.findOpen(dogId);
    if (!context.mounted) return;

    if (openOccurrence != null) {
      final shouldContinue = await _showOpenOccurrenceDialog(context);
      if (!context.mounted || shouldContinue != true) return;
      rootNavigator.push(
        MaterialPageRoute(
          builder: (_) =>
              ActiveOccurrenceScreen(occurrenceId: openOccurrence.id),
        ),
      );
      return;
    }

    rootNavigator.push(
      MaterialPageRoute(builder: (_) => const StartOccurrenceScreen()),
    );
  }

  String _dogNameFor(BuildContext context, String dogId) {
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    for (final dog in dogVM.dogs) {
      if (dog.id == dogId) return dog.name;
    }
    return dogVM.dogs.isNotEmpty ? dogVM.dogs.first.name : 'K9';
  }

  void _continueActiveOccurrence(
    BuildContext context, {
    required Occurrence occurrence,
  }) {
    HapticFeedback.lightImpact();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => ActiveOccurrenceScreen(occurrenceId: occurrence.id),
      ),
    );
  }
}


