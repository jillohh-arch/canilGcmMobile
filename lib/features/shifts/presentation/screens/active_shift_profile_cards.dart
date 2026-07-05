part of 'active_shift_dashboard_screen.dart';

class _ShiftProfileCardsSection extends StatelessWidget {
  final Dog dog;
  final String callsign;
  final String? conductorPhotoUrl;

  const _ShiftProfileCardsSection({
    required this.dog,
    required this.callsign,
    required this.conductorPhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final shiftVM = context.watch<ShiftViewModel>();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DashboardPanelTitle(
            icon: Icons.pets_rounded,
            title: 'Binômio em serviço',
          ),
          const SizedBox(height: 18),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: Builder(
                    builder: (ctx) => _ServiceSummaryColumn(
                      imageUrl: dog.profileImageUrl,
                      icon: Icons.pets_rounded,
                      accent: AppTheme.success,
                      title: dog.name,
                      subtitle: 'Cão de serviço',
                      enableHero: true,
                      heroTag: 'dog_avatar_${dog.id}',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(ctx).push(
                          MaterialPageRoute(
                            builder: (_) => K9ProfilePage(dog: dog),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const _ServiceSummaryDivider(),
                Expanded(
                  child: _ServiceSummaryColumn(
                    imageUrl: conductorPhotoUrl,
                    icon: Icons.person_rounded,
                    accent: AppTheme.primary,
                    title: callsign,
                    subtitle: 'Condutor',
                    detail: 'RA ${shiftVM.handlerId ?? '-'}',
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

class _ServiceSummaryColumn extends StatelessWidget {
  final String? imageUrl;
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String? detail;
  final bool enableHero;
  final String? heroTag;
  final VoidCallback? onTap;

  const _ServiceSummaryColumn({
    this.imageUrl,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    this.detail,
    this.enableHero = false,
    this.heroTag,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ServiceSummaryAvatar(
            imageUrl: imageUrl,
            icon: icon,
            accent: accent,
            enableHero: enableHero,
            heroTag: heroTag,
          ),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: _kTextPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(color: _kTextSecondary, fontSize: 12),
        ),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(
            detail!,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(color: _kTextMuted, fontSize: 12),
          ),
        ],
      ],
      ),
    );
  }
}

class _ServiceSummaryAvatar extends StatelessWidget {
  final String? imageUrl;
  final IconData icon;
  final Color accent;
  final bool enableHero;
  final String? heroTag;

  const _ServiceSummaryAvatar({
    this.imageUrl,
    required this.icon,
    required this.accent,
    this.enableHero = false,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl?.trim().isNotEmpty == true;

    Widget avatar = Container(
      width: 58,
      height: 58,
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
                errorWidget: (_, _, _) => Icon(icon, color: accent, size: 28),
              )
            : Icon(icon, color: accent, size: 28),
      ),
    );

    if (enableHero && heroTag != null && hasImage) {
      avatar = Hero(
        tag: heroTag!,
        child: avatar,
      );
    }

    return avatar;
  }
}

class _ServiceSummaryDivider extends StatelessWidget {
  const _ServiceSummaryDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      color: AppTheme.textPrimary.withAlpha(18),
    );
  }
}

/// ─────────────────────────────────────────────────────────────
/// Card "Guarnição" - mini-quadro dos 5 postos
/// ─────────────────────────────────────────────────────────────
class _GuarnicaoCard extends StatelessWidget {
  const _GuarnicaoCard();

  @override
  Widget build(BuildContext context) {
    final shiftVM = context.watch<ShiftViewModel>();
    final crewId = shiftVM.vehicleCrewId;
    final vehicleLabel = shiftVM.vehicleLabel?.trim();

    // Se não tem viatura assumida, não mostra o card
    if (crewId == null || crewId.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<VehicleCrewMember>>(
      stream: VehicleCrewService().watchMembers(crewId),
      builder: (context, snapshot) {
        final members = snapshot.data ?? [];
        final activeMembers = {
          for (final m in members.where((m) => m.isActive)) m.role: m
        };

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            VehicleCrewPostSheet.show(context);
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.textPrimary.withAlpha(7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.groups_3_rounded, color: AppTheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'GUARNIÇÃO',
                        style: GoogleFonts.inter(
                          color: AppTheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    if (vehicleLabel != null && vehicleLabel.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withAlpha(15),
                          borderRadius: BorderRadius.circular(5),
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
                      builder: (context, statusSnap) {
                        final status = statusSnap.data ?? 'empty';
                        return _MiniOperationalStatusChip(status: status);
                      },
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary, size: 20),
                  ],
                ),
                const SizedBox(height: 14),
                // Mini-quadro: 4 postos em linha compacta + badge K9
                Row(
                  children: [
                    Expanded(child: _MiniPostSlot(role: 'motorista', member: activeMembers['motorista'])),
                    const SizedBox(width: 6),
                    Expanded(child: _MiniPostSlot(role: 'encarregado', member: activeMembers['encarregado'])),
                    const SizedBox(width: 6),
                    Expanded(child: _MiniPostSlot(role: 'auxiliar_1', member: activeMembers['auxiliar_1'])),
                    const SizedBox(width: 6),
                    Expanded(child: _MiniPostSlot(role: 'auxiliar_2', member: activeMembers['auxiliar_2'])),
                  ],
                ),
                // Linha K9: vínculo, não posto
                const SizedBox(height: 8),
                _MiniK9Line(activeMembers: activeMembers),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Slot compacto para o mini-quadro da guarnição.
class _MiniPostSlot extends StatelessWidget {
  final String role;
  final VehicleCrewMember? member;

  const _MiniPostSlot({required this.role, this.member});

  @override
  Widget build(BuildContext context) {
    final isOccupied = member != null;
    final memberName = member?.name;

    return Column(
      children: [
        // Avatar/inicial ou slot vago
        if (isOccupied && memberName != null && memberName.trim().isNotEmpty)
          _MiniOccupiedAvatar(name: memberName, role: role, hasK9: member!.dogId?.trim().isNotEmpty == true)
        else if (isOccupied)
          _MiniOccupiedAvatar(name: member!.handlerId, role: role, hasK9: member!.dogId?.trim().isNotEmpty == true)
        else
          _MiniVacantSlot(role: role),
        const SizedBox(height: 4),
        // Nome curto ou traço
        Text(
          isOccupied ? _shortName(memberName ?? member!.handlerId) : '-',
          style: GoogleFonts.inter(
            color: isOccupied ? AppTheme.textPrimary : AppTheme.textTertiary,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        // Label da função
        Text(
          _roleLabelShort(role),
          style: GoogleFonts.robotoMono(
            color: AppTheme.textTertiary,
            fontSize: 7,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        // Badge K9 se o member é o condutor do cão
        if (isOccupied && member!.dogId != null && member!.dogId!.trim().isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: AppTheme.primary.withAlpha(50)),
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
      ],
    );
  }

  String _shortName(String name) {
    if (name.isEmpty) return '-';
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0].substring(0, parts[0].length.clamp(0, 4)).toUpperCase();
    return parts[0].substring(0, 1).toUpperCase() + (parts.length > 1 ? '.${parts.last.substring(0, 1).toUpperCase()}.' : '');
  }
}

/// Avatar compacto ocupado mostrando iniciais do nome.
class _MiniOccupiedAvatar extends StatelessWidget {
  final String name;
  final String role;
  final bool hasK9;

  const _MiniOccupiedAvatar({
    required this.name,
    required this.role,
    required this.hasK9,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(name);
    final accentColor = hasK9 ? AppTheme.primary : AppTheme.success;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accentColor.withAlpha(15),
            border: Border.all(color: accentColor.withAlpha(180)),
          ),
          child: Center(
            child: Text(
              initials,
              style: GoogleFonts.inter(
                color: accentColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        // Dot de status
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor,
              border: Border.all(color: AppTheme.surfacePanel, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '--';
    final parts = name.trim().split(' ');
    if (parts.length == 1) {
      // Nome único: até 2 caracteres
      return parts[0].substring(0, parts[0].length.clamp(0, 2)).toUpperCase();
    }
    // Primeiro nome + última letra do último nome (ex: "Ragonha" → "Ra", "Rui Santos" → "Rs")
    final first = parts.first.substring(0, 1).toUpperCase();
    final last = parts.last.isNotEmpty ? parts.last.substring(0, 1).toUpperCase() : '';
    return '$first$last';
  }
}

/// Slot vago com ícone da função e borda dashed.
class _MiniVacantSlot extends StatelessWidget {
  final String role;

  const _MiniVacantSlot({required this.role});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.surfacePanelAlt,
        border: Border.all(
          color: AppTheme.textTertiary.withAlpha(60),
          style: BorderStyle.solid,
          width: 1.5,
        ),
      ),
      child: Icon(
        _roleIcon(role),
        color: AppTheme.textTertiary.withAlpha(80),
        size: 14,
      ),
    );
  }
}

/// Linha compacta K9 (vínculo, não posto).
class _MiniK9Line extends StatelessWidget {
  final Map<String, VehicleCrewMember> activeMembers;

  const _MiniK9Line({required this.activeMembers});

  @override
  Widget build(BuildContext context) {
    // Identificar condutor K9
    VehicleCrewMember? k9Member;
    for (final m in activeMembers.values) {
      if (m.dogId != null && m.dogId!.trim().isNotEmpty) {
        k9Member = m;
        break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: k9Member != null ? AppTheme.primary.withAlpha(8) : AppTheme.surfacePanelAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: k9Member != null ? AppTheme.primary.withAlpha(30) : AppTheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.pets_rounded,
            color: k9Member != null ? AppTheme.primary : AppTheme.textTertiary,
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            'K9',
            style: GoogleFonts.robotoMono(
              color: AppTheme.textTertiary,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              k9Member != null
                  ? '${k9Member.name ?? 'RA ${k9Member.handlerId}'} (${_roleLabelShort(k9Member.role)})'
                  : 'Sem cão',
              style: GoogleFonts.inter(
                color: k9Member != null ? AppTheme.textPrimary : AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _roleLabelShort(String role) {
    return switch (role) {
      'motorista' => 'MOT',
      'encarregado' => 'ENC',
      'auxiliar_1' => 'AUX1',
      'auxiliar_2' => 'AUX2',
      'k9' => 'K9',
      _ => role,
    };
  }
}

/// Chip de status operacional compacto.
class _MiniOperationalStatusChip extends StatelessWidget {
  final String status;

  const _MiniOperationalStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'operational' => ('OPERACIONAL', AppTheme.success),
      'incomplete' => ('INCOMPLETA', AppTheme.warning),
      _ => ('DISPONIVEL', AppTheme.textTertiary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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

/// Helper: ícone para cada função.
IconData _roleIcon(String role) {
  return switch (role) {
    'motorista' => Icons.drive_eta_rounded,
    'encarregado' => Icons.star_rounded,
    'auxiliar_1' => Icons.person_outline_rounded,
    'auxiliar_2' => Icons.person_outline_rounded,
    'k9' => Icons.pets_rounded,
    _ => Icons.person_outline_rounded,
  };
}

/// Helper: label curto para cada função.
String _roleLabelShort(String role) {
  return switch (role) {
    'motorista' => 'MOT',
    'encarregado' => 'ENC',
    'auxiliar_1' => 'AUX1',
    'auxiliar_2' => 'AUX2',
    'k9' => 'K9',
    _ => role.toUpperCase().substring(0, 3),
  };
}
