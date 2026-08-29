import 'dart:async';

import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

/// Fake controlável apenas para testes da Fase 3A.
///
/// Permite:
/// - enfileirar páginas;
/// - delays;
/// - erros / offline;
/// - completar requests pendentes manualmente (races).
class FakeHealthTimelineSource implements HealthTimelineSource {
  final List<HealthTimelineQuery> requests = [];

  /// Respostas enfileiradas (FIFO) para o próximo [loadPage].
  final List<_QueuedResponse> _queue = [];

  /// Requests aguardando conclusão manual (quando [holdResponses] é true).
  final List<_PendingRequest> _held = [];

  /// Se true, [loadPage] não completa até [completeNext] / [failNext].
  bool holdResponses = false;

  Duration delay = Duration.zero;

  /// Handler opcional com precedência sobre a fila.
  Future<HealthTimelinePage> Function(HealthTimelineQuery query)? handler;

  void enqueuePage(HealthTimelinePage page) {
    _queue.add(_QueuedResponse.page(page));
  }

  void enqueueError(Object error) {
    _queue.add(_QueuedResponse.error(error));
  }

  void enqueueOffline([String message = 'offline']) {
    enqueueError(HealthTimelineSourceException(message, isOffline: true));
  }

  /// Completa o request held mais antigo com [page].
  void completeNext(HealthTimelinePage page) {
    if (_held.isEmpty) {
      throw StateError('Nenhum request pendente para completeNext');
    }
    final pending = _held.removeAt(0);
    pending.completer.complete(page);
  }

  /// Falha o request held mais antigo.
  void failNext(Object error) {
    if (_held.isEmpty) {
      throw StateError('Nenhum request pendente para failNext');
    }
    final pending = _held.removeAt(0);
    pending.completer.completeError(error);
  }

  /// Completa o request held cujo [match] retorna true (primeiro).
  void completeMatching(
    bool Function(HealthTimelineQuery query) match,
    HealthTimelinePage page,
  ) {
    final index = _held.indexWhere((p) => match(p.query));
    if (index < 0) {
      throw StateError('Nenhum request held correspondente');
    }
    final pending = _held.removeAt(index);
    pending.completer.complete(page);
  }

  void failMatching(
    bool Function(HealthTimelineQuery query) match,
    Object error,
  ) {
    final index = _held.indexWhere((p) => match(p.query));
    if (index < 0) {
      throw StateError('Nenhum request held correspondente');
    }
    final pending = _held.removeAt(index);
    pending.completer.completeError(error);
  }

  int get pendingCount => _held.length;

  List<HealthTimelineQuery> get pendingQueries =>
      _held.map((e) => e.query).toList(growable: false);

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    requests.add(query);

    final custom = handler;
    if (custom != null) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      return custom(query);
    }

    if (holdResponses) {
      final completer = Completer<HealthTimelinePage>();
      _held.add(_PendingRequest(query: query, completer: completer));
      return completer.future;
    }

    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }

    if (_queue.isEmpty) {
      throw StateError(
        'FakeHealthTimelineSource: sem resposta enfileirada para $query',
      );
    }
    final next = _queue.removeAt(0);
    if (next.error != null) {
      throw next.error!;
    }
    return next.page!;
  }

  void reset() {
    requests.clear();
    _queue.clear();
    for (final p in _held) {
      if (!p.completer.isCompleted) {
        p.completer.completeError(StateError('source reset'));
      }
    }
    _held.clear();
    holdResponses = false;
    delay = Duration.zero;
    handler = null;
  }
}

class _QueuedResponse {
  _QueuedResponse.page(this.page) : error = null;
  _QueuedResponse.error(this.error) : page = null;

  final HealthTimelinePage? page;
  final Object? error;
}

class _PendingRequest {
  _PendingRequest({required this.query, required this.completer});

  final HealthTimelineQuery query;
  final Completer<HealthTimelinePage> completer;
}
