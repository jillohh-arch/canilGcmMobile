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
    final crewId = shiftVM.vehicleCrewId;
    final vehicleLabel = shiftVM.vehicleLabel?.trim();

    return StreamBuilder<List<VehicleCrewMember>>(
      stream: crewId == null || crewId.isEmpty
          ? Stream.value(const <VehicleCrewMember>[])
          : VehicleCrewService().watchMembers(crewId),
      builder: (context, snapshot) {
        final members = snapshot.data ?? const <VehicleCrewMember>[];
        final activeCount = members.where((member) => member.isActive).length;
        final pendingCount = members.where((member) => member.isPending).length;
        final teamSubtitle = crewId == null || crewId.isEmpty
            ? 'Sem equipe ativa'
            : '$activeCount condutor${activeCount == 1 ? '' : 'es'} + K9'
                  '${pendingCount == 0 ? '' : ' · $pendingCount pendente(s)'}';

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
                icon: Icons.groups_2_rounded,
                title: 'Binômio em serviço',
              ),
              const SizedBox(height: 18),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _ServiceSummaryColumn(
                        imageUrl: dog.profileImageUrl,
                        icon: Icons.pets_rounded,
                        accent: AppTheme.success,
                        title: dog.name,
                        subtitle: 'Cão de serviço',
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
                    const _ServiceSummaryDivider(),
                    Expanded(
                      child: _ServiceSummaryColumn(
                        icon: Icons.directions_car_filled_rounded,
                        accent: AppTheme.primary,
                        title: vehicleLabel?.isNotEmpty == true
                            ? vehicleLabel!
                            : 'Sem viatura',
                        subtitle: 'Equipe',
                        detail: teamSubtitle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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

  const _ServiceSummaryColumn({
    this.imageUrl,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ServiceSummaryAvatar(imageUrl: imageUrl, icon: icon, accent: accent),
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
    );
  }
}

class _ServiceSummaryAvatar extends StatelessWidget {
  final String? imageUrl;
  final IconData icon;
  final Color accent;

  const _ServiceSummaryAvatar({
    this.imageUrl,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl?.trim().isNotEmpty == true;
    return Container(
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
