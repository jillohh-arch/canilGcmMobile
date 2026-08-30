import 'package:flutter/foundation.dart';

import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_models.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_provider.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Read controller canônico de Nutrição (5D Gate 4).
// dogId-keyed · generation token · dispose-safe · sem mutation state.
// ─────────────────────────────────────────────────────────────────────────────

/// Controller de leitura de coexistência Nutrição Health v1.
///
/// ## Contrato
/// - Estado sempre associado a [activeDogId] (D29).
/// - [selectDog] / [refresh] usam generation token: resposta stale de dog A
///   nunca sobrescreve dog B.
/// - Após [dispose], Futures antigas não chamam [notifyListeners].
/// - Não mistura mutation state (isso é [HealthNutritionMutationController]).
enum HealthNutritionTemporalState { synchronizing, fresh, stale, unavailable }

class HealthNutritionReadController extends ChangeNotifier {
  HealthNutritionReadController({
    required CoexistenceNutritionReadSource source,
    AuthoritativeTimeProvider? authoritativeTimeProvider,
    @visibleForTesting DateTime Function()? clock,
  }) : _source = source,
       _authoritativeTimeProvider = authoritativeTimeProvider,
       _testClock = clock;

  final CoexistenceNutritionReadSource _source;
  final AuthoritativeTimeProvider? _authoritativeTimeProvider;
  final DateTime Function()? _testClock;

  NutritionReadResult<NutritionCoexistenceSnapshot> _snapshotResult =
      const NutritionReadResult.loading();
  NutritionReadResult<NutritionTodayReadModel>? _todayResult;

  String? _activeDogId;
  DateTime? _mealsFrom;
  DateTime? _mealsTo;
  int _generation = 0;
  bool _disposed = false;
  bool _loading = false;
  HealthNutritionTemporalState _temporalState =
      HealthNutritionTemporalState.synchronizing;
  AuthoritativeTimeFailure? _temporalFailure;

  NutritionReadResult<NutritionCoexistenceSnapshot> get snapshotResult =>
      _snapshotResult;

  NutritionReadResult<NutritionTodayReadModel>? get todayResult => _todayResult;

  String? get activeDogId => _activeDogId;

  bool get isLoading =>
      _loading || _snapshotResult.status == NutritionReadStatus.loading;

  NutritionCoexistenceSnapshot? get snapshotOrNull =>
      _snapshotResult.valueOrNull;

  NutritionTodayReadModel? get todayOrNull => _todayResult?.valueOrNull;

  HealthNutritionTemporalState get temporalState => _temporalState;

  AuthoritativeTimeFailure? get temporalFailure => _temporalFailure;

  bool get temporalActionsAllowed =>
      _temporalState == HealthNutritionTemporalState.fresh;

  String? get temporalDiagnosticTitle => switch (_temporalState) {
    HealthNutritionTemporalState.synchronizing =>
      'Atualizando horário confiável',
    HealthNutritionTemporalState.stale => 'Horário aguardando atualização',
    HealthNutritionTemporalState.unavailable =>
      'Horário confiável indisponível',
    HealthNutritionTemporalState.fresh when _temporalFailure != null =>
      'Falha ao atualizar o horário',
    HealthNutritionTemporalState.fresh => null,
  };

  String? get temporalDiagnosticMessage => switch (_temporalState) {
    HealthNutritionTemporalState.synchronizing =>
      'Ações dependentes de horário permanecem bloqueadas até o fim da sincronização.',
    HealthNutritionTemporalState.stale =>
      'Os dados permanecem disponíveis para consulta. Atualize a sincronização antes de registrar novas ações.',
    HealthNutritionTemporalState.unavailable =>
      'Os dados podem ser consultados, mas ações dependentes de horário estão temporariamente bloqueadas.',
    HealthNutritionTemporalState.fresh when _temporalFailure != null =>
      _temporalFailure!.message,
    HealthNutritionTemporalState.fresh => null,
  };

  /// Seleciona o K9 e carrega o snapshot de coexistência.
  ///
  /// Respostas de gerações anteriores são descartadas (stale protection).
  Future<void> selectDog(
    String dogId, {
    DateTime? mealsFrom,
    DateTime? mealsTo,
  }) async {
    if (_disposed) return;
    final normalized = _normalizeDogId(dogId);
    _activeDogId = normalized;
    _mealsFrom = mealsFrom;
    _mealsTo = mealsTo;
    final generation = ++_generation;
    await _load(
      generation: generation,
      dogId: normalized,
      mealsFrom: mealsFrom,
      mealsTo: mealsTo,
      forceTimeSync: false,
    );
  }

  /// Recarrega o [activeDogId] atual (read-after-write / pull-to-refresh).
  Future<void> refresh() async {
    if (_disposed) return;
    final id = _activeDogId;
    if (id == null) {
      throw StateError(
        'refresh exige dogId ativo (chame selectDog ou ensureDogAndRefresh)',
      );
    }
    final generation = ++_generation;
    await _load(
      generation: generation,
      dogId: id,
      mealsFrom: _mealsFrom,
      mealsTo: _mealsTo,
      forceTimeSync: true,
    );
  }

