import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

    return Container(
      key: const ValueKey('MenuSheet'),
      decoration: const BoxDecoration(
        color: Color(0xFF171717),
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            offset: Offset(0, -6),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 20),
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(80),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            alignment: Alignment.centerLeft,
            child: Text(
              'SELECIONE A CATEGORIA',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: _ActivityCategoryCarousel(
              cards: cards,
              currentPage: safePage,
              pageController: pageController,
              onPageChanged: onPageChanged,
              onCardConfirmed: onCardConfirmed,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityCategoryCarousel extends StatelessWidget {
  final List<Map<String, dynamic>> cards;
  final int currentPage;
  final PageController pageController;
  final ValueChanged<int> onPageChanged;
  final void Function(Map<String, dynamic> card) onCardConfirmed;

  const _ActivityCategoryCarousel({
    required this.cards,
    required this.currentPage,
    required this.pageController,
    required this.onPageChanged,
    required this.onCardConfirmed,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: PageView.builder(
            controller: pageController,
            itemCount: cards.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, index) {
              final card = cards[index];
              return AnimatedBuilder(
                animation: pageController,
                builder: (context, child) {
                  double value = 1.0;
                  if (pageController.position.haveDimensions) {
                    value = (pageController.page ?? 0) - index;
                  } else {
                    value = (currentPage - index).toDouble();
                  }

                  final scale = (1 - (value.abs() * 0.15)).clamp(0.85, 1.0);
                  final opacity = (1 - (value.abs() * 0.5)).clamp(0.5, 1.0);
                  final isFocused = currentPage == index;

                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: isFocused
                              ? [
                                  BoxShadow(
                                    color: (card['glow'] as Color).withAlpha(
                                      150,
                                    ),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : [],
                        ),
                        child: InkWell(
                          onTap: () {
                            if (!isFocused) {
                              pageController.animateToPage(
                                index,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                              );
                              return;
                            }
                            onCardConfirmed(card);
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Hero(
                              tag: 'hero_category_${card['id']}',
                              child: Image.asset(
                                card['image'],
                                fit: BoxFit.cover,
                                alignment: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cards[currentPage]['glow'],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                elevation: 0,
              ),
              onPressed: () => onCardConfirmed(cards[currentPage]),
              child: Text(
                'CONFIRMAR SELEÇÃO',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
