import 'package:flutter/material.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';

class TeamHeaderWidget extends StatelessWidget {
  final List<OccurrenceTeamMember> team;
  final double? avatarSize;
  final bool showRoleLabels;

  const TeamHeaderWidget({
    super.key,
    required this.team,
    this.avatarSize = 32,
    this.showRoleLabels = false,
  });

  @override
  Widget build(BuildContext context) {
    if (team.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Text(
            team.any((member) => member.hasServiceDog) ? 'Guarnição' : 'Equipe',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          // Avatares
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: team.map((member) {
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: _TeamAvatarMember(
                    member: member,
                    size: avatarSize!,
                    showRoleLabel: showRoleLabels,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamAvatarMember extends StatelessWidget {
  final OccurrenceTeamMember member;
  final double size;
  final bool showRoleLabel;

  const _TeamAvatarMember({
    required this.member,
    required this.size,
    required this.showRoleLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Stack com avatar e indicador de titular
        Stack(
          clipBehavior: Clip.none,
          children: [
            // Avatar
            CircleAvatar(
              radius: size / 2,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                _avatarText(member),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // Indicador de titular
            if (member.role == TeamRole.titular)
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.workspace_premium_rounded,
                    color: Theme.of(context).colorScheme.surface,
                    size: 12,
                  ),
                ),
              ),
          ],
        ),

        // Label do papel
        if (showRoleLabel)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              member.dogName?.trim().isNotEmpty == true
                  ? '${member.role == TeamRole.titular ? 'Relator' : 'Integrante'} + K9'
                  : member.role == TeamRole.titular
                  ? 'Titular'
                  : 'Integrante',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  String _avatarText(OccurrenceTeamMember member) {
    final source = member.displayName?.trim().isNotEmpty == true
        ? member.displayName!.trim()
        : member.handlerId;
    if (source.length <= 2) return source.toUpperCase();
    return source.substring(0, 2).toUpperCase();
  }
}
