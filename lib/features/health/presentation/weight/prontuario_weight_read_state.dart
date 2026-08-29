import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/dogs/data/weight_history_service.dart';
import 'package:canil_gcm/features/dogs/domain/weight_record.dart';

/// Estado factual da leitura de peso canônico (WEIGHT-01E-C2B.1A).
///
/// Os quatro estados são distinguíveis por contrato. O defeito original do
/// prontuário não era um rótulo errado: era informação perdida —
/// `inconclusive` e erro de leitura colapsavam em "sem registro" e a tela
/// exibia `dogs.weight`, uma projeção legada, como se fosse evidência clínica.
enum ProntuarioWeightState {
  /// Há peso atual factual.
  current,

  /// Nenhuma pesagem canônica elegível (coleção vazia ou somente invalidated).
  none,

  /// Bloqueador global (`malformed`/`unsupported`/`entityId` duplicado):
  /// o peso atual é desconhecido e nenhum registro anterior é promovido.
  inconclusive,

  /// Falha de leitura (permissão/rede/parsing). NÃO é ausência de registro.
  unavailable,
}

/// Resultado da resolução de peso do prontuário.
@immutable
class ProntuarioWeightReadState {
  const ProntuarioWeightReadState._(this.state, this.current);

  const ProntuarioWeightReadState.current(WeightRecord record)
    : this._(ProntuarioWeightState.current, record);

  const ProntuarioWeightReadState.none()
    : this._(ProntuarioWeightState.none, null);

  const ProntuarioWeightReadState.inconclusive()
    : this._(ProntuarioWeightState.inconclusive, null);

  const ProntuarioWeightReadState.unavailable()
    : this._(ProntuarioWeightState.unavailable, null);

  final ProntuarioWeightState state;

  /// Registro factual; `null` em qualquer estado que não seja
  /// [ProntuarioWeightState.current].
  final WeightRecord? current;

  /// Peso atual canônico em kg, ou `null` quando não há evidência factual.
  double? get weightKg => current?.weightKg;

  bool get isCurrent => state == ProntuarioWeightState.current;
  bool get isNone => state == ProntuarioWeightState.none;
  bool get isInconclusive => state == ProntuarioWeightState.inconclusive;
  bool get isUnavailable => state == ProntuarioWeightState.unavailable;
}

/// Resolve o peso atual do prontuário a partir da fonte canônica.
///
/// Delega inteiramente a [WeightHistoryService.getLatest], que aplica a policy
/// coletiva compartilhada (coleção completa, bloqueadores globais, desempate
/// canônico). Esta unidade NÃO reclassifica documentos, não ordena e não
/// conhece `dogs.weight` / `_last_weight_kg` / `_last_weight_at`: uma projeção
/// legada nunca participa da decisão de peso atual.
///
/// Mapeamento preservado do WEIGHT-01E-C2B:
/// - `WeightRecord`                → [ProntuarioWeightState.current]
/// - `null`                        → [ProntuarioWeightState.none]
/// - `WeightHistoryReadException`  → [ProntuarioWeightState.inconclusive]
/// - `FirebaseException`           → [ProntuarioWeightState.unavailable]
/// - erro genérico                 → [ProntuarioWeightState.unavailable]
class ProntuarioWeightResolver {
  const ProntuarioWeightResolver(this._service);

  final WeightHistoryService _service;

  Future<ProntuarioWeightReadState> resolve(String dogId) async {
    try {
      final record = await _service.getLatest(dogId);
      return record == null
          ? const ProntuarioWeightReadState.none()
          : ProntuarioWeightReadState.current(record);
    } on WeightHistoryReadException catch (e) {
      // Documento ilegível ou schema não suportado em qualquer posição da
      // coleção: estado honestamente inconclusivo, sem promover anterior.
      debugPrint('[Prontuario] peso inconclusivo: ${e.reason}');
      return const ProntuarioWeightReadState.inconclusive();
    } on FirebaseException catch (e) {
      debugPrint('[Prontuario] peso indisponível [${e.code}]: ${e.message}');
      return const ProntuarioWeightReadState.unavailable();
    } catch (e) {
      debugPrint('[Prontuario] peso indisponível: $e');
      return const ProntuarioWeightReadState.unavailable();
    }
  }
}
