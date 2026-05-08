part of 'dog_details_screen.dart';

const _trainingAccent = Color(0xFFFFB300);
const _healthAccent = Color(0xFFEF5350);
const _weightAccent = Color(0xFF66BB6A);
const _maleAccent = Color(0xFF82B1FF);
const _femaleAccent = Color(0xFFFF80AB);
const _ageAccent = Color(0xFF4ECDE4);

class _CockpitBento extends StatelessWidget {
  final Dog dog;
  const _CockpitBento({required this.dog});

  @override
  Widget build(BuildContext context) {
    final tVM = Provider.of<TrainingViewModel>(context);
    final hVM = Provider.of<HealthViewModel>(context);

    final trainings = [...tVM.trainings]
      ..sort((a, b) => b.date.compareTo(a.date));
    final lastTraining = trainings.isNotEmpty ? trainings.first : null;
    final scentCount = trainings.where((t) => t.trainingType == 'Faro').length;

    final healthLogs = [...hVM.healthLogs]
      ..sort((a, b) => b.date.compareTo(a.date));
    final lastHealth = healthLogs.isNotEmpty ? healthLogs.first : null;
    final lastHealthWeight = healthLogs
        .where((h) => h.weight != null)
        .firstOrNull
        ?.weight;
    final lastWeight = dog.weight ?? lastHealthWeight;

    return Column(
      children: [
        _TrainingSummaryBento(
          lastTraining: lastTraining,
          scentCount: scentCount,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _HealthSummaryBento(
                lastHealth: lastHealth,
                lastVaccineDate: dog.lastVaccineDate,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _WeightSummaryBento(dog: dog, weight: lastWeight),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _DogTraitsBentoRow(dog: dog),
      ],
    );
  }
}

String _formatDogDetailsDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}
