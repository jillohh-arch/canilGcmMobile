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
                errorWidget: (_, _, _) => Icon(icon, color: accent, size: iconSize),
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
  final Dog? dog;

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
  final Dog? dog;

  const _GuarnicaoEmbarcada({super.key, required this.dog});

  @override
  State<_GuarnicaoEmbarcada> createState() => _GuarnicaoEmbarcadaState();
}

class _GuarnicaoEmbarcadaState extends State<_GuarnicaoEmbarcada>
    with SingleTickerProviderStateMixin {
  late AnimationController _staggerController;
  late Animation<double> _staggerAnimation;
  final _crewService = VehicleCrewService();

  String? _crewId;
  Stream<List<VehicleCrewMember>>? _membersStream;
  Future<String>? _statusFuture;

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

    // Cache the stream and status — only recreate if crewId changes
    if (_crewId != crewId) {
      _crewId = crewId;
      _membersStream = _crewService.watchMembers(crewId);
      _statusFuture = _crewService.getCrewOperationalStatus(crewId);
    }

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
                  future: _statusFuture,
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
              stream: _membersStream,
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
                      dogName: widget.dog?.name ?? '',
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
  final Dog? dog;
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
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.0, // Cards mais altos para a foto respirar (~95px)
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

/// Card do K9 na grade (baixo-direita) — acento teal/cyan quente, sem dourado.
class _K9Card extends StatelessWidget {
  final Dog? dog;
  final String dogName;

  const _K9Card({required this.dog, required this.dogName});

  @override
  Widget build(BuildContext context) {
    // Acento teal diferenciado — não briga com o dark navy nem com cyan puro
    const k9Accent = Color(0xFF26C6DA); // cyan mais quente
    const k9AccentBg = Color(0xFF0A2E35); // background card

    // Buscar quem é o condutor deste cão
    final shiftVM = context.watch<ShiftViewModel>();
    final userVM = Provider.of<UserViewModel>(context, listen: false);

    final handlerId = shiftVM.handlerId;
    final conductorName = handlerId != null
        ? userVM.displayNameFor(ra: handlerId)
        : null;

    final hasDog = dog != null && dog!.id.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: hasDog ? k9AccentBg : AppTheme.surfacePanelAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasDog ? k9Accent.withAlpha(100) : AppTheme.outlineVariant.withAlpha(60),
        ),
      ),
      child: hasDog
          ? Row(
              children: [
                // Foto do cão — retangular crachá (~3:4)
                _K9Photo(
                  size: 56,
                  imageUrl: dog?.profileImageUrl,
                  accent: k9Accent,
                ),
                const SizedBox(width: 8),
                // Info
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Título K9 no topo (mono, pequeno)
                      Text(
                        'K9',
                        style: GoogleFonts.robotoMono(
                          color: k9Accent.withAlpha(140),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        dogName.isNotEmpty ? dogName : dog!.name,
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (conductorName != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          'com $conductorName',
                          style: GoogleFonts.inter(
                            color: k9Accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            )
          : Row(
              children: [
                // Placeholder dashed
                Container(
                  width: 40,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: AppTheme.surfacePanelAlt,
                    border: Border.all(
                      color: AppTheme.textTertiary.withAlpha(60),
                      width: 1.5,
                      strokeAlign: BorderSide.strokeAlignInside,
                    ),
                  ),
                  child: Icon(
                    Icons.pets_outlined,
                    color: AppTheme.textTertiary.withAlpha(80),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'K9',
                        style: GoogleFonts.robotoMono(
                          color: AppTheme.textTertiary.withAlpha(100),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SEM K9',
                        style: GoogleFonts.inter(
                          color: AppTheme.textTertiary.withAlpha(100),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Card de posto de tripulante na grade.
/// Layout: foto grande retangular à esquerda (~3:4), texto à direita.
/// Altura do card ≈ 95px para a foto respirar.
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
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isOccupied ? AppTheme.surfacePanel : AppTheme.surfacePanelAlt,
        borderRadius: BorderRadius.circular(10),
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

/// Card ocupado com foto grande retangular estilo crachá.
/// Layout: foto à esquerda (proporção ~3:4, altura ≈ altura do card) |
///          título do POSTO (mono, caixa alta, esmaecido)
///          NOME COMPLETO (ellipsis se não couber)
///          badges CONDUTOR + K9 + dot de status
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

    // isCondutorK9 vem de specialties do UserModel — campo specialties[] no Firestore.
    final isCondutorK9 = user?.isCondutorK9 ?? false;

    final initials = _getInitials(displayName);
    final dotColor = isCurrentUser ? AppTheme.primary : AppTheme.success;

    return Row(
      children: [
        // Foto grande retangular estilo crachá (~3:4)
        _CrewBadgePhoto(
          width: 52,
          height: 68,
          imageUrl: memberPhoto,
          fallbackText: initials,
          accent: dotColor,
        ),
        const SizedBox(width: 8),
        // Info à direita
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Título do POSTO no topo — mono, caixa alta, esmaecido
              Text(
                post.displayName.toUpperCase(),
                style: GoogleFonts.robotoMono(
                  color: AppTheme.textTertiary.withAlpha(120),
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 2),
              // Nome completo — ellipsis se não couber
              Text(
                displayName,
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // Linha de badges: CONDUTOR + K9 + dot
              Row(
                children: [
                  // CONDUTOR badge — cyan outline (se o membro tem "Condutor K9" em specialties)
                  if (isCondutorK9) ...[
                    _BadgeCondutor(),
                    const SizedBox(width: 4),
                  ],
                  // K9 badge — cyan sólido (se este membro tem cão embarcado)
                  if (hasK9) ...[
                    _BadgeK9(),
                    const SizedBox(width: 4),
                  ],
                  // Dot de status
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor,
                      boxShadow: [
                        BoxShadow(
                          color: dotColor.withAlpha(100),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
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
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

/// Badge "CONDUTOR" — cyan outline.
class _BadgeCondutor extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.primary.withAlpha(140), width: 1),
      ),
      child: Text(
        'CONDUTOR',
        style: GoogleFonts.robotoMono(
          color: AppTheme.primary,
          fontSize: 7,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Badge "K9" — cyan sólido.
class _BadgeK9 extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'K9',
        style: GoogleFonts.robotoMono(
          color: AppTheme.primary,
          fontSize: 7,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Card vago com placeholder dashed estilo crachá.
/// Layout: foto vazia dashed à esquerda | título POSTO no topo |
///          "POSTO VAGO" esmaecido | título do posto abaixo
class _VacantCrewCard extends StatelessWidget {
  final CrewPost post;

  const _VacantCrewCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Placeholder dashed — formato retangular crachá (~3:4)
        Container(
          width: 52,
          height: 68,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: AppTheme.surfacePanelAlt,
            border: Border.all(
              color: AppTheme.textTertiary.withAlpha(60),
              width: 1.5,
              strokeAlign: BorderSide.strokeAlignInside,
              // dashed simulation via custom painting would need CustomPainter;
              // settling for subtle dashed look via lighter border
            ),
          ),
          child: Icon(
            _postIcon(post),
            color: AppTheme.textTertiary.withAlpha(80),
            size: 22,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Título do posto no topo — esmaecido
              Text(
                post.displayName.toUpperCase(),
                style: GoogleFonts.robotoMono(
                  color: AppTheme.textTertiary.withAlpha(80),
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'POSTO VAGO',
                style: GoogleFonts.inter(
                  color: AppTheme.textTertiary.withAlpha(150),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                post.shortLabel,
                style: GoogleFonts.robotoMono(
                  color: AppTheme.textTertiary.withAlpha(80),
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

/// Foto estilo crachá: retangular (~3:4), cantos arredondados.
/// Fallback: bloco com inicial do nome.
class _CrewBadgePhoto extends StatelessWidget {
  final double width;
  final double height;
  final String? imageUrl;
  final String? fallbackText;
  final Color accent;

  const _CrewBadgePhoto({
    required this.width,
    required this.height,
    this.imageUrl,
    this.fallbackText,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = imageUrl?.trim().isNotEmpty == true;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: accent.withAlpha(15),
        border: Border.all(
          color: accent.withAlpha(120),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? CachedNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => _fallbackWidget,
            )
          : _fallbackWidget,
    );
  }

  Widget get _fallbackWidget {
    final text = fallbackText?.isNotEmpty == true ? fallbackText! : '--';
    return Center(
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: accent,
          fontSize: height * 0.28,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

/// Foto estilo crachá para o cão K9.
class _K9Photo extends StatelessWidget {
  final double size;
  final String? imageUrl;
  final Color accent;

  const _K9Photo({
    required this.size,
    this.imageUrl,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = imageUrl?.trim().isNotEmpty == true;
    // height = width * 4/3 para proporção ~3:4
    final height = size * 4 / 3;

    return Container(
      width: size,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: accent.withAlpha(15),
        border: Border.all(
          color: accent.withAlpha(120),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? CachedNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => _fallbackWidget,
            )
          : _fallbackWidget,
    );
  }

  Widget get _fallbackWidget {
    return Icon(
      Icons.pets_rounded,
      color: accent.withAlpha(160),
      size: size * 0.5,
    );
  }
}

/// Linha compacta para AUX2 quando ocupado — novo estilo com foto crachá.
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
    final initials = _getInitials(displayName);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrentUser
              ? AppTheme.primary.withAlpha(180)
              : AppTheme.outlineVariant,
          width: isCurrentUser ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Foto crachá compacta
          _CrewBadgePhoto(
            width: 36,
            height: 48,
            imageUrl: memberPhoto,
            fallbackText: initials,
            accent: dotColor,
          ),
          const SizedBox(width: 8),
          Text(
            displayName,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(width: 6),
          Text(
            'AUXILIAR 2',
            style: GoogleFonts.robotoMono(
              color: AppTheme.textTertiary.withAlpha(150),
              fontSize: 8,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              boxShadow: [
                BoxShadow(
                  color: dotColor.withAlpha(100),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
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
