import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OccurrenceStartScreen extends StatelessWidget {
  final Color accentColor;
  final Color panelColor;
  final String dogName;
  final String? dogImageUrl;
  final String locationLabel;
  final String timeLabel;
  final String dateLabel;
  final String natureText;
  final bool showNatureEditor;
  final Widget natureEditor;
  final VoidCallback onRefreshLocation;
  final VoidCallback onRefreshTime;
  final VoidCallback onToggleNatureEditor;

  const OccurrenceStartScreen({
    super.key,
    required this.accentColor,
    required this.panelColor,
    required this.dogName,
    required this.dogImageUrl,
    required this.locationLabel,
    required this.timeLabel,
    required this.dateLabel,
    required this.natureText,
    required this.showNatureEditor,
    required this.natureEditor,
    required this.onRefreshLocation,
    required this.onRefreshTime,
    required this.onToggleNatureEditor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Center(
          child: Column(
            children: [
              _buildDogAvatar(),
              const SizedBox(height: 16),
              Text(
                dogName.toUpperCase(),
                textAlign: TextAlign.center,
                style: GoogleFonts.oxanium(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 5,
                ),
              ),
              const SizedBox(height: 8),
              _OccurrenceStatusPill(
                icon: Icons.circle,
                label: 'TURNO ATIVO',
                color: const Color(0xFF00F5A0),
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        Row(
          children: [
            Expanded(
              child: _OccurrenceStartCommandCard(
                icon: Icons.location_on_outlined,
                label: 'LOCAL ATUAL',
                value: locationLabel,
                color: const Color(0xFF00E5FF),
                panelColor: panelColor,
                onTap: onRefreshLocation,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _OccurrenceStartCommandCard(
                icon: Icons.access_time_rounded,
                label: 'HORA ATUAL',
                value: '$timeLabel\n$dateLabel',
                color: const Color(0xFF00E5FF),
                panelColor: panelColor,
                onTap: onRefreshTime,
              ),
            ),
          ],
        ),
        const SizedBox(height: 44),
        if (showNatureEditor) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: panelColor.withAlpha(185),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withAlpha(90)),
            ),
            child: natureEditor,
          ),
          const SizedBox(height: 14),
        ],
        TextButton.icon(
          onPressed: onToggleNatureEditor,
          icon: Icon(
            showNatureEditor
                ? Icons.keyboard_arrow_up_rounded
                : Icons.add_rounded,
            color: accentColor,
          ),
          label: Text(
            natureText.isEmpty
                ? 'Ajustar natureza (opcional)'
                : 'Natureza: $natureText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: accentColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Local e horário são preenchidos automaticamente. Toque nos cards para atualizar antes de iniciar.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: Colors.white.withAlpha(105),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildDogAvatar() {
    final imageUrl = dogImageUrl;

    return Container(
      width: 156,
      height: 156,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accentColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withAlpha(95),
            blurRadius: 36,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: Container(
          color: panelColor,
          child: imageUrl != null && imageUrl.isNotEmpty
              ? Image.network(imageUrl, fit: BoxFit.cover)
              : Icon(Icons.pets_rounded, color: accentColor, size: 66),
        ),
      ),
    );
  }
}

class _OccurrenceStartCommandCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color panelColor;
  final VoidCallback onTap;

  const _OccurrenceStartCommandCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.panelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 96),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panelColor.withAlpha(205),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(115)),
          boxShadow: [BoxShadow(color: color.withAlpha(18), blurRadius: 16)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.robotoMono(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OccurrenceStatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _OccurrenceStatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 7),
          Text(
            label,
            style: GoogleFonts.robotoMono(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
