import 'dart:async';

import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_page.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';

/// Fake controlável para testes da Agenda (Fase 4A).
class FakeHealthScheduleSource implements HealthScheduleSource {
  final List<HealthScheduleQuery> requests = [];
  final List<_QueuedResponse> _queue = [];
  final List<_PendingRequest> _held = [];

  bool holdResponses = false;
  Duration delay = Duration.zero;
  Future<HealthSchedulePage> Function(HealthScheduleQuery query)? handler;

  void enqueuePage(HealthSchedulePage page) {
    _queue.add(_QueuedResponse.page(page));
  }

  void enqueueError(Object error) {
    _queue.add(_QueuedResponse.error(error));
  }

  void enqueueOffline([String message = 'offline']) {
    enqueueError(HealthScheduleSourceException(message, isOffline: true));
  }

  void completeNext(HealthSchedulePage page) {
    if (_held.isEmpty) {
      throw StateError('Nenhum request pendente para completeNext');
    }
    final pending = _held.removeAt(0);
    pending.completer.complete(page);
  }

  void failNext(Object error) {
    if (_held.isEmpty) {
      throw StateError('Nenhum request pendente para failNext');
    }
    final pending = _held.removeAt(0);
    pending.completer.completeError(error);
  }

  void completeMatching(
    bool Function(HealthScheduleQuery query) match,
    HealthSchedulePage page,
  ) {
    final index = _held.indexWhere((p) => match(p.query));
    if (index < 0) {
      throw StateError('Nenhum request held correspondente');
    }
    final pending = _held.removeAt(index);
    pending.completer.complete(page);
  }

  void failMatching(
    bool Function(HealthScheduleQuery query) match,
    Object error,
  ) {
    final index = _held.indexWhere((p) => match(p.query));
    if (index < 0) {
      throw StateError('Nenhum request held correspondente');
    }
    final pending = _held.removeAt(index);
    pending.completer.completeError(error);
  }

  void reset() {
    requests.clear();
    _queue.clear();
    for (final h in _held) {
      if (!h.completer.isCompleted) {
        h.completer.completeError(StateError('reset'));
      }
    }
    _held.clear();
    holdResponses = false;
    delay = Duration.zero;
    handler = null;
  }

  @override
  Future<HealthSchedulePage> loadPage(HealthScheduleQuery query) async {
    requests.add(query);
    if (handler != null) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      return handler!(query);
    }
    if (holdResponses) {
      final completer = Completer<HealthSchedulePage>();
      _held.add(_PendingRequest(query: query, completer: completer));
      return completer.future;
    }
    if (_queue.isEmpty) {
      throw StateError('FakeHealthScheduleSource: fila vazia para $query');
    }
    final next = _queue.removeAt(0);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (next.error != null) {
      return Future<HealthSchedulePage>.error(next.error!);
    }
    return next.page!;
  }
}

class _QueuedResponse {
  _QueuedResponse.page(this.page) : error = null;
  _QueuedResponse.error(this.error) : page = null;

  final HealthSchedulePage? page;
  final Object? error;
}

class _PendingRequest {
  _PendingRequest({required this.query, required this.completer});

  final HealthScheduleQuery query;
  final Completer<HealthSchedulePage> completer;
}
