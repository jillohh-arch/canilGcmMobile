import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

part 'occurrence_initial_data_sheet_done_button.dart';
part 'occurrence_initial_data_sheet_frame.dart';
part 'occurrence_initial_data_sheet_header.dart';
part 'occurrence_initial_data_sheet_panel.dart';

class OccurrenceInitialDataSheet extends StatelessWidget {
  final Color accentColor;
  final Color backgroundColor;
  final Widget child;
  final VoidCallback onDone;

  const OccurrenceInitialDataSheet({
    super.key,
    required this.accentColor,
    required this.backgroundColor,
    required this.child,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return _InitialDataSheetFrame(
      bottomInset: MediaQuery.of(context).viewInsets.bottom,
      accentColor: accentColor,
      backgroundColor: backgroundColor,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _InitialDataSheetHeader(accentColor: accentColor),
            const SizedBox(height: 10),
            child,
            const SizedBox(height: 12),
            _InitialDataDoneButton(
              accentColor: accentColor,
              backgroundColor: backgroundColor,
              onDone: onDone,
            ),
          ],
        ),
      ),
    );
  }
}
