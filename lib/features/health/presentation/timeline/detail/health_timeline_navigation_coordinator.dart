import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_resolution.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_resolver.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';

/// Mensagens humanas do coordinator (sem sourceType/collection/docId).
abstract final class HealthTimelineNavigationCopy {
  HealthTimelineNavigationCopy._();

  /// Unavailable: sem prometer “detalhe unitário”.
  static const unavailable =
      'O histórico relacionado não está disponível para este registro.';
}

/// Coordinator fino: resolution → ação (3D-D).
///
/// Resolver é a autoridade de O QUÊ; coordinator só executa COMO.
/// Anti double-tap com `_busy` protegido por try/finally em todos os ramos.
class HealthTimelineNavigationCoordinator {
  HealthTimelineNavigationCoordinator({
    required Future<void> Function(HealthTimelineDetailTarget target)
    onNavigate,
    void Function(String message)? onUnavailable,
    void Function(Object error, StackTrace stackTrace)? onNavigateError,
  }) : _onNavigate = onNavigate,
       _onUnavailable = onUnavailable,
       _onNavigateError = onNavigateError;

  final Future<void> Function(HealthTimelineDetailTarget target) _onNavigate;
  final void Function(String message)? _onUnavailable;
  final void Function(Object error, StackTrace stackTrace)? _onNavigateError;

  bool _busy = false;

  bool get isBusy => _busy;

  /// Processa tap de entry.
  ///
  /// - unsupported → 0 callbacks, busy liberado;
  /// - unavailable → feedback (falha do callback não prende busy);
  /// - resolved → no máximo 1 navegação concorrente;
  /// - falha no navigate → busy liberado + [_onNavigateError] (não silencioso).
  /// - `_busy` **sempre** volta a false no [finally] (Gate I / 3E-D2).
  Future<void> onEntryTap(HealthTimelineEntryView entry) async {
    if (_busy) return;
    _busy = true;
    try {
      final resolution = HealthTimelineDetailResolver.resolveEntry(entry);
      switch (resolution) {
        case HealthTimelineDetailUnsupported():
          return;
        case HealthTimelineDetailUnavailable():
          try {
            _onUnavailable?.call(HealthTimelineNavigationCopy.unavailable);
          } catch (_) {
            // Feedback falhou — não propaga, não prende busy.
          }
          return;
        case HealthTimelineDetailResolved(:final target):
          try {
            await _onNavigate(target);
          } catch (error, stackTrace) {
            // 3E-D2: falha async não pode morrer silenciosa (release/profile).
            final handler = _onNavigateError;
            if (handler != null) {
              try {
                handler(error, stackTrace);
              } catch (_) {
                // Handler de erro não pode re-prender o fluxo.
              }
            } else {
              rethrow;
            }
          }
      }
    } finally {
      _busy = false;
    }
  }

  /// Handler de card: ignora não-navegáveis (mesma allowlist do resolver).
  void Function(HealthTimelineEntryView entry)? cardTapHandler() {
    return (entry) {
      if (!HealthTimelineDetailResolver.isNavigable(entry)) return;
      // ignore: discarded_futures
      onEntryTap(entry);
    };
  }
}
