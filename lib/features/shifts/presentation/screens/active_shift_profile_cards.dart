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

/// Helper: label curto para cada função.
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
                const SizedBox(height: 12),
                // Mini-quadro: 4 linhas compactas
                Column(
                  children: [
                    _MiniPostLine(role: 'motorista', member: activeMembers['motorista']),
                    const SizedBox(height: 4),
                    _MiniPostLine(role: 'encarregado', member: activeMembers['encarregado']),
                    const SizedBox(height: 4),
                    _MiniPostLine(role: 'auxiliar_1', member: activeMembers['auxiliar_1']),
                    const SizedBox(height: 4),
                    _MiniPostLine(role: 'auxiliar_2', member: activeMembers['auxiliar_2']),
                  ],
                ),
                // Linha K9: vínculo
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

/// Linha compacta para o mini-quadro da guarnição.
class _MiniPostLine extends StatelessWidget {
  final String role;
  final VehicleCrewMember? member;

  const _MiniPostLine({required this.role, this.member});

  @override
  Widget build(BuildContext context) {
    final isOccupied = member != null && member!.isActive;
    final memberName = member?.name;
    final hasK9 = isOccupied && member!.dogId?.trim().isNotEmpty == true;

    // Nome visível: nome real ou fallback handlerId
    String displayName;
    if (isOccupied && memberName != null && memberName.trim().isNotEmpty) {
      displayName = memberName;
    } else if (isOccupied) {
      displayName = member!.handlerId;
    } else {
      displayName = 'vago';
    }

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          // Label da função - largura fixa, mono, esmaecido
          SizedBox(
            width: 44,
            child: Text(
              _roleLabelShort(role),
              style: GoogleFonts.robotoMono(
                color: AppTheme.textTertiary.withAlpha(isOccupied ? 180 : 120),
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Conteúdo: nome ou "vago"
          Expanded(
            child: Text(
              displayName,
              style: GoogleFonts.inter(
                color: isOccupied ? AppTheme.textPrimary : AppTheme.textTertiary,
                fontSize: 11,
                fontWeight: isOccupied ? FontWeight.w600 : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Badge K9 se condutor do cão
          if (hasK9)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'K9',
                style: GoogleFonts.robotoMono(
                  color: AppTheme.primary,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          // Dot de status - só se ocupado
          if (isOccupied)
            Container(
              margin: const EdgeInsets.only(left: 6),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasK9 ? AppTheme.primary : AppTheme.success,
              ),
            ),
        ],
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
