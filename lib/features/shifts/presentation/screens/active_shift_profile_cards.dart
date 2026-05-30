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
    final vehicleLabel = shiftVM.vehicleLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(emoji: '', text: 'BINÔMIO & EQUIPE'),
        _ShiftProfileCard(
          eyebrow: 'CÃO DE SERVIÇO',
          title: dog.name,
          subtitle:
              '${dog.operationalStatus} · ${dog.specialties?.length ?? 0} especialidade(s)',
          color: AppTheme.success,
          imageUrl: dog.profileImageUrl,
          icon: Icons.pets_rounded,
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => DogProfileScreen(dog: dog))),
        ),
        const SizedBox(height: 8),
        _ShiftProfileCard(
          eyebrow: 'CONDUTOR',
          title: callsign,
          subtitle:
              '${shiftVM.crewRole == 'titular' ? 'Titular' : 'Integrante'} · RA ${shiftVM.handlerId ?? '-'}',
          color: AppTheme.primary,
          imageUrl: conductorPhotoUrl,
          icon: Icons.person_rounded,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const HandlerProfilePage(showBottomNav: false),
            ),
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<VehicleCrewMember>>(
          stream: crewId == null || crewId.isEmpty
              ? Stream.value(const <VehicleCrewMember>[])
              : VehicleCrewService().watchMembers(crewId),
          builder: (context, snapshot) {
            final members = snapshot.data ?? const <VehicleCrewMember>[];
            final activeCount = members
                .where((member) => member.isActive)
                .length;
            final pendingCount = members
                .where((member) => member.isPending)
                .length;
            final subtitle = crewId == null || crewId.isEmpty
                ? 'Turno sem viatura'
                : '$activeCount condutor(es) + K9'
                      '${pendingCount == 0 ? '' : ' · $pendingCount convite(s) pendente(s)'}';
            return _ShiftProfileCard(
              eyebrow: 'EQUIPE · GUARNIÇÃO',
              title: vehicleLabel?.trim().isNotEmpty == true
                  ? vehicleLabel!
                  : 'Sem viatura',
              subtitle: subtitle,
              color: AppTheme.primary,
              icon: Icons.directions_car_filled_rounded,
              highlighted: crewId != null && crewId.isNotEmpty,
              onTap: crewId == null || crewId.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            VehicleCrewProfileScreen(crewId: crewId),
                      ),
                    ),
            );
          },
        ),
      ],
    );
  }
}

class _ShiftProfileCard extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final Color color;
  final String? imageUrl;
  final IconData icon;
  final VoidCallback? onTap;
  final bool highlighted;

  const _ShiftProfileCard({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.onTap,
    this.imageUrl,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? color.withAlpha(10) : Colors.white.withAlpha(7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: highlighted ? color.withAlpha(70) : Colors.white.withAlpha(18),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _ShiftProfileAvatar(imageUrl: imageUrl, color: color, icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: GoogleFonts.inter(
                        color: AppTheme.textTertiary,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: onTap == null
                    ? AppTheme.textTertiary.withAlpha(90)
                    : AppTheme.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShiftProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final Color color;
  final IconData icon;

  const _ShiftProfileAvatar({
    required this.imageUrl,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl?.trim().isNotEmpty == true;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withAlpha(8),
        border: Border.all(color: color),
      ),
      child: ClipOval(
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Icon(icon, color: color, size: 22),
              )
            : Icon(icon, color: color, size: 22),
      ),
    );
  }
}
