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
