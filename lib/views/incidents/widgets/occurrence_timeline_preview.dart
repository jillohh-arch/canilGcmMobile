import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/incident.dart';

class OccurrenceTimelinePreview extends StatelessWidget {
  final List<IncidentProgressUpdate> updates;
  final Color accent;
  final ValueChanged<int>? onEventTap;

  const OccurrenceTimelinePreview({
    super.key,
    required this.updates,
    required this.accent,
    this.onEventTap,
  });

  @override
  Widget build(BuildContext context) {
    if (updates.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibleEntries = updates.asMap().entries.toList().reversed.take(5);
    final hiddenCount = updates.length > 5 ? updates.length - 5 : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(color: accent.withAlpha(75), blurRadius: 10),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'REGISTRO OPERACIONAL',
                style: GoogleFonts.robotoMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: accent.withAlpha(16),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withAlpha(95)),
              ),
              child: Text(
                '${updates.length} evento${updates.length == 1 ? '' : 's'}',
                style: GoogleFonts.robotoMono(
                  color: accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        if (hiddenCount > 0) ...[
          const SizedBox(height: 7),
          Text(
            'Mostrando os 5 eventos mais recentes. Toque em um registro para editar detalhes.',
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1220).withAlpha(190),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: accent.withAlpha(70)),
          ),
          child: Column(
            children: [
              ...visibleEntries.map(
                (entry) => _OccurrenceTimelineTile(
                  update: entry.value,
                  accent: accent,
                  isLatest: entry.key == updates.length - 1,
                  onTap: onEventTap == null
                      ? null
                      : () => onEventTap!(entry.key),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _TimelineMetaChip({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withAlpha(18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _OccurrenceTimelineTile extends StatelessWidget {
  final IncidentProgressUpdate update;
  final Color accent;
  final bool isLatest;
  final VoidCallback? onTap;

  const _OccurrenceTimelineTile({
    required this.update,
    required this.accent,
    required this.isLatest,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final eventColor = _colorForTitle(update.title, accent);
    final assetPath = _assetForTitle(update.title);

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isLatest
              ? eventColor.withAlpha(14)
              : Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isLatest ? eventColor.withAlpha(120) : Colors.white12,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 48,
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: eventColor.withAlpha(isLatest ? 35 : 18),
                      shape: BoxShape.circle,
                      border: Border.all(color: eventColor.withAlpha(150)),
                    ),
                    child: assetPath == null
                        ? Icon(
                            _iconForTitle(update.title),
                            color: eventColor,
                            size: 17,
                          )
                        : ClipOval(
                            child: Image.asset(
                              assetPath,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                _iconForTitle(update.title),
                                color: eventColor,
                                size: 17,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatHour(update.timestamp),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.robotoMono(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          update.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.oxanium(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      if (isLatest) ...[
                        const SizedBox(width: 8),
                        _TimelineMetaChip(
                          icon: Icons.bolt_rounded,
                          label: 'RECENTE',
                          accent: accent,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if ((update.authorName ?? '').isNotEmpty)
                        _TimelineMetaChip(
                          icon: Icons.person_rounded,
                          label: update.authorName!,
                          accent: accent,
                        ),
                      if ((update.location ?? '').isNotEmpty)
                        _TimelineMetaChip(
                          icon: Icons.place_rounded,
                          label: 'Local',
                          accent: accent,
                        ),
                      if (update.attachments.isNotEmpty)
                        _TimelineMetaChip(
                          icon: Icons.photo_camera_rounded,
                          label:
                              '${update.attachments.length} foto${update.attachments.length == 1 ? '' : 's'}',
                          accent: accent,
                        ),
                      if (update.latitude != null && update.longitude != null)
                        _TimelineMetaChip(
                          icon: Icons.my_location_rounded,
                          label: 'GPS',
                          accent: accent,
                        ),
                    ],
                  ),
                  if ((update.location ?? '').isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      update.location!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  if (update.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      update.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withAlpha(90),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _colorForTitle(String title, Color fallback) {
    final value = title.toUpperCase();
    if (value.contains('ABORDAGEM')) return const Color(0xFFFFB300);
    if (value.contains('K9') ||
        value.contains('CÃO') ||
        value.contains('CAO')) {
      return const Color(0xFF00F5A0);
    }
    if (value.contains('BUSCA')) return const Color(0xFF42A5F5);
    if (value.contains('MATERIAL') ||
        value.contains('ENTORPECENTE') ||
        value.contains('ARMA') ||
        value.contains('MUNIÇÃO')) {
      return const Color(0xFFB388FF);
    }
    if (value.contains('CONDUZ')) return const Color(0xFFFF8A65);
    if (value.contains('ALTERAÇÃO')) return Colors.blueGrey;
    if (value.contains('ENCERR')) return const Color(0xFF00E5FF);
    return fallback;
  }

  IconData _iconForTitle(String title) {
    final value = title.toLowerCase();
    if (value.contains('cão') || value.contains('k9')) {
      return Icons.pets_rounded;
    }
    if (value.contains('busca')) {
      return Icons.search_rounded;
    }
    if (value.contains('material') ||
        value.contains('entorpecente') ||
        value.contains('arma') ||
        value.contains('munição')) {
      return Icons.inventory_2_rounded;
    }
    if (value.contains('conduz')) {
      return Icons.person_rounded;
    }
    if (value.contains('abordagem')) {
      return Icons.person_search_rounded;
    }
    if (value.contains('encerr')) {
      return Icons.flag_rounded;
    }
    if (value.contains('alteração')) {
      return Icons.highlight_off_rounded;
    }
    return Icons.timeline_rounded;
  }

  String? _assetForTitle(String title) {
    final value = title.toLowerCase();
    if (value.contains('abordagem')) {
      return 'assets/images/actions/k9_abordagem_timeline.png';
    }
    return null;
  }

  String _formatHour(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}
