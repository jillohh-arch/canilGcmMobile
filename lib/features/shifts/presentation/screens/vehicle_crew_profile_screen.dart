import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/shifts/data/vehicle_crew_service.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle_crew.dart';
import 'package:canil_gcm/features/users/domain/user.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

class VehicleCrewProfileScreen extends StatefulWidget {
  final String crewId;

  const VehicleCrewProfileScreen({super.key, required this.crewId});

  @override
  State<VehicleCrewProfileScreen> createState() =>
      _VehicleCrewProfileScreenState();
}

class _VehicleCrewProfileScreenState extends State<VehicleCrewProfileScreen> {
  final VehicleCrewService _crewService = VehicleCrewService();

  @override
  Widget build(BuildContext context) {
    final authVM = context.watch<AuthViewModel>();
    final userVM = context.watch<UserViewModel>();
    final dogVM = context.watch<DogViewModel>();
    final currentRa = HandlerIdentityService.raFromUser(authVM.user) ?? '';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('Equipe'),
      ),
      body: StreamBuilder<VehicleCrew?>(
        stream: _crewService.watchCrew(widget.crewId),
        builder: (context, crewSnapshot) {
          final crew = crewSnapshot.data;
          if (crewSnapshot.connectionState == ConnectionState.waiting &&
              crew == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (crew == null) {
            return const Center(
              child: Text(
                'Guarnição não encontrada.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            );
          }

          return StreamBuilder<List<VehicleCrewMember>>(
            stream: _crewService.watchMembers(crew.id),
            builder: (context, membersSnapshot) {
              final members =
                  membersSnapshot.data ?? const <VehicleCrewMember>[];
              final activeCount = members
                  .where((member) => member.isActive)
                  .length;
              final dog = _dogFor(dogVM, crew.serviceDogId);

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _VehicleCard(crew: crew),
                  const SizedBox(height: 20),
                  _SectionHeader(
                    title: 'CONDUTORES',
                    trailing: '$activeCount de ${crew.crewSize}',
                  ),
                  const SizedBox(height: 10),
                  ...members.where((m) => m.isActive).map(
                    (member) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MemberCard(
                        member: member,
                        user: userVM.findByRa(member.handlerId),
                        isCurrentUser: member.handlerId == currentRa,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _SectionHeader(title: 'CÃO DE SERVIÇO'),
                  const SizedBox(height: 10),
                  _ServiceDogCard(dog: dog, fallbackId: crew.serviceDogId),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Dog? _dogFor(DogViewModel dogVM, String dogId) {
    for (final dog in dogVM.dogs) {
      if (dog.id == dogId) return dog;
    }
    return null;
  }
}

class _VehicleCard extends StatelessWidget {
  final VehicleCrew crew;

  const _VehicleCard({required this.crew});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(10),
        border: Border.all(color: AppTheme.primary.withAlpha(48)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(22),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.directions_car_filled_rounded,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      crew.vehicleLabel,
                      style: GoogleFonts.robotoMono(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (crew.vehicleModel?.isNotEmpty == true)
                      Text(
                        crew.vehicleModel!,
                        style: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(label: 'cap.', value: '${crew.crewSize} + K9'),
              if (crew.vehicleUnit?.isNotEmpty == true)
                _InfoChip(label: 'unidade', value: crew.vehicleUnit!),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(12),
        border: Border.all(color: AppTheme.textPrimary.withAlpha(16)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label $value',
        style: GoogleFonts.robotoMono(
          color: AppTheme.textSecondary,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: AppTheme.textPrimary.withAlpha(18))),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Text(
            trailing!,
            style: GoogleFonts.robotoMono(
              color: AppTheme.textTertiary,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );
  }
}

class _MemberCard extends StatelessWidget {
  final VehicleCrewMember member;
  final UserModel? user;
  final bool isCurrentUser;

  const _MemberCard({
    required this.member,
    required this.user,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    final name = user?.callsign.trim().isNotEmpty == true
        ? user!.callsign.trim()
        : 'RA ${member.handlerId}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? AppTheme.primary.withAlpha(10)
            : AppTheme.textPrimary.withAlpha(7),
        border: Border.all(
          color: AppTheme.textPrimary.withAlpha(18),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _InitialsAvatar(text: name, color: AppTheme.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'RA ${member.handlerId}',
                  style: GoogleFonts.robotoMono(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          _StatusBadge(
            text: isCurrentUser ? 'VOCÊ' : 'NA EQUIPE',
            color: isCurrentUser ? AppTheme.primary : AppTheme.success,
          ),
        ],
      ),
    );
  }
}

class _ServiceDogCard extends StatelessWidget {
  final Dog? dog;
  final String fallbackId;

  const _ServiceDogCard({required this.dog, required this.fallbackId});

  @override
  Widget build(BuildContext context) {
    final name = dog?.name ?? fallbackId;
    final meta = [
      if (dog?.registrationNumber?.isNotEmpty == true)
        'matrícula ${dog!.registrationNumber}',
      if (dog?.breed.isNotEmpty == true) dog!.breed,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.success.withAlpha(8),
        border: Border.all(color: AppTheme.success.withAlpha(52)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _InitialsAvatar(text: name, color: AppTheme.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name  K9',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    style: GoogleFonts.robotoMono(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
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

class _InitialsAvatar extends StatelessWidget {
  final String text;
  final Color color;

  const _InitialsAvatar({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final normalized = text.trim();
    final initials = normalized.isEmpty
        ? '--'
        : normalized.length <= 3
        ? normalized.toUpperCase()
        : normalized.substring(0, 3).toUpperCase();
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.textPrimary.withAlpha(8),
        border: Border.all(color: color),
      ),
      child: Text(
        initials,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        border: Border.all(color: color.withAlpha(80)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
