import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/readiness_callable.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/readiness_snapshot_parser.dart';
import 'package:canil_gcm/features/health/domain/readiness_snapshot.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_user_copy.dart';

/// Par de seções derivadas de um único snapshot de Prontidão.
///
/// Prontidão e Atenções vêm do MESMO documento: nunca podem discordar entre si.
typedef ReadinessSections = ({
  HealthSummarySectionData<HealthSummaryReadinessView> readiness,
  HealthSummarySectionData<HealthSummaryAttentionView> attention,
});

/// Leitor de `dogs/{dogId}/health_summary/current`.
///
/// READINESS-V1 Gate 6 — **substitui** os placeholders
/// `HealthSummaryUnsafeSections.readiness` / `.attention`.
///
/// ## O que este leitor NÃO faz
///
/// Não calcula prontidão. Não deriva rótulo a partir do enum. Não reconstrói o
/// motivo a partir de alertas, peso, vacina, consulta, nutrição ou timeline.
/// Não consulta a timeline clínica para fabricar atenções. Não escreve em
/// `health_summary`. Não autoriza ação operacional.
///
/// Toda decisão clínica pertence a `functions/src/health_readiness_policy.ts`.
///
/// ## Frescor e recuperação
///
/// Snapshot com mais de [freshnessWindow] pede reprojeção ao backend — tanto
/// `ready` (frescor) quanto `unavailable` (recuperação de bloqueio técnico já
/// resolvido no servidor). A idade usa tempo de PROJEÇÃO
/// (`readiness_updated_at` quando `ready`, `projection_attempted_at` quando
/// `unavailable`), nunca `last_evaluated_at`, que é tempo clínico e mediria a
/// coisa errada.
///
/// A reprojeção é tentada UMA vez por leitura. Se a re-leitura seguir
/// `unavailable`, a UI mostra indisponível — não há laço de retentativa.
class HealthSummaryReadinessReader {
  HealthSummaryReadinessReader({
    FirebaseFirestore? firestore,
    ReadinessRefreshGateway? refreshGateway,
    DateTime Function()? now,
  }) : _firestoreOverride = firestore,
       _refreshGatewayOverride = refreshGateway,
       _now = now ?? DateTime.now;

  /// Instância injetada; `null` significa "resolver o default sob demanda".
  ///
  /// A resolução é LAZY (ver [_firestore]): tocar `FirebaseFirestore.instance`
  /// no construtor quebraria qualquer teste que apenas constrói a fonte de
  /// Resumo sem inicializar o Firebase.
  final FirebaseFirestore? _firestoreOverride;
  final ReadinessRefreshGateway? _refreshGatewayOverride;
  final DateTime Function() _now;

  FirebaseFirestore? _cachedFirestore;
  ReadinessRefreshGateway? _cachedGateway;

  FirebaseFirestore get _firestore =>
      _cachedFirestore ??= _firestoreOverride ?? FirebaseFirestore.instance;

  ReadinessRefreshGateway get _refreshGateway =>
      _cachedGateway ??=
          _refreshGatewayOverride ??
          ReadinessRefreshGateway(
            invoke: FirebaseFunctionsReadinessCallableInvoker().call,
          );

  /// Janela de frescor: idade `<=` este valor é fresca.
  ///
  /// Fronteira congelada: exatamente 5 minutos ainda é fresco; acima refresca.
  static const freshnessWindow = Duration(minutes: 5);

  /// Refreshes em voo por cão — impede tempestade de callable.
  ///
  /// Um rebuild durante uma requisição pendente reaproveita o mesmo Future em
  /// vez de disparar outra chamada.
  final Map<String, Future<bool>> _inFlightRefresh = {};

  @visibleForTesting
  bool hasInFlightRefresh(String dogId) =>
      _inFlightRefresh.containsKey(dogId.trim());

  /// Lê o snapshot e produz as duas seções da UI.
  Future<ReadinessSections> read(String dogId) async {
    final normalized = dogId.trim();
    if (normalized.isEmpty) return _unavailableSections();

    try {
      var result = await _fetch(normalized);

      // Documento ausente: pede a primeira projeção ao backend.
      if (result is ReadinessParseIncompatible &&
          result.failure == ReadinessParseFailure.missing) {
        final refreshed = await _requestRefresh(normalized);
        if (!refreshed) return _unavailableSections();
        result = await _fetch(normalized);
      }

      if (result is ReadinessParseIncompatible) {
        debugPrint(
          '[HealthSummaryReadinessReader] snapshot incompatível '
          '[${result.failure.name}]: ${result.detail ?? "sem detalhe"}',
        );
        return _unavailableSections();
      }

      var snapshot = (result as ReadinessParseSuccess).snapshot;

      // Snapshot velho pede reprojeção, seja `ready` (frescor) ou `unavailable`
      // (recuperação). Sem isto um bloqueio técnico já corrigido no servidor
      // ficaria congelado até que alguém gravasse um registro clínico — o app
      // exibiria INDISPONÍVEL indefinidamente por causa de uma falha passada.
      //
      // UMA tentativa por leitura: se a re-leitura seguir `unavailable`, a UI
      // mostra indisponível e para. Nunca read→refresh→read→refresh em laço.
      if (_isStale(snapshot)) {
        final refreshed = await _requestRefresh(normalized);
        if (refreshed) {
          final reread = await _fetch(normalized);
          if (reread is ReadinessParseSuccess) {
            snapshot = reread.snapshot;
          }
          // Falha de re-leitura mantém o snapshot anterior; o estado técnico
          // abaixo decide o que a UI mostra.
        }
      }

      return _sectionsFor(snapshot);
    } on FirebaseException catch (e) {
      // Erro de canal nunca vira "sem pendências".
      debugPrint(
        '[HealthSummaryReadinessReader] leitura bloqueada [${e.code}]: '
        '${e.message}',
      );
      return _unavailableSections(
        readinessMessage: e.code == 'unavailable'
            ? HealthSummaryUserCopy.networkUnavailable
            : null,
        attentionMessage: e.code == 'unavailable'
            ? HealthSummaryUserCopy.networkUnavailable
            : null,
      );
    }
  }

