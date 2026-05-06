import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/incidents/domain/occurrence_nature.dart';

typedef OccurrenceNatureFieldBuilder =
    Widget Function(
      BuildContext context,
      TextEditingController controller,
      FocusNode focusNode,
      ValueChanged<String> onChanged,
    );

class OccurrenceNatureSearch extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final List<OccurrenceNature> natures;
  final Color panelColor;
  final Color accent;
  final OccurrenceNatureFieldBuilder fieldBuilder;
  final ValueChanged<OccurrenceNature> onSelected;
  final ValueChanged<String> onChanged;

  const OccurrenceNatureSearch({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.natures,
    required this.panelColor,
    required this.accent,
    required this.fieldBuilder,
    required this.onSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RawAutocomplete<OccurrenceNature>(
          textEditingController: controller,
          focusNode: focusNode,
          displayStringForOption: (option) => option.label,
          optionsBuilder: _buildOptions,
          onSelected: onSelected,
          fieldViewBuilder: (context, controller, focusNode, _) {
            return fieldBuilder(context, controller, focusNode, onChanged);
          },
          optionsViewBuilder: _buildOptionsView,
        ),
        const SizedBox(height: 8),
        Text(
          'Digite parte da natureza ou do código. A busca ignora acentos.',
          style: GoogleFonts.inter(
            color: Colors.white.withAlpha(115),
            fontSize: 11,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Iterable<OccurrenceNature> _buildOptions(TextEditingValue value) {
    final query = value.text.trim();
    final matches = natures
        .where((nature) => nature.active && nature.matches(query))
        .take(12)
        .toList();

    if (matches.isEmpty && query.isNotEmpty) {
      return [
        OccurrenceNature(
          code: '',
          name: query,
          group: 'Natureza informada manualmente',
        ),
      ];
    }
    return matches;
  }

  Widget _buildOptionsView(
    BuildContext context,
    AutocompleteOnSelected<OccurrenceNature> onSelected,
    Iterable<OccurrenceNature> options,
  ) {
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
              return InkWell(
                onTap: () => onSelected(option),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
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
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
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
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
