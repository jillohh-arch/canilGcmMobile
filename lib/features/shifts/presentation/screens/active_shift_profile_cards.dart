part of 'active_shift_dashboard_screen.dart';

/// ─────────────────────────────────────────────────────────────
/// Card unificado "EM SERVIÇO" — funde Binômio + Guarnição
/// ─────────────────────────────────────────────────────────────
class _EmServicoCard extends StatelessWidget {
  final Dog dog;
  final String callsign;
  final String? conductorPhotoUrl;

  const _EmServicoCard({
    required this.dog,
    required this.callsign,
    required this.conductorPhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final shiftVM = context.watch<ShiftViewModel>();
    final hasVehicle = shiftVM.hasVehicle;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // FAIXA 1 — BINÔMIO (sempre presente com turno ativo)
          _BinomioFaixa(
            dog: dog,
            callsign: callsign,
            conductorPhotoUrl: conductorPhotoUrl,
            hasVehicle: hasVehicle,
          ),
          // Divisor
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            height: 1,
            color: AppTheme.textPrimary.withAlpha(12),
          ),
          // FAIXA 2 — GUARNIÇÃO (estado-dependente)
          _GuarnicaoFaixa(hasVehicle: hasVehicle),
        ],
      ),
    );
  }
}

/// FAIXA 1 — Binômio: avatares generosos + nomes + papéis.
class _BinomioFaixa extends StatelessWidget {
  final Dog dog;
  final String callsign;
  final String? conductorPhotoUrl;
  final bool hasVehicle;

  const _BinomioFaixa({
    required this.dog,
    required this.callsign,
    required this.conductorPhotoUrl,
    required this.hasVehicle,
  });

  @override
  Widget build(BuildContext context) {
    final shiftVM = context.watch<ShiftViewModel>();
    final handlerId = shiftVM.handlerId;
    final crewRole = shiftVM.crewRole;

    // Papel do condutor no veículo (se embarcado)
    final condutorPapel = hasVehicle && crewRole != null
        ? _roleLabelCapitalized(crewRole)
        : null;
    // Badge K9 junto ao condutor se ele é o condutor do cão
    final isK9Conductor = shiftVM.activeDogId != null &&
        shiftVM.activeDogId!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Row(
        children: [
          // Avatar do cão — generoso
          _BinomioAvatar(
            imageUrl: dog.profileImageUrl,
            icon: Icons.pets_rounded,
            accent: AppTheme.success,
            enableHero: true,
            heroTag: 'dog_avatar_${dog.id}',
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => K9ProfilePage(dog: dog),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          // Info do cão
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dog.name,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Cão de serviço',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Divisor
          Container(
            width: 1,
            height: 48,
            color: AppTheme.textPrimary.withAlpha(15),
          ),
          const SizedBox(width: 12),
          // Info do condutor
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        callsign,
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isK9Conductor && condutorPapel != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withAlpha(20),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppTheme.primary.withAlpha(50)),
                        ),
                        child: Text(
                          '$condutorPapel · K9',
                          style: GoogleFonts.robotoMono(
                            color: AppTheme.primary,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Condutor${handlerId != null ? ' · RA' : ''}',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Avatar do condutor
          _BinomioAvatar(
            imageUrl: conductorPhotoUrl,
            icon: Icons.person_rounded,
            accent: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}

/// Avatar generoso do card binômio.
class _BinomioAvatar extends StatelessWidget {
  final String? imageUrl;
  final IconData icon;
  final Color accent;
  final bool enableHero;
  final String? heroTag;
  final VoidCallback? onTap;

  const _BinomioAvatar({
    this.imageUrl,
    required this.icon,
    required this.accent,
    this.enableHero = false,
    this.heroTag,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl?.trim().isNotEmpty == true;

    Widget avatar = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withAlpha(12),
        border: Border.all(color: accent.withAlpha(180)),
      ),
      child: ClipOval(
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, _) => Icon(icon, color: accent, size: 24),
              )
            : Icon(icon, color: accent, size: 24),
      ),
    );

    if (enableHero && heroTag != null && hasImage) {
      avatar = Hero(tag: heroTag!, child: avatar);
    }

    return GestureDetector(
      onTap: onTap,
      child: avatar,
    );
  }
}

/// FAIXA 2 — Guarnição: estado-dependente (sem viatura ou embarcado).
class _GuarnicaoFaixa extends StatelessWidget {
  final bool hasVehicle;

  const _GuarnicaoFaixa({required this.hasVehicle});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: HudDurations.normal,
      switchInCurve: HudCurves.enter,
      switchOutCurve: HudCurves.exit,
      child: hasVehicle
          ? _GuarnicaoEmbarcada(key: const ValueKey('embarcado'))
          : _GuarnicaoSemViatura(key: const ValueKey('sem_viatura')),
    );
  }
}

