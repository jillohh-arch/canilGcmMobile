/// Experiência de Agenda elegível para a sessão autenticada.
///
/// **Não é autorização.** É apenas a escolha de qual experiência apresentar.
/// A autoridade final permanece nas Firestore Rules: mesmo em [global], toda
/// leitura continua sujeita a `canReadHealthScheduleRecord` e qualquer
/// `permission-denied` continua sendo erro — nunca fallback silencioso.
enum HealthScheduleExperience {
  /// Escopo global já reconhecido pelo sistema → Agenda Global habilitada.
  global,

  /// Restrito ou indeterminado → permanece na Agenda per-dog.
  perDog,
}

/// Contrato de resolução da experiência.
///
/// Sem Firebase/Firestore nesta fronteira: a implementação que lê a autoridade
/// persistida vive em `data/` (mesma convenção de
/// `HealthScheduleSource` / `FirestoreHealthScheduleSource`).
abstract interface class HealthScheduleExperienceGateway {
  /// Resolve a experiência da sessão vigente. Nunca lança: falha → per-dog.
  Future<HealthScheduleExperience> resolve();
}

/// Regras **puras** de escopo, decididas somente pelas claims já emitidas.
///
/// Conclusivo em dois casos, e ambos espelham as Rules:
/// - `admin` (claim `admin`, `role` ou `roles`) → global-capable, pois
///   `isAdmin()` concede bypass explícito;
/// - `access_scope == 'own_records'` → NÃO global, pois qualquer camada que
///   declare `own_records` restringe e ampliar é impossível.
///
/// Qualquer outro caso é **indeterminado** aqui: o escopo canônico vive em
/// `access_profiles/{id}.scope`, que exige leitura (ver o gateway em `data/`).
///
/// Proibido por contrato: comparar `Dog.conductorRa` com o RA do usuário,
/// derivar acesso dos documentos de `health_schedule`, ou reproduzir
/// `canAccessDogRecord`. Isso criaria uma segunda autoridade.
abstract final class HealthScheduleExperienceClaims {
  const HealthScheduleExperienceClaims._();

  /// `true` quando as claims declaram restrição `own_records`.
  static bool declaresOwnRecords(Map<String, dynamic> claims) {
    return asString(claims['access_scope']) == 'own_records' ||
        asString(claims['accessScope']) == 'own_records';
  }

  /// `true` quando as claims marcam autoridade administrativa.
  static bool marksAdmin(Map<String, dynamic> claims) {
    if (claims['admin'] == true) return true;
    final role = asString(claims['role']);
    if (role == 'admin' || role == 'administrador') return true;
    final roles = claims['roles'];
    if (roles is List) {
      for (final entry in roles) {
        final value = asString(entry);
        if (value == 'admin' || value == 'administrador') return true;
      }
    }
    return false;
  }

  /// Resolve somente pelo que as claims provam (sem I/O).
  ///
  /// Fail-closed: escopo não conclusivo pela identidade → per-dog.
  static HealthScheduleExperience fromClaims(Map<String, dynamic>? claims) {
    final map = claims ?? const <String, dynamic>{};
    if (declaresOwnRecords(map)) return HealthScheduleExperience.perDog;
    if (marksAdmin(map)) return HealthScheduleExperience.global;
    return HealthScheduleExperience.perDog;
  }

  static String asString(Object? value) => value is String ? value.trim() : '';

  static String firstNonEmpty(List<Object?> values) {
    for (final value in values) {
      final normalized = asString(value);
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }
}

/// Gateway que nunca habilita o modo global.
///
/// Default seguro para composição/testes: mantém a Agenda per-dog.
final class PerDogHealthScheduleExperienceGateway
    implements HealthScheduleExperienceGateway {
  const PerDogHealthScheduleExperienceGateway();

  @override
  Future<HealthScheduleExperience> resolve() async =>
      HealthScheduleExperience.perDog;
}

/// Gateway de valor fixo (testes de wiring).
final class FixedHealthScheduleExperienceGateway
    implements HealthScheduleExperienceGateway {
  const FixedHealthScheduleExperienceGateway(this.experience);

  final HealthScheduleExperience experience;

  @override
  Future<HealthScheduleExperience> resolve() async => experience;
}
