import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/widgets/tactical_text_field.dart';
import 'occurrence_event_category.dart';
import 'occurrence_quick_action.dart';

part 'occurrence_event_center_sheet_action_tile.dart';
part 'occurrence_event_center_sheet_body.dart';
part 'occurrence_event_center_sheet_category_pill.dart';
part 'occurrence_event_center_sheet_composer.dart';
part 'occurrence_event_center_sheet_flow.dart';
part 'occurrence_event_center_sheet_frame.dart';
part 'occurrence_event_center_sheet_header.dart';
part 'occurrence_event_center_sheet_tabs.dart';

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

    return _EventCenterFrame(
      bottomInset: bottomInset,
      backgroundColor: widget.backgroundColor,
      accentColor: widget.accentColor,
      child: _buildSheetBody(context, selectedCategory),
    );
  }
}
