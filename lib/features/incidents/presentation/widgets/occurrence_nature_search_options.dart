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

class _OccurrenceNatureCodeBadge extends StatelessWidget {
  final OccurrenceNature option;
  final Color accent;

  const _OccurrenceNatureCodeBadge({
    required this.option,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withAlpha(16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(100)),
      ),
      child: Text(
        option.code.isEmpty ? 'MAN' : option.code,
        textAlign: TextAlign.center,
        style: GoogleFonts.robotoMono(
          color: accent,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _OccurrenceNatureOptionTexts extends StatelessWidget {
  final OccurrenceNature option;

  const _OccurrenceNatureOptionTexts({required this.option});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          option.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          option.group,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.robotoMono(
            color: Colors.white.withAlpha(115),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}
