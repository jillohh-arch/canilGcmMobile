part of 'active_shift_dashboard_screen.dart';

class _ActivityRow extends StatelessWidget {
  final _ActivityEntry entry;

  const _ActivityRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: entry.color.withAlpha(40),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: entry.color.withAlpha(110)),
              boxShadow: [
                BoxShadow(color: entry.color.withAlpha(30), blurRadius: 12),
              ],
            ),
            child: Icon(entry.icon, color: entry.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.label,
              style: GoogleFonts.oxanium(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                letterSpacing: 0.6,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            timeStr,
            style: GoogleFonts.robotoMono(
              color: _hudCyan.withAlpha(170),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
