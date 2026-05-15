part of 'occurrence_start_screen.dart';

class _OccurrenceStartHero extends StatelessWidget {
  final String dogName;
  final String? dogImageUrl;
  final Color accentColor;
  final Color panelColor;

  const _OccurrenceStartHero({
    required this.dogName,
    required this.dogImageUrl,
    required this.accentColor,
    required this.panelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          _OccurrenceStartDogAvatar(
            imageUrl: dogImageUrl,
            accentColor: accentColor,
            panelColor: panelColor,
          ),
          const SizedBox(height: 16),
          Text(
            dogName.toUpperCase(),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 5,
            ),
          ),
          const SizedBox(height: 8),
          const _OccurrenceStatusPill(
            icon: Icons.circle,
            label: 'TURNO ATIVO',
            color: AppTheme.success,
          ),
        ],
      ),
    );
  }
}

class _OccurrenceStartDogAvatar extends StatelessWidget {
  final String? imageUrl;
  final Color accentColor;
  final Color panelColor;

  const _OccurrenceStartDogAvatar({
    required this.imageUrl,
    required this.accentColor,
    required this.panelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 156,
      height: 156,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accentColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withAlpha(50),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipOval(
        child: Container(
          color: panelColor,
          child: imageUrl != null && imageUrl!.isNotEmpty
              ? Image.network(imageUrl!, fit: BoxFit.cover)
              : Icon(Icons.pets_rounded, color: accentColor, size: 66),
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
            style: GoogleFonts.inter(
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
