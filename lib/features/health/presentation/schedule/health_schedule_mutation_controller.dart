import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:canil_gcm/features/health/domain/health_schedule_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_action_availability.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_outcome.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_state.dart';

/// Coordenador de apresentação das mutações da Agenda Preventiva (Gate 5).
///
/// Responsabilidades:
/// - loading / double-submit por item e por create;
/// - geração e preservação de operationId / idempotencyKey por intenção;
/// - chamada exclusiva a [HealthScheduleMutationGateway];
/// - refresh obrigatório após sucesso;
/// - distinção mutation failure vs post-success refresh failure.
///
/// Não move regra de domínio para presentation. Não escreve Firestore.
class HealthScheduleMutationController extends ChangeNotifier {
  HealthScheduleMutationController({
    required HealthScheduleMutationGateway gateway,
    required HealthScheduleController scheduleController,
    String Function()? operationIdFactory,
  }) : _gateway = gateway,
       _scheduleController = scheduleController,
       _operationIdFactory = operationIdFactory ?? (() => const Uuid().v4());

  final HealthScheduleMutationGateway _gateway;
  final HealthScheduleController _scheduleController;
  final String Function() _operationIdFactory;

  final Set<String> _busyScheduleIds = <String>{};
  bool _createSubmitting = false;
  bool _disposed = false;

  /// Idempotency key da intenção de create atual (preservada em retry).
  String? _createIdempotencyKey;

  /// operationId por scheduleId da intenção de update em curso.
  final Map<String, String> _updateOperationIds = <String, String>{};

  /// operationId por scheduleId da intenção de complete em curso.
  final Map<String, String> _completeOperationIds = <String, String>{};

  /// operationId por scheduleId da intenção de cancel em curso.
  final Map<String, String> _cancelOperationIds = <String, String>{};

  bool get isCreateSubmitting => _createSubmitting;

  bool isItemBusy(String scheduleId) =>
      _busyScheduleIds.contains(scheduleId.trim());

  bool get hasAnyMutationInFlight =>
      _createSubmitting || _busyScheduleIds.isNotEmpty;

  // ── Intents / operation IDs ────────────────────────────────────────────

  /// Garante uma idempotencyKey estável para a sessão de create atual.
  ///
  /// Retry da mesma submissão reutiliza a mesma key. Nova intenção (após
  /// [endCreateIntent] ou sucesso) gera nova key.
  String ensureCreateIdempotencyKey() {
    final existing = _createIdempotencyKey;
    if (existing != null && existing.isNotEmpty) return existing;
    final next = _operationIdFactory().trim();
    _createIdempotencyKey = next;
    return next;
  }

  /// Descarta a intenção de create (dispose do formulário sem sucesso).
  void endCreateIntent() {
    _createIdempotencyKey = null;
  }

  /// Inicia/obtém operationId estável da edição do item.
  String ensureUpdateOperationId(String scheduleId) {
    final id = scheduleId.trim();
    return _updateOperationIds.putIfAbsent(id, () => _operationIdFactory());
  }

  /// Nova intenção de edição (abre formulário de novo após fechar).
  void beginUpdateIntent(String scheduleId) {
    final id = scheduleId.trim();
    _updateOperationIds[id] = _operationIdFactory();
  }

  void endUpdateIntent(String scheduleId) {
    _updateOperationIds.remove(scheduleId.trim());
  }

  String ensureCompleteOperationId(String scheduleId) {
    final id = scheduleId.trim();
    return _completeOperationIds.putIfAbsent(id, () => _operationIdFactory());
  }

  void endCompleteIntent(String scheduleId) {
    _completeOperationIds.remove(scheduleId.trim());
  }

  String ensureCancelOperationId(String scheduleId) {
    final id = scheduleId.trim();
    return _cancelOperationIds.putIfAbsent(id, () => _operationIdFactory());
  }

  void endCancelIntent(String scheduleId) {
    _cancelOperationIds.remove(scheduleId.trim());
  }

  // ── Mutations ──────────────────────────────────────────────────────────

