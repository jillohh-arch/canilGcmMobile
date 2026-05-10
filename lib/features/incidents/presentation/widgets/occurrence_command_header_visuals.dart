part of 'occurrence_command_header.dart';

class _ClipboardIcon extends StatelessWidget {
  final Color accent;

  const _ClipboardIcon({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: accent.withAlpha(16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withAlpha(135)),
      ),
      child: Icon(Icons.assignment_rounded, color: accent, size: 25),
    );
  }
}
