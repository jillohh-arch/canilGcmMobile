/// Copy operacional do Resumo (sem jargão de arquitetura / SDK).
abstract final class HealthSummaryUserCopy {
  HealthSummaryUserCopy._();

  static const readinessUnavailable =
      'A avaliação de prontidão ainda não está disponível.';
  static const treatmentsUnavailable =
      'Informações de tratamentos ainda não estão disponíveis.';
  static const attentionUnavailable =
      'Não foi possível determinar as atenções deste K9 no momento.';
  static const vaccinationUnavailable =
      'Dados de vacinação indisponíveis no momento.';
  static const weightUnavailable = 'Dados de peso indisponíveis no momento.';
  static const nutritionUnavailable =
      'Dados de alimentação indisponíveis no momento.';
  static const recentUnavailable =
      'Não foi possível carregar os registros recentes.';
  static const genericUnavailable = 'Dados indisponíveis no momento.';

  /// Falha de canal/rede (preserva distinção offline após sanitização).
  /// Mantém palavras reconhecíveis por [CoexistenceHealthSummarySource] offline.
  static const networkUnavailable =
      'Não foi possível conectar. Verifique a rede.';

  static const readinessNotRecorded = 'Prontidão ainda não registrada.';
  static const weightNotRecorded = 'Nenhuma pesagem registrada.';
  static const vaccinationNotRecorded = 'Nenhuma vacinação registrada.';
  static const treatmentsNotRecorded = 'Nenhuma medicação registrada.';
  static const nutritionNotRecorded =
      'Nenhum plano ou refeição registrada para hoje.';
  static const recentNotRecorded = 'Nenhum registro recente.';

  /// Remove mensagens técnicas de infraestrutura antes da UI.
  static String sanitizeUnavailable(
    String? technical, {
    required String fallback,
  }) {
    if (technical == null) return fallback;
    final t = technical.trim();
    if (t.isEmpty) return fallback;

    final lower = t.toLowerCase();
    if (lower.contains('index') ||
        lower.contains('firebase') ||
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
        lower.contains('[') ||
        t.length > 72) {
      return fallback;
    }
    return t;
  }

  static bool looksTechnical(String? message) {
    if (message == null || message.trim().isEmpty) return false;
    return sanitizeUnavailable(message, fallback: '__tech__') == '__tech__';
  }
}
