import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_card_surface.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_formatters.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_type_visuals.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';

/// Card base da timeline — recebe [HealthTimelineEntryView] e renderiza metadata.
///
/// Não resolve navegação. Se [onTap] for null, não parece botão.
class HealthTimelineEntryCard extends StatelessWidget {
  final HealthTimelineEntryView entry;
  final ValueChanged<HealthTimelineEntryView>? onTap;

  /// Prefixo de ação honesta (ex.: relatedHistory) — 3E-A.
  final String? navigationActionLabel;

  const HealthTimelineEntryCard({
    super.key,
    required this.entry,
    this.onTap,
    this.navigationActionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final visual = HealthTimelineTypeVisuals.resolve(entry.type);
    final cancelled = entry.isCancelled;
    final interactive = onTap != null;
    final semanticLabel = _semanticLabel(
      entry,
      visual,
      navigationActionLabel: interactive ? navigationActionLabel : null,
    );

    final content = HealthSummaryCardSurface(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      borderRadius: 14,
      borderColor: cancelled
          ? AppTheme.surfaceWhiteBorder
          : visual.accent.withValues(alpha: 0.22),
      backgroundColor: cancelled
          ? AppTheme.surfacePanelSoft.withValues(alpha: 0.92)
          : AppTheme.surfacePanel.withValues(alpha: 0.94),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderRow(
            visual: visual,
            cancelled: cancelled,
            timeLabel: HealthTimelineFormatters.timeOfDay(entry.occurredAt),
            showChevron: interactive,
          ),
          const SizedBox(height: 8),
          Text(
            entry.title,
            style: GoogleFonts.inter(
              color: cancelled ? AppTheme.textSecondary : AppTheme.textPrimary,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          if (entry.subtitle != null && entry.subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              entry.subtitle!.trim(),
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ],
          if (_hasMetadata(entry)) ...[
            const SizedBox(height: 10),
            _MetadataBlock(entry: entry),
          ],
        ],
      ),
    );

    return Semantics(
      button: interactive,
      enabled: interactive ? true : null,
      label: semanticLabel,
      excludeSemantics: true,
      child: interactive
          ? Material(
              color: AppTheme.transparent,
              child: InkWell(
                onTap: () => onTap!(entry),
                borderRadius: BorderRadius.circular(14),
                child: content,
              ),
            )
          : content,
    );
  }

  /// Label único e completo para leitores de tela (evita anúncio triplo).
  static String _semanticLabel(
    HealthTimelineEntryView entry,
    HealthTimelineTypeVisual visual, {
    String? navigationActionLabel,
  }) {
    final parts = <String>[
      if (navigationActionLabel != null &&
          navigationActionLabel.trim().isNotEmpty)
        navigationActionLabel.trim(),
      visual.label,
      entry.title,
      if (entry.subtitle != null && entry.subtitle!.trim().isNotEmpty)
        entry.subtitle!.trim(),
      if (entry.isCancelled) HealthTimelineUserCopy.cancelledLabel,
      HealthTimelineFormatters.timeOfDay(entry.occurredAt),
    ];

    final professional = entry.professional;
    if (professional != null && professional.name.trim().isNotEmpty) {
      parts.add(_professionalText(professional));
    }

    final recorded = entry.recordedBy == null
        ? null
        : HealthTimelineFormatters.recordedByLabel(entry.recordedBy!.name);
    if (recorded != null) parts.add(recorded);

    final impact = entry.operationalImpact;
    if (impact != null && impact.level != OperationalImpactLevel.none) {
      parts.add(HealthTimelineFormatters.operationalImpactLabel(impact));
    }

    final attachments = HealthTimelineFormatters.attachmentsLabel(
      hasAttachments: entry.hasAttachments,
      attachmentCount: entry.attachmentCount,
    );
    if (attachments != null) parts.add(attachments);

    final amendments = HealthTimelineFormatters.amendmentsLabel(
      hasAmendments: entry.amendments.hasAmendments,
      amendmentCount: entry.amendments.amendmentCount,
    );
    if (amendments != null) parts.add(amendments);

    return parts.join('. ');
  }

  static bool _hasMetadata(HealthTimelineEntryView entry) {
    final professional = entry.professional;
    if (professional != null && professional.name.trim().isNotEmpty) {
      return true;
    }
    if (entry.recordedBy != null && entry.recordedBy!.name.trim().isNotEmpty) {
      return true;
    }
    if (entry.operationalImpact != null &&
        entry.operationalImpact!.level != OperationalImpactLevel.none) {
      return true;
    }
    if (entry.hasAttachments) return true;
    if (entry.amendments.hasAmendments) return true;
    return false;
  }

  static String _professionalText(ProfessionalIdentitySummary p) {
    final name = p.name.trim();
    final specialty = p.specialty?.trim();
    if (specialty == null || specialty.isEmpty) return name;
    return '$name · $specialty';
  }
}

class _HeaderRow extends StatelessWidget {
  final HealthTimelineTypeVisual visual;
  final bool cancelled;
  final String timeLabel;
  final bool showChevron;

