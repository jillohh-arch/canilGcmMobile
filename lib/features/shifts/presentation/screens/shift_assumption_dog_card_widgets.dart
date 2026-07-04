part of 'shift_assumption_screen.dart';

class _DogSelectionCard extends StatelessWidget {
  final Dog dog;
  final bool isSelected;
  final bool isTitular;
  final String? titularName;
  final DogFitnessResult fitness;
  final VoidCallback onTap;

  const _DogSelectionCard({
    required this.dog,
    required this.isSelected,
    required this.isTitular,
    this.titularName,
    required this.fitness,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isUnfit = fitness.status == DogFitnessStatus.unfit;
    final borderColor = isSelected
        ? AppTheme.primary
        : isTitular
        ? AppTheme.primary.withAlpha(80)
        : AppTheme.outlineVariant;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(17, 14, 14, 14),
        // Stack com 2 camadas:
        // 1) container base com border uniforme + borderRadius (evita
        //    "A borderRadius can only be given on borders with uniform
        //    colors" quando o lado esquerdo precisa de cor diferente).
        // 2) barra esquerda (titular/selecionado) sobreposta.
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withAlpha(10)
              : isTitular
              ? AppTheme.primary.withAlpha(5)
              : AppTheme.surfacePanel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // barra lateral esquerda (cor distinta para titular/selecionado)
              if (isTitular || isSelected)
                Container(
                  width: 3,
                  margin: const EdgeInsets.only(right: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                    ),
                  ),
                )
              else
                const SizedBox(width: 0),
              Expanded(
                child: Opacity(
                  opacity: isUnfit ? 0.85 : 1.0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    // ── Top row: avatar + info ─────────────────────
                    Row(
                      children: [
                        _DogAvatar(dog: dog, fitness: fitness),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Nome + badge titular
                              Row(
                                children: [
                                  Text(
                                    dog.name,
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  if (isTitular) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary.withAlpha(20),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'SEU CÃO',
                                        style: GoogleFonts.inter(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.primary,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              // Raça + idade + peso
                              Text(
                                _buildSubtitle(),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              // Status operacional
                              _OperationalStatusLine(dog: dog),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── Status badge ─────────────────────────────
                    _FitnessBadge(fitness: fitness),

                    // ── Pendências ─────────────────────────────────
                    if (fitness.pendencies.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _PendenciesList(pendencies: fitness.pendencies),
                    ],

                    // ── Footer: titular + última atividade ─────────
                    const SizedBox(height: 6),
                    _CardFooter(
                      isTitular: isTitular,
                      titularName: titularName,
                      lastTrainingDate: dog.lastTrainingDate,
                    ),
                  ],
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  String _buildSubtitle() {
    final parts = <String>[];
    if (dog.breed.isNotEmpty) parts.add(dog.breed);
    parts.add('${dog.age} anos');
    if (dog.weight != null) parts.add('${dog.weight!.toStringAsFixed(0)}kg');
    return parts.join(' · ');
  }
}

class _DogAvatar extends StatelessWidget {
  final Dog dog;
  final DogFitnessResult fitness;

  const _DogAvatar({required this.dog, required this.fitness});

  @override
  Widget build(BuildContext context) {
    final borderColor = switch (fitness.status) {
      DogFitnessStatus.apt => AppTheme.success,
      DogFitnessStatus.warning => AppTheme.warning,
      DogFitnessStatus.unfit => AppTheme.error,
    };

    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2.5),
      ),
      child: ClipOval(
        child: dog.profileImageUrl != null && dog.profileImageUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: dog.profileImageUrl!,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                placeholder: (_, _) => _AvatarPlaceholder(name: dog.name),
                errorWidget: (_, _, _) => _AvatarPlaceholder(name: dog.name),
              )
            : _AvatarPlaceholder(name: dog.name),
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  final String name;

  const _AvatarPlaceholder({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surfacePanelAlt,
      child: Center(
        child: Text(
          name.isNotEmpty
              ? name.substring(0, name.length.clamp(0, 4)).toUpperCase()
              : 'K9',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _OperationalStatusLine extends StatelessWidget {
  final Dog dog;

  const _OperationalStatusLine({required this.dog});

  @override
  Widget build(BuildContext context) {
    final specialtyCount = dog.specialties?.length ?? 0;
    final statusText = dog.status == 'Ativo'
        ? 'Operacional${specialtyCount > 0 ? ' · $specialtyCount especialidade${specialtyCount > 1 ? 's' : ''}' : ''}'
        : dog.status;
    final statusColor = dog.status == 'Ativo'
        ? AppTheme.success
        : AppTheme.warning;
    final statusIcon = dog.status == 'Ativo' ? '●' : '◔';

    return Row(
      children: [
        Text(statusIcon, style: TextStyle(fontSize: 10, color: statusColor)),
        const SizedBox(width: 5),
        Text(
          statusText,
          style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textTertiary),
        ),
      ],
    );
  }
}

class _FitnessBadge extends StatelessWidget {
  final DogFitnessResult fitness;

  const _FitnessBadge({required this.fitness});

  @override
  Widget build(BuildContext context) {
    final color = switch (fitness.status) {
      DogFitnessStatus.apt => AppTheme.success,
      DogFitnessStatus.warning => AppTheme.warning,
      DogFitnessStatus.unfit => AppTheme.error,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            fitness.statusIcon,
            style: TextStyle(fontSize: 12, color: color),
          ),
          const SizedBox(width: 5),
          Text(
            fitness.statusLabel,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendenciesList extends StatelessWidget {
  final List<DogPendency> pendencies;

  const _PendenciesList({required this.pendencies});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.background.withAlpha(50),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: pendencies.map((p) {
          final color = p.severity == DogPendencySeverity.critical
              ? AppTheme.error
              : AppTheme.warning;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Text('●', style: TextStyle(fontSize: 11, color: color)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    p.label,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _CardFooter extends StatelessWidget {
  final bool isTitular;
  final String? titularName;
  final DateTime? lastTrainingDate;

  const _CardFooter({
    required this.isTitular,
    this.titularName,
    this.lastTrainingDate,
  });

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];

    if (!isTitular && titularName != null && titularName!.isNotEmpty) {
      parts.add('Titular: $titularName');
    }

    if (lastTrainingDate != null) {
      parts.add('Última: ${_formatRelativeDate(lastTrainingDate!)}');
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join(' · '),
      style: GoogleFonts.inter(
        fontSize: 9,
        fontStyle: FontStyle.italic,
        color: AppTheme.textTertiary,
      ),
    );
  }

  String _formatRelativeDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inHours < 1) return 'agora';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    if (diff.inDays == 1) return 'ontem';
    if (diff.inDays < 7) return 'há ${diff.inDays} dias';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }
}


class _AssumptionCta extends StatelessWidget {
  final Dog dog;
  final DogFitnessResult fitness;
  final bool isLoading;
  final VoidCallback onPressed;

  const _AssumptionCta({
    required this.dog,
    required this.fitness,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isUnfit = fitness.status == DogFitnessStatus.unfit;

    final bgColor = isUnfit ? AppTheme.warning.withAlpha(20) : AppTheme.primary;
    final fgColor = isUnfit ? AppTheme.warning : AppTheme.background;
    final borderSide = isUnfit
        ? BorderSide(color: AppTheme.warning.withAlpha(130))
        : BorderSide.none;
    final label = isUnfit
        ? 'ASSUMIR ${dog.name.toUpperCase()} COM PENDENCIA'
        : 'INICIAR TURNO';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.background.withAlpha(0), AppTheme.background],
          stops: const [0.0, 0.2],
        ),
      ),
      child: SizedBox(
        height: 56,
        child: Material(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: isLoading ? null : onPressed,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.fromBorderSide(borderSide),
              ),
              child: Center(
                child: isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: fgColor,
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: fgColor,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
