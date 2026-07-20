import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_outcome.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_pending_intent.dart';

/// Coordenador de apresentação das mutações canônicas de Nutrição (Gate 3).
///
/// ## Controller lifecycle ≠ intent lifecycle
///
/// - [dispose] é técnico (widget/nav) — **não** descarta pending intent.
/// - [discardIntent] é semântico (usuário abandonou o registro).
/// - Após erro incerto (`unavailable` / `network`), a [HealthNutritionPendingIntent]
///   permanece no [HealthNutritionPendingIntentHolder] e pode restaurar a mesma
///   [operationId] em um controller recriado.
///
/// Demais: double-submit, wasNoOp=sucesso, success vs refresh failure.
class HealthNutritionMutationController extends ChangeNotifier {
  HealthNutritionMutationController({
    required HealthNutritionMutationGateway gateway,
    Future<void> Function()? onRefreshAfterSuccess,
    String Function()? operationIdFactory,
    HealthNutritionPendingIntentHolder? pendingIntentHolder,
  }) : _gateway = gateway,
       _onRefreshAfterSuccess = onRefreshAfterSuccess,
       _operationIdFactory = operationIdFactory ?? (() => const Uuid().v4()),
       _pendingHolder =
           pendingIntentHolder ?? HealthNutritionPendingIntentHolder();

  final HealthNutritionMutationGateway _gateway;
  final Future<void> Function()? _onRefreshAfterSuccess;
  final String Function() _operationIdFactory;
  final HealthNutritionPendingIntentHolder _pendingHolder;

  bool _submitting = false;
  bool _disposed = false;

  HealthNutritionMutationResult? _lastResult;
  HealthNutritionMutationFailure? _lastError;

  bool get isSubmitting => _submitting;
  HealthNutritionMutationResult? get lastResult => _lastResult;
  HealthNutritionMutationFailure? get lastError => _lastError;

  /// Pending intent atual (pode viver fora deste controller via holder).
  HealthNutritionPendingIntent? get pendingIntent => _pendingHolder.value;

  /// Holder compartilhado (composition root / restauração).
  HealthNutritionPendingIntentHolder get pendingIntentHolder => _pendingHolder;

  /// Garante operationId estável para a intenção atual.
  ///
  /// - Mesma fingerprint (ex.: controller recriado / remount) → reutiliza.
  /// - Fingerprint diferente com pending ainda ativa → **não sobrescreve**;
  ///   exige [discardIntent] explícito (fail-closed).
  /// - Sem pending → gera nova key.
  String ensureOperationIdForIntent({
    required String intentFingerprint,
    required HealthNutritionMutationKind kind,
    HealthNutritionPendingPlannedMealDraft? plannedMealDraft,
  }) {
    final fp = intentFingerprint.trim();
    final existing = _pendingHolder.value;
    if (existing != null && existing.operationId.isNotEmpty) {
      if (existing.intentFingerprint == fp) {
        if (existing.kind != kind ||
            (existing.plannedMealDraft == null && plannedMealDraft != null)) {
          _pendingHolder.value = existing.copyWith(
            kind: kind,
            plannedMealDraft: plannedMealDraft,
          );
        }
        return existing.operationId;
      }
      throw const HealthNutritionMutationValidation(
        'Já existe uma intenção de nutrição pendente. '
        'Descarte-a antes de iniciar outra operação.',
        detailCode: 'pending_intent_incompatible',
      );
    }
    final next = _operationIdFactory().trim();
    _pendingHolder.value = HealthNutritionPendingIntent(
      operationId: next,
      intentFingerprint: fp,
      kind: kind,
      plannedMealDraft: plannedMealDraft,
    );
    return next;
  }

  /// Descarte **semântico** da intenção (usuário abandonou o registro).
  ///
  /// Diferente de [dispose] técnico.
  void discardIntent() {
    _pendingHolder.clear();
  }

  /// Alias explícito de descarte semântico (compatibilidade de API).
  void endIntent() => discardIntent();

