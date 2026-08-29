import 'dart:async';

import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';

/// Fake controlável apenas para testes da Fase 2B.
///
/// Controllers permanecem abertos após cancel da subscription para permitir
/// simular emissões tardias (race A→B).
class FakeHealthSummarySource implements HealthSummarySource {
  final Map<String, StreamController<HealthSummaryViewData?>> _controllers = {};
  final List<String> watchCalls = [];
  final List<String> cancelledDogIds = [];

  @override
  Stream<HealthSummaryViewData?> watchSummary(String dogId) {
    watchCalls.add(dogId);
    final controller = _controllers.putIfAbsent(
      dogId,
      () => StreamController<HealthSummaryViewData?>.broadcast(),
    );

    // Envolve para detectar cancel da subscription sem fechar o controller.
    late StreamController<HealthSummaryViewData?> bridge;
    bridge = StreamController<HealthSummaryViewData?>(
      onListen: () {
        final sub = controller.stream.listen(
          bridge.add,
          onError: bridge.addError,
          onDone: bridge.close,
        );
        bridge.onCancel = () async {
          cancelledDogIds.add(dogId);
          await sub.cancel();
        };
      },
    );
    return bridge.stream;
  }

  void emit(String dogId, HealthSummaryViewData? data) {
    final controller = _controllers[dogId];
    if (controller == null || controller.isClosed) {
      throw StateError('Sem stream criada para $dogId');
    }
    controller.add(data);
  }

  void emitError(String dogId, Object error) {
    final controller = _controllers[dogId];
    if (controller == null || controller.isClosed) {
      throw StateError('Sem stream criada para $dogId');
    }
    controller.addError(error);
  }

  /// Fecha a stream do [dogId] (dispara onDone nos listeners).
  void complete(String dogId) {
    final controller = _controllers[dogId];
    if (controller == null || controller.isClosed) {
      throw StateError('Sem stream criada para $dogId');
    }
    unawaited(controller.close());
    _controllers.remove(dogId);
  }

  Future<void> disposeAll() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();
  }
}
