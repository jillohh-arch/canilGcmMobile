/// Snapshot de Prontidão lido de `dogs/{dogId}/health_summary/current`.
///
/// READINESS-V1 Gate 6 — **leitor**, nunca avaliador.
///
/// O Mobile NÃO calcula prontidão. Toda decisão clínica é do servidor
/// (`functions/src/health_readiness_policy.ts`). Este modelo apenas transporta
/// o veredito já decidido.
///
/// ## Dois planos independentes
///
/// ```text
/// CLÍNICO    readinessStatus    — exatamente 5 estados (ReadinessStatus)
/// TÉCNICO    projectionStatus   — ready | unavailable
/// ```
///
/// Falha técnica **nunca** se transforma em estado clínico. Em particular nunca
/// vira `notEvaluated`: "não foi possível avaliar" e "nunca foi avaliado" são
/// afirmações diferentes.
library;

import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';

/// Plano técnico da projeção. Nunca é exibido como estado clínico.
enum ReadinessProjectionStatus {
  /// Projeção concluída com sucesso; há veredito clínico válido.
  ready,

  /// Projeção não pôde ser concluída nesta tentativa.
  unavailable;

  static ReadinessProjectionStatus? fromWire(String? wire) => switch (wire) {
    'ready' => ReadinessProjectionStatus.ready,
    'unavailable' => ReadinessProjectionStatus.unavailable,
    _ => null,
  };
}

/// Nível de restrição operacional, na precedência canônica do servidor.
enum ReadinessRestrictionLevel {
  absolute,
  partial,
  attention;

  static ReadinessRestrictionLevel? fromWire(String? wire) => switch (wire) {
    'absolute' => ReadinessRestrictionLevel.absolute,
    'partial' => ReadinessRestrictionLevel.partial,
    'attention' => ReadinessRestrictionLevel.attention,
    _ => null,
  };

  /// Menor valor = mais severo. Usado apenas para ordenação determinística.
  int get severityRank => switch (this) {
    ReadinessRestrictionLevel.absolute => 0,
    ReadinessRestrictionLevel.partial => 1,
    ReadinessRestrictionLevel.attention => 2,
  };
}

/// Restrição operacional ativa, como projetada pelo servidor.
///
/// Exibição apenas. Esta classe NÃO autoriza nem bloqueia ação operacional —
/// autorização crítica permanece no backend sobre `operational_restrictions`.
final class ReadinessRestriction {
  const ReadinessRestriction({
    required this.id,
    required this.level,
    required this.category,
    required this.description,
    required this.activitiesRestricted,
    required this.since,
    required this.isOverdue,
    this.expectedEnd,
  });

  final String id;
  final ReadinessRestrictionLevel level;
  final String category;
  final String description;
  final List<String> activitiesRestricted;
  final DateTime since;
  final DateTime? expectedEnd;

  /// `expected_end` no passado com restrição ainda ativa. Não remove a restrição.
  final bool isOverdue;

  @override
  bool operator ==(Object other) =>
      other is ReadinessRestriction &&
      other.id == id &&
      other.level == level &&
      other.category == category &&
      other.description == description &&
      _listEq(other.activitiesRestricted, activitiesRestricted) &&
      other.since == since &&
      other.expectedEnd == expectedEnd &&
      other.isOverdue == isOverdue;

  @override
  int get hashCode => Object.hash(
    id,
    level,
    category,
    description,
    Object.hashAll(activitiesRestricted),
    since,
    expectedEnd,
    isOverdue,
  );
}

/// Alerta clínico aberto, decidido pelo servidor.
final class ReadinessAlert {
  const ReadinessAlert({
    required this.code,
    required this.severity,
    required this.message,
  });

  final String code;
  final String severity;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ReadinessAlert &&
      other.code == code &&
      other.severity == severity &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, severity, message);
}

/// Contagem de restrições ativas por nível.
final class ReadinessRestrictionCount {
  const ReadinessRestrictionCount({
    required this.absolute,
    required this.partial,
    required this.attention,
  });

  final int absolute;
  final int partial;
  final int attention;

  int get total => absolute + partial + attention;

  @override
  bool operator ==(Object other) =>
      other is ReadinessRestrictionCount &&
      other.absolute == absolute &&
      other.partial == partial &&
      other.attention == attention;

  @override
  int get hashCode => Object.hash(absolute, partial, attention);
}

/// Completude de dados — exatamente os quatro gates ratificados.
///
/// `has_recent_exam` **não existe** neste contrato: exame é informativo e nunca
/// foi gate de prontidão na decisão humana ratificada.
final class ReadinessCompleteness {
  const ReadinessCompleteness({
    required this.hasRecentWeight,
    required this.hasVaccinationCurrent,
    required this.hasRecentConsultation,
    required this.hasActiveNutrition,
  });

  final bool hasRecentWeight;
  final bool hasVaccinationCurrent;
  final bool hasRecentConsultation;
  final bool hasActiveNutrition;

  @override
  bool operator ==(Object other) =>
      other is ReadinessCompleteness &&
      other.hasRecentWeight == hasRecentWeight &&
      other.hasVaccinationCurrent == hasVaccinationCurrent &&
      other.hasRecentConsultation == hasRecentConsultation &&
      other.hasActiveNutrition == hasActiveNutrition;

  @override
  int get hashCode => Object.hash(
    hasRecentWeight,
    hasVaccinationCurrent,
    hasRecentConsultation,
    hasActiveNutrition,
  );
}

