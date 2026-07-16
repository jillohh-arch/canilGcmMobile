/// Copy operacional da Timeline do Histórico Clínico (sem jargão técnico).
abstract final class HealthTimelineUserCopy {
  HealthTimelineUserCopy._();

  static const title = 'HISTÓRICO CLÍNICO';
  static const subtitleDefault = 'Linha do tempo da saúde';

  static const filterAction = 'Filtros';
  static const filterActionShort = 'Filtrar';

  static const emptyTitle = 'Sem registros';
  static const emptyMessage = 'Nenhum registro de saúde encontrado.';
  static const emptyWithFiltersTitle = 'Nenhum resultado';
  static const emptyWithFiltersMessage =
      'Nenhum registro corresponde aos filtros aplicados.';
  static const clearFilters = 'Limpar filtros';

  static const errorTitle = 'Não foi possível carregar';
  static const errorMessage =
      'Não foi possível carregar o histórico agora. Tente novamente.';

  static const offlineTitle = 'Sem conexão';
  static const offlineMessage =
      'Não foi possível carregar o histórico sem conexão.';

  static const retry = 'Tentar novamente';
  static const loadMore = 'Carregar mais';
  static const loadingMore = 'Carregando mais registros…';
  static const loadMoreError = 'Não foi possível carregar mais registros.';

  static const refreshError = 'Não foi possível atualizar o histórico agora.';
  static const refreshOffline =
      'Sem conexão. Exibindo os registros já carregados.';

  static const cancelledLabel = 'CANCELADO';
  static const unknownTypeLabel = 'REGISTRO DE SAÚDE';

  static const initialTitle = 'Histórico clínico';
  static const initialMessage =
      'O histórico aparece após a seleção do K9 e o carregamento dos registros.';

  static const loadingMessage = 'Carregando histórico…';

  /// Remove mensagens técnicas antes da UI (espelha a disciplina do Resumo).
  static String sanitizeMessage(String? technical, {required String fallback}) {
    if (technical == null) return fallback;
    final t = technical.trim();
    if (t.isEmpty) return fallback;

    final lower = t.toLowerCase();
    if (lower.contains('index') ||
        lower.contains('firebase') ||
        lower.contains('firestore') ||
        lower.contains('googleapis') ||
        lower.contains('cloud_firestore') ||
        lower.contains('permission') ||
        lower.contains('failed-precondition') ||
        lower.contains('exception') ||
        lower.contains('stack') ||
        lower.contains('http://') ||
        lower.contains('https://') ||
        lower.contains('console.firebase') ||
        lower.contains('coexist') ||
        lower.contains('legado') ||
        lower.contains('health v1') ||
        lower.contains('adapter') ||
        lower.contains('reader') ||
        lower.contains('.dart') ||
        lower.contains('collection') ||
        lower.contains('document/') ||
        lower.contains('dogs/') ||
        lower.contains('[') ||
        t.contains('\n') ||
        t.length > 96) {
      return fallback;
    }
    return t;
  }
}
