import 'dart:async';

import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_result.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_source.dart';

/// Fake do Global Agenda Source.
///
/// Registra TODA chamada em [requests] — é assim que os testes provam que
/// catálogo vazio não emite query e que `own_records` nunca chega ao reader.
///
/// Falha explicitamente quando usado sem resposta enfileirada: fila vazia é
/// erro de teste, não resultado vazio.
class FakeHealthScheduleGlobalSource implements HealthScheduleGlobalSource {
  final List<HealthScheduleGlobalQuery> requests = [];
  final List<Completer<HealthScheduleGlobalResult>> _pending = [];
  final List<Object> _queue = [];

  /// Quando `true`, respostas ficam pendentes até [completeNext]/[failNext].
  bool holdResponses = false;

  int get callCount => requests.length;
  int get pendingCount => _pending.length;

  void enqueueResult(HealthScheduleGlobalResult result) => _queue.add(result);

  void enqueueItems(
    List<HealthScheduleItem> items, {
    bool truncated = false,
    int queriedChunks = 1,
  }) {
    _queue.add(
      HealthScheduleGlobalResult(
        items: items,
        truncated: truncated,
        queriedChunks: queriedChunks,
      ),
    );
  }

  void enqueueError(Object error) => _queue.add(_FakeError(error));

  /// Completa um request pendente.
  ///
  /// [index] permite responder FORA DE ORDEM, que é o cenário perigoso de
  /// stale response: o request antigo chegando DEPOIS do novo.
  void completeNext(HealthScheduleGlobalResult result, {int index = 0}) {
    if (_pending.isEmpty) {
      throw StateError('Nenhum request pendente para completeNext');
    }
    _pending.removeAt(index).complete(result);
  }

  void completeNextItems(
    List<HealthScheduleItem> items, {
    bool truncated = false,
    int index = 0,
  }) {
    completeNext(
      HealthScheduleGlobalResult(
        items: items,
        truncated: truncated,
        queriedChunks: 1,
      ),
      index: index,
    );
  }

  void failNext(Object error) {
    if (_pending.isEmpty) {
      throw StateError('Nenhum request pendente para failNext');
    }
    _pending.removeAt(0).completeError(error);
  }

  void reset() {
    requests.clear();
    _pending.clear();
    _queue.clear();
    holdResponses = false;
  }

  @override
  Future<HealthScheduleGlobalResult> loadGlobal(
    HealthScheduleGlobalQuery query,
  ) {
    requests.add(query);

    if (holdResponses) {
      final completer = Completer<HealthScheduleGlobalResult>();
      _pending.add(completer);
      return completer.future;
    }

    if (_queue.isEmpty) {
      throw StateError(
        'FakeHealthScheduleGlobalSource: fila vazia para '
        '${query.authorizedDogIds}',
      );
    }
    final next = _queue.removeAt(0);
    if (next is _FakeError) return Future.error(next.error);
    return Future.value(next as HealthScheduleGlobalResult);
  }
}

final class _FakeError {
  const _FakeError(this.error);
  final Object error;
}
