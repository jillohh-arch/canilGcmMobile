part of 'training_log_screen.dart';

class _NewTrainingForm extends StatefulWidget {
  final String dogId;
  final VoidCallback onSaved;

  const _NewTrainingForm({required this.dogId, required this.onSaved});

  @override
  State<_NewTrainingForm> createState() => _NewTrainingFormState();
}

class _NewTrainingFormState extends State<_NewTrainingForm> {
  static const _trainingTypes = ['Faro', 'Proteção', 'Obediência'];
  static const _substances = [
    'Maconha',
    'Cocaína',
    'Crack',
    'Armas/Munições',
    'Pessoas',
  ];

  final _formKey = GlobalKey<FormState>();
  final _locationController = TextEditingController();
  final _weatherController = TextEditingController();
  final _handlerNotesController = TextEditingController();
  final _hidingTimeController = TextEditingController();
  final _humidityController = TextEditingController();
  final _windDirectionController = TextEditingController();
  final _searchDurationController = TextEditingController();

  String _selectedTrainingType = 'Faro';
  String? _selectedSubstance;

  @override
  void dispose() {
    _locationController.dispose();
    _weatherController.dispose();
    _handlerNotesController.dispose();
    _hidingTimeController.dispose();
    _humidityController.dispose();
    _windDirectionController.dispose();
    _searchDurationController.dispose();
    super.dispose();
  }

  Future<void> _saveTraining() async {
    if (!_formKey.currentState!.validate()) return;

    final session = TrainingSessionModel(
      dogId: widget.dogId,
      date: DateTime.now(),
      trainingType: _selectedTrainingType,
      substanceUsed: _selectedSubstance,
      location: _locationController.text.trim(),
      weather: _weatherController.text.trim(),
      handlerNotes: _handlerNotesController.text.trim(),
      hidingTime: _hidingTimeController.text.trim().isNotEmpty
          ? _hidingTimeController.text.trim()
          : null,
      humidity: double.tryParse(_humidityController.text.trim()),
      windDirection: _windDirectionController.text.trim().isNotEmpty
          ? _windDirectionController.text.trim()
          : null,
      searchDuration: int.tryParse(_searchDurationController.text.trim()),
    );
    final viewModel = Provider.of<TrainingViewModel>(context, listen: false);

    try {
      await viewModel.addTrainingSession(session);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Treino registrado!'),
          backgroundColor: Colors.green,
        ),
      );
      _clearForm();
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _clearForm() {
    _locationController.clear();
    _weatherController.clear();
    _handlerNotesController.clear();
    _hidingTimeController.clear();
    _humidityController.clear();
    _windDirectionController.clear();
    _searchDurationController.clear();
    setState(() => _selectedSubstance = null);
  }

  void _selectTrainingType(String type) {
    setState(() {
      _selectedTrainingType = type;
      if (type != 'Faro') _selectedSubstance = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showScentFields = _selectedTrainingType == 'Faro';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TrainingSectionLabel('Tipo de Treino'),
            _TrainingTypeSelector(
              trainingTypes: _trainingTypes,
              selectedTrainingType: _selectedTrainingType,
              onSelected: _selectTrainingType,
            ),
            const SizedBox(height: 24),
            if (showScentFields) ...[
              _SubstanceSelector(
                substances: _substances,
                selectedSubstance: _selectedSubstance,
                onSelected: (substance) {
                  setState(() => _selectedSubstance = substance);
                },
              ),
              const SizedBox(height: 24),
              _ScentMetricsFields(
                searchDurationController: _searchDurationController,
                hidingTimeController: _hidingTimeController,
              ),
              const SizedBox(height: 20),
            ],
            _EnvironmentalTrainingFields(
              weatherController: _weatherController,
              humidityController: _humidityController,
              locationController: _locationController,
              windDirectionController: _windDirectionController,
            ),
            const SizedBox(height: 20),
            _TrainingNotesField(controller: _handlerNotesController),
            const SizedBox(height: 32),
            _SaveTrainingButton(
              selectedTrainingType: _selectedTrainingType,
              onPressed: _saveTraining,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
