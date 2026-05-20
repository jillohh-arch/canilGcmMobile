import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/profiles/domain/operational_profile_models.dart';

const Color profileBackground = Color(0xFF040B0F);
const Color profileCard = Color(0xFF071923);
const Color profileCardAlt = Color(0xFF091F2B);
const Color profileBorder = Color(0xFF244556);
const Color profilePrimary = Color(0xFF49D7F0);
const Color profileSuccess = Color(0xFF74E66C);
const Color profileAttention = Color(0xFFFFC62D);
const Color profileCritical = Color(0xFFFF4E4E);
const Color profileTextPrimary = Color(0xFFF2F6F8);
const Color profileTextSecondary = Color(0xFFC6D0D6);
const Color profileTextMuted = Color(0xFF8A98A1);

BoxDecoration profileCardDecoration({Color? borderColor}) {
  return BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [profileCardAlt, profileCard, Color(0xFF06141C)],
    ),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: borderColor ?? profileBorder, width: 1),
    boxShadow: [
      BoxShadow(
        color: profilePrimary.withAlpha(10),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

class ProfileHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onMenu;

  const ProfileHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.onBack,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              if (onBack != null) {
                onBack!();
              } else {
                Navigator.of(context).maybePop();
              }
            },
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: profileTextPrimary,
              size: 30,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: profilePrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: profileTextPrimary,
                    fontSize: 23,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onMenu ?? () => HapticFeedback.selectionClick(),
            icon: const Icon(
              Icons.more_vert_rounded,
              color: profileTextSecondary,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileMainCard extends StatelessWidget {
  final String title;
  final String photoUrl;
  final List<MapEntry<String, String>> rows;
  final String badge;
  final List<String> chips;
  final IconData fallbackIcon;

  const ProfileMainCard({
    super.key,
    required this.title,
    required this.photoUrl,
    required this.rows,
    required this.badge,
    required this.chips,
    required this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    return ProfilePanel(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 365;
          final avatarSize = compact ? 86.0 : 96.0;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OperationalAvatar(
                imageUrl: photoUrl,
                size: avatarSize,
                fallbackIcon: fallbackIcon,
              ),
              SizedBox(width: compact ? 12 : 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: profileTextPrimary,
                        fontSize: compact ? 18 : 20,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final row in rows) _InfoRow(row: row),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      children: [
                        OperationalBadge(
                          label: badge,
                          color: profileSuccess,
                          compact: true,
                        ),
                        ...chips.map(
                          (chip) => OperationalBadge(
                            label: chip,
                            color: profileSuccess,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class MetricSummaryCard extends StatelessWidget {
  final String title;
  final List<MetricData> metrics;

  const MetricSummaryCard({
    super.key,
    required this.title,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    return ProfilePanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < metrics.length; i++) ...[
                Expanded(child: _MetricCell(data: metrics[i])),
                if (i < metrics.length - 1) const ProfileVerticalDivider(),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class OperationalBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool compact;

  const OperationalBadge({
    super.key,
    required this.label,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: compact ? 140 : 180,
        minHeight: compact ? 28 : 30,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 13,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(9),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withAlpha(150)),
      ),
      child: AutoScaleText(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: compact ? 10.5 : 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class StatusLineItem extends StatelessWidget {
  final StatusLineData data;
  final bool showDivider;

  const StatusLineItem({
    super.key,
    required this.data,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Icon(data.icon, color: profileTextSecondary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: profileTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                    color: data.color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                data.statusIcon ?? Icons.check_circle_outline_rounded,
                color: data.color,
                size: 18,
              ),
            ],
          ),
        ),
        if (showDivider) const ProfileDivider(),
      ],
    );
  }
}

class DocumentCard extends StatelessWidget {
  final DocumentData data;
  final bool showDivider;

  const DocumentCard({super.key, required this.data, this.showDivider = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(data.icon, color: profileTextSecondary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  data.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: profileTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: profileTextSecondary,
                size: 22,
              ),
            ],
          ),
        ),
        if (showDivider) const ProfileDivider(),
      ],
    );
  }
}

class MiniTimelineCard extends StatelessWidget {
  final String title;
  final List<MiniTimelineEntry> entries;

  const MiniTimelineCard({
    super.key,
    required this.title,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    return ProfilePanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Nenhum registro recente.',
                style: GoogleFonts.inter(
                  color: profileTextSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            Stack(
              children: [
                Positioned(
                  left: 8,
                  top: 17,
                  bottom: 17,
                  child: Container(width: 1, color: profileTextMuted),
                ),
                Column(
                  children: [
                    for (int i = 0; i < entries.length; i++)
                      _MiniTimelineRow(
                        entry: entries[i],
                        isLast: i == entries.length - 1,
                      ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class AuditInfoCard extends StatelessWidget {
  final String title;
  final List<StatusLineData> items;

  const AuditInfoCard({super.key, required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return ProfilePanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title),
          const SizedBox(height: 9),
          for (int i = 0; i < items.length; i++)
            StatusLineItem(data: items[i], showDivider: i < items.length - 1),
        ],
      ),
    );
  }
}

class OperationalBottomNav extends StatelessWidget {
  final int activeIndex;

  const OperationalBottomNav({super.key, required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF06131A),
        border: Border(top: BorderSide(color: profilePrimary.withAlpha(65))),
        boxShadow: [
          BoxShadow(
            color: profilePrimary.withAlpha(18),
            blurRadius: 22,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 86,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _NavItem(
                  icon: Icons.home_outlined,
                  label: 'Turno',
                  active: activeIndex == 0,
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.history_rounded,
                  label: 'Histórico',
                  active: activeIndex == 1,
                ),
              ),
              const SizedBox(width: 106, child: _CenterNavItem()),
              Expanded(
                child: _NavItem(
                  icon: Icons.fitness_center_rounded,
                  label: 'Treino',
                  active: activeIndex == 3,
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.pets_rounded,
                  label: 'Cão',
                  active: activeIndex == 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfilePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ProfilePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: profileCardDecoration(),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.inter(
        color: profilePrimary,
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: .2,
      ),
    );
  }
}

class OperationalAvatar extends StatelessWidget {
  final String imageUrl;
  final double size;
  final IconData fallbackIcon;

  const OperationalAvatar({
    super.key,
    required this.imageUrl,
    required this.size,
    required this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    final dotSize = size <= 60 ? 14.0 : 18.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: profileTextPrimary, width: 1.5),
          ),
          child: ClipOval(
            child: imageUrl.trim().isEmpty
                ? _fallback()
                : CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => _fallback(),
                    errorWidget: (_, _, _) => _fallback(),
                  ),
          ),
        ),
        Positioned(
          right: size <= 60 ? 2 : 4,
          bottom: size <= 60 ? 3 : 5,
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: profileSuccess,
              shape: BoxShape.circle,
              border: Border.all(color: profileCard, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallback() {
    return Container(
      color: profileCardAlt,
      alignment: Alignment.center,
      child: Icon(fallbackIcon, color: profileTextMuted, size: size * .38),
    );
  }
}

class ProfileDivider extends StatelessWidget {
  const ProfileDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: profileBorder.withAlpha(150));
  }
}

class ProfileVerticalDivider extends StatelessWidget {
  const ProfileVerticalDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 72,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: profileBorder.withAlpha(180),
    );
  }
}

class AutoScaleText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Alignment alignment;
  final TextAlign textAlign;

  const AutoScaleText(
    this.text, {
    super.key,
    required this.style,
    this.alignment = Alignment.center,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitted = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: textAlign,
            style: style,
          ),
        );
        if (!constraints.maxWidth.isFinite) return fitted;
        return SizedBox(width: constraints.maxWidth, child: fitted);
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final MapEntry<String, String> row;

  const _InfoRow({required this.row});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              row.key,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: profileTextSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              row.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: profileTextPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  final MetricData data;

  const _MetricCell({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(data.icon, color: profileTextSecondary, size: 24),
        const SizedBox(height: 8),
        Text(
          data.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: profileTextSecondary,
            fontSize: 12,
            height: 1.05,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 7),
        AutoScaleText(
          data.value,
          style: GoogleFonts.inter(
            color: data.color,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _MiniTimelineRow extends StatelessWidget {
  final MiniTimelineEntry entry;
  final bool isLast;

  const _MiniTimelineRow({required this.entry, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: entry.color,
              shape: BoxShape.circle,
              border: Border.all(color: profileCard, width: 1.5),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 39,
            child: Text(
              entry.time,
              style: GoogleFonts.inter(
                color: profileTextSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: entry.color.withAlpha(13),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: profileBorder),
            ),
            child: Icon(entry.icon, color: entry.color, size: 20),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: profileTextPrimary,
                    fontSize: 12.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (entry.subtitle.trim().isNotEmpty)
                  Text(
                    entry.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: profileTextMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          if (entry.trailing != null) ...[
            const SizedBox(width: 6),
            AutoScaleText(
              entry.trailing!,
              style: GoogleFonts.inter(
                color: profileTextPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const Icon(
            Icons.chevron_right_rounded,
            color: profileTextSecondary,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? profilePrimary : profileTextSecondary;
    return SizedBox(
      height: 70,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 29),
          const SizedBox(height: 5),
          AutoScaleText(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: active ? 34 : 0,
            height: 3,
            decoration: BoxDecoration(
              color: profilePrimary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterNavItem extends StatelessWidget {
  const _CenterNavItem();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 0,
            child: Container(
              width: 76,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFF0A2430),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                  bottom: Radius.circular(2),
                ),
                border: Border.all(color: profilePrimary, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: profilePrimary.withAlpha(42),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: profilePrimary,
                size: 34,
              ),
            ),
          ),
          Positioned(
            left: 2,
            right: 2,
            top: 58,
            child: AutoScaleText(
              'Nova Ocorrência',
              style: GoogleFonts.inter(
                color: profilePrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
