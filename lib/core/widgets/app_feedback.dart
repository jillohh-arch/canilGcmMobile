import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/main.dart' show globalScaffoldMessengerKey;

enum AppFeedbackType { success, error, warning, info, loading }

class AppFeedback {
  const AppFeedback._();

  static void success(
    BuildContext context,
    String message, {
    String title = 'Tudo certo',
  }) {
    show(context, message, title: title, type: AppFeedbackType.success);
  }

  static void warning(
    BuildContext context,
    String message, {
    String title = 'Atenção',
  }) {
    show(context, message, title: title, type: AppFeedbackType.warning);
  }

  static void info(
    BuildContext context,
    String message, {
    String title = 'Informação',
  }) {
    show(context, message, title: title, type: AppFeedbackType.info);
  }

  static void loading(
    BuildContext context,
    String message, {
    String title = 'Sincronizando',
  }) {
    show(context, message, title: title, type: AppFeedbackType.loading);
  }

  static void error(
    BuildContext context,
    Object error, {
    String fallback = 'Não foi possível concluir a ação.',
  }) {
    final message = AppFeedbackText.fromError(error, fallback: fallback);
    show(
      context,
      message,
      title: 'Algo não saiu como esperado',
      type: AppFeedbackType.error,
    );
  }

  static void show(
    BuildContext context,
    String message, {
    AppFeedbackType type = AppFeedbackType.info,
    String? title,
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    // Fallback no messenger global: ao encerrar turno (ou outra ação que troca
    // de tela), o widget de origem é desmontado antes do snackbar renderizar.
    // Tocar em ScaffoldMessenger.maybeOf com um contexto desmontado lança
    // exceção, então só consultamos o contexto se ele ainda estiver montado;
    // caso contrário caímos no messenger global, que sobrevive à navegação.
    final messenger =
        (context.mounted ? ScaffoldMessenger.maybeOf(context) : null) ??
        globalScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    final visual = _visualFor(type);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        duration: type == AppFeedbackType.loading
            ? const Duration(seconds: 2)
            : duration,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        action: action,
        content: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceSnack.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: visual.color.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(
                color: visual.color.withValues(alpha: 0.20),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          visual.color.withValues(alpha: 0.18),
                          Colors.transparent,
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: visual.color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: visual.color.withValues(alpha: 0.42),
                          ),
                        ),
                        child: type == AppFeedbackType.loading
                            ? Padding(
                                padding: const EdgeInsets.all(10),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    visual.color,
                                  ),
                                ),
                              )
                            : Icon(visual.icon, color: visual.color, size: 21),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title ?? visual.title,
                              style: GoogleFonts.inter(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              AppFeedbackText.clean(message),
                              style: GoogleFonts.inter(
                                color: AppTheme.textSoft,
                                fontSize: 12,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static _FeedbackVisual _visualFor(AppFeedbackType type) {
    switch (type) {
      case AppFeedbackType.success:
        return const _FeedbackVisual(
          color: AppTheme.success,
          icon: Icons.check_circle_rounded,
          title: 'Tudo certo',
        );
      case AppFeedbackType.error:
        return const _FeedbackVisual(
          color: AppTheme.errorStrong,
          icon: Icons.error_outline_rounded,
          title: 'Algo não saiu como esperado',
        );
      case AppFeedbackType.warning:
        return const _FeedbackVisual(
          color: AppTheme.warning,
          icon: Icons.warning_amber_rounded,
          title: 'Atenção',
        );
      case AppFeedbackType.info:
        return const _FeedbackVisual(
          color: AppTheme.primary,
          icon: Icons.info_outline_rounded,
          title: 'Informação',
        );
      case AppFeedbackType.loading:
        return const _FeedbackVisual(
          color: AppTheme.primary,
          icon: Icons.sync_rounded,
          title: 'Sincronizando',
        );
    }
  }
}

class AppFeedbackText {
  const AppFeedbackText._();

  static String fromError(Object error, {required String fallback}) {
    if (error is FirebaseException) {
      return _firebaseMessage(error.code, fallback: fallback);
    }
    if (error is FirebaseAuthException) {
      return _firebaseMessage(error.code, fallback: fallback);
    }
    if (error is StateError || error is ArgumentError) {
      return clean(error.toString());
    }

    final raw = error.toString();
    final normalized = raw.toLowerCase();
    if (normalized.contains('permission-denied') ||
        normalized.contains('missing or insufficient permissions') ||
        normalized.contains('does not have permission')) {
      return _firebaseMessage('permission-denied', fallback: fallback);
    }
    if (normalized.contains('network') ||
        normalized.contains('unavailable') ||
        normalized.contains('deadline-exceeded') ||
        normalized.contains('timeoutexception') ||
        normalized.contains('tempo excedido')) {
      return _firebaseMessage('unavailable', fallback: fallback);
    }
    if (normalized.contains('unauthenticated')) {
      return _firebaseMessage('unauthenticated', fallback: fallback);
    }

    final cleaned = clean(raw);
    if (cleaned.isEmpty || _looksTechnical(cleaned)) return fallback;
    return cleaned;
  }

  static String clean(String value) {
    var message = value.trim();
    message = message.replaceFirst(RegExp(r'^Exception:\s*'), '');
    message = message.replaceFirst(RegExp(r'^StateError:\s*'), '');
    message = message.replaceFirst(RegExp(r'^Invalid argument\(s\):\s*'), '');
    message = message.replaceFirst(RegExp(r'^FirebaseException:\s*'), '');
    message = message.replaceAll(RegExp(r'\[cloud_firestore/[^]]+\]\s*'), '');
    message = message.replaceAll(RegExp(r'\[firebase_auth/[^]]+\]\s*'), '');
    message = message.replaceAll(
      'The caller does not have permission to execute the specified operation.',
      '',
    );
    message = message.replaceAll('Missing or insufficient permissions.', '');
    message = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    return message;
  }

  static String _firebaseMessage(String code, {required String fallback}) {
    switch (code) {
      case 'permission-denied':
        return 'Você não tem permissão para essa ação. Atualize o login ou procure o administrador.';
      case 'unauthenticated':
      case 'user-token-expired':
        return 'Sua sessão precisa ser renovada. Saia e entre novamente.';
      case 'unavailable':
      case 'deadline-exceeded':
      case 'network-request-failed':
        return 'Não foi possível sincronizar agora. Verifique a conexão e tente novamente.';
      case 'not-found':
        return 'O registro não foi encontrado. Atualize a tela e tente novamente.';
      case 'already-exists':
        return 'Esse registro já existe.';
      case 'cancelled':
        return 'A operação foi cancelada antes de concluir.';
      default:
        return fallback;
    }
  }

  static bool _looksTechnical(String value) {
    final normalized = value.toLowerCase();
    return normalized.contains('cloud_firestore') ||
        normalized.contains('firebaseexception') ||
        normalized.contains('stacktrace') ||
        normalized.contains('package:') ||
        normalized.contains('documentreference') ||
        normalized.contains('collectionreference');
  }
}

class _FeedbackVisual {
  final Color color;
  final IconData icon;
  final String title;

  const _FeedbackVisual({
    required this.color,
    required this.icon,
    required this.title,
  });
}
