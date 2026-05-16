part of 'main_root_screen.dart';

extension _MainRootActions on _MainRootScreenState {
  Widget _buildBottomNavigation(BuildContext context, String? activeDogId) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF07141B),
        border: Border(
          top: BorderSide(color: AppTheme.primary.withAlpha(45), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withAlpha(22),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 86,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _buildNavItem(0, Icons.home_outlined, 'Turno')),
              Expanded(
                child: _buildNavItem(1, Icons.history_rounded, 'Histórico'),
              ),
              SizedBox(
                width: 106,
                child: _buildCenterOccurrenceAction(context, activeDogId),
              ),
              Expanded(
                child: _buildNavItem(2, Icons.fitness_center_rounded, 'Treino'),
              ),
              Expanded(child: _buildNavItem(3, Icons.pets_rounded, 'Cão')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? AppTheme.primary : const Color(0xFFB4BFC5);

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        _onTabTapped(index);
      },
      child: SizedBox(
        height: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 29),
            const SizedBox(height: 5),
            _RootAutoFitText(
              label,
              style: GoogleFonts.inter(
                color: color,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: isSelected ? 34 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterOccurrenceAction(
    BuildContext context,
    String? activeDogId,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _openOccurrenceFromRoot(context, activeDogId),
      child: SizedBox(
        height: 86,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: 0,
              child: Container(
                width: 76,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A2430),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                    bottom: Radius.circular(2),
                  ),
                  border: Border.all(color: AppTheme.primary, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withAlpha(58),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: AppTheme.primary,
                  size: 34,
                ),
              ),
            ),
            Positioned(
              left: 2,
              right: 2,
              top: 58,
              child: _RootAutoFitText(
                'Nova Ocorrência',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

    final dogName = _dogNameFor(context, dogId);
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final incidentVM = Provider.of<IncidentViewModel>(context, listen: false);
    final openIncident = await incidentVM.findOpenIncident(dogId: dogId);
    if (!context.mounted) return;

    if (openIncident != null) {
      final shouldContinue = await _showOpenIncidentDialog(context);
      if (!context.mounted || shouldContinue != true) return;
      rootNavigator.push(
        MaterialPageRoute(
          builder: (_) => OccurrenceFlowScreen(
            dogId: dogId,
            dogName: dogName,
            incident: openIncident,
          ),
        ),
      );
      return;
    }

    rootNavigator.push(
      MaterialPageRoute(
        builder: (_) => OccurrenceFlowScreen(dogId: dogId, dogName: dogName),
      ),
    );
  }

  Incident? _activeIncidentForDog(List<Incident> incidents, String dogId) {
    final openIncidents =
        incidents
            .where(
              (incident) => incident.dogId == dogId && incident.isInProgress,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (openIncidents.isEmpty) return null;
    return openIncidents.first;
  }

  String _dogNameFor(BuildContext context, String dogId) {
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    for (final dog in dogVM.dogs) {
      if (dog.id == dogId) return dog.name;
    }
    return dogVM.dogs.isNotEmpty ? dogVM.dogs.first.name : 'K9';
  }

  void _continueActiveIncident(
    BuildContext context, {
    required String dogId,
    required Incident incident,
  }) {
    HapticFeedback.lightImpact();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => OccurrenceFlowScreen(
          dogId: dogId,
          dogName: _dogNameFor(context, dogId),
          incident: incident,
        ),
      ),
    );
  }
}

class _RootAutoFitText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _RootAutoFitText(this.text, {required this.style});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitted = FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: style,
          ),
        );

        if (!constraints.maxWidth.isFinite) {
          return fitted;
        }

        return SizedBox(width: constraints.maxWidth, child: fitted);
      },
    );
  }
}
