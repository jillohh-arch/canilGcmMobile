import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../widgets/tactical_text_field.dart';
import 'occurrence_event_category.dart';
import 'occurrence_quick_action.dart';

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
              _buildHeader(context),
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
              TacticalTextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                labelText: 'Evento personalizado / observação',
                prefixIcon: Icons.edit_note_rounded,
                maxLines: 3,
                minLines: 2,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: () =>
                      _submitCustomEvent(context, selectedCategory.color),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(
                    'REGISTRAR EVENTO',
                    style: GoogleFonts.robotoMono(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.accentColor,
                    foregroundColor: widget.backgroundColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.playlist_add_rounded, color: widget.accentColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'ADICIONAR EVENTO',
            style: GoogleFonts.robotoMono(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
          color: Colors.white54,
        ),
      ],
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

class _EventCategoryPill extends StatelessWidget {
  final OccurrenceEventCategory category;
  final Color panelColor;
  final bool selected;
  final VoidCallback onTap;

  const _EventCategoryPill({
    required this.category,
    required this.panelColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? category.color.withAlpha(35) : panelColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? category.color : category.color.withAlpha(70),
          ),
        ),
        child: Row(
          children: [
            Icon(category.icon, color: category.color, size: 17),
            const SizedBox(width: 7),
            Text(
              category.title.toUpperCase(),
              style: GoogleFonts.robotoMono(
                color: selected ? category.color : Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventActionTile extends StatelessWidget {
  final OccurrenceQuickAction action;
  final Color panelColor;
  final VoidCallback onTap;

  const _EventActionTile({
    required this.action,
    required this.panelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: panelColor.withAlpha(210),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: action.color.withAlpha(85)),
          ),
          child: Row(
            children: [
              Icon(action.icon, color: action.color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: GoogleFonts.oxanium(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      action.description,
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.add_circle_outline_rounded,
                color: action.color.withAlpha(220),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