/// Estado 1: sem viatura — painel discreto + CTA.
class _GuarnicaoSemViatura extends StatelessWidget {
  const _GuarnicaoSemViatura({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        VehicleCrewPostSheet.show(context);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Row(
          children: [
            Icon(
              Icons.directions_car_outlined,
              color: AppTheme.textTertiary.withAlpha(150),
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sem viatura',
                style: GoogleFonts.inter(
                  color: AppTheme.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.primary.withAlpha(40)),
              ),
              child: Text(
                'ASSUMIR POSTO',
                style: GoogleFonts.robotoMono(
                  color: AppTheme.primary,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textTertiary.withAlpha(150),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Estado 2: embarcado — grade 2×2 dos postos.
class _GuarnicaoEmbarcada extends StatefulWidget {
  const _GuarnicaoEmbarcada({super.key});

  @override
  State<_GuarnicaoEmbarcada> createState() => _GuarnicaoEmbarcadaState();
}

class _GuarnicaoEmbarcadaState extends State<_GuarnicaoEmbarcada>
    with SingleTickerProviderStateMixin {
  late AnimationController _staggerController;
  late Animation<double> _staggerAnimation;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _staggerAnimation = CurvedAnimation(
      parent: _staggerController,
      curve: HudCurves.enter,
    );
    _staggerController.forward();
  }

  @override
  void dispose() {
    _staggerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shiftVM = context.watch<ShiftViewModel>();
    final crewId = shiftVM.vehicleCrewId!;
    final vehicleLabel = shiftVM.vehicleLabel?.trim();
    final currentHandlerId = shiftVM.handlerId;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        VehicleCrewPostSheet.show(context);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sub-header: viatura + status + chevron
            Row(
              children: [
                Icon(
                  Icons.groups_3_rounded,
                  color: AppTheme.textTertiary.withAlpha(150),
                  size: 16,
                ),
                const SizedBox(width: 8),
                if (vehicleLabel != null && vehicleLabel.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withAlpha(15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      vehicleLabel,
                      style: GoogleFonts.robotoMono(
                        color: AppTheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // Status chip
                Expanded(
                  child: FutureBuilder<String>(
                    future: VehicleCrewService().getCrewOperationalStatus(crewId),
                    builder: (context, snap) {
                      final status = snap.data ?? 'empty';
                      return _StatusChip(status: status);
                    },
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.textTertiary.withAlpha(150),
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Grade 2×2 dos postos
            StreamBuilder<List<VehicleCrewMember>>(
              stream: VehicleCrewService().watchMembers(crewId),
              builder: (context, snapshot) {
                final members = snapshot.data ?? [];
                final activeMembers = {
                  for (final m in members.where((m) => m.isActive)) m.role: m
                };

                return _MiniPostGrid(
                  activeMembers: activeMembers,
                  currentHandlerId: currentHandlerId,
                  staggerAnimation: _staggerAnimation,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Grade 2×2 dos mini-cards de posto.
class _MiniPostGrid extends StatelessWidget {
  final Map<String, VehicleCrewMember> activeMembers;
  final String? currentHandlerId;
  final Animation<double> staggerAnimation;

  const _MiniPostGrid({
    required this.activeMembers,
    required this.currentHandlerId,
    required this.staggerAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final roles = [
      ('encarregado', 0),
      ('motorista', 1),
      ('auxiliar_1', 2),
      ('auxiliar_2', 3),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 2.2,
      children: roles.map((r) {
        final index = r.$2;
        final role = r.$1;
        final member = activeMembers[role];
        final isCurrentUser = member != null && member.handlerId == currentHandlerId;

        return AnimatedBuilder(
          animation: staggerAnimation,
          builder: (context, child) {
            // Stagger: cada card entra com delay progressivo
            final delay = (index * 0.15).clamp(0.0, 0.6);
            final progress = ((staggerAnimation.value - delay) / (1.0 - delay))
                .clamp(0.0, 1.0);

            return Opacity(
              opacity: progress,
              child: Transform.translate(
                offset: Offset(0, 8 * (1 - progress)),
                child: _MiniPostCard(
                  role: role,
                  member: member,
                  isCurrentUser: isCurrentUser,
                ),
              ),
            );
          },
        );
      }).toList(),
    );
  }
}

/// Mini-card de posto para a grade 2×2.
class _MiniPostCard extends StatelessWidget {
  final String role;
  final VehicleCrewMember? member;
  final bool isCurrentUser;

  const _MiniPostCard({
    required this.role,
    required this.member,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    final isOccupied = member != null && member!.isActive;
    final memberName = member?.name;
    final hasK9 = isOccupied && member!.dogId?.trim().isNotEmpty == true;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isOccupied ? AppTheme.surfacePanel : AppTheme.surfacePanelAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCurrentUser
              ? AppTheme.primary.withAlpha(180)
              : isOccupied
                  ? AppTheme.outlineVariant
                  : AppTheme.outlineVariant.withAlpha(60),
          width: isCurrentUser ? 1.5 : 1,
        ),
      ),
      child: isOccupied
          ? _OccupiedMiniCard(
              role: role,
              member: member!,
              memberName: memberName,
              hasK9: hasK9,
              isCurrentUser: isCurrentUser,
            )
          : _VacantMiniCard(role: role),
    );
  }
}

/// Mini-card ocupado.
class _OccupiedMiniCard extends StatelessWidget {
  final String role;
  final VehicleCrewMember member;
  final String? memberName;
  final bool hasK9;
  final bool isCurrentUser;

  const _OccupiedMiniCard({
    required this.role,
    required this.member,
    required this.memberName,
    required this.hasK9,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = memberName?.trim().isNotEmpty == true
        ? memberName!
        : member.handlerId;

    // Obter iniciais do nome
    final initials = _getInitials(displayName);
    final dotColor = isCurrentUser ? AppTheme.primary : AppTheme.success;

    return Row(
      children: [
        // Avatar com iniciais
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor.withAlpha(15),
            border: Border.all(color: dotColor.withAlpha(150)),
          ),
          child: Center(
            child: Text(
              initials,
              style: GoogleFonts.inter(
                color: dotColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // Info
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _roleLabelUpper(role),
                style: GoogleFonts.robotoMono(
                  color: AppTheme.textTertiary,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
        // Badge K9 + dot
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (hasK9)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'K9',
                  style: GoogleFonts.robotoMono(
                    color: AppTheme.primary,
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            if (hasK9)
              const SizedBox(height: 3),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '--';
    final parts = name.trim().split(' ');
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(0, 2)).toUpperCase();
    }
    final first = parts.first.substring(0, 1).toUpperCase();
    final last = parts.last.isNotEmpty ? parts.last.substring(0, 1).toUpperCase() : '';
    return '$first$last';
  }

  String _roleLabelUpper(String role) {
    return switch (role) {
      'motorista' => 'MOTORISTA',
      'encarregado' => 'ENCARREGADO',
      'auxiliar_1' => 'AUXILIAR 1',
      'auxiliar_2' => 'AUXILIAR 2',
      'k9' => 'K9',
      _ => role.toUpperCase(),
    };
  }
}

/// Mini-card vago.
class _VacantMiniCard extends StatelessWidget {
  final String role;

  const _VacantMiniCard({required this.role});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Slot dashed
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.surfacePanelAlt,
            border: Border.all(
              color: AppTheme.textTertiary.withAlpha(60),
              width: 1,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Icon(
            _roleIcon(role),
            color: AppTheme.textTertiary.withAlpha(80),
            size: 12,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'POSTO VAGO',
                style: GoogleFonts.robotoMono(
                  color: AppTheme.textTertiary.withAlpha(150),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
              ),
              Text(
                _roleLabelUpper(role),
                style: GoogleFonts.robotoMono(
                  color: AppTheme.textTertiary.withAlpha(100),
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _roleLabelUpper(String role) {
    return switch (role) {
      'motorista' => 'MOTORISTA',
      'encarregado' => 'ENCARREGADO',
      'auxiliar_1' => 'AUXILIAR 1',
      'auxiliar_2' => 'AUXILIAR 2',
      'k9' => 'K9',
      _ => role.toUpperCase(),
    };
  }

  IconData _roleIcon(String role) {
    return switch (role) {
      'motorista' => Icons.drive_eta_outlined,
      'encarregado' => Icons.star_outline_rounded,
      'auxiliar_1' => Icons.person_outline,
      'auxiliar_2' => Icons.person_outline,
      'k9' => Icons.pets_outlined,
      _ => Icons.person_outline,
    };
  }
}

/// Chip de status operacional.
class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'operational' => ('OPERACIONAL', AppTheme.success),
      'incomplete' => ('INCOMPLETA', AppTheme.warning),
      _ => ('DISPONIVEL', AppTheme.textTertiary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Label capitalizado para função.
String _roleLabelCapitalized(String role) {
  return switch (role) {
    'motorista' => 'Motorista',
    'encarregado' => 'Encarregado',
    'auxiliar_1' => 'Auxiliar 1',
    'auxiliar_2' => 'Auxiliar 2',
    'k9' => 'K9',
    _ => role,
  };
}

/// Título de painel do dashboard (reutilizado por quick_actions e today_section).
class _DashboardPanelTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _DashboardPanelTitle({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: subtitle == null
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.primary, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  color: _kTextPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: GoogleFonts.inter(
                    color: _kTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
