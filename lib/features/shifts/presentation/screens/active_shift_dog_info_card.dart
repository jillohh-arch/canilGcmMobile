part of 'active_shift_dashboard_screen.dart';

class _DogInfoCockpitCard extends StatelessWidget {
  final Dog dog;

  const _DogInfoCockpitCard({required this.dog});

  @override
  Widget build(BuildContext context) {
    final ageStr = '${dog.age} anos';
    final sexStr = dog.sex == 'M' ? 'Macho' : 'Fêmea';
    final healthSnapshot = _effectiveHealthSnapshot(context);
    final effectiveWeight = healthSnapshot.weight ?? dog.weight;
    final readinessBreakdown = dog.calculateReadinessBreakdown(
      lastBathOverride: healthSnapshot.lastBathDate,
      weightOverride: effectiveWeight,
    );
    final weightStr = effectiveWeight != null
        ? '${effectiveWeight.toStringAsFixed(1)} kg'
        : '-- kg';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(110), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _hudCyan.withAlpha(28),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.info_outline_rounded, color: _hudCyan, size: 16),
              const _PulsingIndicator(),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            dog.name.toUpperCase(),
            style: GoogleFonts.oxanium(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: _hudCyan,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 16),
          _DogReadinessSummary(breakdown: readinessBreakdown),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _CockpitMiniStat(
                  icon: Icons.cake_outlined,
                  label: 'Idade',
                  value: ageStr,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CockpitMiniStat(
                  icon: Icons.pets_outlined,
                  label: 'Sexo',
                  value: sexStr,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CockpitMiniStat(
                  icon: Icons.monitor_weight_outlined,
                  label: 'Peso',
                  value: weightStr,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  ({double? weight, DateTime? lastBathDate}) _effectiveHealthSnapshot(
    BuildContext context,
  ) {
    final healthLogs =
        Provider.of<HealthViewModel>(
            context,
          ).healthLogs.where((log) => log.dogId == dog.id).toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    double? latestWeight;
    DateTime? latestBathDate;

    for (final log in healthLogs) {
      latestWeight ??= log.weight;
      if (latestBathDate == null && log.logType == 'Banho') {
        latestBathDate = log.date;
      }
      if (latestWeight != null && latestBathDate != null) break;
    }

    return (weight: latestWeight, lastBathDate: latestBathDate);
  }
}