  Future<HealthNutritionMutationUiOutcome> createPlannedMeal({
    required String dogId,
    required String planId,
    required String plannedMealId,
    required double offeredGrams,
    required ParsedHealthEnum<MealAcceptance> acceptance,
    required DateTime fedAt,
    double? consumedGrams,
    String? observations,
    List<String>? attachmentRefs,
  }) async {
    if (_disposed || _submitting) {
      return const HealthNutritionMutationUiBlocked();
    }

    late final CreatePlannedMealLogCommand command;
    try {
      final draftFp = CreatePlannedMealLogCommand(
        dogId: dogId,
        planId: planId,
        plannedMealId: plannedMealId,
        offeredGrams: offeredGrams,
        acceptance: acceptance,
        fedAt: fedAt,
        operationId: 'pending',
        consumedGrams: consumedGrams,
        observations: observations,
        attachmentRefs: attachmentRefs,
      ).intentFingerprint();
      final operationId = ensureOperationIdForIntent(
        intentFingerprint: draftFp,
        kind: HealthNutritionMutationKind.plannedMeal,
        plannedMealDraft: HealthNutritionPendingPlannedMealDraft(
          dogId: dogId,
          planId: planId,
          plannedMealId: plannedMealId,
          offeredGrams: offeredGrams,
          consumedGrams: consumedGrams,
          acceptance: acceptance,
          fedAt: fedAt,
          observations: observations,
        ),
      );
      command = CreatePlannedMealLogCommand(
        dogId: dogId,
        planId: planId,
        plannedMealId: plannedMealId,
        offeredGrams: offeredGrams,
        acceptance: acceptance,
        fedAt: fedAt,
        operationId: operationId,
        consumedGrams: consumedGrams,
        observations: observations,
        attachmentRefs: attachmentRefs,
      );
    } on HealthNutritionMutationFailure catch (e) {
      _lastError = e;
      return HealthNutritionMutationUiFailure(
        failure: e,
        userMessage: e.message,
      );
    }

    return _submitMeal(command: command, planned: true);
  }

  Future<HealthNutritionMutationUiOutcome> createAdhocMeal({
    required String dogId,
    required ParsedHealthEnum<MealPeriod> period,
    required double offeredGrams,
    required ParsedHealthEnum<MealAcceptance> acceptance,
    required DateTime fedAt,
    double? consumedGrams,
    String? observations,
    List<String>? attachmentRefs,
  }) async {
    if (_disposed || _submitting) {
      return const HealthNutritionMutationUiBlocked();
    }

    late final CreateAdhocMealLogCommand command;
    try {
      final draftFp = CreateAdhocMealLogCommand(
        dogId: dogId,
        period: period,
        offeredGrams: offeredGrams,
        acceptance: acceptance,
        fedAt: fedAt,
        operationId: 'pending',
        consumedGrams: consumedGrams,
        observations: observations,
        attachmentRefs: attachmentRefs,
      ).intentFingerprint();
      final operationId = ensureOperationIdForIntent(
        intentFingerprint: draftFp,
        kind: HealthNutritionMutationKind.adhocMeal,
      );
      command = CreateAdhocMealLogCommand(
        dogId: dogId,
        period: period,
        offeredGrams: offeredGrams,
        acceptance: acceptance,
        fedAt: fedAt,
        operationId: operationId,
        consumedGrams: consumedGrams,
        observations: observations,
        attachmentRefs: attachmentRefs,
      );
    } on HealthNutritionMutationFailure catch (e) {
      _lastError = e;
      return HealthNutritionMutationUiFailure(
        failure: e,
        userMessage: e.message,
      );
    }

    return _submitMeal(command: command, planned: false);
  }

  Future<HealthNutritionMutationUiOutcome> createSupplement({
    required String dogId,
    required String supplementName,
    required double dose,
    required ParsedHealthEnum<SupplementDoseUnit> unit,
    required DateTime administeredAt,
    String? nutritionPlanId,
    String? supplementRegimenId,
    String? notes,
    String? batchNumber,
    String? protocolId,
  }) async {
    if (_disposed || _submitting) {
      return const HealthNutritionMutationUiBlocked();
    }

    late final CreateSupplementLogCommand command;
    try {
      final draftFp = CreateSupplementLogCommand(
        dogId: dogId,
        supplementName: supplementName,
        dose: dose,
        unit: unit,
        administeredAt: administeredAt,
        operationId: 'pending',
        nutritionPlanId: nutritionPlanId,
        supplementRegimenId: supplementRegimenId,
        notes: notes,
        batchNumber: batchNumber,
        protocolId: protocolId,
      ).intentFingerprint();
      final operationId = ensureOperationIdForIntent(
        intentFingerprint: draftFp,
        kind: HealthNutritionMutationKind.supplement,
      );
      command = CreateSupplementLogCommand(
        dogId: dogId,
        supplementName: supplementName,
        dose: dose,
        unit: unit,
        administeredAt: administeredAt,
        operationId: operationId,
        nutritionPlanId: nutritionPlanId,
        supplementRegimenId: supplementRegimenId,
        notes: notes,
        batchNumber: batchNumber,
        protocolId: protocolId,
      );
    } on HealthNutritionMutationFailure catch (e) {
      _lastError = e;
      return HealthNutritionMutationUiFailure(
        failure: e,
        userMessage: e.message,
      );
    }

    _submitting = true;
    _lastError = null;
    _safeNotify();

    try {
      final result = await _gateway.createSupplementLog(command);
      _lastResult = result;
      return await _handleResult(result);
    } on HealthNutritionMutationFailure catch (e) {
      _lastError = e;
      return HealthNutritionMutationUiFailure(
        failure: e,
        userMessage: e.message,
      );
    } catch (e, st) {
      _logUnexpected(e, st);
      const failure = HealthNutritionMutationUnexpected();
      _lastError = failure;
      return const HealthNutritionMutationUiFailure(
        failure: failure,
        userMessage: 'Falha inesperada na mutação de nutrição.',
      );
    } finally {
      _submitting = false;
      _safeNotify();
    }
  }

