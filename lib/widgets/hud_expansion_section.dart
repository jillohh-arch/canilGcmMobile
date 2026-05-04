import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HudExpansionSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;
  final bool initiallyExpanded;

  const HudExpansionSection({
    super.key,
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        maintainState: true,
        collapsedBackgroundColor: const Color(0xFF1E1E1E),
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: iconColor),
        title: Text(
          title,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: Colors.white,
          ),
        ),
        childrenPadding: const EdgeInsets.all(16),
        children: children,
      ),
    );
  }
}
