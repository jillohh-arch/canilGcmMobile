part of 'incident_form_screen.dart';

class _NewIncidentForm extends StatefulWidget {
  final String dogId;
  final VoidCallback onSaved;
  const _NewIncidentForm({required this.dogId, required this.onSaved});

  @override
  State<_NewIncidentForm> createState() => _NewIncidentFormState();
}

class _NewIncidentFormState extends State<_NewIncidentForm> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _natureController = TextEditingController();
  final FocusNode _natureFocus = FocusNode();
  String? _selectedNatureCode;
  String _selectedNatureName = '';

  @override
  void dispose() {
    _natureController.dispose();
    _natureFocus.dispose();
    super.dispose();
  }

  void _startIncident() async {
    if (!_formKey.currentState!.validate()) return;

    // Inicia com os dados mínimos da triagem rápida.
    final nature = _selectedNatureName.isNotEmpty
        ? _selectedNatureName
        : 'Ocorrência Geral';

    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final currentRa =
        HandlerIdentityService.raFromUser(authVM.user) ?? '000000';
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final userModel = userVM.users.cast<dynamic>().firstWhere(
      (u) => u?.ra == currentRa,
      orElse: () => null,
    );
    final authorName =
        userModel?.callsign?.toString() ??
        authVM.user?.displayName ??
        currentRa;

    final viewModel = Provider.of<IncidentViewModel>(context, listen: false);
    final openIncident = await viewModel.findOpenIncident(dogId: widget.dogId);
    if (openIncident != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Já existe uma ocorrência em andamento para este K9. Conclua ou cancele-a primeiro.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final incident = Incident(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      dogId: widget.dogId,
      handlerId: currentRa,
      date: DateTime.now(),
      location: 'Local atual (GPS Automático)', // Será enriquecido no console
      description: 'Ocorrência iniciada rapidamente.',
      result: 'Pendente',
      type: nature,
      extraFields:
          _selectedNatureCode != null && _selectedNatureCode!.isNotEmpty
          ? {'naturezaCodigo': _selectedNatureCode}
          : null,
      status: 'Em andamento',
      progressUpdates: [
        IncidentProgressUpdate(
          title: 'Ocorrência Iniciada',
          description: 'Natureza: $nature',
          timestamp: DateTime.now(),
          location: 'Local atual',
          authorId: currentRa,
          authorName: authorName,
        ),
      ],
    );

    try {
      await viewModel.saveIncident(incident);
      if (mounted) {
        HapticFeedback.heavyImpact();
        _natureController.clear();
        setState(() {
          _selectedNatureCode = null;
          _selectedNatureName = '';
        });
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dogVM = Provider.of<DogViewModel>(context);
    final dog = dogVM.dogs.cast<dynamic>().firstWhere(
      (d) => d.id == widget.dogId,
      orElse: () => null,
    );

    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _TacticalGridPainter())),
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _NewIncidentHero(dog: dog),
                const SizedBox(height: 32),
                _IncidentStartContextRow(timestamp: DateTime.now()),
                const SizedBox(height: 32),
                _IncidentNatureField(
                  controller: _natureController,
                  focusNode: _natureFocus,
                  onSelected: (nature) {
                    setState(() {
                      _selectedNatureCode = nature.code;
                      _selectedNatureName = nature.name;
                    });
                  },
                  onChanged: (value) => _selectedNatureName = value,
                ),
                const SizedBox(height: 32),
                _IncidentStartButton(onPressed: _startIncident),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
