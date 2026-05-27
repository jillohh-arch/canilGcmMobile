import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';

class ActiveOccurrenceEventCard extends StatelessWidget {
  final OccurrenceEvent event;
  final bool isRecent;
  final VoidCallback onTap;
  final VoidCallback? onLocationTap;
  final String? handlerName;
  final String? locationLabel;

  const ActiveOccurrenceEventCard({
    super.key,
    required this.event,
    this.isRecent = false,
    required this.onTap,
    this.onLocationTap,
    this.handlerName,
    this.locationLabel,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${event.timestamp.hour.toString().padLeft(2, '0')}:${event.timestamp.minute.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRecent
                ? AppTheme.primary.withAlpha(75)
                : Colors.white.withAlpha(15),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                _CategoryIcon(category: event.category),
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF5A7280),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.title ?? event.category.label,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isRecent)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withAlpha(38),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'RECENTE',
                            style: GoogleFonts.inter(
                              color: AppTheme.primary,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Description
                  if (event.description != null &&
                      event.description!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      event.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: const Color(0xFFB0C4CC),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],

                  // Edited badge
                  if (event.auditTrail.length > 1) ...[
                    const SizedBox(height: 4),
                    Text(
                      'editado',
                      style: GoogleFonts.inter(
                        color: Colors.white.withAlpha(100),
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],

                  // Meta chips
                  if (handlerName != null ||
                      locationLabel != null ||
                      event.gpsLat != null) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (handlerName != null)
                          _MetaChip(icon: '👤', label: handlerName!),
                        if (locationLabel != null)
                          _MetaChip(icon: '📍', label: 'Local'),
                        if (event.gpsLat != null)
                          GestureDetector(
                            onTap: onLocationTap,
                            child: const _MetaChip(icon: '⊙', label: 'GPS'),
                          ),
                      ],
                    ),
                  ],

                  // Photo thumbnails
                  if (event.photoUrls.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _PhotoThumbnails(photoUrls: event.photoUrls),
                  ],

                  // Edit button
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: onTap,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_outlined,
                              color: AppTheme.primary, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            'editar',
                            style: GoogleFonts.inter(
                              color: AppTheme.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoThumbnails extends StatelessWidget {
  final List<String> photoUrls;

  const _PhotoThumbnails({required this.photoUrls});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(photoUrls.length, (i) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Image.network(
              photoUrls[i],
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: Colors.white.withAlpha(10),
                child: Icon(Icons.broken_image_outlined,
                    color: Colors.white.withAlpha(60), size: 20),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  final OccurrenceEventCategory category;

  const _CategoryIcon({required this.category});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (category) {
      OccurrenceEventCategory.opening => ('▶', AppTheme.primary),
      OccurrenceEventCategory.arrival => ('▶', AppTheme.primary),
      OccurrenceEventCategory.approach => ('👤', const Color(0xFFF1C40F)),
      OccurrenceEventCategory.dogWork => ('🐾', const Color(0xFF2ECC71)),
      OccurrenceEventCategory.positiveIndication =>
        ('✓', const Color(0xFF2ECC71)),
      OccurrenceEventCategory.seizure => ('📦', const Color(0xFF9B59B6)),
      OccurrenceEventCategory.closure => ('■', const Color(0xFF95A5A6)),
      OccurrenceEventCategory.other => ('●', const Color(0xFFE67E22)),
    };

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withAlpha(30),
      ),
      alignment: Alignment.center,
      child: Text(icon, style: TextStyle(fontSize: 16, color: color)),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.primary.withAlpha(38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
