part of 'main_root_screen.dart';

extension _MainRootExitDialog on _MainRootScreenState {
  Future<void> _handleBackNavigation(BuildContext context) async {
    // 1. Se há rotas empilhadas acima do MainRootScreen, desempilhar
    final nav = globalNavigatorKey.currentState ?? Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }

    // 2. Se não estiver na aba Início, voltar para ela
    if (_currentIndex != 0) {
      _onTabTapped(0);
      return;
    }

    // 3. Double-back para sair: primeiro toque mostra snackbar,
    //    segundo toque dentro de 2s fecha o app.
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;

    if (!context.mounted) return;
    // TODO migração manual: SnackBar com styling customizado
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Toque novamente para sair',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: AppTheme.surfacePanelAlt,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