  const _HeaderRow({
    required this.visual,
    required this.cancelled,
    required this.timeLabel,
    required this.showChevron,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: (cancelled ? AppTheme.textMuted : visual.accent).withValues(
              alpha: 0.12,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(
            visual.icon,
            size: 18,
            color: cancelled ? AppTheme.textMuted : visual.accent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                visual.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: cancelled ? AppTheme.textMuted : visual.accent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  height: 1.2,
                ),
              ),
              if (cancelled) ...[const SizedBox(height: 4), _CancelledChip()],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          timeLabel,
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (showChevron) ...[
          const SizedBox(width: 2),
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AppTheme.textMuted,
          ),
        ],
      ],
    );
  }
}

class _CancelledChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhiteOverlay,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.surfaceWhiteBorderMedium),
      ),
      child: Text(
        HealthTimelineUserCopy.cancelledLabel,
        style: GoogleFonts.inter(
          // Contraste pleno no chip (não depende de Opacity do card).
          color: AppTheme.textSecondary,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _MetadataBlock extends StatelessWidget {
  final HealthTimelineEntryView entry;

  const _MetadataBlock({required this.entry});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    final professional = entry.professional;
    if (professional != null && professional.name.trim().isNotEmpty) {
      chips.add(
        _MetaLine(
          icon: Icons.person_outline_rounded,
          text: HealthTimelineEntryCard._professionalText(professional),
        ),
      );
    }

    final recordedBy = entry.recordedBy;
    if (recordedBy != null) {
      final label = HealthTimelineFormatters.recordedByLabel(recordedBy.name);
      if (label != null) {
        chips.add(_MetaLine(icon: Icons.edit_note_outlined, text: label));
      }
    }

    final impact = entry.operationalImpact;
    if (impact != null && impact.level != OperationalImpactLevel.none) {
      chips.add(_ImpactLine(impact: impact));
    }

    final attachments = HealthTimelineFormatters.attachmentsLabel(
      hasAttachments: entry.hasAttachments,
      attachmentCount: entry.attachmentCount,
    );
    if (attachments != null) {
      chips.add(_MetaLine(icon: Icons.attach_file_rounded, text: attachments));
    }

    final amendments = HealthTimelineFormatters.amendmentsLabel(
      hasAmendments: entry.amendments.hasAmendments,
      amendmentCount: entry.amendments.amendmentCount,
    );
    if (amendments != null) {
      chips.add(_MetaLine(icon: Icons.history_edu_outlined, text: amendments));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          chips[i],
        ],
      ],
    );
  }
}

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: AppTheme.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              color: AppTheme.textSoft,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _ImpactLine extends StatelessWidget {
  final OperationalImpact impact;

  const _ImpactLine({required this.impact});

  @override
  Widget build(BuildContext context) {
    final color = HealthTimelineFormatters.operationalImpactColor(impact.level);
    final text = HealthTimelineFormatters.operationalImpactLabel(impact);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