/// Veredito clínico completo de uma projeção bem-sucedida.
final class ReadinessClinicalVerdict {
  const ReadinessClinicalVerdict({
    required this.status,
    required this.label,
    required this.reason,
    required this.reasonCode,
    required this.updatedAt,
    required this.completeness,
    required this.activeRestrictions,
    required this.restrictionCount,
    required this.openAlerts,
    this.lastEvaluatedAt,
  });

  /// Estado clínico oficial. Um dos cinco — nunca um estado técnico.
  final ReadinessStatus status;

  /// Rótulo PT-BR congelado pelo servidor. O Mobile exibe, não deriva.
  final String label;

  /// Explicação factual do servidor. O Mobile NÃO reconstrói a partir de alertas.
  final String reason;

  final String reasonCode;

  /// Instante em que a Function avaliou (tempo de projeção).
  final DateTime updatedAt;

  final ReadinessCompleteness completeness;
  final List<ReadinessRestriction> activeRestrictions;
  final ReadinessRestrictionCount restrictionCount;
  final List<ReadinessAlert> openAlerts;

  /// Último instante factual de avaliação clínica (tempo clínico).
  ///
  /// Distinto de [updatedAt]. Nunca usado para decidir frescor de projeção.
  final DateTime? lastEvaluatedAt;

  @override
  bool operator ==(Object other) =>
      other is ReadinessClinicalVerdict &&
      other.status == status &&
      other.label == label &&
      other.reason == reason &&
      other.reasonCode == reasonCode &&
      other.updatedAt == updatedAt &&
      other.completeness == completeness &&
      _listEq(other.activeRestrictions, activeRestrictions) &&
      other.restrictionCount == restrictionCount &&
      _listEq(other.openAlerts, openAlerts) &&
      other.lastEvaluatedAt == lastEvaluatedAt;

  @override
  int get hashCode => Object.hash(
    status,
    label,
    reason,
    reasonCode,
    updatedAt,
    completeness,
    Object.hashAll(activeRestrictions),
    restrictionCount,
    Object.hashAll(openAlerts),
    lastEvaluatedAt,
  );
}

/// Snapshot de Prontidão já validado.
///
/// Invariante central: [verdict] é não-nulo **somente** quando
/// [projectionStatus] é `ready`. Quando a projeção está `unavailable`,
/// campos clínicos preservados pelo servidor ficam em [lastKnownGood] — e
/// [lastKnownGood] NUNCA deve ser apresentado como estado atual.
final class ReadinessSnapshot {
  const ReadinessSnapshot._({
    required this.projectionStatus,
    required this.projectionAttemptedAt,
    required this.technicalBlockers,
    required this.schemaVersion,
    this.verdict,
    this.lastKnownGood,
  });

  /// Projeção bem-sucedida: há veredito clínico atual.
  const ReadinessSnapshot.ready({
    required ReadinessClinicalVerdict verdict,
    required DateTime projectionAttemptedAt,
    required int schemaVersion,
  }) : this._(
         projectionStatus: ReadinessProjectionStatus.ready,
         projectionAttemptedAt: projectionAttemptedAt,
         technicalBlockers: const [],
         schemaVersion: schemaVersion,
         verdict: verdict,
       );

  /// Projeção indisponível. [lastKnownGood] é diagnóstico, não estado atual.
  const ReadinessSnapshot.unavailable({
    required DateTime projectionAttemptedAt,
    required List<String> technicalBlockers,
    required int schemaVersion,
    ReadinessClinicalVerdict? lastKnownGood,
  }) : this._(
         projectionStatus: ReadinessProjectionStatus.unavailable,
         projectionAttemptedAt: projectionAttemptedAt,
         technicalBlockers: technicalBlockers,
         schemaVersion: schemaVersion,
         lastKnownGood: lastKnownGood,
       );

  final ReadinessProjectionStatus projectionStatus;
  final DateTime projectionAttemptedAt;
  final List<String> technicalBlockers;
  final int schemaVersion;

  /// Veredito clínico ATUAL. Não-nulo apenas quando [isReady].
  final ReadinessClinicalVerdict? verdict;

  /// Veredito preservado de uma projeção anterior bem-sucedida.
  ///
  /// Presente apenas quando [projectionStatus] é `unavailable` e o servidor
  /// preservou os campos clínicos. Serve para cache/offline e diagnóstico —
  /// a UI online NÃO pode apresentá-lo como situação atual.
  final ReadinessClinicalVerdict? lastKnownGood;

  bool get isReady => projectionStatus == ReadinessProjectionStatus.ready;

  bool get isUnavailable =>
      projectionStatus == ReadinessProjectionStatus.unavailable;

  /// Idade da projeção em relação a [now], usando tempo de projeção.
  ///
  /// Baseia-se em `readiness_updated_at` (quando `ready`) ou
  /// `projection_attempted_at`. NUNCA em `last_evaluated_at`, que é tempo
  /// clínico e mediria a coisa errada.
  Duration ageFrom(DateTime now) {
    final reference = verdict?.updatedAt ?? projectionAttemptedAt;
    final delta = now.difference(reference);
    return delta.isNegative ? Duration.zero : delta;
  }

  @override
  bool operator ==(Object other) =>
      other is ReadinessSnapshot &&
      other.projectionStatus == projectionStatus &&
      other.projectionAttemptedAt == projectionAttemptedAt &&
      _listEq(other.technicalBlockers, technicalBlockers) &&
      other.schemaVersion == schemaVersion &&
      other.verdict == verdict &&
      other.lastKnownGood == lastKnownGood;

  @override
  int get hashCode => Object.hash(
    projectionStatus,
    projectionAttemptedAt,
    Object.hashAll(technicalBlockers),
    schemaVersion,
    verdict,
    lastKnownGood,
  );
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
