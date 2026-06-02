import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';

class ActiveOccurrenceContextCard extends StatelessWidget {
  final String typeName;
  final String dogName;
  final String? dogImageUrl;
  final String handlerName;
  final String? handlerImageUrl;
  final String locationAddress;
  final String startedAtLabel;
  final String durationLabel;
  final int eventCount;
  final List<OccurrenceTeamMember> team;
  final int teamSizeMax;
  final VoidCallback? onTeamTap;

  const ActiveOccurrenceContextCard({
    super.key,
    required this.typeName,
    required this.dogName,
    this.dogImageUrl,
    required this.handlerName,
    this.handlerImageUrl,
    required this.locationAddress,
    required this.startedAtLabel,
    required this.durationLabel,
    required this.eventCount,
    this.team = const [],
    this.teamSizeMax = 3,
    this.onTeamTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: title + badge
          Row(
            children: [
              Expanded(
                child: Text(
                  typeName,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StatusBadge(),
            ],
          ),
          const SizedBox(height: 12),

          // Binômio
          Row(
            children: [
              _MiniAvatar(label: dogName, imageUrl: dogImageUrl),
              const SizedBox(width: 6),
              _MiniAvatar(label: handlerName, imageUrl: handlerImageUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$dogName · $handlerName',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'K9 · CONDUTOR',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Info rows
          _InfoRow(
            label: 'Local:',
            value: locationAddress.isNotEmpty ? locationAddress : '—',
          ),
          const SizedBox(height: 4),
          _InfoRow(
            label: 'Guarnição:',
            value: '',
            trailing: Expanded(
              child: _TeamSummaryAction(
                team: team,
                teamSizeMax: teamSizeMax,
                onTap: onTeamTap,
              ),
            ),
          ),
          const SizedBox(height: 4),
          _InfoRow(label: 'Início:', value: startedAtLabel),
          const SizedBox(height: 12),

          // Metrics
          Row(
            children: [
              _Metric(label: 'DURAÇÃO', value: durationLabel),
              const SizedBox(width: 24),
              _Metric(label: 'EVENTOS', value: '$eventCount'),
            ],
          ),
          const SizedBox(height: 12),

          // Sync indicator
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppTheme.primary.withAlpha(20)),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_done_outlined,
                  color: AppTheme.success,
                  size: 12,
                ),
                const SizedBox(width: 6),
                Text(
                  'Sincronizado · em andamento',
                  style: GoogleFonts.inter(
                    color: AppTheme.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
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

class _TeamSummaryAction extends StatelessWidget {
  final List<OccurrenceTeamMember> team;
  final int teamSizeMax;
  final VoidCallback? onTap;

  const _TeamSummaryAction({
    required this.team,
    required this.teamSizeMax,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasTeam = team.isNotEmpty;
    final hasServiceDog = team.any((member) => member.hasServiceDog);
    final label = hasTeam
        ? hasServiceDog
              ? '${team.length} condutor${team.length == 1 ? '' : 'es'} + K9'
              : '${team.length}/$teamSizeMax condutores'
        : 'Guarnição não vinculada';

    return Material(
      color: AppTheme.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasTeam) ...[
                _TeamAvatarStack(team: team),
                const SizedBox(width: 8),
              ] else ...[
                Icon(
                  Icons.groups_2_outlined,
                  color: AppTheme.primary,
                  size: 16,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.primary.withAlpha(180),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamAvatarStack extends StatelessWidget {
  final List<OccurrenceTeamMember> team;

  const _TeamAvatarStack({required this.team});

  @override
  Widget build(BuildContext context) {
    final visible = team.take(3).toList();
    return SizedBox(
      width: 18.0 + (visible.length - 1).clamp(0, 2) * 14.0,
      height: 22,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final entry in visible.asMap().entries)
            Positioned(
              left: entry.key * 14.0,
              child: _TeamMiniAvatar(member: entry.value),
            ),
        ],
      ),
    );
  }
}

class _TeamMiniAvatar extends StatelessWidget {
  final OccurrenceTeamMember member;

  const _TeamMiniAvatar({required this.member});

  @override
  Widget build(BuildContext context) {
    final label = member.displayName?.trim().isNotEmpty == true
        ? member.displayName!.trim()
        : member.handlerId;
    final initials = label.length >= 2
        ? label.substring(0, 2).toUpperCase()
        : label.toUpperCase();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: member.role == TeamRole.titular
                ? AppTheme.primary
                : AppTheme.surfacePanelAlt,
            border: Border.all(color: AppTheme.background, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: GoogleFonts.inter(
              color: member.role == TeamRole.titular
                  ? AppTheme.background
                  : AppTheme.primary,
              fontSize: 7,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (member.role == TeamRole.titular)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.background,
                border: Border.all(color: AppTheme.primary, width: 1),
              ),
              child: Icon(
                Icons.workspace_premium_rounded,
                color: AppTheme.primary,
                size: 7,
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.success.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.success.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'EM ANDAMENTO',
            style: GoogleFonts.inter(
              color: AppTheme.success,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  final String label;
  final String? imageUrl;

  const _MiniAvatar({required this.label, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.surfacePanelAlt,
        border: Border.all(color: AppTheme.primary.withAlpha(100)),
      ),
      child: ClipOval(
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? Image.network(imageUrl!, fit: BoxFit.cover, width: 28, height: 28)
            : Center(
                child: Text(
                  label.length > 3
                      ? label.substring(0, 3).toUpperCase()
                      : label.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;

  const _InfoRow({required this.label, required this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        if (trailing != null)
          trailing!
        else
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
