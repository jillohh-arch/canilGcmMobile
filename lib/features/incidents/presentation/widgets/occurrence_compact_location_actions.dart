part of 'occurrence_compact_location_block.dart';

class _OccurrenceCompactLocationActions extends StatelessWidget {
  final bool hasLocation;
  final Color gpsColor;
  final Color timeColor;
  final VoidCallback onCaptureGps;
  final VoidCallback onSetCurrentTime;

  const _OccurrenceCompactLocationActions({
    required this.hasLocation,
    required this.gpsColor,
    required this.timeColor,
    required this.onCaptureGps,
    required this.onSetCurrentTime,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _OccurrenceMiniCommandButton(
            icon: Icons.gps_fixed_rounded,
            label: hasLocation ? 'ATUALIZAR GPS' : 'CAPTURAR GPS',
            color: gpsColor,
            onTap: onCaptureGps,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _OccurrenceMiniCommandButton(
            icon: Icons.schedule_rounded,
            label: 'HORA ATUAL',
            color: timeColor,
            onTap: onSetCurrentTime,
          ),
        ),
      ],
    );
  }
}

class _OccurrenceMiniCommandButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _OccurrenceMiniCommandButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: color, size: 18),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.robotoMono(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: color.withAlpha(16),
          side: BorderSide(color: color.withAlpha(125)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
    );
  }
}
