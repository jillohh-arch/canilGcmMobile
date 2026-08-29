import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/coexistence/summary/health_readiness_convergence_gateway.dart';
import '../../domain/health_restriction_flow_errors.dart';
import '../../domain/health_restriction_lifecycle_gateway.dart';
import 'health_restriction_convergence_coordinator.dart';

/// Progresso do cancelamento.
///
/// Uma única etapa: não há documento, não há upload. A máquina de estados é
/// deliberadamente mais simples que a do END.
enum HealthRestrictionCancelStage { idle, cancelling, success, failure }

/// Intenção de cancelamento, materializada para fingerprint.
final class HealthRestrictionCancelIntent {
  const HealthRestrictionCancelIntent({
    required this.dogId,
    required this.restrictionId,
    required this.cancelReason,
  });

  final String dogId;
  final String restrictionId;
  final String cancelReason;

  /// Chave determinística da intenção. Razão é comparada já normalizada, para
  /// que mudança apenas de espaçamento não invalide a chave de operação.
  String get fingerprint =>
      [dogId, restrictionId, cancelReason.trim()].join('\u{0000}');
}

/// Invalida o registro de uma restrição. NÃO afirma liberação clínica.
///
/// Deliberadamente sem dependência de HealthDocument, Storage ou
/// ProfessionalIdentity: o contrato do backend rejeita prova clínica no CANCEL
/// como erro, não como campo opcional. Se qualquer uma dessas dependências
/// aparecer aqui, é falha arquitetural.
final class HealthRestrictionCancelController extends ChangeNotifier {
  HealthRestrictionCancelController({
    required HealthRestrictionLifecycleGateway gateway,
    required HealthReadinessConvergenceGateway convergenceGateway,
    String Function()? operationIdFactory,
  }) : _gateway = gateway,
       _newOperationId = operationIdFactory ?? (() => const Uuid().v4()) {
    _convergence = HealthRestrictionConvergenceCoordinator(
      gateway: convergenceGateway,
      onChanged: notifyListeners,
    );
  }

  final HealthRestrictionLifecycleGateway _gateway;
  final String Function() _newOperationId;
  late final HealthRestrictionConvergenceCoordinator _convergence;

  /// Fase causal do comando já commitado (B4-R.C3).
  HealthRestrictionConvergenceCoordinator get convergence => _convergence;

  HealthRestrictionCancelStage _stage = HealthRestrictionCancelStage.idle;
  HealthRestrictionFlowFailure? _failure;
  bool _submitting = false;

  String? _operationId;
  String? _intentFingerprint;
  HealthRestrictionTerminalResult? _result;

  HealthRestrictionCancelStage get stage => _stage;
  HealthRestrictionFlowFailure? get failure => _failure;
  bool get isSubmitting => _submitting;
  HealthRestrictionTerminalResult? get result => _result;

  @visibleForTesting
  String? get operationIdForTest => _operationId;

  /// Executa (ou repete) o cancelamento.
  ///
  /// Retry da MESMA intenção preserva o `operationId`, então uma resposta
  /// perdida é resolvida por replay do receipt no backend. Razão alterada é
  /// intenção nova e recebe chave nova — reusar a anterior produziria
  /// `idempotency-conflict`, corretamente.
  Future<bool> submit(HealthRestrictionCancelIntent intent) async {
    if (_submitting) return false;
    _submitting = true;
    _failure = null;
    notifyListeners();

    try {
      final reason = normalizeHealthRestrictionReason(intent.cancelReason);
      if (reason == null) {
        return _fail(
          const HealthRestrictionFlowValidation(
            HealthRestrictionFlowStep.restrictionCancel,
            'Informe o motivo do cancelamento.',
          ),
        );
      }

      _reconcileIntent(intent);
      _setStage(HealthRestrictionCancelStage.cancelling);

      final outcome = await _gateway.cancel(
        CancelOperationalRestrictionCommand(
          dogId: intent.dogId,
          restrictionId: intent.restrictionId,
          operationId: _operationId!,
          cancelReason: reason,
        ),
      );

      switch (outcome) {
        case HealthRestrictionTerminalSuccess(:final result):
          _result = result;
          // O comando terminal já é fato canônico. A partir daqui, qualquer
          // falha é de CONVERGÊNCIA, nunca de cancelamento: `_result` e o stage
          // `success` são preservados independentemente do que ocorra na
          // barreira causal.
          _stage = HealthRestrictionCancelStage.success;
          await _convergence.onMutationCommitted(intent.dogId);
          return true;
        case HealthRestrictionTerminalError(:final failure):
          return _fail(failure);
      }
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  void _reconcileIntent(HealthRestrictionCancelIntent intent) {
    final fingerprint = intent.fingerprint;
    if (_intentFingerprint != null && _intentFingerprint != fingerprint) {
      _operationId = null;
      _result = null;
    }
    _intentFingerprint = fingerprint;
    _operationId ??= _newOperationId();
  }

  void _setStage(HealthRestrictionCancelStage next) {
    _stage = next;
    notifyListeners();
  }

  bool _fail(HealthRestrictionFlowFailure failure) {
    _failure = failure;
    _stage = HealthRestrictionCancelStage.failure;
    return false;
  }
}
