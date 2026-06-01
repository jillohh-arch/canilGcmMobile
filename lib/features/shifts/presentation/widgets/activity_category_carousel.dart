part of 'activity_category_menu_sheet.dart';

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
              return _ActivityCategoryPage(
                card: cards[index],
                index: index,
                currentPage: currentPage,
                pageController: pageController,
                onCardConfirmed: onCardConfirmed,
              );
            },
          ),
        ),
        const SizedBox(height: 32),
        _ActivityCategoryConfirmButton(
          card: cards[currentPage],
          onPressed: () => onCardConfirmed(cards[currentPage]),
        ),
      ],
    );
  }
}

class _ActivityCategoryPage extends StatelessWidget {
  final Map<String, dynamic> card;
  final int index;
  final int currentPage;
  final PageController pageController;
  final void Function(Map<String, dynamic> card) onCardConfirmed;

  const _ActivityCategoryPage({
    required this.card,
    required this.index,
    required this.currentPage,
    required this.pageController,
    required this.onCardConfirmed,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, child) {
        final offset = _pageOffset();
        final scale = (1 - (offset.abs() * 0.15)).clamp(0.85, 1.0);
        final opacity = (1 - (offset.abs() * 0.5)).clamp(0.5, 1.0);
        final isFocused = currentPage == index;

        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: _ActivityCategoryCard(
              card: card,
              isFocused: isFocused,
              onTap: () => _handleTap(isFocused),
            ),
          ),
        );
      },
    );
  }

  double _pageOffset() {
    if (pageController.position.haveDimensions) {
      return (pageController.page ?? 0) - index;
    }
    return (currentPage - index).toDouble();
  }

  void _handleTap(bool isFocused) {
    if (!isFocused) {
      pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    onCardConfirmed(card);
  }
}

class _ActivityCategoryCard extends StatelessWidget {
  final Map<String, dynamic> card;
  final bool isFocused;
  final VoidCallback onTap;

  const _ActivityCategoryCard({
    required this.card,
    required this.isFocused,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final glow = card['glow'] as Color;
    final image = card['image'] as String;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: glow.withAlpha(150),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: InkWell(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Hero(
            tag: 'hero_category_${card['id']}',
            child: Image.asset(
              image,
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityCategoryConfirmButton extends StatelessWidget {
  final Map<String, dynamic> card;
  final VoidCallback onPressed;

  const _ActivityCategoryConfirmButton({
    required this.card,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: card['glow'] as Color,
            foregroundColor: AppTheme.textPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            elevation: 0,
          ),
          onPressed: onPressed,
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
    );
  }
}
