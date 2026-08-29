import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/presentation/shared/forms/health_form_status.dart';

/// Validador síncrono: retorna mensagem de erro ou `null` se válido.
typedef HealthFormValidator = String? Function();

/// Controller reutilizável para formulários do Health v1.
///
/// Responsabilidades concretas (e apenas estas):
/// - rastrear dirty state;
/// - serializar submit e bloquear duplo submit;
/// - expor status para a UI (submitting / success / error);
/// - evitar `notifyListeners` após [dispose] (Futures de submit podem
///   completar depois que a tela descartou o controller).
///
/// Pós-[dispose]: mutações e [submit] retornam sem efeito colateral
/// observável (sem notify, sem executar action se o submit ainda não
/// começou). Isso é deliberado para async em andamento — não substitui
/// o cancelamento real da operação de negócio (que fica no caller).
///
/// Não realiza persistência, não conhece Firestore e não depende de
/// `HealthLogModel` ou services legados.
class HealthFormController extends ChangeNotifier {
  HealthFormStatus _status = HealthFormStatus.initial;
  bool _dirty = false;
  String? _errorMessage;
  bool _disposed = false;

  HealthFormStatus get status => _status;

  /// `true` quando o usuário alterou algo desde o último pristine/sucesso.
  bool get isDirty => _dirty;

  bool get isSubmitting => _status == HealthFormStatus.submitting;

  bool get isSuccess => _status == HealthFormStatus.success;

  bool get hasError => _status == HealthFormStatus.error;

  /// Bloqueia submit concorrente; validação é responsabilidade do caller.
  bool get canSubmit => !_disposed && !isSubmitting;

  String? get errorMessage => _errorMessage;

  /// Marca o formulário como alterado. Idempotente enquanto dirty.
  void markDirty() {
    if (_disposed || isSubmitting) return;
    final changed = !_dirty || _status != HealthFormStatus.dirty;
    _dirty = true;
    _status = HealthFormStatus.dirty;
    _errorMessage = null;
    if (changed) _safeNotify();
  }

  /// Restaura o formulário para o estado pristine (ex.: após hidratar campos).
  void markPristine() {
    if (_disposed || isSubmitting) return;
    final changed =
        _dirty || _status != HealthFormStatus.initial || _errorMessage != null;
    _dirty = false;
    _status = HealthFormStatus.initial;
    _errorMessage = null;
    if (changed) _safeNotify();
  }

  /// Limpa mensagem de erro sem alterar dirty.
  void clearError() {
    if (_disposed || _errorMessage == null) return;
    _errorMessage = null;
    if (_status == HealthFormStatus.error) {
      _status = _dirty ? HealthFormStatus.dirty : HealthFormStatus.initial;
    }
    _safeNotify();
  }

  /// Executa [action] com proteção contra submit duplicado.
  ///
  /// [validate] roda antes do submit; se retornar mensagem, o status vira
  /// [HealthFormStatus.error] e a ação não é executada.
  ///
  /// Em sucesso, dirty é limpo. Em falha da action, dirty é preservado para
  /// permitir correção e nova tentativa.
  Future<bool> submit({
    required Future<void> Function() action,
    HealthFormValidator? validate,
  }) async {
    if (_disposed || isSubmitting) return false;

    final validationError = validate?.call();
    if (validationError != null) {
      _status = HealthFormStatus.error;
      _errorMessage = validationError;
      _safeNotify();
      return false;
    }

    _status = HealthFormStatus.submitting;
    _errorMessage = null;
    _safeNotify();

    try {
      await action();
      if (_disposed) return false;
      _dirty = false;
      _status = HealthFormStatus.success;
      _errorMessage = null;
      _safeNotify();
      return true;
    } catch (error, stackTrace) {
      assert(() {
        debugPrint('[HealthFormController] submit falhou: $error\n$stackTrace');
        return true;
      }());
      if (_disposed) return false;
      _status = HealthFormStatus.error;
      _errorMessage = _messageFromError(error);
      // Mantém dirty para o usuário não perder o contexto de edição.
      _dirty = true;
      _safeNotify();
      return false;
    }
  }

  static String _messageFromError(Object error) {
    if (error is HealthFormException) return error.message;
    final text = error.toString().trim();
    if (text.isEmpty) return 'Não foi possível salvar o registro.';
    // Remove prefixo "Exception: " comum em toString de Exception.
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }

  @visibleForTesting
  bool get isDisposedForTest => _disposed;
}

/// Erro tipado para mensagens de submit controladas pela feature.
class HealthFormException implements Exception {
  final String message;

  const HealthFormException(this.message);

  @override
  String toString() => message;
}