  Future<HealthScheduleMutationUiOutcome> createManual({
    required String dogId,
    required ScheduleType scheduleType,
    required String title,
    required DateTime scheduledFor,
    required String timezone,
    DateTime? dueUntil,
    String? notes,
  }) async {
    if (_disposed || _createSubmitting) {
      return const HealthScheduleMutationUiBlocked();
    }

    _createSubmitting = true;
    _safeNotify();

    try {
      final operationId = ensureCreateIdempotencyKey();
      final command = CreateManualScheduleItemCommand(
        dogId: dogId,
        scheduleType: scheduleType,
        title: title,
        scheduledFor: scheduledFor,
        timezone: timezone,
        operationId: operationId,
        dueUntil: dueUntil,
        notes: notes,
      );

      final result = await _gateway.createManual(command);
      return await _handleResult(
        result: result,
        successMessage: HealthScheduleMutationUserCopy.successCreated,
        onSuccessSideEffects: () {
          // Criação concluída: encerra a key para não reutilizar em novo form.
          _createIdempotencyKey = null;
        },
      );
    } on HealthScheduleMutationFailure catch (e) {
      return _failureOutcome(e);
    } catch (e, st) {
      _logUnexpected(e, st);
      return _failureOutcome(const HealthScheduleMutationUnexpected());
    } finally {
      _createSubmitting = false;
      _safeNotify();
    }
  }

  Future<HealthScheduleMutationUiOutcome> updateOpen({
    required String dogId,
    required String scheduleId,
    required HealthScheduleRevision expectedRevision,
    String? title,
    DateTime? scheduledFor,
    DateTime? dueUntil,
    bool clearDueUntil = false,
    String? timezone,
    String? notes,
    bool clearNotes = false,
  }) async {
    final id = scheduleId.trim();
    if (_disposed || isItemBusy(id)) {
      return const HealthScheduleMutationUiBlocked();
    }
    if (expectedRevision.token.trim().isEmpty) {
      return _failureOutcome(
        const HealthScheduleMutationValidation(
          'Revisão do item indisponível. Atualize a agenda e tente novamente.',
        ),
      );
    }

    _busyScheduleIds.add(id);
    _safeNotify();

    try {
      final operationId = ensureUpdateOperationId(id);
      final command = UpdateOpenScheduleItemCommand(
        dogId: dogId,
        scheduleId: id,
        expectedRevision: expectedRevision,
        operationId: operationId,
        title: title,
        scheduledFor: scheduledFor,
        dueUntil: dueUntil,
        clearDueUntil: clearDueUntil,
        timezone: timezone,
        notes: notes,
        clearNotes: clearNotes,
      );

      final result = await _gateway.updateOpen(command);
      return await _handleResult(
        result: result,
        successMessage: HealthScheduleMutationUserCopy.successUpdated,
        onSuccessSideEffects: () {
          endUpdateIntent(id);
        },
      );
    } on HealthScheduleMutationFailure catch (e) {
      return _failureOutcome(e);
    } catch (e, st) {
      _logUnexpected(e, st);
      return _failureOutcome(const HealthScheduleMutationUnexpected());
    } finally {
      _busyScheduleIds.remove(id);
      _safeNotify();
    }
  }

  Future<HealthScheduleMutationUiOutcome> complete({
    required String dogId,
    required String scheduleId,
  }) async {
    final id = scheduleId.trim();
    if (_disposed || isItemBusy(id)) {
      return const HealthScheduleMutationUiBlocked();
    }

    _busyScheduleIds.add(id);
    _safeNotify();

    try {
      final operationId = ensureCompleteOperationId(id);
      final command = CompleteScheduleItemCommand(
        dogId: dogId,
        scheduleId: id,
        operationId: operationId,
      );

      final result = await _gateway.complete(command);
      return await _handleResult(
        result: result,
        successMessage: HealthScheduleMutationUserCopy.successCompleted,
        onSuccessSideEffects: () {
          endCompleteIntent(id);
          endCancelIntent(id);
        },
      );
    } on HealthScheduleMutationFailure catch (e) {
      return _failureOutcome(e);
    } catch (e, st) {
      _logUnexpected(e, st);
      return _failureOutcome(const HealthScheduleMutationUnexpected());
    } finally {
      _busyScheduleIds.remove(id);
      _safeNotify();
    }
  }

