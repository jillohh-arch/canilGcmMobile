part of 'active_shift_dashboard_screen.dart';

/// Card "Status do binômio" com leitura operacional do K9.
class _K9StatusCard extends StatelessWidget {
  final Dog dog;

  const _K9StatusCard({required this.dog});

  @override
  Widget build(BuildContext context) {
    final healthVM = Provider.of<HealthViewModel>(context);
    final trainingVM = Provider.of<TrainingViewModel>(context);

    final lastVaccination = _lastVaccinationDate(healthVM);
    final nextTraining = _nextTrainingLabel(trainingVM);
    final weightLabel = dog.weight != null
        ? '${dog.weight!.toStringAsFixed(1)} kg'
        : '—';

    return _DashboardPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        children: [
          const _PanelTitle(
            icon: Icons.shield_outlined,
            label: 'STATUS DO BINÔMIO',
          ),
          const SizedBox(height: 16),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => DogProfileScreen(dog: dog)),
              );
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 390;
                final identity = _DogIdentityBlock(
                  dog: dog,
                  weightLabel: weightLabel,
                  compact: compact,
                );
                final data = _DogDataColumn(
                  weightLabel: weightLabel,
                  lastVaccination: lastVaccination,
                  nextTraining: nextTraining,
                );

                if (compact) {
                  return Column(
                    children: [
                      identity,
                      Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(vertical: 13),
                        color: _kBorderStrong.withAlpha(82),
                      ),
                      data,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(flex: 10, child: identity),
                    const SizedBox(width: 12),
                    Container(
                      width: 1,
                      height: 88,
                      color: _kBorderStrong.withAlpha(82),
                    ),
                    const SizedBox(width: 18),
                    Expanded(flex: 11, child: data),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _lastVaccinationDate(HealthViewModel healthVM) {
    final directDate = dog.lastVaccineDate;
    if (directDate != null) return _formatDate(directDate);

    final vaccinations =
        healthVM.healthLogs
            .where((h) => h.logType.toLowerCase().contains('vacin'))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    if (vaccinations.isEmpty) return '—';
    return _formatDate(vaccinations.first.date);
  }

  String _nextTrainingLabel(TrainingViewModel trainingVM) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final hasToday = trainingVM.trainings.any(
      (t) =>
          t.date.year == today.year &&
          t.date.month == today.month &&
          t.date.day == today.day,
    );
    return hasToday ? 'Hoje' : '—';
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

class _DogIdentityBlock extends StatelessWidget {
  final Dog dog;
  final String weightLabel;
  final bool compact;

  const _DogIdentityBlock({
    required this.dog,
    required this.weightLabel,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DogStatusAvatar(dog: dog, compact: compact),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AutoFitText(
                dog.name.toUpperCase(),
                alignment: Alignment.centerLeft,
                textAlign: TextAlign.left,
                style: GoogleFonts.inter(
                  color: _kTextPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              _AutoFitText(
                '${dog.breed} • ${dog.age} anos • $weightLabel',
                alignment: Alignment.centerLeft,
                textAlign: TextAlign.left,
                style: GoogleFonts.inter(
                  color: _kTextSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              _StatusBadge(status: dog.operationalStatus),
            ],
          ),
        ),
      ],
    );
  }
}

class _DogDataColumn extends StatelessWidget {
  final String weightLabel;
  final String lastVaccination;
  final String nextTraining;

  const _DogDataColumn({
    required this.weightLabel,
    required this.lastVaccination,
    required this.nextTraining,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DogDataRow(
          icon: Icons.monitor_weight_outlined,
          label: 'Peso atual:',
          value: weightLabel,
        ),
        _DogDataDivider(),
        _DogDataRow(
          icon: Icons.vaccines_outlined,
          label: 'Última vacinação:',
          value: lastVaccination,
        ),
        _DogDataDivider(),
        _DogDataRow(
          icon: Icons.calendar_month_outlined,
          label: 'Próximo treino:',
          value: nextTraining,
          valueColor: nextTraining == 'Hoje'
              ? const Color(0xFF8BE36D)
              : _kTextPrimary,
        ),
      ],
    );
  }
}

class _DogStatusAvatar extends StatelessWidget {
  final Dog dog;
  final bool compact;

  const _DogStatusAvatar({required this.dog, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final size = compact ? 68.0 : 78.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF74DB69), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF74DB69).withAlpha(46),
                blurRadius: 14,
              ),
            ],
          ),
          child: ClipOval(
            child:
                dog.profileImageUrl != null && dog.profileImageUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: dog.profileImageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _dogFallback(),
                    errorWidget: (_, __, ___) => _dogFallback(),
                  )
                : _dogFallback(),
          ),
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF74DB69),
              border: Border.all(color: _kSurfaceElevated, width: 2),
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _dogFallback() {
    return Container(
      color: _kSurfaceElevated,
      alignment: Alignment.center,
      child: Text(
        dog.name.isNotEmpty ? dog.name[0] : 'K',
        style: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w900,
          color: AppTheme.primary,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isOperational =
        status.toLowerCase().contains('operacional') ||
        status.toLowerCase().contains('ativo') ||
        status.toLowerCase().contains('treino');
    final color = isOperational ? const Color(0xFF74DB69) : AppTheme.warning;
    final label = isOperational ? 'OPERACIONAL' : status.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: _AutoFitText(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DogDataRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DogDataRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _kTextSecondary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          flex: 6,
          child: _AutoFitText(
            label,
            alignment: Alignment.centerLeft,
            textAlign: TextAlign.left,
            style: GoogleFonts.inter(
              color: _kTextSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: _AutoFitText(
            value,
            alignment: Alignment.centerRight,
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              color: valueColor ?? _kTextPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _DogDataDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.only(left: 32, top: 8, bottom: 8),
      color: _kBorder,
    );
  }
}
