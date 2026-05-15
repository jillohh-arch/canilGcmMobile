import 'package:flutter/material.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

final _hudBackground = AppTheme.background;
final _hudCyan = AppTheme.primary;

class HudTabBar extends StatelessWidget {
  final TabController? controller;
  final List<Widget> tabs;

  const HudTabBar({super.key, this.controller, required this.tabs});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _hudBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x3300E5FF)),
        boxShadow: [BoxShadow(color: _hudCyan.withAlpha(24), blurRadius: 16)],
      ),
      child: TabBar(
        controller: controller,
        isScrollable: false,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: _hudCyan.withAlpha(28),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _hudCyan),
        ),
        labelColor: _hudCyan,
        unselectedLabelColor: Colors.white54,
        labelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.8,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: 0.5,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        tabs: tabs,
      ),
    );
  }
}
