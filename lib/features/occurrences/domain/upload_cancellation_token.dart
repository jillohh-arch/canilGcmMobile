import 'package:flutter/foundation.dart';

/// Exceção lançada quando uma operação de upload é interrompida por cancelamento.
class UploadCancelledException implements Exception {
  final String message;
  const UploadCancelledException([
    this.message = 'Upload cancelado pelo usuário.',
  ]);

  @override
  String toString() => 'UploadCancelledException: $message';
}

/// Token cooperativo para cancelamento de tarefas de upload de mídia.
class UploadCancellationToken {
  bool _isCancelled = false;
  final List<VoidCallback> _listeners = [];

  bool get isCancelled => _isCancelled;

  /// Registra um callback invocado imediatamente se já cancelado,
  /// ou assim que [cancel()] for chamado.
  void onCancel(VoidCallback callback) {
    if (_isCancelled) {
      try {
        callback();
      } catch (e) {
        debugPrint(
          '[UploadCancellationToken] Erro ao invocar callback de cancelamento: $e',
        );
      }
    } else {
      _listeners.add(callback);
    }
  }

  /// Cancela a operação e notifica todos os listeners registrados.
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final listener in List.of(_listeners)) {
      try {
        listener();
      } catch (e) {
        debugPrint('[UploadCancellationToken] Erro ao disparar listener: $e');
      }
    }
    _listeners.clear();
  }

  /// Lança [UploadCancelledException] se o token estiver cancelado.
  void throwIfCancelled() {
    if (_isCancelled) {
      throw const UploadCancelledException();
    }
  }
}
