part of 'main_root_screen.dart';

extension _MainRootActionSheet on _MainRootScreenState {
  void _openActionSheet(BuildContext context, String dogId) {
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final dogName = dogVM.dogs
        .firstWhere(
          (dog) => dog.id == dogId,
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
      builder: (menuContext) {
        return _ActionSheetContent(
          options: [
            _buildMenuOption(
              context,
              menuContext,
              'OCORRÊNCIA',
              Icons.local_police_outlined,
              Colors.redAccent,
              dogId,
              dogName,
              _MainRootScreenState._categoryOccurrence,
            ),
            _buildMenuOption(
              context,
              menuContext,
              'TREINO',
              Icons.track_changes,
              Colors.orangeAccent,
              dogId,
              dogName,
              'Treino',
            ),
            _buildMenuOption(
              context,
              menuContext,
              'SAÚDE',
              Icons.medical_services_outlined,
              const Color(0xFFFF00FF),
              dogId,
              dogName,
              'Saude',
            ),
            _buildMenuOption(
              context,
              menuContext,
              'ROTINA',
              Icons.assignment_outlined,
              Colors.cyanAccent,
              dogId,
              dogName,
              'Rotina',
            ),
          ],
        );
      },
    );
  }

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
    return _ActionMenuOption(
      title: title,
      icon: icon,
      color: color,
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
