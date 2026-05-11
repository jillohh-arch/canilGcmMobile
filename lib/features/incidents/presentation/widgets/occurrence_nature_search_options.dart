part of 'occurrence_nature_search.dart';

class _OccurrenceNatureOptionsView extends StatelessWidget {
  final Color panelColor;
  final Color accent;
  final Iterable<OccurrenceNature> options;
  final AutocompleteOnSelected<OccurrenceNature> onSelected;

  const _OccurrenceNatureOptionsView({
    required this.panelColor,
    required this.accent,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width - 32,
          constraints: const BoxConstraints(maxHeight: 280),
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: accent.withAlpha(130)),
            boxShadow: [BoxShadow(color: accent.withAlpha(35), blurRadius: 18)],
          ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, index) {
              final option = options.elementAt(index);
              return _OccurrenceNatureOptionTile(
                option: option,
                accent: accent,
                onTap: () => onSelected(option),
              );
            },
          ),
        ),
      ),
    );
  }
}
