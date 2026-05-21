import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/occurrences/domain/occurrence_nature.dart';

part 'occurrence_nature_search_hint.dart';
part 'occurrence_nature_search_options.dart';
part 'occurrence_nature_search_option_badge.dart';
part 'occurrence_nature_search_option_texts.dart';
part 'occurrence_nature_search_option_tile.dart';

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
        const _OccurrenceNatureSearchHint(),
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
    return _OccurrenceNatureOptionsView(
      panelColor: panelColor,
      accent: accent,
      options: options,
      onSelected: onSelected,
    );
  }
}
