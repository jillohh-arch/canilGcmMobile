part of 'activity_category_menu_sheet.dart';

class _ActivityCategoryMenuFrame extends StatelessWidget {
  final Widget child;

  const _ActivityCategoryMenuFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('MenuSheet'),
      decoration: BoxDecoration(
        color: AppTheme.surfaceModal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.background.withAlpha(138),
            offset: Offset(0, -6),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        children: [
          const _ActivityCategoryDragHandle(),
          const _ActivityCategoryMenuTitle(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _ActivityCategoryDragHandle extends StatelessWidget {
  const _ActivityCategoryDragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 20),
        width: 48,
        height: 5,
        decoration: BoxDecoration(
          color: AppTheme.textPrimary.withAlpha(80),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

class _ActivityCategoryMenuTitle extends StatelessWidget {
  const _ActivityCategoryMenuTitle();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      alignment: Alignment.centerLeft,
      child: Text(
        'SELECIONE A CATEGORIA',
        style: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}
