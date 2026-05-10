part of 'occurrence_close_wizard.dart';

class _StepShell extends StatelessWidget {
  final String title;
  final Color accent;
  final Widget child;

  const _StepShell({
    super.key,
    required this.title,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              title,
              style: GoogleFonts.robotoMono(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: accent.withAlpha(120))),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _InstructionBox extends StatelessWidget {
  final String text;

  const _InstructionBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF082031),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: Color(0xFF00E5FF), width: 3),
        ),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: Colors.white70,
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NarrationButton extends StatelessWidget {
  final bool listening;
  final VoidCallback onPressed;

  const _NarrationButton({required this.listening, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        listening ? Icons.stop_circle_rounded : Icons.mic_rounded,
        size: 17,
      ),
      label: Text(listening ? 'PARAR NARRAÇÃO' : 'NARRAÇÃO'),
      style: OutlinedButton.styleFrom(
        foregroundColor: listening
            ? const Color(0xFFFF3B5C)
            : const Color(0xFF00E5FF),
        side: BorderSide(
          color: listening
              ? const Color(0xFFFF3B5C).withAlpha(145)
              : const Color(0xFF00E5FF).withAlpha(145),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: GoogleFonts.robotoMono(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
