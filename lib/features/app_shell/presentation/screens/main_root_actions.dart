part of 'main_root_screen.dart';

extension _MainRootActions on _MainRootScreenState {
  // Helper para construir os itens da barra de navegação
  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return MaterialButton(
      minWidth: 40,
      onPressed: () => _onTabTapped(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isSelected ? Colors.cyanAccent : Colors.white54,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.cyanAccent : Colors.white54,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
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

  void _openActionSheet(BuildContext context, String dogId) {
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final dogName = dogVM.dogs
        .firstWhere(
          (d) => d.id == dogId,
          orElse: () => dogVM.dogs.isNotEmpty
              ? dogVM.dogs.first
              : throw Exception('Cão não encontrado'),
        )
        .name;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      builder: (BuildContext bc) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 24.0,
              horizontal: 16.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Título do Menu
                Text(
                  'CENTRAL DE REGISTRO',
                  style: GoogleFonts.oxanium(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.cyanAccent.withValues(alpha: 0.8),
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 24),
                // Grid de Opções
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildMenuOption(
                      context,
                      bc,
                      'OCORRÊNCIA',
                      Icons.local_police_outlined,
                      Colors.redAccent,
                      dogId,
                      dogName,
                      _MainRootScreenState._categoryOccurrence,
                    ),
                    _buildMenuOption(
                      context,
                      bc,
                      'TREINO',
                      Icons.track_changes,
                      Colors.orangeAccent,
                      dogId,
                      dogName,
                      'Treino',
                    ),
                    _buildMenuOption(
                      context,
                      bc,
                      'SAÚDE',
                      Icons.medical_services_outlined,
                      const Color(0xFFFF00FF),
                      dogId,
                      dogName,
                      'Saude',
                    ),
                    _buildMenuOption(
                      context,
                      bc,
                      'ROTINA',
                      Icons.assignment_outlined,
                      Colors.cyanAccent,
                      dogId,
                      dogName,
                      'Rotina',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  // Design Tático dos Botões do Menu
  Widget _buildMenuOption(
    BuildContext rootContext,
    BuildContext menuContext,
    String title,
    IconData icon,
    Color color,
    String dogId,
    String dogName,
    String category,
  ) {
    return InkWell(
      onTap: () async {
        final rootNavigator = Navigator.of(rootContext, rootNavigator: true);
        if (category == _MainRootScreenState._categoryOccurrence) {
          final incidentVM = Provider.of<IncidentViewModel>(
            rootContext,
            listen: false,
          );
          final openIncident = await incidentVM.findOpenIncident(dogId: dogId);
          if (!rootContext.mounted) return;
          if (Navigator.of(menuContext).canPop()) {
            Navigator.of(menuContext).pop();
          }
          if (openIncident != null) {
            final shouldContinue = await _showOpenIncidentDialog(rootContext);
            if (!rootContext.mounted || shouldContinue != true) return;
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
              builder: (_) =>
                  OccurrenceFlowScreen(dogId: dogId, dogName: dogName),
            ),
          );
          return;
        }

        if (Navigator.of(menuContext).canPop()) {
          Navigator.of(menuContext).pop();
        }
        // Abre o formulário correto
        Future.microtask(() {
          if (!mounted) return;
          if (category == _MainRootScreenState._categoryOccurrence) {
            rootNavigator.push(
              MaterialPageRoute(
                builder: (_) =>
                    OccurrenceFlowScreen(dogId: dogId, dogName: dogName),
              ),
            );
            return;
          }

          showModalBottomSheet(
            context: rootNavigator.context,
            useRootNavigator: true,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) => DynamicActivitySheet(
              category: category,
              dogId: dogId,
              dogName: dogName,
            ),
          );
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 150, // Largura para caber 2 botões por linha
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.shareTechMono(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showOpenIncidentDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: const Text(
          'Ocorrência em andamento',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Já existe uma ocorrência aberta para este K9. Continue o registro ou encerre antes de iniciar outra.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }
}
