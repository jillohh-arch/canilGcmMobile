part of 'training_hub_screen.dart';

class _TrainingSpecialtiesSection extends StatelessWidget {
  final List<TrainingSpecialtyModel> specialties;
  final bool loading;
  final ValueChanged<String> onTap;

  const _TrainingSpecialtiesSection({
    required this.specialties,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _TrainingPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TrainingPanelTitle(
            icon: Icons.shield_outlined,
            label: 'ESPECIALIDADES OPERACIONAIS',
          ),
          const SizedBox(height: 12),
          if (specialties.isEmpty)
            _TrainingEmptyState(
              icon: loading ? Icons.sync_rounded : Icons.shield_outlined,
              message: loading
                  ? 'Carregando especialidades...'
                  : 'Nenhuma especialidade cadastrada',
            )
          else
            for (int i = 0; i < specialties.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == specialties.length - 1 ? 0 : 10,
                ),
                child: _SpecialtyRow(
                  specialty: specialties[i],
                  onTap: () => onTap(specialties[i].name),
                ),
              ),
        ],
      ),
    );
  }
}

class _SpecialtyRow extends StatelessWidget {
  final TrainingSpecialtyModel specialty;
  final VoidCallback onTap;

  const _SpecialtyRow({required this.specialty, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _trainingColorFor(specialty.name, status: specialty.status);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 84),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(7),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: _trainingBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 84,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(7),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _TrainingIconBox(
                icon: _trainingIconFor(specialty.name),
                color: color,
                size: 54,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TrainingAutoFitText(
                        specialty.name.toUpperCase(),
                        alignment: Alignment.centerLeft,
                        textAlign: TextAlign.left,
                        style: GoogleFonts.inter(
                          color: _trainingTextPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 5),
                      if (specialty.subAreas.isEmpty)
                        _StatusLine(
                          label: specialty.statusLabel,
                          color: color,
                          prefixDot: true,
                        )
                      else
                        ...specialty.subAreas
                            .take(2)
                            .map(
                              (area) => Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: _StatusLine(
                                  label: '${area.name}: ${area.statusLabel}',
                                  color: area.isOperational
                                      ? _trainingGreen
                                      : _trainingYellow,
                                  prefixDot: true,
                                ),
                              ),
                            ),
                      const SizedBox(height: 4),
                      Text(
                        'Último treino: ${specialty.lastTrainingLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: _trainingTextSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ProgressOrCheck(specialty: specialty, color: color),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: _trainingTextSecondary,
                size: 24,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressOrCheck extends StatelessWidget {
  final TrainingSpecialtyModel specialty;
  final Color color;

  const _ProgressOrCheck({required this.specialty, required this.color});

  @override
  Widget build(BuildContext context) {
    if (specialty.isOperational && specialty.progressPercentage >= 100) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _trainingGreen, width: 2.5),
        ),
        child: const Icon(Icons.check_rounded, color: _trainingGreen, size: 28),
      );
    }

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              value: specialty.progressPercentage / 100,
              strokeWidth: 5,
              backgroundColor: _trainingBorder,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          _TrainingAutoFitText(
            '${specialty.progressPercentage}%',
            style: GoogleFonts.inter(
              color: _trainingTextPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrainingGeneralSection extends StatelessWidget {
  final List<TrainingGeneralTypeModel> trainings;
  final ValueChanged<String> onTap;

  const _TrainingGeneralSection({required this.trainings, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _TrainingPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TrainingPanelTitle(
            icon: Icons.fitness_center_rounded,
            label: 'TREINOS GERAIS',
          ),
          const SizedBox(height: 12),
          if (trainings.isEmpty)
            const _TrainingEmptyState(
              icon: Icons.fitness_center_rounded,
              message: 'Nenhum treino geral registrado',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 360;
                final itemWidth = twoColumns
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: trainings
                      .map(
                        (training) => SizedBox(
                          width: itemWidth,
                          child: _GeneralTrainingTile(
                            training: training,
                            onTap: () => onTap(training.name),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _GeneralTrainingTile extends StatelessWidget {
  final TrainingGeneralTypeModel training;
  final VoidCallback onTap;

  const _GeneralTrainingTile({required this.training, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _trainingColorFor(training.name, status: training.status);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(7),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: _trainingBorder),
          ),
          child: Row(
            children: [
              Icon(_trainingIconFor(training.name), color: color, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      training.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: _trainingTextPrimary,
                        fontSize: 14,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _StatusLine(
                      label: training.lastTrainingLabel,
                      color: _trainingGreen,
                      prefixDot: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.check_circle_outline_rounded,
                color: _trainingGreen,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrainingRecentSessionsSection extends StatelessWidget {
  final List<TrainingHubSession> sessions;
  final VoidCallback onOpenLog;

  const _TrainingRecentSessionsSection({
    required this.sessions,
    required this.onOpenLog,
  });

  @override
  Widget build(BuildContext context) {
    return _TrainingPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TrainingPanelTitle(
            icon: Icons.history_rounded,
            label: 'SESSÕES RECENTES',
            trailing: TextButton(
              onPressed: onOpenLog,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ver todas',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (sessions.isEmpty)
            const _TrainingEmptyState(
              icon: Icons.history_rounded,
              message: 'Nenhuma sessão registrada',
            )
          else
            Stack(
              children: [
                Positioned(
                  left: 9,
                  top: 18,
                  bottom: 18,
                  child: Container(width: 1, color: AppTheme.primary),
                ),
                Column(
                  children: [
                    for (int i = 0; i < sessions.length; i++)
                      _RecentSessionRow(
                        session: sessions[i],
                        isLast: i == sessions.length - 1,
                      ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RecentSessionRow extends StatelessWidget {
  final TrainingHubSession session;
  final bool isLast;

  const _RecentSessionRow({required this.session, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final color = _trainingColorFor(session.trainingType);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 330;
        final timeWidth = compact ? 44.0 : 52.0;
        final iconSize = compact ? 42.0 : 48.0;

        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
          child: Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: _trainingSurface, width: 1.8),
                ),
              ),
              SizedBox(width: compact ? 10 : 14),
              SizedBox(
                width: timeWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatTime(session.date),
                      style: GoogleFonts.inter(
                        color: _trainingTextSecondary,
                        fontSize: compact ? 12 : 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _relativeDay(session.date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: _trainingTextMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              _TrainingIconBox(
                icon: _trainingIconFor(session.trainingType),
                color: color,
                size: iconSize,
              ),
              SizedBox(width: compact ? 9 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: _trainingTextPrimary,
                        fontSize: compact ? 13 : 14,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      session.displaySubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: _trainingTextSecondary,
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 5 : 8),
              compact
                  ? const Icon(
                      Icons.cloud_done_rounded,
                      color: _trainingGreen,
                      size: 20,
                    )
                  : _TrainingStatusChip(label: session.syncStatusLabel),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                color: _trainingTextSecondary,
                size: 22,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NewTrainingSessionButton extends StatelessWidget {
  final VoidCallback onTap;

  const _NewTrainingSessionButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 58,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.add_rounded,
                color: _trainingBackground,
                size: 29,
              ),
              const SizedBox(width: 12),
              Text(
                'NOVA SESSÃO DE TREINO',
                style: GoogleFonts.inter(
                  color: _trainingBackground,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrainingIconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _TrainingIconBox({
    required this.icon,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _trainingBorderStrong.withAlpha(105)),
      ),
      child: Icon(icon, color: color, size: size * .48),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final String label;
  final Color color;
  final bool prefixDot;

  const _StatusLine({
    required this.label,
    required this.color,
    this.prefixDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (prefixDot) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _TrainingStatusChip extends StatelessWidget {
  final String label;

  const _TrainingStatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _trainingGreen.withAlpha(10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _trainingGreen.withAlpha(150)),
      ),
      child: _TrainingAutoFitText(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          color: _trainingGreen,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TrainingEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _TrainingEmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _trainingBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                color: _trainingTextSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTime(DateTime date) {
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String _relativeDay(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Hoje';
  if (diff == 1) return 'Ontem';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
}
