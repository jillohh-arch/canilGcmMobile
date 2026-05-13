part of 'training_log_screen.dart';

class _ScentMetricsFields extends StatelessWidget {
  final TextEditingController searchDurationController;
  final TextEditingController hidingTimeController;

  const _ScentMetricsFields({
    required this.searchDurationController,
    required this.hidingTimeController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TrainingSectionLabel('Métricas de Desempenho'),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: searchDurationController,
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
                controller: hidingTimeController,
                decoration: const InputDecoration(
                  labelText: 'Ocultação (ex: 15min)',
                  prefixIcon: Icon(Icons.timelapse_rounded),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EnvironmentalTrainingFields extends StatelessWidget {
  final TextEditingController weatherController;
  final TextEditingController humidityController;
  final TextEditingController locationController;
  final TextEditingController windDirectionController;

  const _EnvironmentalTrainingFields({
    required this.weatherController,
    required this.humidityController,
    required this.locationController,
    required this.windDirectionController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TrainingSectionLabel('Condições Ambientais'),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: weatherController,
                decoration: const InputDecoration(
                  labelText: 'Clima',
                  prefixIcon: Icon(Icons.cloud_outlined),
                ),
                validator: _requiredField,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: humidityController,
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
                controller: locationController,
                decoration: const InputDecoration(
                  labelText: 'Local',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                validator: _requiredField,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: windDirectionController,
                decoration: const InputDecoration(
                  labelText: 'Dir. Vento',
                  prefixIcon: Icon(Icons.air),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TrainingNotesField extends StatelessWidget {
  final TextEditingController controller;

  const _TrainingNotesField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TrainingSectionLabel('Notas do Condutor'),
        TextFormField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Comportamento, detalhes, evolução...',
            alignLabelWithHint: true,
          ),
          validator: (value) => value == null || value.isEmpty
              ? 'Adicione ao menos uma nota'
              : null,
        ),
      ],
    );
  }
}
