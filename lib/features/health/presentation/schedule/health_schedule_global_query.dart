import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';

/// Query estruturada da Agenda Preventiva **global** (multi-K9).
///
/// Diferente de [HealthScheduleQuery] (um único `dogId` obrigatório), esta
/// query recebe o **catálogo autorizado** de K9s e nunca representa "todos os
/// cães": a fronteira collection-group das Rules exige prova de `dog_id` por
/// igualdade/`in`, então uma consulta irrestrita é negada — inclusive para
/// escopo global. Enumerar o catálogo é requisito de autorização, não
/// otimização.
///
/// A resolução do catálogo é responsabilidade de camada superior. Este objeto
/// apenas transporta a lista já autorizada, normalizada e sem duplicatas.
final class HealthScheduleGlobalQuery {
  HealthScheduleGlobalQuery({
    required Iterable<String> authorizedDogIds,
    this.lifecycleStatus = ScheduleLifecycleStatus.open,
    Set<ScheduleType> types = const {},
    this.maxItems = defaultMaxItems,
    this.chunkSize = defaultChunkSize,
  }) : authorizedDogIds = _normalizeCatalog(authorizedDogIds),
       types = Set<ScheduleType>.unmodifiable(types) {
    if (maxItems <= 0) {
      throw ArgumentError.value(maxItems, 'maxItems', 'deve ser positivo');
    }
    if (chunkSize <= 0 || chunkSize > maxChunkSize) {
      throw ArgumentError.value(
        chunkSize,
        'chunkSize',
        'deve estar em 1..$maxChunkSize',
      );
    }
  }

  /// Teto absoluto do operador `in` do Firestore (HW-4A.2D.1: GLOBAL_MAX = 30).
  static const int maxChunkSize = 30;

  /// Chunk operacional padrão.
  ///
  /// HW-4A.2D.1 mediu dois tetos independentes e **o menor vence**:
  /// `in` do Firestore = 30; orçamento de `get()`/`exists()` das Rules = 10,
  /// que na prática limita `own_records` a 8 (cada documento avaliado exige
  /// `canAccessDogRecord(dogId)`; escopo global curto-circuita e não faz
  /// lookup por cão).
  ///
  /// Este source não conhece o escopo do chamador, então adota o valor
  /// operacional seguro com folga: um chamador global apenas emite mais
  /// queries, enquanto um condutor `own_records` com chunk 30 receberia
  /// `permission-denied`. Ajustar somente com evidência de escopo.
  static const int defaultChunkSize = 5;

  /// Limite explícito de itens desta foundation (sem paginação multi-chunk).
  static const int defaultMaxItems = 100;

  /// Catálogo autorizado — normalizado, deduplicado, sem entradas vazias.
  ///
  /// Vazio é permitido e significa "nada autorizado": o source devolve vazio
  /// **sem emitir query**. Nunca degrada para consulta irrestrita.
  final List<String> authorizedDogIds;

  /// Lifecycle **persistido** consultado remotamente.
  ///
  /// Estados temporais (`today`/`upcoming`/`pending`/`overdue`) são derivados
  /// na leitura pela policy de apresentação e nunca são consultados aqui.
  final ScheduleLifecycleStatus lifecycleStatus;

  /// Vazio = todos os tipos. Filtro aplicado localmente (sem índice novo).
  final Set<ScheduleType> types;

  final int maxItems;
  final int chunkSize;

  bool get isEmptyCatalog => authorizedDogIds.isEmpty;

  /// Divide o catálogo em chunks determinísticos de no máximo [chunkSize].
  List<List<String>> get chunks {
    final out = <List<String>>[];
    for (var i = 0; i < authorizedDogIds.length; i += chunkSize) {
      final end = (i + chunkSize) > authorizedDogIds.length
          ? authorizedDogIds.length
          : i + chunkSize;
      out.add(List<String>.unmodifiable(authorizedDogIds.sublist(i, end)));
    }
    return List<List<String>>.unmodifiable(out);
  }

  /// Normaliza preservando a ordem de primeira aparição (determinismo dos
  /// chunks entre execuções com o mesmo catálogo).
  static List<String> _normalizeCatalog(Iterable<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final entry in raw) {
      final normalized = entry.trim();
      if (normalized.isEmpty) {
        throw ArgumentError.value(
          entry,
          'authorizedDogIds',
          'dogId vazio não é identidade válida',
        );
      }
      if (seen.add(normalized)) out.add(normalized);
    }
    return List<String>.unmodifiable(out);
  }
}
