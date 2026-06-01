import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';

part 'activity_category_carousel.dart';
part 'activity_category_menu_frame.dart';

class ActivityCategoryMenuSheet extends StatelessWidget {
  final List<Map<String, dynamic>> cards;
  final int currentPage;
  final PageController pageController;
  final ValueChanged<int> onPageChanged;
  final void Function(Map<String, dynamic> card) onCardConfirmed;

  const ActivityCategoryMenuSheet({
    super.key,
    required this.cards,
    required this.currentPage,
    required this.pageController,
    required this.onPageChanged,
    required this.onCardConfirmed,
  });

  @override
  Widget build(BuildContext context) {
    final safePage = cards.isEmpty ? 0 : currentPage.clamp(0, cards.length - 1);

    return _ActivityCategoryMenuFrame(
      child: _ActivityCategoryCarousel(
        cards: cards,
        currentPage: safePage,
        pageController: pageController,
        onPageChanged: onPageChanged,
        onCardConfirmed: onCardConfirmed,
      ),
    );
  }
}
