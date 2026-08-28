import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_experience_scope.dart';

/// Resolve a experiência de Agenda lendo a **mesma autoridade que as Rules
/// usam**: `users/{ra}.access_profile_id` → `access_profiles/{id}.scope`.
///
/// Isto NÃO é cálculo de autorização no cliente: é leitura da fonte canônica
/// do servidor, ambas legíveis pela sessão autenticada
/// (`users/{ra}`: `allow read: if signedIn()`; `access_profiles/{id}`:
/// `allow read: if canReadAccessProfile()`). Nenhuma heurística, nenhum
/// `conductorRa`, nenhuma inferência a partir de `health_schedule`.
///
/// Espelha `authState()` na ordem exata:
///   1. `admin` na claim → global imediatamente (bypass reconhecido);
///   2. `access_scope == 'own_records'` na claim → per-dog imediatamente;
///   3. `ra` da claim localiza `users/{ra}`;
///   4. `access_profile_id` (ou `accessProfileId`) localiza o perfil;
///   5. `status` ausente é tolerado como `active`;
///   6. `scope == 'global'` habilita; `own_records` restringe;
///   7. usuário soft-deleted nunca é global.
///
/// Fail-closed: qualquer inconsistência, ausência, erro de rede ou
/// `permission-denied` devolve [HealthScheduleExperience.perDog]. A Agenda
/// per-dog é funcional, apenas menos ampla — degradar para ela é seguro;
/// habilitar o global indevidamente não é.
final class FirestoreHealthScheduleExperienceGateway
    implements HealthScheduleExperienceGateway {
  FirestoreHealthScheduleExperienceGateway({
    required FirebaseFirestore firestore,
    required User? user,
  }) : _db = firestore,
       _user = user;

  final FirebaseFirestore _db;
  final User? _user;

  /// Factory de produção: sessão e instância padrão.
  ///
  /// Firebase pode não estar inicializado (testes de widget): nesse caso
  /// devolve um gateway que mantém a Agenda per-dog.
  static HealthScheduleExperienceGateway forDefault() {
    try {
      return FirestoreHealthScheduleExperienceGateway(
        firestore: FirebaseFirestore.instance,
        user: FirebaseAuth.instance.currentUser,
      );
    } catch (_) {
      return const PerDogHealthScheduleExperienceGateway();
    }
  }

  @override
  Future<HealthScheduleExperience> resolve() async {
    final user = _user;
    if (user == null) return HealthScheduleExperience.perDog;

    final Map<String, dynamic> claims;
    try {
      claims = (await user.getIdTokenResult()).claims ?? const {};
    } catch (_) {
      return HealthScheduleExperience.perDog;
    }

    return resolveWithClaims(claims);
  }

  /// Mesma resolução, a partir de claims já obtidas.
  ///
  /// Permite provar a cadeia canônica sem depender de uma sessão real.
  Future<HealthScheduleExperience> resolveWithClaims(
    Map<String, dynamic> claims,
  ) async {
    // Restrição declarada na claim vence sem precisar de I/O.
    if (HealthScheduleExperienceClaims.declaresOwnRecords(claims)) {
      return HealthScheduleExperience.perDog;
    }

    // Admin já é conclusivo pelas Rules (isAdmin concede bypass).
    if (HealthScheduleExperienceClaims.marksAdmin(claims)) {
      return HealthScheduleExperience.global;
    }

    final ra = HealthScheduleExperienceClaims.asString(claims['ra']);
    if (ra.isEmpty) return HealthScheduleExperience.perDog;

    try {
      final userSnap = await _db.collection('users').doc(ra).get();
      if (!userSnap.exists) return HealthScheduleExperience.perDog;
      final userData = userSnap.data() ?? const <String, dynamic>{};

      // Soft-delete: nunca global.
      if (userData['deleted_at'] != null) {
        return HealthScheduleExperience.perDog;
      }

      // Restrição na camada do usuário também vence.
      if (HealthScheduleExperienceClaims.declaresOwnRecords(userData)) {
        return HealthScheduleExperience.perDog;
      }

      final profileId = HealthScheduleExperienceClaims.firstNonEmpty([
        userData['access_profile_id'],
        userData['accessProfileId'],
      ]);
      if (profileId.isEmpty) return HealthScheduleExperience.perDog;

      final profileSnap = await _db
          .collection('access_profiles')
          .doc(profileId)
          .get();
      if (!profileSnap.exists) return HealthScheduleExperience.perDog;
      final profile = profileSnap.data() ?? const <String, dynamic>{};

      // Enum persistido é 'active' | 'inactive'; ausente tolerado como ativo.
      final status = HealthScheduleExperienceClaims.asString(profile['status']);
      if (status.isNotEmpty && status != 'active') {
        return HealthScheduleExperience.perDog;
      }

      return HealthScheduleExperienceClaims.asString(profile['scope']) ==
              'global'
          ? HealthScheduleExperience.global
          : HealthScheduleExperience.perDog;
    } catch (_) {
      // Inclui permission-denied na leitura do perfil: fail-closed.
      return HealthScheduleExperience.perDog;
    }
  }
}
