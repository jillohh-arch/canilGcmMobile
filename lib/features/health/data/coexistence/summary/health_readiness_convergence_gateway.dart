import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/readiness_callable.dart';
import 'package:canil_gcm/features/health/domain/health_readiness_convergence.dart';

/// Barreira causal de Prontidão: refresh + releitura one-shot + prova local.
///
/// B4-R.C3. Autoridade: `docs/health/adr/ADR-009-READINESS-PROJECTION-CAUSAL-CONSISTENCY.md`.
///
/// Esta é a ÚNICA implementação do predicado causal no Mobile. ISSUE, END e
/// CANCEL a consomem; nenhum deles reimplementa `generation >= required` nem
/// parseia o wire por conta própria.
///
/// ## O que este gateway deliberadamente não faz
///
/// - não usa listener, polling, `Timer`, `Future.delayed` ou `sleep`;
/// - não repete a mutation, em nenhuma circunstância;
/// - não compara relógio de cliente, `readiness_updated_at`, `operationId`,
///   `receiptId` nem `eventId` — ADR-009 congelou generations como o contrato
///   causal;
/// - não deriva convergência de `response['ok']`, que permanece apenas contrato
///   legado de execução.
///
/// Uma tentativa = um refresh + uma releitura. Retry é ação explícita do
/// controller.
final class HealthReadinessConvergenceGateway {
  HealthReadinessConvergenceGateway({
    required ReadinessCallableInvoker invoke,
    FirebaseFirestore? firestore,
  }) : _invoke = invoke,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final ReadinessCallableInvoker _invoke;
  final FirebaseFirestore _firestore;

  /// Executa uma única tentativa de convergência para [dogId].
  ///
  /// [dogId] deve ser o cão capturado da intenção/resultado da mutation, nunca
  /// "o cão atualmente selecionado": a seleção pode mudar enquanto o trabalho
  /// assíncrono está em voo.
  ///
  /// Nunca lança — toda falha vira um outcome tipado, porque o chamador precisa
  /// distinguir "não provei a projeção" de "a mutation falhou".
  Future<HealthReadinessConvergenceResult> converge(String dogId) async {
    // 1. Barreira: o refresh reserva a generation G server-side.
    final Map<String, dynamic> response;
    try {
      response = await _invoke(ReadinessCallableNames.refresh, {'dogId': dogId});
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        '[HealthReadinessConvergence] refresh bloqueado [${e.code}]: '
        '${e.message}',
      );
      return const HealthReadinessConvergenceResult(
        outcome: HealthReadinessConvergenceOutcome.readFailure,
      );
    } catch (e) {
      debugPrint('[HealthReadinessConvergence] refresh falhou: $e');
      return const HealthReadinessConvergenceResult(
        outcome: HealthReadinessConvergenceOutcome.readFailure,
      );
    }

    // 2. Contrato causal. Ausência é rollout; malformação é falha fechada.
    final parsed = parseHealthReadinessConvergenceResponse(response);
    final report = parsed.report;
    if (report == null) {
      final failure =
          parsed.failure ??
          HealthReadinessConvergenceContractFailure.contractMalformed;
      final absent =
          failure == HealthReadinessConvergenceContractFailure.contractAbsent;
      debugPrint(
        absent
            ? '[HealthReadinessConvergence] backend sem contrato causal '
                  '(rollout backend-first pendente)'
            : '[HealthReadinessConvergence] contrato causal malformado',
      );
      return HealthReadinessConvergenceResult(
        outcome: absent
            ? HealthReadinessConvergenceOutcome.contractUnavailable
            : HealthReadinessConvergenceOutcome.integrityFailure,
        contractFailure: failure,
      );
    }

    // 3. Releitura one-shot: o app só pode renderizar o que acabou de ler.
    final HealthReadinessCausalMarker marker;
    try {
      final doc = await _firestore
          .collection('dogs')
          .doc(dogId)
          .collection('health_summary')
          .doc('current')
          .get();
      marker = HealthReadinessCausalMarker.fromDocument(doc.data());
    } on FirebaseException catch (e) {
      debugPrint(
        '[HealthReadinessConvergence] releitura bloqueada [${e.code}]: '
        '${e.message}',
      );
      // Sem snapshot atual não há prova. Preserva a resposta do servidor para
      // diagnóstico, mas nunca converge.
      return HealthReadinessConvergenceResult(
        outcome: report.status == HealthReadinessServerConvergence.unavailable
            ? HealthReadinessConvergenceOutcome.unavailable
            : HealthReadinessConvergenceOutcome.readFailure,
        serverReport: report,
      );
    } catch (e) {
      debugPrint('[HealthReadinessConvergence] releitura falhou: $e');
      return HealthReadinessConvergenceResult(
        outcome: report.status == HealthReadinessServerConvergence.unavailable
            ? HealthReadinessConvergenceOutcome.unavailable
            : HealthReadinessConvergenceOutcome.readFailure,
        serverReport: report,
      );
    }

    // 4. Prova local decide.
    return decideHealthReadinessConvergence(
      serverReport: report,
      observedMarker: marker,
    );
  }
}

/// Resultado do parse do wire causal. Exatamente um campo é não-nulo.
final class HealthReadinessConvergenceParse {
  const HealthReadinessConvergenceParse.report(this.report) : failure = null;

  const HealthReadinessConvergenceParse.failure(this.failure) : report = null;

  final HealthReadinessServerConvergenceReport? report;
  final HealthReadinessConvergenceContractFailure? failure;
}

/// Parseia `result.convergence` de forma estrita e fail-closed.
///
/// Exposto para teste direto do wire, sem canal. Nunca lança.
HealthReadinessConvergenceParse parseHealthReadinessConvergenceResponse(
  Map<String, dynamic> response,
) {
  const absent = HealthReadinessConvergenceParse.failure(
    HealthReadinessConvergenceContractFailure.contractAbsent,
  );
  const malformed = HealthReadinessConvergenceParse.failure(
    HealthReadinessConvergenceContractFailure.contractMalformed,
  );

  final result = response['result'];
  if (result is! Map) return absent;

  final convergence = result['convergence'];
  // Backend anterior a C2: `ok` pode ser true e ainda assim não haver contrato
  // causal. Isso NUNCA é convergido.
  if (convergence == null) return absent;
  if (convergence is! Map) return malformed;

  final status = HealthReadinessServerConvergence.fromWire(
    convergence['status'],
  );
  if (status == null) return malformed;

  final required = convergence['requiredGeneration'];
  if (required is! int || required <= 0) return malformed;

  // A chave `observedGeneration` é obrigatória; seu valor pode ser null.
  if (!convergence.containsKey('observedGeneration')) return malformed;
  final observed = convergence['observedGeneration'];
  if (observed != null && (observed is! int || observed <= 0)) return malformed;

  return HealthReadinessConvergenceParse.report(
    HealthReadinessServerConvergenceReport(
      status: status,
      requiredGeneration: required,
      observedGeneration: observed as int?,
    ),
  );
}
