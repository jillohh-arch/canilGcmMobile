import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_state.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';

/// Controller do Resumo Health v1 (ChangeNotifier).
///
/// Responsabilidades:
/// - associar estado ao [dogId] ativo;
/// - cancelar observação anterior na troca de K9;
/// - ignorar emissões/erros/done tardios (geração + dogId);
/// - [refresh] para retry/reconexão do dogId ativo;
/// - não calcular prontidão;
/// - não conhecer Firebase/Firestore.
///
/// ## Offline vs metadata.isOffline
/// - [HealthSummaryOffline]: estado **atual do canal/UI** (falha offline ou
///   snapshot emitido com metadata offline).
/// - [HealthSummarySourceMetadata.isOffline]: origem do **payload** recebido.
/// - Cache de A nunca é reutilizado para B.
class HealthSummaryController extends ChangeNotifier {
  HealthSummaryController({required HealthSummarySource source})
    : _source = source;

  final HealthSummarySource _source;

  HealthSummaryState _state = const HealthSummaryInitial();
  StreamSubscription<HealthSummaryViewData?>? _subscription;
  String? _activeDogId;
  int _generation = 0;
  bool _disposed = false;

  /// Último payload válido por dogId (cache em memória de sessão).
  final Map<String, HealthSummaryViewData> _lastDataByDogId = {};

  HealthSummaryState get state => _state;

  String? get activeDogId => _activeDogId;

  /// Seleciona o K9 do Resumo.
  ///
  /// Mesmo [dogId] com subscription ainda ativa: no-op (evita double watch).
  /// Após [onDone] (subscription limpa) ou para outro dogId: reconecta.
  /// Para retry após error/offline com sub ainda aberta, use [refresh].
  void selectDog(String dogId) {
    final normalized = _normalizeDogId(dogId);
    if (_disposed) return;

    if (_activeDogId == normalized && _subscription != null) {
      return;
    }

    _startWatch(normalized);
  }

  /// Reabre a observação do [activeDogId] (retry / pull-to-refresh).
  ///
  /// Cancela a subscription atual e inicia novo ciclo loading → …,
  /// mesmo se o dogId não mudou. Não afeta outro K9.
  void refresh() {
    if (_disposed) return;
    final id = _activeDogId;
    if (id == null) {
      throw StateError('refresh exige um dogId ativo (chame selectDog antes)');
    }
    _startWatch(id);
  }

  void _startWatch(String dogId) {
    _activeDogId = dogId;
    final generation = ++_generation;

    unawaited(_subscription?.cancel());
    _subscription = null;

    _setState(HealthSummaryLoading(dogId: dogId));

    _subscription = _source
        .watchSummary(dogId)
        .listen(
          (payload) => _onData(generation, dogId, payload),
          onError: (Object error, StackTrace stackTrace) =>
              _onError(generation, dogId, error),
          onDone: () => _onDone(generation, dogId),
          cancelOnError: false,
        );
  }

  void _onData(int generation, String dogId, HealthSummaryViewData? payload) {
    if (!_isCurrent(generation, dogId)) return;

    if (payload == null) {
      _setState(HealthSummaryEmpty(dogId: dogId));
      return;
    }

    if (payload.dogId.trim() != dogId) return;

    _lastDataByDogId[dogId] = payload;

    // Snapshot marcado offline pela fonte → estado de canal offline com dados.
    if (payload.metadata.isOffline) {
      _setState(HealthSummaryOffline(dogId: dogId, cachedData: payload));
      return;
    }

    _setState(HealthSummaryData(data: payload));
  }

  void _onError(int generation, String dogId, Object error) {
    if (!_isCurrent(generation, dogId)) return;

    final isOffline = error is HealthSummarySourceException && error.isOffline;
    final message = error is HealthSummarySourceException
        ? error.message
        : error.toString();

    // Cache estritamente do mesmo dogId.
    final cached = _lastDataByDogId[dogId];

    if (isOffline) {
      _setState(HealthSummaryOffline(dogId: dogId, cachedData: cached));
      return;
    }

    // Erro após data: preserva lastKnownData do mesmo dogId (não muda readiness).
    _setState(
      HealthSummaryError(dogId: dogId, message: message, lastKnownData: cached),
    );
  }

  void _onDone(int generation, String dogId) {
    if (!_isCurrent(generation, dogId)) return;
    // Permite selectDog(mesmo id) / refresh reconectar após fim natural.
    _subscription = null;
  }

  bool _isCurrent(int generation, String dogId) {
    if (_disposed) return false;
    if (generation != _generation) return false;
    if (_activeDogId != dogId) return false;
    return true;
  }

  void _setState(HealthSummaryState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  static String _normalizeDogId(String dogId) {
    final normalized = dogId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(dogId, 'dogId', 'dogId não pode ser vazio');
    }
    return normalized;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
  }

  @visibleForTesting
  bool get isDisposedForTest => _disposed;

  @visibleForTesting
  int get generationForTest => _generation;

  @visibleForTesting
  bool get hasActiveSubscriptionForTest => _subscription != null;
}
