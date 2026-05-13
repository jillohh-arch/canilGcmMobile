part of 'main_root_screen.dart';

extension _MainRootExitDialog on _MainRootScreenState {
  Future<void> _handleBackNavigation(BuildContext context) async {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator.canPop()) {
      rootNavigator.pop();
      return;
    }

    final localNavigator = Navigator.of(context);
    if (localNavigator.canPop()) {
      localNavigator.pop();
      return;
    }

    // Se não estiver no dashboard ativo (aba 0), voltar para a aba 0
    if (_currentIndex != 0) {
      _onTabTapped(0);
      return;
    }

    // Se estiver na aba 0, pedir confirmação para fechar o app
    final shouldExit = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        title: const Text(
          'Encerrar Aplicativo?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Tem certeza que deseja fechar o aplicativo e encerrar sua sessão no dispositivo?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
            ),
            child: const Text(
              'Sair',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (shouldExit == true) {
      SystemNavigator.pop();
    }
  }
}
