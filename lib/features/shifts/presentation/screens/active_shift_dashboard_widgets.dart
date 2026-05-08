part of 'active_shift_dashboard_screen.dart';

class _DogInfoCockpitCard extends StatelessWidget {
  final Dog dog;
  const _DogInfoCockpitCard({required this.dog});

  @override
  Widget build(BuildContext context) {
    final String ageStr = '${dog.age} anos';
    final String sexStr = dog.sex == 'M' ? 'Macho' : 'Fêmea';
    final healthSnapshot = _effectiveHealthSnapshot(context);
    final effectiveWeight = healthSnapshot.weight ?? dog.weight;
    final readinessBreakdown = dog.calculateReadinessBreakdown(
      lastBathOverride: healthSnapshot.lastBathDate,
      weightOverride: effectiveWeight,
    );
    final String weightStr = effectiveWeight != null
        ? '${effectiveWeight.toStringAsFixed(1)} kg'
        : '-- kg';
    final raStr = dog.conductorRa != null && dog.conductorRa!.isNotEmpty
        ? dog.conductorRa!
        : 'S/N';

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
              _PulsingIndicator(),
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
          const SizedBox(height: 4),
          Text(
            'RA: $raStr',
            style: GoogleFonts.robotoMono(
              fontSize: 14,
              color: Colors.white54,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _buildReadinessBar(readinessBreakdown.total, readinessBreakdown),
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

  Widget _buildReadinessBar(
    int score,
    ({int total, int vacinacao, int peso, int higiene, int treino}) breakdown,
  ) {
    Color barColor;
    if (score >= 80) {
      barColor = _hudGreen;
    } else if (score >= 50) {
      barColor = _hudAmber;
    } else {
      barColor = _hudDanger;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'PRONTIDÃO OPERACIONAL',
              style: GoogleFonts.robotoMono(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.white60,
                letterSpacing: 1.0,
              ),
            ),
            Text(
              '$score%',
              style: GoogleFonts.oxanium(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: barColor,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: score / 100,
            backgroundColor: Colors.white.withAlpha(18),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Vacinação, peso, higiene e treino recente.',
          style: GoogleFonts.inter(
            fontSize: 10,
            color: Colors.white38,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Vacinação ${breakdown.vacinacao}/30 • Peso ${breakdown.peso}/25 • Higiene ${breakdown.higiene}/15 • Treino ${breakdown.treino}/30',
          style: GoogleFonts.robotoMono(
            fontSize: 10,
            color: Colors.white54,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CockpitMiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _CockpitMiniStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: _hudPanelAlt.withAlpha(210),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(75)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: _hudCyan.withAlpha(190), size: 22),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value.toUpperCase(),
              style: GoogleFonts.oxanium(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.robotoMono(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Colors.white54,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
