part of 'training_log_screen.dart';

class _NewTrainingForm extends StatefulWidget {
  final String dogId;
  final VoidCallback onSaved;
  const _NewTrainingForm({required this.dogId, required this.onSaved});

  @override
  State<_NewTrainingForm> createState() => _NewTrainingFormState();
}

class _NewTrainingFormState extends State<_NewTrainingForm> {
  final _formKey = GlobalKey<FormState>();
  String _selectedTrainingType = 'Faro';
  String? _selectedSubstance;

  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _weatherController = TextEditingController();
  final TextEditingController _handlerNotesController = TextEditingController();
  final TextEditingController _hidingTimeController = TextEditingController();
  final TextEditingController _humidityController = TextEditingController();
  final TextEditingController _windDirectionController =
      TextEditingController();
  final TextEditingController _searchDurationController =
      TextEditingController();

  final List<String> _trainingTypes = ['Faro', 'Proteção', 'Obediência'];
  final List<String> _substances = [
    'Maconha',
    'Cocaína',
    'Crack',
    'Armas/Munições',
    'Pessoas',
  ];

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

  void _saveTraining() async {
    if (_formKey.currentState!.validate()) {
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Treino registrado!'),
              backgroundColor: Colors.green,
            ),
          );
          _locationController.clear();
          _weatherController.clear();
          _handlerNotesController.clear();
          _hidingTimeController.clear();
          _humidityController.clear();
          _windDirectionController.clear();
          _searchDurationController.clear();
          setState(() => _selectedSubstance = null);
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
  }

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.poppins(
          color: Colors.white38,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Training type selector
            _sectionLabel('Tipo de Treino'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _trainingTypes.map((type) {
                final isSelected = _selectedTrainingType == type;
                final (icon, color) = _sessionStyle(type);
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedTrainingType = type;
                    if (type != 'Faro') _selectedSubstance = null;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withAlpha(40)
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? color : Colors.white12,
                        width: isSelected ? 1.5 : 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 18,
                          color: isSelected ? color : Colors.white38,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          type,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected ? color : Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Substance (Faro only)
            if (_selectedTrainingType == 'Faro') ...[
              _sectionLabel('Substância Procurada'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _substances.map((substance) {
                  final isSelected = _selectedSubstance == substance;
                  return FilterChip(
                    label: Text(substance),
                    labelStyle: GoogleFonts.poppins(
                      fontSize: 13,
                      color: isSelected ? Colors.black : Colors.white70,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    backgroundColor: cs.surfaceContainerHighest,
                    selectedColor: AppTheme.amber,
                    selected: isSelected,
                    onSelected: (v) => setState(
                      () => _selectedSubstance = v ? substance : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],

            // Scent fields
            if (_selectedTrainingType == 'Faro') ...[
              _sectionLabel('Métricas de Desempenho'),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _searchDurationController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Duração (segundos)',
                        prefixIcon: Icon(Icons.timer_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _hidingTimeController,
                      decoration: const InputDecoration(
                        labelText: 'Ocultação (ex: 15min)',
                        prefixIcon: Icon(Icons.timelapse_rounded),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],

            _sectionLabel('Condições Ambientais'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _weatherController,
                    decoration: const InputDecoration(
                      labelText: 'Clima',
                      prefixIcon: Icon(Icons.cloud_outlined),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Obrigatório' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _humidityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Umidade (%)',
                      prefixIcon: Icon(Icons.water_drop_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: 'Local',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Obrigatório' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _windDirectionController,
                    decoration: const InputDecoration(
                      labelText: 'Dir. Vento',
                      prefixIcon: Icon(Icons.air),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _sectionLabel('Notas do Condutor'),
            TextFormField(
              controller: _handlerNotesController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Comportamento, detalhes, evolução...',
                alignLabelWithHint: true,
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Adicione ao menos uma nota' : null,
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: Consumer<TrainingViewModel>(
                builder: (context, viewModel, child) {
                  final (_, color) = _sessionStyle(_selectedTrainingType);
                  return ElevatedButton.icon(
                    icon: viewModel.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.save_rounded, size: 22),
                    label: Text(
                      viewModel.isLoading ? 'SALVANDO...' : 'SALVAR TREINO',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: viewModel.isLoading ? null : _saveTraining,
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  (IconData, Color) _sessionStyle(String type) {
    switch (type) {
      case 'Faro':
        return (Icons.track_changes_rounded, const Color(0xFFFFB300));
      case 'Proteção':
        return (Icons.shield_rounded, const Color(0xFFEF5350));
      case 'Obediência':
        return (Icons.school_rounded, const Color(0xFF42A5F5));
      default:
        return (Icons.fitness_center_rounded, AppTheme.amber);
    }
  }
}
