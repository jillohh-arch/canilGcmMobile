part of 'health_log_screen.dart';

class _NewHealthLogForm extends StatefulWidget {
  final String dogId;
  final VoidCallback onSaved;

  const _NewHealthLogForm({required this.dogId, required this.onSaved});

  @override
  State<_NewHealthLogForm> createState() => _NewHealthLogFormState();
}

class _NewHealthLogFormState extends State<_NewHealthLogForm> {
  static const _logTypes = [
    'Consulta',
    'Vacina',
    'Exame',
    'Medicação',
    'Banho',
  ];

  final _formKey = GlobalKey<FormState>();
  final _weightController = TextEditingController();
  final _observationsController = TextEditingController();
  final _vaccineNameController = TextEditingController();

  String _selectedLogType = 'Consulta';

  @override
  void dispose() {
    _weightController.dispose();
    _observationsController.dispose();
    _vaccineNameController.dispose();
    super.dispose();
  }

  Future<void> _saveHealthLog() async {
    if (!_formKey.currentState!.validate()) return;

    final log = HealthLogModel(
      dogId: widget.dogId,
      date: DateTime.now(),
      logType: _selectedLogType,
      weight: double.tryParse(
        _weightController.text.trim().replaceAll(',', '.'),
      ),
      vaccines:
          _selectedLogType == 'Vacina' &&
              _vaccineNameController.text.trim().isNotEmpty
          ? [_vaccineNameController.text.trim()]
          : [],
      healthObservations: _observationsController.text.trim(),
    );
    final viewModel = Provider.of<HealthViewModel>(context, listen: false);

    try {
      await viewModel.addHealthLog(log);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registro médico salvo!'),
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
    _weightController.clear();
    _observationsController.clear();
    _vaccineNameController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HealthLogTypeSelector(
              logTypes: _logTypes,
              selectedLogType: _selectedLogType,
              onSelected: (type) => setState(() => _selectedLogType = type),
            ),
            const SizedBox(height: 24),
            if (_selectedLogType == 'Vacina') ...[
              _VaccineNameField(controller: _vaccineNameController),
              const SizedBox(height: 20),
            ],
            _HealthWeightField(controller: _weightController),
            const SizedBox(height: 20),
            _HealthObservationField(controller: _observationsController),
            const SizedBox(height: 32),
            _SaveHealthLogButton(
              selectedLogType: _selectedLogType,
              onPressed: _saveHealthLog,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