  Future<ReadinessParseResult> _fetch(String dogId) async {
    final doc = await _firestore
        .collection('dogs')
        .doc(dogId)
        .collection('health_summary')
        .doc('current')
        .get();

    if (!doc.exists) {
      return const ReadinessParseIncompatible(ReadinessParseFailure.missing);
    }
    return ReadinessSnapshotParser.parse(doc.data());
  }

  bool _isStale(ReadinessSnapshot snapshot) =>
      snapshot.ageFrom(_now()) > freshnessWindow;

  /// Dispara refresh garantindo uma única requisição em voo por cão.
  Future<bool> _requestRefresh(String dogId) {
    final pending = _inFlightRefresh[dogId];
    if (pending != null) return pending;

    final future = _refreshGateway.refresh(dogId).whenComplete(() {
      _inFlightRefresh.remove(dogId);
    });
    _inFlightRefresh[dogId] = future;
    return future;
  }

  /// Converte snapshot validado nas duas seções.
  ///
  /// Projeção indisponível → ambas indisponíveis, **mesmo** com last-known-good.
  /// Exibir um `operational` preservado como situação atual seria afirmar uma
  /// confirmação clínica que não aconteceu.
  ReadinessSections _sectionsFor(ReadinessSnapshot snapshot) {
    if (snapshot.isUnavailable) return _unavailableSections();

    final verdict = snapshot.verdict!;
    return (
      readiness: HealthSummarySectionData.available(
        HealthSummaryReadinessView(
          status: verdict.status,
          // Rótulo e motivo são propriedade do servidor.
          reason: verdict.reason,
          restrictionSummaries: verdict.activeRestrictions
              .map((r) => r.description)
              .toList(growable: false),
          updatedAt: verdict.updatedAt,
        ),
      ),
      attention: _attentionFor(verdict),
    );
  }

  /// Atenções derivadas exclusivamente do snapshot.
  ///
  /// Fonte: `active_restrictions` + `open_alerts`. Nada de timeline, nada de
  /// sintoma promovido a restrição.
  HealthSummarySectionData<HealthSummaryAttentionView> _attentionFor(
    ReadinessClinicalVerdict verdict,
  ) {
    final items = <HealthSummaryAttentionItem>[];

    // Restrições primeiro, na precedência canônica absolute > partial >
    // attention. Ordenação estável preserva a ordem do servidor dentro do nível.
    final restrictions = [...verdict.activeRestrictions]
      ..sort((a, b) => a.level.severityRank.compareTo(b.level.severityRank));

    for (final restriction in restrictions) {
      items.add(
        HealthSummaryAttentionItem(
          id: 'restriction:${restriction.id}',
          title: restriction.description,
          subtitle: _restrictionSubtitle(restriction),
        ),
      );
    }

    // Alertas clínicos do servidor, na ordem já decidida por ele.
    for (final alert in verdict.openAlerts) {
      items.add(
        HealthSummaryAttentionItem(
          id: 'alert:${alert.code}',
          title: alert.message,
        ),
      );
    }

    // Vazio verificado é `available` com lista vazia — NÃO `unavailable`.
    // A UI apresenta ausência de pendências; indisponível seria mentira.
    return HealthSummarySectionData.available(
      HealthSummaryAttentionView(items: items),
    );
  }

  String? _restrictionSubtitle(ReadinessRestriction restriction) {
    final parts = <String>[];
    if (restriction.isOverdue) parts.add('Prazo expirado');
    if (restriction.activitiesRestricted.isNotEmpty) {
      parts.add(restriction.activitiesRestricted.join(', '));
    }
    return parts.isEmpty ? null : parts.join(' • ');
  }

  ReadinessSections _unavailableSections({
    String? readinessMessage,
    String? attentionMessage,
  }) {
    return (
      readiness: HealthSummarySectionData.unavailable(
        message: readinessMessage ?? HealthSummaryUserCopy.readinessUnavailable,
      ),
      attention: HealthSummarySectionData.unavailable(
        message: attentionMessage ?? HealthSummaryUserCopy.attentionUnavailable,
      ),
    );
  }
}
