part of 'health_log_screen.dart';

class _NewHealthLogForm extends StatefulWidget {
  final String dogId;
  final VoidCallback onSaved;
  const _NewHealthLogForm({required this.dogId, required this.onSaved});

  @override
  State<_NewHealthLogForm> createState() => _NewHealthLogFormState();
}

class _NewHealthLogFormState extends State<_NewHealthLogForm> {
  final _formKey = GlobalKey<FormState>();
  String _selectedLogType = 'Consulta';
  final List<String> _logTypes = [
    'Consulta',
    'Vacina',
    'Exame',
    'Medicação',
    'Banho',
  ];
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _observationsController = TextEditingController();
  final TextEditingController _vaccineNameController = TextEditingController();

  @override
  void dispose() {
    _weightController.dispose();
    _observationsController.dispose();
    _vaccineNameController.dispose();
    super.dispose();
  }

  void _saveHealthLog() async {
    if (_formKey.currentState!.validate()) {
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Registro médico salvo!'),
              backgroundColor: Colors.green,
            ),
          );
          _weightController.clear();
          _observationsController.clear();
          _vaccineNameController.clear();
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (_, selectedColor) = _iconAndColor(_selectedLogType);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type selector
            _SectionLabel(label: 'Tipo de Registro'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _logTypes.map((type) {
                final isSelected = _selectedLogType == type;
                final (icon, color) = _iconAndColor(type);
                return GestureDetector(
                  onTap: () => setState(() => _selectedLogType = type),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
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
                          size: 16,
                          color: isSelected ? color : Colors.white70,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          type,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
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

            if (_selectedLogType == 'Vacina') ...[
              _SectionLabel(label: 'Nome da Vacina'),
              const SizedBox(height: 10),
              TextFormField(
                controller: _vaccineNameController,
                decoration: const InputDecoration(
                  labelText: 'Ex: V10, Antirrábica, Giardíase...',
                  prefixIcon: Icon(Icons.vaccines_rounded),
                ),
                validator: (val) => val == null || val.isEmpty
                    ? 'Informe o nome da vacina'
                    : null,
              ),
              const SizedBox(height: 20),
            ],

            _SectionLabel(label: 'Peso Atual'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Ex: 28.5 kg',
                prefixIcon: Icon(Icons.monitor_weight_outlined),
              ),
            ),
            const SizedBox(height: 20),

            _SectionLabel(label: 'Observações Clínicas'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _observationsController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Sintomas, dosagem, histórico...',
                alignLabelWithHint: true,
              ),
              validator: (value) => value == null || value.isEmpty
                  ? 'Adicione ao menos uma observação'
                  : null,
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: Consumer<HealthViewModel>(
                builder: (context, viewModel, child) {
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
                        : Icon(_logIcon(_selectedLogType), size: 22),
                    label: Text(
                      viewModel.isLoading ? 'SALVANDO...' : 'SALVAR PRONTUÁRIO',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: selectedColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: viewModel.isLoading ? null : _saveHealthLog,
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
}
