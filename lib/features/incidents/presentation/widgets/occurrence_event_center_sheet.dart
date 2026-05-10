import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/widgets/tactical_text_field.dart';
import 'occurrence_event_category.dart';
import 'occurrence_quick_action.dart';

part 'occurrence_event_center_sheet_action_tile.dart';
part 'occurrence_event_center_sheet_category_pill.dart';
part 'occurrence_event_center_sheet_composer.dart';
part 'occurrence_event_center_sheet_header.dart';

class OccurrenceEventCenterSheet extends StatefulWidget {
  final Color accentColor;
  final Color backgroundColor;
  final Color panelColor;
  final List<OccurrenceEventCategory> categories;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<OccurrenceQuickAction> onActionSelected;

  const OccurrenceEventCenterSheet({
    super.key,
    required this.accentColor,
    required this.backgroundColor,
    required this.panelColor,
    required this.categories,
    required this.controller,
    required this.focusNode,
    required this.onActionSelected,
  });

  @override
  State<OccurrenceEventCenterSheet> createState() =>
      _OccurrenceEventCenterSheetState();
}

class _OccurrenceEventCenterSheetState
    extends State<OccurrenceEventCenterSheet> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final selectedCategory = widget.categories[_selectedIndex];

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: widget.backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: widget.accentColor.withAlpha(135)),
          boxShadow: [
            BoxShadow(color: widget.accentColor.withAlpha(38), blurRadius: 24),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EventCenterHeader(
                accentColor: widget.accentColor,
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 10),
              _buildCategoryTabs(),
              const SizedBox(height: 14),
              Text(
                'EVENTOS SUGERIDOS',
                style: GoogleFonts.robotoMono(
                  color: selectedCategory.color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              ...selectedCategory.actions.map(
                (action) => _EventActionTile(
                  action: action,
                  panelColor: widget.panelColor,
                  onTap: () => _selectAction(context, action),
                ),
              ),
              const SizedBox(height: 12),
              _CustomEventComposer(
                controller: widget.controller,
                focusNode: widget.focusNode,
                accentColor: widget.accentColor,
                backgroundColor: widget.backgroundColor,
                onSubmit: () =>
                    _submitCustomEvent(context, selectedCategory.color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = widget.categories[index];
          return _EventCategoryPill(
            category: category,
            panelColor: widget.panelColor,
            selected: index == _selectedIndex,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedIndex = index);
            },
          );
        },
      ),
    );
  }

  void _submitCustomEvent(BuildContext context, Color color) {
    final description = widget.controller.text.trim();
    if (description.isEmpty) {
      widget.focusNode.requestFocus();
      return;
    }

    _selectAction(
      context,
      OccurrenceQuickAction(
        title: 'Evento personalizado',
        description: description,
        icon: Icons.edit_note_rounded,
        color: color,
      ),
    );
  }

  void _selectAction(BuildContext context, OccurrenceQuickAction action) {
    Navigator.of(context).pop();
    widget.onActionSelected(action);
  }
}
