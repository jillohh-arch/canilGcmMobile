part of 'health_dashboard_screen.dart';

extension _HealthSensorCards on _HealthDashboardScreenState {
  Widget _buildSensorRow(Dog dog, DateTime? lastBath) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _SensorCard(
              label: 'PESO',
              value: '${dog.weight?.toStringAsFixed(1) ?? "--"} KG',
              icon: const Icon(
                Icons.monitor_weight_outlined,
                size: 24,
                color: AppTheme.primary,
              ),
              isSelected: true,
              onTap: () => _showWeightDialog(dog),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SensorCard(
              label: 'IDADE',
              value: '${dog.age} ANOS',
              icon: Icon(
                Icons.query_builder,
                size: 24,
                color: AppTheme.primary.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SensorCard(
              label: 'ÚLT. BANHO',
              value: _formatShortDate(lastBath).toUpperCase(),
              icon: Icon(
                Icons.water_drop_outlined,
                size: 24,
                color: AppTheme.primary.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showWeightDialog(Dog dog) async {
    final controller = TextEditingController(
      text: dog.weight != null ? dog.weight!.toStringAsFixed(1) : '',
    );

    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return _WeightUpdateDialog(
          controller: controller,
          onSubmit: (value) => Navigator.pop(dialogContext, value),
        );
      },
    );

    controller.dispose();
    if (result == null || !mounted) return;

    await _persistWeightUpdate(dog, result);
  }

  Future<void> _persistWeightUpdate(Dog dog, double weight) async {
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final healthVM = Provider.of<HealthViewModel>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await dogVM.updateDogWeight(dog.id, weight);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar peso: $e'),
          backgroundColor: AppTheme.errorStrong,
        ),
      );
      return;
    }

    try {
      await healthVM.addHealthLog(
        HealthLogModel(
          dogId: dog.id,
          dogName: dog.name,
          date: DateTime.now(),
          type: 'other',
          subtype: 'Pesagem',
          healthObservations: 'Pesagem operacional registrada no app.',
          weight: weight,
        ),
      );

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Peso atualizado e histórico registrado.'),
          backgroundColor: AppTheme.successOperational,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Peso atualizado. Histórico médico pendente: ${_cleanHealthError(e)}',
          ),
          backgroundColor: AppTheme.warningAccent,
        ),
      );
    }
  }
}

String _cleanHealthError(Object error) {
  return error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('Falha ao salvar registro médico: ', '')
      .trim();
}
