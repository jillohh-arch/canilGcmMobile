part of 'occurrence_form_scaffold.dart';

class _OccurrenceTopBar extends StatelessWidget {
  final Color panelColor;
  final Color backgroundColor;
  final Color accentColor;
  final bool isSaving;
  final String modeLabel;
  final String statusLabel;
  final VoidCallback onBack;

  const _OccurrenceTopBar({
    required this.panelColor,
    required this.backgroundColor,
    required this.accentColor,
    required this.isSaving,
    required this.modeLabel,
    required this.statusLabel,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 10),
      decoration: BoxDecoration(
        color: backgroundColor.withAlpha(246),
        border: const Border(bottom: BorderSide(color: Color(0x2200E5FF))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_rounded,
              color: Colors.white,
              size: 20,
            ),
            onPressed: isSaving ? null : onBack,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'K9 - COMANDO',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3.2,
                    shadows: [
                      Shadow(color: accentColor.withAlpha(160), blurRadius: 12),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  modeLabel,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
              ],
            ),
          ),
          _OccurrenceTopBarStatusBadge(
            label: statusLabel,
            panelColor: panelColor,
            accentColor: accentColor,
          ),
        ],
      ),
    );
  }
}

class _OccurrenceTopBarStatusBadge extends StatelessWidget {
  final String label;
  final Color panelColor;
  final Color accentColor;

  const _OccurrenceTopBarStatusBadge({
    required this.label,
    required this.panelColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accentColor.withAlpha(120)),
        boxShadow: [
          BoxShadow(color: accentColor.withAlpha(35), blurRadius: 14),
        ],
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: accentColor,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