  Future<HealthNutritionMutationUiOutcome> _submitMeal({
    required Object command,
    required bool planned,
  }) async {
    _submitting = true;
    _lastError = null;
    _safeNotify();

    try {
      final HealthNutritionMutationResult result;
      if (planned) {
        result = await _gateway.createPlannedMealLog(
          command as CreatePlannedMealLogCommand,
        );
      } else {
        result = await _gateway.createAdhocMealLog(
          command as CreateAdhocMealLogCommand,
        );
      }
      _lastResult = result;
      return await _handleResult(result);
    } on HealthNutritionMutationFailure catch (e) {
      _lastError = e;
      return HealthNutritionMutationUiFailure(
        failure: e,
        userMessage: e.message,
      );
    } catch (e, st) {
      _logUnexpected(e, st);
      const failure = HealthNutritionMutationUnexpected();
      _lastError = failure;
      return const HealthNutritionMutationUiFailure(
        failure: failure,
        userMessage: 'Falha inesperada na mutação de nutrição.',
      );
    } finally {
      _submitting = false;
      _safeNotify();
    }
  }

  Future<HealthNutritionMutationUiOutcome> _handleResult(
    HealthNutritionMutationResult result,
  ) async {
    switch (result) {
      case CreateMealLogSuccess():
        // Sucesso confirmado encerra a intenção (nova ação → nova key).
        discardIntent();
        final refreshFailed = await _refreshAfterSuccess();
        return HealthNutritionMutationUiSuccess.fromMeal(
          remote: result,
          refreshFailed: refreshFailed,
          refreshWarning: refreshFailed
              ? 'Registro salvo, mas a atualização da tela falhou.'
              : null,
        );
      case CreateSupplementLogSuccess():
        discardIntent();
        final refreshFailed = await _refreshAfterSuccess();
        return HealthNutritionMutationUiSuccess.fromSupplement(
          remote: result,
          refreshFailed: refreshFailed,
          refreshWarning: refreshFailed
              ? 'Registro salvo, mas a atualização da tela falhou.'
              : null,
        );
      case HealthNutritionMutationErrorResult(:final failure):
        _lastError = failure;
        // Incerto ou determinístico: NÃO discardIntent — key permanece no holder.
        return HealthNutritionMutationUiFailure(
          failure: failure,
          userMessage: failure.message,
        );
    }
  }

  Future<bool> _refreshAfterSuccess() async {
    final cb = _onRefreshAfterSuccess;
    if (cb == null) {
      return false;
    }
    try {
      await cb();
      return false;
    } catch (e, st) {
      assert(() {
        debugPrint(
          '[HealthNutritionMutationController] refresh pós-sucesso: $e\n$st',
        );
        return true;
      }());
      return true;
    }
  }

  void _logUnexpected(Object error, StackTrace stackTrace) {
    assert(() {
      debugPrint(
        '[HealthNutritionMutationController] inesperado: $error\n$stackTrace',
      );
      return true;
    }());
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Lifecycle **técnico**. Não equivale a [discardIntent].
  ///
  /// A pending intent no holder sobrevive para restauração.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // NÃO limpar _pendingHolder — dispose ≠ discard semântico.
    super.dispose();
  }

  @visibleForTesting
  bool get isDisposedForTest => _disposed;

  @visibleForTesting
  String? get activeOperationIdForTest => _pendingHolder.value?.operationId;

  @visibleForTesting
  String? get activeIntentFingerprintForTest =>
      _pendingHolder.value?.intentFingerprint;
}