  Future<HealthScheduleMutationUiOutcome> cancel({
    required String dogId,
    required String scheduleId,
    required String cancelReason,
  }) async {
    final id = scheduleId.trim();
    if (_disposed || isItemBusy(id)) {
      return const HealthScheduleMutationUiBlocked();
    }

    final reason = cancelReason.trim();
    if (reason.isEmpty) {
      return _failureOutcome(
        const HealthScheduleMutationValidation(
          HealthScheduleMutationUserCopy.cancelReasonRequired,
        ),
      );
    }
    if (reason.length >
        HealthScheduleActionAvailability.maxCancelReasonLength) {
      return _failureOutcome(
        const HealthScheduleMutationValidation(
          HealthScheduleMutationUserCopy.cancelReasonTooLong,
        ),
      );
    }

    _busyScheduleIds.add(id);
    _safeNotify();

    try {
      final operationId = ensureCancelOperationId(id);
      final command = CancelScheduleItemCommand(
        dogId: dogId,
        scheduleId: id,
        cancelReason: reason,
        operationId: operationId,
      );

      final result = await _gateway.cancel(command);
      return await _handleResult(
        result: result,
        successMessage: HealthScheduleMutationUserCopy.successCancelled,
        onSuccessSideEffects: () {
          endCancelIntent(id);
          endCompleteIntent(id);
        },
      );
    } on HealthScheduleMutationFailure catch (e) {
      return _failureOutcome(e);
    } catch (e, st) {
      _logUnexpected(e, st);
      return _failureOutcome(const HealthScheduleMutationUnexpected());
    } finally {
      _busyScheduleIds.remove(id);
      _safeNotify();
    }
  }

  /// Refresh público para falhas que exigem releitura (conflict/notFound/…).
  Future<void> refreshSchedule() async {
    if (_disposed) return;
    final dogId = _scheduleController.activeDogId;
    if (dogId == null || dogId.isEmpty) return;
    try {
      await _scheduleController.refresh();
    } catch (e, st) {
      assert(() {
        debugPrint(
          '[HealthScheduleMutationController] refresh falhou: $e\n$st',
        );
        return true;
      }());
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────

  Future<HealthScheduleMutationUiOutcome> _handleResult({
    required HealthScheduleMutationResult result,
    required String successMessage,
    void Function()? onSuccessSideEffects,
  }) async {
    switch (result) {
      case HealthScheduleMutationSuccess():
        onSuccessSideEffects?.call();
        final refreshFailed = await _refreshAfterSuccess();
        return HealthScheduleMutationUiSuccess.fromRemote(
          remote: result,
          successMessage: successMessage,
          refreshFailed: refreshFailed,
          refreshWarning: refreshFailed
              ? HealthScheduleMutationUserCopy.refreshFailedAfterSuccess
              : null,
        );
      case HealthScheduleMutationErrorResult(:final failure):
        // alreadyCompleted/alreadyCancelled com asSuccess no engine local
        // chegam como ErrorResult no path remoto quando o backend retorna
        // o código correspondente — UI trata como falha + refresh.
        return _failureOutcome(failure);
    }
  }

  Future<bool> _refreshAfterSuccess() async {
    try {
      await _scheduleController.refresh();
      return _scheduleShowsRefreshFailure();
    } catch (e, st) {
      assert(() {
        debugPrint(
          '[HealthScheduleMutationController] refresh pós-sucesso: $e\n$st',
        );
        return true;
      }());
      return true;
    }
  }

  bool _scheduleShowsRefreshFailure() {
    final state = _scheduleController.state;
    return switch (state) {
      HealthScheduleData(:final snapshot) => snapshot.hasRefreshFailure,
      HealthScheduleError() => true,
      HealthScheduleOffline() => true,
      _ => false,
    };
  }

  HealthScheduleMutationUiFailure _failureOutcome(
    HealthScheduleMutationFailure failure,
  ) {
    return HealthScheduleMutationUiFailure(
      failure: failure,
      userMessage: HealthScheduleMutationUserCopy.messageFor(failure),
      shouldRefresh: HealthScheduleMutationUserCopy.shouldRefreshAfterFailure(
        failure,
      ),
    );
  }

  void _logUnexpected(Object error, StackTrace stackTrace) {
    assert(() {
      debugPrint(
        '[HealthScheduleMutationController] inesperado: $error\n$stackTrace',
      );
      return true;
    }());
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _busyScheduleIds.clear();
    _updateOperationIds.clear();
    _completeOperationIds.clear();
    _cancelOperationIds.clear();
    _createIdempotencyKey = null;
    super.dispose();
  }

  @visibleForTesting
  bool get isDisposedForTest => _disposed;

  @visibleForTesting
  String? get createIdempotencyKeyForTest => _createIdempotencyKey;

  @visibleForTesting
  String? updateOperationIdForTest(String scheduleId) =>
      _updateOperationIds[scheduleId.trim()];

  @visibleForTesting
  String? completeOperationIdForTest(String scheduleId) =>
      _completeOperationIds[scheduleId.trim()];

  @visibleForTesting
  String? cancelOperationIdForTest(String scheduleId) =>
      _cancelOperationIds[scheduleId.trim()];
}
