import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_card_surface.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_formatters.dart';

/// Card principal: identidade do K9 + prontidão (5 estados oficiais).
class HealthSummaryReadinessCard extends StatelessWidget {
  final HealthSummaryDogContextView dogContext;
  final HealthSummarySectionData<HealthSummaryReadinessView> readiness;

  const HealthSummaryReadinessCard({
    super.key,
    required this.dogContext,
    required this.readiness,
  });

  @override
  Widget build(BuildContext context) {
    return HealthSummaryCardSurface(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 340;
          final photoSize = compact ? 88.0 : 104.0;

          return Stack(
            children: [
              Positioned(
                right: -4,
                top: 4,
                bottom: 4,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.10,
                    child: Icon(
                      Icons.shield_outlined,
                      size: compact ? 88 : 110,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DogPhoto(
                    dogContext: dogContext,
                    size: photoSize,
                    readiness: readiness,
                  ),
                  SizedBox(width: compact ? 12 : 16),
                  Expanded(
                    child: _IdentityAndStatus(
                      dogContext: dogContext,
                      readiness: readiness,
                      compact: compact,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DogPhoto extends StatelessWidget {
  final HealthSummaryDogContextView dogContext;
  final double size;
  final HealthSummarySectionData<HealthSummaryReadinessView> readiness;

  const _DogPhoto({
    required this.dogContext,
    required this.size,
    required this.readiness,
  });

  @override
  Widget build(BuildContext context) {
    final accent = readiness.isAvailable
        ? HealthSummaryReadinessVisuals.forStatus(readiness.value!.status).color
        : AppTheme.primary;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: accent.withValues(alpha: 0.55),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 14,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: ClipOval(child: _buildImage()),
          ),
          if (readiness.isAvailable &&
              readiness.value!.status == ReadinessStatus.operational)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppTheme.successCheck,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.surfacePanel, width: 2.5),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    final url = dogContext.photoUrl?.trim();
    if (url == null || url.isEmpty) {
      return ColoredBox(
        color: AppTheme.surfacePanelAlt,
        child: Icon(
          Icons.pets_rounded,
          size: size * 0.42,
          color: AppTheme.textMuted,
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (context, url) => ColoredBox(
        color: AppTheme.surfacePanelAlt,
        child: Icon(
          Icons.pets_rounded,
          size: size * 0.42,
          color: AppTheme.textMuted,
        ),
      ),
      errorWidget: (context, url, error) => ColoredBox(
        color: AppTheme.surfacePanelAlt,
        child: Icon(
          Icons.pets_rounded,
          size: size * 0.42,
          color: AppTheme.textMuted,
        ),
      ),
    );
  }
}

class _IdentityAndStatus extends StatelessWidget {
  final HealthSummaryDogContextView dogContext;
  final HealthSummarySectionData<HealthSummaryReadinessView> readiness;
  final bool compact;

  const _IdentityAndStatus({
    required this.dogContext,
    required this.readiness,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final breedSex = _breedSexLine(dogContext);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dogContext.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontSize: compact ? 22 : 26,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: 0.2,
          ),
        ),
        if (breedSex != null) ...[
          const SizedBox(height: 4),
          Text(
            breedSex,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: compact ? 12.5 : 13.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
        const SizedBox(height: 8),
        _ReadinessBlock(readiness: readiness, ageLabel: dogContext.ageLabel),
      ],
    );
  }

  static String? _breedSexLine(HealthSummaryDogContextView dog) {
    final parts = <String>[
      if (dog.breed != null && dog.breed!.trim().isNotEmpty) dog.breed!.trim(),
      if (dog.sexLabel != null && dog.sexLabel!.trim().isNotEmpty)
        dog.sexLabel!.trim(),
    ];
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }
}

class _ReadinessBlock extends StatelessWidget {
  final HealthSummarySectionData<HealthSummaryReadinessView> readiness;
  final String? ageLabel;

  const _ReadinessBlock({required this.readiness, this.ageLabel});

  @override
  Widget build(BuildContext context) {
    switch (readiness.status) {
      case HealthSummarySectionStatus.loading:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HealthSummarySkeletonBar(height: 22, width: 120),
            SizedBox(height: 10),
            HealthSummarySkeletonBar(height: 12, width: 160),
            SizedBox(height: 6),
            HealthSummarySkeletonBar(height: 10, width: 140),
          ],
        );
      case HealthSummarySectionStatus.notRecorded:
        return _neutralStatus(
          icon: Icons.help_outline_rounded,
          color: AppTheme.textMuted,
          badge: 'SEM REGISTRO',
          reason: readiness.message ?? 'Prontidão ainda não registrada',
          updatedAt: null,
        );
      case HealthSummarySectionStatus.unavailable:
        return _neutralStatus(
          icon: Icons.cloud_off_outlined,
          color: AppTheme.textSoft,
          badge: 'INDISPONÍVEL',
          reason: readiness.message ?? 'Dados indisponíveis',
          updatedAt: null,
        );
      case HealthSummarySectionStatus.available:
        final view = readiness.value!;
        final visual = HealthSummaryReadinessVisuals.forStatus(view.status);
        return _availableStatus(view, visual);
    }
  }

  Widget _availableStatus(
    HealthSummaryReadinessView view,
    HealthSummaryReadinessVisuals visual,
  ) {
    final age = ageLabel?.trim();
    // Não inventar reason clínico: só exibe o texto vindo do contrato.
    final reason = view.reason?.trim();
    final hasReason = reason != null && reason.isNotEmpty;
    final restrictions = view.restrictionSummaries
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final restrictionNote = restrictions.isEmpty
        ? ''
        : '. Restrições resumidas (apresentação): ${restrictions.take(3).join(', ')}';

    return Semantics(
      label:
          'Prontidão: ${visual.label}'
          '${hasReason ? '. $reason' : ''}'
          '$restrictionNote',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              if (age != null && age.isNotEmpty)
                Text(
                  age,
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              _StatusBadge(label: visual.label, color: visual.color),
            ],
          ),
          // Status sempre com ícone + label (cor nunca é o único canal).
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(visual.icon, size: 16, color: visual.color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasReason ? reason : visual.label,
                  style: GoogleFonts.inter(
                    color: visual.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          if (restrictions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              // Resumos compactos — não são autorização operacional definitiva.
              restrictions.take(3).join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: AppTheme.textSoft,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            HealthSummaryFormatters.updatedLabel(view.updatedAt),
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _neutralStatus({
    required IconData icon,
    required Color color,
    required String badge,
    required String reason,
    required DateTime? updatedAt,
  }) {
    return Semantics(
      label: 'Prontidão: $badge. $reason',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ageLabel != null && ageLabel!.trim().isNotEmpty) ...[
            Text(
              ageLabel!.trim(),
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
          ],
          _StatusBadge(label: badge, color: color),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  reason,
                  style: GoogleFonts.inter(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            HealthSummaryFormatters.updatedLabel(updatedAt),
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.75), width: 1),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Mapeamento visual dos 5 estados oficiais (cor + texto + ícone).
///
/// Não calcula prontidão e não inventa reason clínico.
final class HealthSummaryReadinessVisuals {
  const HealthSummaryReadinessVisuals({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  static HealthSummaryReadinessVisuals forStatus(ReadinessStatus status) {
    switch (status) {
      case ReadinessStatus.operational:
        return const HealthSummaryReadinessVisuals(
          label: 'OPERACIONAL',
          color: AppTheme.success,
          icon: Icons.check_circle_rounded,
        );
      case ReadinessStatus.operationalAttention:
        return const HealthSummaryReadinessVisuals(
          label: 'OPERACIONAL C/ ATENÇÃO',
          color: AppTheme.warningAccent,
          icon: Icons.warning_amber_rounded,
        );
      case ReadinessStatus.fitWithRestrictions:
        return const HealthSummaryReadinessVisuals(
          label: 'APTO C/ RESTRIÇÕES',
          color: AppTheme.attention,
          icon: Icons.gpp_maybe_outlined,
        );
      case ReadinessStatus.temporarilyUnfit:
        return const HealthSummaryReadinessVisuals(
          label: 'TEMP. INAPTO',
          color: AppTheme.error,
          icon: Icons.block_rounded,
        );
      case ReadinessStatus.notEvaluated:
        return const HealthSummaryReadinessVisuals(
          label: 'NÃO AVALIADO',
          color: AppTheme.textMuted,
          icon: Icons.help_outline_rounded,
        );
    }
  }
}
