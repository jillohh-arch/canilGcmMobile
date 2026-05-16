part of 'active_shift_dashboard_screen.dart';

/// Card "Status do Binômio" — perfil do K9 com dados operacionais.
class _K9StatusCard extends StatelessWidget {
  final Dog dog;

  const _K9StatusCard({required this.dog});

  @override
  Widget build(BuildContext context) {
    final healthVM = Provider.of<HealthViewModel>(context);
    final trainingVM = Provider.of<TrainingViewModel>(context);

    // Última vacinação
    final lastVaccination = _lastVaccinationDate(healthVM);
    // Próximo treino
    final nextTraining = _nextTrainingLabel(trainingVM);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(text: 'STATUS DO BINÔMIO'),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => DogProfileScreen(dog: dog)),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              children: [
                // Avatar do cão
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primary.withAlpha(60), width: 2),
                  ),
                  child: ClipOval(
                    child: dog.profileImageUrl != null && dog.profileImageUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: dog.profileImageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => _dogFallback(),
                            errorWidget: (_, __, ___) => _dogFallback(),
                          )
                        : _dogFallback(),
                  ),
                ),
                const SizedBox(width: 14),

                // Info principal
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            dog.name.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _kTextPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusBadge(status: dog.operationalStatus),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${dog.breed} · ${dog.age} anos${dog.weight != null ? ' · ${dog.weight!.toStringAsFixed(1)} kg' : ''}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: _kTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Dados laterais
                      Row(
                        children: [
                          _MiniStat(
                            label: 'Peso',
                            value: dog.weight != null
                                ? '${dog.weight!.toStringAsFixed(1)} kg'
                                : '—',
                          ),
                          const SizedBox(width: 16),
                          _MiniStat(
                            label: 'Vacinação',
                            value: lastVaccination,
                          ),
                          const SizedBox(width: 16),
                          _MiniStat(
                            label: 'Treino',
                            value: nextTraining,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                Icon(Icons.chevron_right_rounded, color: _kTextMuted, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dogFallback() {
    return Container(
      color: const Color(0xFF0F2026),
      child: Center(
        child: Text(
          dog.name.isNotEmpty ? dog.name[0] : 'K',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppTheme.primary,
          ),
        ),
      ),
    );
  }

  String _lastVaccinationDate(HealthViewModel healthVM) {
    final vaccinations = healthVM.healthLogs
        .where((h) => h.logType.toLowerCase().contains('vacin'))
        .toList();
    if (vaccinations.isEmpty) return '—';
    vaccinations.sort((a, b) => b.date.compareTo(a.date));
    final d = vaccinations.first.date;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _nextTrainingLabel(TrainingViewModel trainingVM) {
    if (trainingVM.trainings.isEmpty) return '—';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final hasToday = trainingVM.trainings.any((t) =>
        t.date.year == today.year &&
        t.date.month == today.month &&
        t.date.day == today.day);
    return hasToday ? 'Hoje' : '—';
  }
}

/// Badge de status operacional.
class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isOperational = status.toLowerCase().contains('operacional') ||
        status.toLowerCase().contains('ativo');
    final color = isOperational ? AppTheme.success : AppTheme.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Mini stat inline (label + value).
class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: _kTextMuted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _kTextSecondary,
          ),
        ),
      ],
    );
  }
}
