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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withAlpha(10)
              : isTitular
              ? AppTheme.primary.withAlpha(5)
              : AppTheme.surfacePanel,
          borderRadius: BorderRadius.circular(14),
          border: Border(
            left: BorderSide(
              color: isTitular ? AppTheme.primary : borderColor,
              width: isTitular ? 3 : (isSelected ? 2 : 1),
            ),
            top: BorderSide(color: borderColor, width: isSelected ? 2 : 1),
            right: BorderSide(color: borderColor, width: isSelected ? 2 : 1),
            bottom: BorderSide(color: borderColor, width: isSelected ? 2 : 1),
          ),
        ),
        child: Opacity(
          opacity: isUnfit ? 0.85 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: avatar + info ─────────────────────────────
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

              // ── Status badge ───────────────────────────────────────
              _FitnessBadge(fitness: fitness),

              // ── Pendências ─────────────────────────────────────────
              if (fitness.pendencies.isNotEmpty) ...[
                const SizedBox(height: 8),
                _PendenciesList(pendencies: fitness.pendencies),
              ],

              // ── Footer: titular + última atividade ─────────────────
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

class _VehicleSelectionSection extends StatelessWidget {
  final VehicleService vehicleService;
  final Vehicle? selectedVehicle;
  final ValueChanged<Vehicle> onSelected;

  const _VehicleSelectionSection({
    required this.vehicleService,
    required this.selectedVehicle,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Vehicle>>(
      stream: vehicleService.watchActiveVehicles(),
      builder: (context, vehicleSnapshot) {
        return StreamBuilder<Map<String, int>>(
          stream: vehicleService.watchVehicleOccupancies(),
          builder: (context, occupancySnapshot) {
            final vehicles = vehicleSnapshot.data ?? const <Vehicle>[];
            final occupancies = occupancySnapshot.data ?? const <String, int>{};
            final vehicleError = vehicleSnapshot.error;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Assumir viatura',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.textTertiary.withAlpha(25),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.textTertiary.withAlpha(60),
                        ),
                      ),
                      child: Text(
                        'OPCIONAL',
                        style: GoogleFonts.inter(
                          color: AppTheme.textTertiary,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'A lista vem do Firebase. Se for apenas treino, voce pode iniciar o turno so com o K9.',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                if (vehicleError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Nao foi possivel carregar viaturas: $vehicleError',
                      style: GoogleFonts.inter(
                        color: AppTheme.error,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  )
                else if (vehicleSnapshot.connectionState ==
                        ConnectionState.waiting &&
                    vehicles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    ),
                  )
                else if (vehicles.isEmpty)
                  _VehicleEmptyState()
                else
                  for (final vehicle in vehicles)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _VehicleOptionCard(
                        vehicle: vehicle,
                        occupancy: occupancies[vehicle.id] ?? 0,
                        selected: selectedVehicle?.id == vehicle.id,
                        onTap: () => onSelected(vehicle),
                      ),
                    ),
              ],
            );
          },
        );
      },
    );
  }
}

class _VehicleOptionCard extends StatelessWidget {
  final Vehicle vehicle;
  final int occupancy;
  final bool selected;
  final VoidCallback onTap;

  const _VehicleOptionCard({
    required this.vehicle,
    required this.occupancy,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final full = occupancy >= vehicle.crewSize;
    final borderColor = selected
        ? AppTheme.primary
        : AppTheme.primary.withAlpha(30);

    return Opacity(
      opacity: full && !selected ? 0.72 : 1,
      child: GestureDetector(
        onTap: full && !selected ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withAlpha(18)
                : AppTheme.primary.withAlpha(8),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withAlpha(selected ? 35 : 18),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: AppTheme.primary.withAlpha(70)),
                    ),
                    child: const Icon(
                      Icons.directions_car_filled_rounded,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vehicle.label,
                          style: GoogleFonts.robotoMono(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (vehicle.modelName.isNotEmpty)
                          Text(
                            vehicle.modelName,
                            style: GoogleFonts.inter(
                              color: AppTheme.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected ? AppTheme.primary : AppTheme.textTertiary,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _VehicleChip(
                    label: 'Capacidade',
                    value: '${vehicle.crewSize} + K9',
                  ),
                  _VehicleChip(
                    label: 'Ocupacao',
                    value: full
                        ? '$occupancy de ${vehicle.crewSize} cheia'
                        : '$occupancy de ${vehicle.crewSize}',
                    warning: full,
                  ),
                  _VehicleChip(label: 'Unidade', value: vehicle.unit),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleChip extends StatelessWidget {
  final String label;
  final String value;
  final bool warning;

  const _VehicleChip({
    required this.label,
    required this.value,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = warning ? AppTheme.warning : AppTheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(14),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withAlpha(45)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: GoogleFonts.robotoMono(
                color: AppTheme.textSecondary,
                fontSize: 10,
              ),
            ),
            TextSpan(
              text: value,
              style: GoogleFonts.robotoMono(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withAlpha(28)),
      ),
      child: Text(
        'Nenhuma viatura ativa cadastrada no Firebase.',
        style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12),
      ),
    );
  }
}

class _AssumptionCta extends StatelessWidget {
  final Dog dog;
  final Vehicle? vehicle;
  final DogFitnessResult fitness;
  final bool isLoading;
  final VoidCallback onPressed;
  final VoidCallback? onStartWithoutVehicle;

  const _AssumptionCta({
    required this.dog,
    this.vehicle,
    required this.fitness,
    required this.isLoading,
    required this.onPressed,
    this.onStartWithoutVehicle,
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
        : vehicle == null
        ? 'INICIAR SO COM O K9 ${dog.name.toUpperCase()}'
        : 'ASSUMIR ${vehicle!.label.toUpperCase()} E INICIAR TURNO';

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
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
          if (onStartWithoutVehicle != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 42,
              width: double.infinity,
              child: OutlinedButton(
                onPressed: isLoading ? null : onStartWithoutVehicle,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: BorderSide(color: AppTheme.primary.withAlpha(35)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Iniciar so com o K9'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
