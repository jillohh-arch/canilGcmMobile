part of 'training_log_screen.dart';

class _SessionCardHeader extends StatelessWidget {
  final TrainingSessionModel session;
  final IconData icon;
  final Color color;
  final String dateText;
  final bool expanded;

  const _SessionCardHeader({
    required this.session,
    required this.icon,
    required this.color,
    required this.dateText,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 11),
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        border: Border(bottom: BorderSide(color: color.withAlpha(120))),
      ),
      child: Row(
        children: [
          _SessionTypeIcon(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: _SessionTitleBlock(session: session, color: color),
          ),
          const SizedBox(width: 8),
          _SessionDateBlock(session: session, color: color, dateText: dateText),
          const SizedBox(width: 6),
          Icon(
            expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: 22,
            color: color.withAlpha(180),
          ),
        ],
      ),
    );
  }
}

class _SessionTypeIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _SessionTypeIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFF070B14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(210), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(65),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 19),
    );
  }
}

class _SessionTitleBlock extends StatelessWidget {
  final TrainingSessionModel session;
  final Color color;

  const _SessionTitleBlock({required this.session, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _SessionTag(
              label: session.trainingType.toUpperCase(),
              color: color,
              labelColor: color,
              fontSize: 11,
              letterSpacing: 1.4,
              fontFamily: _SessionTagFont.oxanium,
            ),
            if (session.substanceUsed != null)
              _SessionTag(
                label: session.substanceUsed!.toUpperCase(),
                color: Colors.white,
                labelColor: Colors.white60,
                fontSize: 9,
                letterSpacing: 0.8,
                fontFamily: _SessionTagFont.robotoMono,
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          session.location,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

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

class _SessionExpandedDetails extends StatelessWidget {
  final TrainingSessionModel session;
  final Color color;

  const _SessionExpandedDetails({required this.session, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (session.weather.isNotEmpty)
                _DetailChip(
                  icon: Icons.cloud_outlined,
                  label: session.weather,
                  color: color,
                ),
              if (session.humidity != null)
                _DetailChip(
                  icon: Icons.water_drop_outlined,
                  label: '${session.humidity!.round()}% umidade',
                  color: color,
                ),
              if (session.windDirection != null)
                _DetailChip(
                  icon: Icons.air,
                  label: 'Vento: ${session.windDirection}',
                  color: color,
                ),
              if (session.hidingTime != null)
                _DetailChip(
                  icon: Icons.timer_outlined,
                  label: 'Ocultação: ${session.hidingTime}',
                  color: color,
                ),
            ],
          ),
        ),
        if (session.handlerNotes.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SessionNotesBox(notes: session.handlerNotes, color: color),
        ],
      ],
    );
  }
}

class _SessionNotesBox extends StatelessWidget {
  final String notes;
  final Color color;

  const _SessionNotesBox({required this.notes, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF070B14).withAlpha(210),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withAlpha(90)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.notes_rounded, size: 15, color: color.withAlpha(210)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                notes,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _DetailChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(95)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color.withAlpha(220)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.robotoMono(
              fontSize: 10,
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
