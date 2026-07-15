import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_card_surface.dart';

/// Card individual do grid 2x2 (PESO, VACINAÇÃO, MEDICAÇÃO, ATENÇÕES).
class HealthSummaryMetricCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accentColor;
  final String? primaryValue;
  final String? secondaryValue;
  final bool isLoading;
  final bool isNotRecorded;
  final bool isUnavailable;
  final String? statusMessage;
  final String semanticsLabel;

  const HealthSummaryMetricCard({
    super.key,
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.semanticsLabel,
    this.primaryValue,
    this.secondaryValue,
    this.isLoading = false,
    this.isNotRecorded = false,
    this.isUnavailable = false,
    this.statusMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: HealthSummaryCardSurface(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        borderRadius: 14,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 78),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HealthSummarySkeletonBar(height: 10, width: 64),
          SizedBox(height: 10),
          HealthSummarySkeletonBar(height: 16, width: 88),
          SizedBox(height: 8),
          HealthSummarySkeletonBar(height: 10, width: 72),
        ],
      );
    }

    final primary = isUnavailable
        ? (statusMessage?.trim().isNotEmpty == true
              ? statusMessage!.trim()
              : 'Dados indisponíveis')
        : isNotRecorded
        ? (statusMessage?.trim().isNotEmpty == true
              ? statusMessage!.trim()
              : 'Não registrado')
        : (primaryValue?.trim().isNotEmpty == true
              ? primaryValue!.trim()
              : '—');

    final secondary = isUnavailable || isNotRecorded ? null : secondaryValue;

    // "—" e ausências usam cor neutra — não herdam o acento positivo do bloco.
    final primaryColor = isUnavailable
        ? AppTheme.textSoft
        : isNotRecorded
        ? AppTheme.textSecondary
        : (primaryValue == null || primaryValue!.trim().isEmpty)
        ? AppTheme.textSoft
        : accentColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          primary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: primaryColor,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        if (secondary != null && secondary.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            secondary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: AppTheme.textSoft,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
        ],
      ],
    );
  }
}
