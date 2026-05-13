part of 'training_log_screen.dart';

enum _SessionTagFont { oxanium, robotoMono }

class _SessionTag extends StatelessWidget {
  final String label;
  final Color color;
  final Color labelColor;
  final double fontSize;
  final double letterSpacing;
  final _SessionTagFont fontFamily;

  const _SessionTag({
    required this.label,
    required this.color,
    required this.labelColor,
    required this.fontSize,
    required this.letterSpacing,
    required this.fontFamily,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = fontFamily == _SessionTagFont.oxanium
        ? GoogleFonts.oxanium(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: labelColor,
            letterSpacing: letterSpacing,
          )
        : GoogleFonts.robotoMono(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: labelColor,
            letterSpacing: letterSpacing,
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color == Colors.white
            ? Colors.white.withAlpha(12)
            : color.withAlpha(35),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: color == Colors.white ? Colors.white12 : color.withAlpha(140),
        ),
      ),
      child: Text(label, style: textStyle),
    );
  }
}

class _SessionDateBlock extends StatelessWidget {
  final TrainingSessionModel session;
  final Color color;
  final String dateText;

  const _SessionDateBlock({
    required this.session,
    required this.color,
    required this.dateText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          dateText,
          style: GoogleFonts.robotoMono(
            fontSize: 10,
            color: Colors.white54,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (session.searchDuration != null) ...[
          const SizedBox(height: 4),
          Text(
            '${session.searchDuration}s',
            style: GoogleFonts.oxanium(
              fontSize: 16,
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ],
    );
  }
}

class _SessionStateLine extends StatelessWidget {
  final bool expanded;
  final Color color;

  const _SessionStateLine({required this.expanded, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        children: [
          Container(width: 26, height: 2, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Container(height: 1, color: Colors.white.withAlpha(18)),
          ),
          const SizedBox(width: 8),
          Text(
            expanded ? 'REGISTRO ABERTO' : 'TOQUE PARA DETALHES',
            style: GoogleFonts.robotoMono(
              fontSize: 9,
              color: expanded ? color : Colors.white38,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}
