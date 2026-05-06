import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
            Positioned(
              top: 80,
              left: -120,
              child: _HudGlow(color: accentColor.withAlpha(36), size: 240),
            ),
            Positioned(
              right: -140,
              bottom: 120,
              child: _HudGlow(color: accentColor.withAlpha(24), size: 280),
            ),
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
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: backgroundColor.withAlpha(244),
                      border: const Border(
                        top: BorderSide(color: Color(0x3300E5FF)),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withAlpha(30),
                          blurRadius: 20,
                          offset: const Offset(0, -8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: footer,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HudGlow extends StatelessWidget {
  final Color color;
  final double size;

  const _HudGlow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color, blurRadius: size / 2, spreadRadius: 18),
          ],
        ),
      ),
    );
  }
}

class _OccurrenceTopBar extends StatelessWidget {
  final Color panelColor;
  final Color backgroundColor;
  final Color accentColor;
  final bool isSaving;
  final String modeLabel;
  final String statusLabel;
  final VoidCallback onBack;

  const _OccurrenceTopBar({
    required this.panelColor,
    required this.backgroundColor,
    required this.accentColor,
    required this.isSaving,
    required this.modeLabel,
    required this.statusLabel,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 10),
      decoration: BoxDecoration(
        color: backgroundColor.withAlpha(246),
        border: const Border(bottom: BorderSide(color: Color(0x2200E5FF))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_rounded,
              color: Colors.white,
              size: 20,
            ),
            onPressed: isSaving ? null : onBack,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'K9 - COMANDO',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.robotoMono(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3.2,
                    shadows: [
                      Shadow(color: accentColor.withAlpha(160), blurRadius: 12),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  modeLabel,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: accentColor.withAlpha(120)),
              boxShadow: [
                BoxShadow(color: accentColor.withAlpha(35), blurRadius: 14),
              ],
            ),
            child: Text(
              statusLabel,
              style: GoogleFonts.robotoMono(
                color: accentColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
