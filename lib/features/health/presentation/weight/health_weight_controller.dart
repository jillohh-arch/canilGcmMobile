import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_models.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_provider.dart';
import 'package:canil_gcm/features/health/domain/health_weight_mutation_gateway.dart';

sealed class HealthWeightSubmissionOutcome {
  const HealthWeightSubmissionOutcome();
}

final class HealthWeightSubmissionSuccess
    extends HealthWeightSubmissionOutcome {
  const HealthWeightSubmissionSuccess(this.receipt);
  final HealthWeightMutationReceipt receipt;
}

final class HealthWeightSubmissionFailure
    extends HealthWeightSubmissionOutcome {
  const HealthWeightSubmissionFailure(this.failure);
  final HealthWeightMutationFailure failure;
}

final class HealthWeightSubmissionBlocked
    extends HealthWeightSubmissionOutcome {
  const HealthWeightSubmissionBlocked();
}

final class HealthWeightController extends ChangeNotifier {
  HealthWeightController({
    required HealthWeightMutationGateway gateway,
    required AuthoritativeTimeProvider authoritativeTimeProvider,
    String Function()? operationIdFactory,
    Future<void> Function()? onRefreshAfterSuccess,
  }) : _gateway = gateway,
       _timeProvider = authoritativeTimeProvider,
       _operationIdFactory = operationIdFactory ?? (() => const Uuid().v4()),
       _onRefreshAfterSuccess = onRefreshAfterSuccess;

  final HealthWeightMutationGateway _gateway;
  final AuthoritativeTimeProvider _timeProvider;
  final String Function() _operationIdFactory;
  final Future<void> Function()? _onRefreshAfterSuccess;

  bool _submitting = false;
  bool _disposed = false;
  _PendingWeightIntent? _pending;
  HealthWeightMutationFailure? _lastError;

  bool get isSubmitting => _submitting;
  HealthWeightMutationFailure? get lastError => _lastError;

  @visibleForTesting
  String? get activeOperationIdForTest => _pending?.command.operationId;

  @visibleForTesting
  DateTime? get activeMeasuredAtForTest => _pending?.command.measuredAt;

  @visibleForTesting
  CreateHealthWeightCommand? get activeCommandForTest => _pending?.command;

  Future<HealthWeightSubmissionOutcome> submit({
    required String dogId,
    required double weightKg,
    HealthWeightContext? context,
    String? notes,
  }) async {
    if (_disposed || _submitting) return const HealthWeightSubmissionBlocked();

    final validation = _validate(dogId: dogId, weightKg: weightKg);
    if (validation != null) {
      _lastError = validation;
      _notify();
      return HealthWeightSubmissionFailure(validation);
    }

    final normalizedNotes = _normalizedNotes(notes);
    final fingerprint = _fingerprint(
      dogId: dogId,
      weightKg: weightKg,
      context: context,
      notes: normalizedNotes,
    );
    _submitting = true;
    _lastError = null;
    _notify();
    try {
      var pending = _pending;
      if (pending == null || pending.fingerprint != fingerprint) {
        _pending = null;
        final measuredAt = await _authoritativeNow();
        final operationId = _operationIdFactory().trim();
        if (operationId.isEmpty) {
          throw const HealthWeightMutationFailure(
            HealthWeightMutationErrorCode.internal,
            'Não foi possível iniciar a operação de pesagem.',
          );
        }
        pending = _PendingWeightIntent(
          fingerprint: fingerprint,
          command: CreateHealthWeightCommand(
            dogId: dogId.trim(),
            operationId: operationId,
            weightKg: weightKg,
            measuredAt: measuredAt,
            context: context,
            notes: normalizedNotes,
          ),
        );
        _pending = pending;
      }
      final receipt = await _gateway.createRecord(pending.command);
      _pending = null;
      await _onRefreshAfterSuccess?.call();
      return HealthWeightSubmissionSuccess(receipt);
    } on HealthWeightMutationFailure catch (failure) {
      _lastError = failure;
      if (!failure.isTransient) _pending = null;
      return HealthWeightSubmissionFailure(failure);
    } finally {
      _submitting = false;
      _notify();
    }
  }

  void discardOperation() {
    if (_submitting) return;
    _pending = null;
    _lastError = null;
    _notify();
  }

  HealthWeightMutationFailure? _validate({
    required String dogId,
    required double weightKg,
  }) {
    if (dogId.trim().isEmpty) {
      return const HealthWeightMutationFailure(
        HealthWeightMutationErrorCode.invalidArgument,
        'K9 inválido para registro de pesagem.',
      );
    }
    if (!weightKg.isFinite || weightKg <= 0 || weightKg > 100) {
      return const HealthWeightMutationFailure(
        HealthWeightMutationErrorCode.invalidArgument,
        'Informe um peso maior que 0 e menor ou igual a 100 kg.',
      );
    }
    return null;
  }

  Future<DateTime> _authoritativeNow() async {
    final current = _timeProvider.nowFreshUtc();
    if (current != null) return current;
    final result = await _timeProvider.synchronize();
    if (result is AuthoritativeTimeSyncSuccess) {
      final now = _timeProvider.nowFreshUtc();
      if (now != null) return now;
    }
    throw const HealthWeightMutationFailure(
      HealthWeightMutationErrorCode.unavailable,
      'Não foi possível confirmar o horário oficial. Tente novamente.',
    );
  }

  String _fingerprint({
    required String dogId,
    required double weightKg,
    required HealthWeightContext? context,
    required String? notes,
  }) =>
      '${dogId.trim()}|${weightKg.toString()}|${context?.wireValue ?? ''}|${notes ?? ''}';

  String? _normalizedNotes(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class _PendingWeightIntent {
  const _PendingWeightIntent({
    required this.fingerprint,
    required this.command,
  });

  final String fingerprint;
  final CreateHealthWeightCommand command;
}
