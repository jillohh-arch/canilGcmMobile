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
          _GuarnicaoFaixa(hasVehicle: hasVehicle, dog: dog),
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
            size: 64,
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
          const SizedBox(width: 10),
          // Info do cão — coluna esquerda
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
          const SizedBox(width: 10),
          // Avatar do condutor — mesmo tamanho
          _BinomioAvatar(
            size: 64,
            imageUrl: conductorPhotoUrl,
            icon: Icons.person_rounded,
            accent: AppTheme.primary,
          ),
          const SizedBox(width: 10),
          // Info do condutor — coluna direita
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Nome do condutor
                Text(
                  callsign,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Linha 2: Condutor · RA completo
                Text(
                  'Condutor${handlerId != null ? ' · RA $handlerId' : ''}',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // Linha 3: Badge função/K9 se embarcado
                if (isK9Conductor && condutorPapel != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          ),
        ],
      ),
    );
  }
}

/// Avatar generoso do card binômio.
class _BinomioAvatar extends StatelessWidget {
  final double size;
  final String? imageUrl;
  final IconData icon;
  final Color accent;
  final bool enableHero;
  final String? heroTag;
  final VoidCallback? onTap;

  const _BinomioAvatar({
    this.size = 52,
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
    final iconSize = size * 0.46;

    Widget avatar = Container(
      width: size,
      height: size,
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
                errorWidget: (_, __, _) => Icon(icon, color: accent, size: iconSize),
              )
            : Icon(icon, color: accent, size: iconSize),
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
  final Dog dog;

  const _GuarnicaoFaixa({required this.hasVehicle, required this.dog});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: HudDurations.normal,
      switchInCurve: HudCurves.enter,
      switchOutCurve: HudCurves.exit,
      child: hasVehicle
          ? _GuarnicaoEmbarcada(
              key: const ValueKey('embarcado'),
              dog: dog,
            )
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
  final Dog dog;

  const _GuarnicaoEmbarcada({super.key, required this.dog});

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
                FutureBuilder<String>(
                  future: VehicleCrewService().getCrewOperationalStatus(crewId),
                  builder: (context, snap) {
                    final status = snap.data ?? 'empty';
                    return _StatusChip(status: status);
                  },
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.textTertiary.withAlpha(150),
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Grade 2×2: planta da viatura
            StreamBuilder<List<VehicleCrewMember>>(
              stream: VehicleCrewService().watchMembers(crewId),
              builder: (context, snapshot) {
                final members = snapshot.data ?? [];
                final activeMembers = {
                  for (final m in members.where((m) => m.isActive)) m.role: m
                };

                return Column(
                  children: [
                    // Grade principal (MOT, ENC, AUX1, K9)
                    _VehicleGrid(
                      activeMembers: activeMembers,
                      currentHandlerId: currentHandlerId,
                      staggerAnimation: _staggerAnimation,
                      dog: widget.dog,
                      dogName: widget.dog.name,
                    ),
                    // Linha AUX2 se ocupado (senao invisivel)
                    if (activeMembers.containsKey('auxiliar_2')) ...[
                      const SizedBox(height: 6),
                      _Aux2CompactRow(
                        member: activeMembers['auxiliar_2']!,
                        isCurrentUser: activeMembers['auxiliar_2']!.handlerId == currentHandlerId,
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Grade 2×2: planta da viatura.
/// Layout: MOT (top-left) | ENC (top-right)
///          AUX1 (bot-left) | K9  (bot-right)
class _VehicleGrid extends StatelessWidget {
  final Map<String, VehicleCrewMember> activeMembers;
  final String? currentHandlerId;
  final Animation<double> staggerAnimation;
  final Dog dog;
  final String dogName;

  const _VehicleGrid({
    required this.activeMembers,
    required this.currentHandlerId,
    required this.staggerAnimation,
    required this.dog,
    required this.dogName,
  });

  @override
  Widget build(BuildContext context) {
    // Indices: 0=MOT, 1=ENC, 2=AUX1, 3=K9
    final positions = [
      (CrewPost.motorista, 0),
      (CrewPost.encarregado, 1),
      (CrewPost.auxiliar1, 2),
      (CrewPost.k9, 3),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 2.2,
      children: positions.map((p) {
        final post = p.$1;
        final index = p.$2;
        final member = activeMembers[post.role];

        return AnimatedBuilder(
          animation: staggerAnimation,
          builder: (context, child) {
            final delay = (index * 0.15).clamp(0.0, 0.6);
            final progress = ((staggerAnimation.value - delay) / (1.0 - delay))
                .clamp(0.0, 1.0);

            return Opacity(
              opacity: progress,
              child: Transform.translate(
                offset: Offset(0, 8 * (1 - progress)),
                child: post == CrewPost.k9
                    ? _K9Card(dog: dog, dogName: dogName)
                    : _CrewPostCard(
                        post: post,
                        member: member,
                        isCurrentUser: member?.handlerId == currentHandlerId,
                      ),
              ),
            );
          },
        );
      }).toList(),
    );
  }
}

/// Card do K9 na grade (baixo-direita) — estilo dourado.
class _K9Card extends StatelessWidget {
  final Dog dog;
  final String dogName;

  const _K9Card({required this.dog, required this.dogName});

  @override
  Widget build(BuildContext context) {
    // Cor dourada/ambar para o card K9
    const k9Color = Color(0xFFD4A017); // dourado-ambar
    const k9ColorSoft = Color(0xFFFFF3CD); // fundo suave

    // Buscar quem é o condutor deste cão
    final shiftVM = context.watch<ShiftViewModel>();
    final userVM = Provider.of<UserViewModel>(context, listen: false);

    // Nome do condutor via ShiftViewModel
    final handlerId = shiftVM.handlerId;
    final conductorName = handlerId != null
        ? userVM.displayNameFor(ra: handlerId)
        : null;

    final hasDog = dog.id.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: hasDog ? k9ColorSoft : AppTheme.surfacePanelAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasDog ? k9Color.withAlpha(120) : AppTheme.outlineVariant.withAlpha(60),
        ),
      ),
      child: hasDog
          ? Row(
              children: [
                // Avatar do cão
                _CrewAvatar(
                  size: 24,
                  imageUrl: dog.profileImageUrl,
                  icon: Icons.pets_rounded,
                  color: k9Color,
                ),
                const SizedBox(width: 5),
                // Info
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dogName.isNotEmpty ? dogName : dog.name,
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (conductorName != null)
                        Text(
                          'com $conductorName',
                          style: GoogleFonts.inter(
                            color: k9Color,
                            fontSize: 8,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Badge K9
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: k9Color.withAlpha(25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'K9',
                    style: GoogleFonts.robotoMono(
                      color: k9Color,
                      fontSize: 7,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.surfacePanelAlt,
                    border: Border.all(
                      color: AppTheme.textTertiary.withAlpha(60),
                    ),
                  ),
                  child: Icon(
                    Icons.pets_outlined,
                    color: AppTheme.textTertiary.withAlpha(80),
                    size: 11,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'SEM K9',
                    style: GoogleFonts.robotoMono(
                      color: AppTheme.textTertiary.withAlpha(100),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Card de posto de tripulante na grade.
class _CrewPostCard extends StatelessWidget {
  final CrewPost post;
  final VehicleCrewMember? member;
  final bool isCurrentUser;

  const _CrewPostCard({
    required this.post,
    required this.member,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    final isOccupied = member != null && member!.isActive;
    final hasK9 = isOccupied && member!.dogId?.trim().isNotEmpty == true;

    return Container(
      padding: const EdgeInsets.all(6),
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
          ? _OccupiedCrewCard(
              post: post,
              member: member!,
              hasK9: hasK9,
              isCurrentUser: isCurrentUser,
            )
          : _VacantCrewCard(post: post),
    );
  }
}

/// Card ocupado com avatar (foto real ou inicial).
class _OccupiedCrewCard extends StatelessWidget {
  final CrewPost post;
  final VehicleCrewMember member;
  final bool hasK9;
  final bool isCurrentUser;

  const _OccupiedCrewCard({
    required this.post,
    required this.member,
    required this.hasK9,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    // Nome para display
    String displayName = member.name?.trim().isNotEmpty == true
        ? member.name!
        : member.handlerId;

    // Buscar foto via UserViewModel
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final user = userVM.findByRa(member.handlerId);
    final memberPhoto = user?.photoUrl?.trim().isNotEmpty == true
        ? user!.photoUrl
        : null;

    final initials = _getInitials(displayName);
    final dotColor = isCurrentUser ? AppTheme.primary : AppTheme.success;

    return Row(
      children: [
        // Avatar com foto real ou inicial
        _CrewAvatar(
          size: 24,
          imageUrl: memberPhoto,
          fallbackText: initials,
          icon: _postIcon(post),
          color: dotColor,
        ),
        const SizedBox(width: 5),
        // Info
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
                post.shortLabel,
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
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasK9) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
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
              const SizedBox(width: 3),
            ],
            Container(
              width: 5,
              height: 5,
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

  IconData _postIcon(CrewPost post) {
    return switch (post) {
      CrewPost.motorista => Icons.drive_eta_outlined,
      CrewPost.encarregado => Icons.star_outline_rounded,
      CrewPost.auxiliar1 => Icons.person_outline,
      CrewPost.auxiliar2 => Icons.person_outline,
      CrewPost.k9 => Icons.pets_outlined,
    };
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '--';
    final parts = name.trim().split(' ');
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(0, 2)).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

/// Card vago.
class _VacantCrewCard extends StatelessWidget {
  final CrewPost post;

  const _VacantCrewCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.surfacePanelAlt,
            border: Border.all(
              color: AppTheme.textTertiary.withAlpha(60),
            ),
          ),
          child: Icon(
            _postIcon(post),
            color: AppTheme.textTertiary.withAlpha(80),
            size: 11,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'POSTO VAGO',
                style: GoogleFonts.robotoMono(
                  color: AppTheme.textTertiary.withAlpha(150),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                post.shortLabel,
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

  IconData _postIcon(CrewPost post) {
    return switch (post) {
      CrewPost.motorista => Icons.drive_eta_outlined,
      CrewPost.encarregado => Icons.star_outline_rounded,
      CrewPost.auxiliar1 => Icons.person_outline,
      CrewPost.auxiliar2 => Icons.person_outline,
      CrewPost.k9 => Icons.pets_outlined,
    };
  }
}

/// Avatar genérico: foto ou fallback com texto/ícone.
class _CrewAvatar extends StatelessWidget {
  final double size;
  final String? imageUrl;
  final String? fallbackText;
  final IconData icon;
  final Color color;

  const _CrewAvatar({
    required this.size,
    this.imageUrl,
    this.fallbackText,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = imageUrl?.trim().isNotEmpty == true;

    if (hasPhoto) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withAlpha(15),
          border: Border.all(color: color.withAlpha(150)),
        ),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: imageUrl!,
            fit: BoxFit.cover,
            errorWidget: (_, __, _) => _fallbackWidget,
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withAlpha(15),
        border: Border.all(color: color.withAlpha(150)),
      ),
      child: Center(child: _fallbackWidget),
    );
  }

  Widget get _fallbackWidget {
    if (fallbackText != null && fallbackText!.isNotEmpty) {
      return Text(
        fallbackText!,
        style: GoogleFonts.inter(
          color: color,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w800,
        ),
      );
    }
    return Icon(icon, color: color, size: size * 0.5);
  }
}

/// Linha compacta para AUX2 quando ocupado.
class _Aux2CompactRow extends StatelessWidget {
  final VehicleCrewMember member;
  final bool isCurrentUser;

  const _Aux2CompactRow({
    required this.member,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = member.name?.trim().isNotEmpty == true
        ? member.name!
        : member.handlerId;
    // Buscar foto via UserViewModel
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final user = userVM.findByRa(member.handlerId);
    final memberPhoto = user?.photoUrl?.trim().isNotEmpty == true
        ? user!.photoUrl
        : null;
    final dotColor = isCurrentUser ? AppTheme.primary : AppTheme.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCurrentUser
              ? AppTheme.primary.withAlpha(180)
              : AppTheme.outlineVariant,
          width: isCurrentUser ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          _CrewAvatar(
            size: 20,
            imageUrl: memberPhoto,
            fallbackText: _getInitials(displayName),
            icon: Icons.person_outline,
            color: dotColor,
          ),
          const SizedBox(width: 6),
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
          const SizedBox(width: 4),
          Text(
            'AUXILIAR 2',
            style: GoogleFonts.robotoMono(
              color: AppTheme.textTertiary,
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '--';
    final parts = name.trim().split(' ');
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length.clamp(0, 2)).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
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
