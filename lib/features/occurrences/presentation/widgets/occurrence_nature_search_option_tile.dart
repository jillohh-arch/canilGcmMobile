part of 'occurrence_nature_search.dart';

class _OccurrenceNatureOptionTile extends StatelessWidget {
  final OccurrenceNature option;
  final Color accent;
  final VoidCallback onTap;

  const _OccurrenceNatureOptionTile({
    required this.option,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _OccurrenceNatureCodeBadge(option: option, accent: accent),
            const SizedBox(width: 10),
            Expanded(child: _OccurrenceNatureOptionTexts(option: option)),
          ],
        ),
      ),
    );
  }
}
