import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';

enum GpsPrecision { high, medium, low, unavailable }

class StartOccurrenceInfoGrid extends StatelessWidget {
  final String locationLabel;
  final GpsPrecision gpsPrecision;
  final String timeLabel;
  final String dateLabel;
  final bool isLoadingGps;
  final VoidCallback onRefreshLocation;
  final VoidCallback onRefreshTime;
  final VoidCallback? onManualLocation;

  const StartOccurrenceInfoGrid({
    super.key,
    required this.locationLabel,
    required this.gpsPrecision,
    required this.timeLabel,
    required this.dateLabel,
    this.isLoadingGps = false,
    required this.onRefreshLocation,
    required this.onRefreshTime,
    this.onManualLocation,
  });

  @override
  Widget build(BuildContext context) {
    final showManualLink = !isLoadingGps &&
        gpsPrecision == GpsPrecision.unavailable &&
        onManualLocation != null;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _InfoCard(
                icon: Icons.location_on_outlined,
                label: 'LOCAL ATUAL',
                value: isLoadingGps
                    ? 'Capturando GPS...'
                    : locationLabel.isEmpty
                        ? 'GPS indisponível'
                        : locationLabel,
                footer: _buildGpsFooter(),
                onTap: onRefreshLocation,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InfoCard(
                icon: Icons.access_time_rounded,
                label: 'HORA ATUAL',
                value: '$timeLabel\n$dateLabel',
                onTap: onRefreshTime,
              ),
            ),
          ],
        ),
        if (showManualLink) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onManualLocation,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.edit_location_alt_outlined,
                    color: AppTheme.primary, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Preencher local manualmente',
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget? _buildGpsFooter() {
    if (isLoadingGps) {
      return Row(
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'Capturando...',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    final (color, text) = switch (gpsPrecision) {
      GpsPrecision.high => (AppTheme.success, 'GPS preciso'),
      GpsPrecision.medium => (AppTheme.warning, 'GPS aproximado'),
      GpsPrecision.low => (AppTheme.error, 'GPS impreciso'),
      GpsPrecision.unavailable => (AppTheme.error, 'GPS indisponível'),
    };

    if (locationLabel.isEmpty && gpsPrecision == GpsPrecision.unavailable) {
      return Row(
        children: [
          Icon(Icons.refresh_rounded, color: AppTheme.error, size: 12),
          const SizedBox(width: 4),
          Text(
            'Toque para tentar novamente',
            style: GoogleFonts.inter(
              color: AppTheme.error,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: GoogleFonts.inter(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? footer;
  final VoidCallback onTap;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    this.footer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.primary.withAlpha(10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary.withAlpha(50)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.primary, size: 14),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            if (footer != null) ...[
              const SizedBox(height: 6),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}
