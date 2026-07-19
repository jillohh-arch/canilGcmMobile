import 'package:flutter/foundation.dart';

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
class HealthNutritionReadController extends ChangeNotifier {
  HealthNutritionReadController({
    required CoexistenceNutritionReadSource source,
    DateTime Function()? clock,
  }) : _source = source,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final CoexistenceNutritionReadSource _source;
  final DateTime Function() _clock;

  NutritionReadResult<NutritionCoexistenceSnapshot> _snapshotResult =
      const NutritionReadResult.loading();
  NutritionReadResult<NutritionTodayReadModel>? _todayResult;

  String? _activeDogId;
  DateTime? _mealsFrom;
  DateTime? _mealsTo;
  int _generation = 0;
  bool _disposed = false;
  bool _loading = false;

  NutritionReadResult<NutritionCoexistenceSnapshot> get snapshotResult =>
      _snapshotResult;

  NutritionReadResult<NutritionTodayReadModel>? get todayResult => _todayResult;

  String? get activeDogId => _activeDogId;

  bool get isLoading =>
      _loading || _snapshotResult.status == NutritionReadStatus.loading;

  NutritionCoexistenceSnapshot? get snapshotOrNull =>
      _snapshotResult.valueOrNull;

  NutritionTodayReadModel? get todayOrNull => _todayResult?.valueOrNull;

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
  }) async {
    if (!_isCurrent(generation, dogId)) return;

    _loading = true;
    _setSnapshot(
      const NutritionReadResult.loading(message: 'Carregando nutrição…'),
    );
    _todayResult = const NutritionReadResult.loading();

    try {
      final result = await _source.loadSnapshot(
        dogId,
        mealsFrom: mealsFrom,
        mealsTo: mealsTo,
      );
      if (!_isCurrent(generation, dogId)) return;

      _setSnapshot(result);

      final today = await _source.loadToday(dogId, serverNow: _clock());
      if (!_isCurrent(generation, dogId)) return;
      _todayResult = today;
      _safeNotify();
    } catch (e, st) {
      assert(() {
        debugPrint(
          '[HealthNutritionReadController] load falhou dog=$dogId: $e\n$st',
        );
        return true;
      }());
      if (!_isCurrent(generation, dogId)) return;
      _setSnapshot(
        NutritionReadResult.error(
          message: e.toString(),
          code: 'nutrition_read_controller_exception',
        ),
      );
      _todayResult = NutritionReadResult.error(
        message: e.toString(),
        code: 'nutrition_read_controller_exception',
      );
    } finally {
      if (_isCurrent(generation, dogId)) {
        _loading = false;
        _safeNotify();
      }
    }
  }

  void _setSnapshot(NutritionReadResult<NutritionCoexistenceSnapshot> next) {
    if (_disposed) return;
    _snapshotResult = next;
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
}
