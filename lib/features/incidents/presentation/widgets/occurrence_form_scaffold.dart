import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

part 'occurrence_form_scaffold_chrome.dart';
part 'occurrence_form_top_bar.dart';

class OccurrenceFormScaffold extends StatelessWidget {
  final Color backgroundColor;
  final Color panelColor;
  final Color accentColor;
  final bool showTopBar;
  final bool isSaving;
  final String modeLabel;
  final String statusLabel;
  final Widget content;
  final Widget? footer;
  final VoidCallback onBack;

  const OccurrenceFormScaffold({
    super.key,
    required this.backgroundColor,
    required this.panelColor,
    required this.accentColor,
    required this.showTopBar,
    required this.isSaving,
    required this.modeLabel,
    required this.statusLabel,
    required this.content,
    required this.footer,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Stack(
          children: [
            _OccurrenceScaffoldGlowLayer(accentColor: accentColor),
            Column(
              children: [
                if (showTopBar)
                  _OccurrenceTopBar(
                    panelColor: panelColor,
                    backgroundColor: backgroundColor,
                    accentColor: accentColor,
                    isSaving: isSaving,
                    modeLabel: modeLabel,
                    statusLabel: statusLabel,
                    onBack: onBack,
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const BouncingScrollPhysics(),
                    child: content,
                  ),
                ),
                if (footer != null)
                  _OccurrenceFormFooter(
                    backgroundColor: backgroundColor,
                    accentColor: accentColor,
                    child: footer!,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
