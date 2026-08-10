import 'package:canil_gcm/features/dogs/domain/weight_record.dart';
import 'package:canil_gcm/features/health/domain/weight_collection_policy.dart';
import 'package:canil_gcm/features/health/presentation/weight/prontuario_weight_read_state.dart';

/// Fatos de peso apresentáveis do prontuário (WEIGHT-01E-C2B.3).
///
/// Autoridade única: o registro atual — peso, data e endpoint de tendência —
/// vem SEMPRE de [ProntuarioWeightReadState.current]. O histórico só serve
/// para escolher o registro anterior e desenhar série; nunca redefine o atual.
///
/// O defeito corrigido aqui era uma segunda autoridade: widgets ordenavam o
/// histórico apenas por `measuredAt` e usavam o primeiro como "último peso".
/// Com dois registros no mesmo `measuredAt` — cenário suportado pelo writer —
/// isso divergia do atual canônico, exibindo dois números como fato na mesma
/// tela. O desempate completo (`recordedAt`, depois `entityId` UTF-16) vive em
/// [compareWeightRecency] e não é reimplementado.
class ProntuarioWeightFacts {
  const ProntuarioWeightFacts._({
    required this.current,
    required this.previous,
    required this.recordCount,
  });

  /// Deriva os fatos a partir do estado canônico e do histórico válido.
  ///
  /// [history] participa apenas da escolha de [previous] e da contagem. Se
  /// [readState] não for `current`, não há atual algum: nenhum registro do
  /// histórico é promovido, mesmo que a lista contenha válidos.
  factory ProntuarioWeightFacts.from({
    required ProntuarioWeightReadState readState,
    required List<WeightRecord> history,
  }) {
    final current = readState.current;
    if (current == null) {
      // Estados none / inconclusive / unavailable: sem atual factual.
      return ProntuarioWeightFacts._(
        current: null,
        previous: null,
        recordCount: history.length,
      );
    }

    // Anterior = candidato mais recente excluindo o atual por identidade
    // documental (`entityId`), nunca por peso ou data — dois registros podem
    // compartilhar ambos.
    final candidates =
        history
            .where((record) => record.id != current.id)
            .toList(growable: false)
          ..sort(_byCanonicalRecency);

    return ProntuarioWeightFacts._(
      current: current,
      previous: candidates.isEmpty ? null : candidates.first,
      recordCount: history.length,
    );
  }

  /// Registro atual canônico; `null` quando não há evidência factual.
  final WeightRecord? current;

  /// Registro imediatamente anterior ao atual, quando existe.
  final WeightRecord? previous;

  /// Total de registros válidos no histórico carregado.
  final int recordCount;

  bool get hasCurrent => current != null;

  /// Peso atual em kg.
  double? get currentWeightKg => current?.weightKg;

  /// Data da pesagem atual — do MESMO registro que [currentWeightKg].
  DateTime? get currentMeasuredAt => current?.measuredAt;

  /// Variação entre o atual e o anterior; `null` sem os dois extremos.
  ///
  /// O endpoint atual é o canônico, não o primeiro item de uma lista ordenada
  /// localmente: a tendência compara o mesmo registro que a UI exibe.
  double? get deltaKg {
    final currentRecord = current;
    final previousRecord = previous;
    if (currentRecord == null || previousRecord == null) return null;
    return currentRecord.weightKg - previousRecord.weightKg;
  }
}

/// Aplica a ordenação canônica à façade [WeightRecord].
///
/// Desde que a façade expõe `recordedAt`, o desempate aqui é o MESMO de
/// [compareWeightRecency]: `measuredAt` DESC → `recordedAt` DESC → `entityId`
/// DESC. Ambos delegam a [compareWeightCanonicalOrder], então esta superfície
/// não pode divergir do aggregate sobre qual pesagem é a mais recente.
///
/// Escopo desta ordenação: `current` já chega canônico via
/// [ProntuarioWeightReadState], então este comparador decide apenas
/// [ProntuarioWeightFacts.previous] — e por consequência `deltaKg`/tendência.
/// Ele NÃO redefine qual pesagem é a atual.
int _byCanonicalRecency(WeightRecord a, WeightRecord b) =>
    compareWeightCanonicalOrder(
      aMeasuredAt: a.measuredAt,
      aRecordedAt: a.recordedAt,
      aEntityId: a.id,
      bMeasuredAt: b.measuredAt,
      bRecordedAt: b.recordedAt,
      bEntityId: b.id,
    );