  /// Garante dogId ativo e recarrega — usado pelo callback pós-mutation.
  Future<void> ensureDogAndRefresh(String dogId) async {
    if (_disposed) return;
    final normalized = _normalizeDogId(dogId);
    if (_activeDogId != normalized) {
      await selectDog(normalized, mealsFrom: _mealsFrom, mealsTo: _mealsTo);
      return;
    }
    await refresh();
  }

  Future<void> _load({
    required int generation,
    required String dogId,
    DateTime? mealsFrom,
    DateTime? mealsTo,
    required bool forceTimeSync,
  }) async {
    if (!_isCurrent(generation, dogId)) return;

    _loading = true;
    _temporalState = HealthNutritionTemporalState.synchronizing;
    _temporalFailure = null;
    if (_snapshotResult.valueOrNull == null) {
      _snapshotResult = const NutritionReadResult.loading(
        message: 'Carregando nutrição…',
      );
      _todayResult = const NutritionReadResult.loading();
    }
    _safeNotify();

    DateTime? referenceNow;
    final provider = _authoritativeTimeProvider;
    final testClock = _testClock;
    if (provider != null) {
      final syncResult = await provider.synchronize(force: forceTimeSync);
      if (!_isCurrent(generation, dogId)) return;
      if (syncResult is AuthoritativeTimeSyncFailure) {
        _temporalFailure = syncResult.failure;
      }
      switch (provider.status) {
        case AuthoritativeTimeStatus.fresh:
          _temporalState = HealthNutritionTemporalState.fresh;
          referenceNow = provider.nowFreshUtc();
        case AuthoritativeTimeStatus.stale:
          _temporalState = HealthNutritionTemporalState.stale;
          referenceNow = provider.nowReadOnlyUtc();
        case AuthoritativeTimeStatus.neverSynchronized:
        case AuthoritativeTimeStatus.synchronizing:
        case AuthoritativeTimeStatus.expired:
        case AuthoritativeTimeStatus.failed:
          _temporalState = HealthNutritionTemporalState.unavailable;
      }
    } else if (testClock != null) {
      _temporalState = HealthNutritionTemporalState.fresh;
      referenceNow = testClock().toUtc();
    } else {
      _temporalState = HealthNutritionTemporalState.unavailable;
    }

    NutritionReadResult<NutritionCoexistenceSnapshot> snapshot;
    try {
      snapshot = await _source.loadSnapshot(
        dogId,
        mealsFrom: mealsFrom,
        mealsTo: mealsTo,
      );
    } catch (e, st) {
      assert(() {
        debugPrint(
          '[HealthNutritionReadController] snapshot falhou dog=$dogId: $e\n$st',
        );
        return true;
      }());
      snapshot = NutritionReadResult.error(
        message: e.toString(),
        code: 'nutrition_snapshot_controller_exception',
      );
    }
    if (!_isCurrent(generation, dogId)) return;

    NutritionReadResult<NutritionTodayReadModel> today;
    try {
      if (referenceNow == null) {
        today = const NutritionReadResult.error(
          message: 'Horário confiável indisponível.',
          code: 'authoritative_time_unavailable',
        );
      } else {
        today = _source.projectTodayFromSnapshot(
          dogId: dogId,
          snapshotResult: snapshot,
          serverNow: referenceNow,
        );
        if (_temporalState == HealthNutritionTemporalState.stale &&
            today.valueOrNull != null) {
          today = NutritionReadResult.degraded(
            today.valueOrNull!,
            message:
                'Horário aguardando atualização. Os dados permanecem disponíveis para consulta.',
            code: 'authoritative_time_stale',
          );
        }
      }
    } catch (e, st) {
      assert(() {
        debugPrint(
          '[HealthNutritionReadController] today falhou dog=$dogId: $e\n$st',
        );
        return true;
      }());
      today = NutritionReadResult.error(
        message: e.toString(),
        code: 'nutrition_today_controller_exception',
      );
    }
    if (!_isCurrent(generation, dogId)) return;

    // Publica os dois resultados juntos: ambos derivam do mesmo snapshot.
    _snapshotResult = snapshot;
    _todayResult = today;
    _loading = false;
    _safeNotify();
  }

  bool _isCurrent(int generation, String dogId) {
    if (_disposed) return false;
    if (generation != _generation) return false;
    if (_activeDogId != dogId) return false;
    return true;
  }

  void _safeNotify() {
    if (_disposed) return;
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
    // Incrementa generation para invalidar futures em voo.
    _generation++;
    super.dispose();
  }

  @visibleForTesting
  bool get isDisposedForTest => _disposed;

  @visibleForTesting
  int get generationForTest => _generation;

  @visibleForTesting
  AuthoritativeTimeProvider? get authoritativeTimeProviderForTest =>
      _authoritativeTimeProvider;
}
