import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/schedule/firestore_health_schedule_experience_gateway.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_experience_scope.dart';

/// HW-4C — resolução do escopo efetivo pela MESMA autoridade das Rules:
/// `users/{ra}.access_profile_id` → `access_profiles/{id}.scope`.
///
/// Não é cálculo de autorização no cliente: é leitura da fonte canônica do
/// servidor, ambas legíveis pela sessão autenticada. Espelha `authState()`.
void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  Future<void> seedUser(
    String ra, {
    String? profileId,
    String? accessScope,
    Object? deletedAt,
    bool camelCaseProfile = false,
  }) async {
    final data = <String, dynamic>{'ra': ra};
    if (profileId != null) {
      data[camelCaseProfile ? 'accessProfileId' : 'access_profile_id'] =
          profileId;
    }
    if (accessScope != null) data['access_scope'] = accessScope;
    if (deletedAt != null) data['deleted_at'] = deletedAt;
    await db.collection('users').doc(ra).set(data);
  }

  Future<void> seedProfile(
    String id, {
    required String scope,
    String? status,
  }) async {
    final data = <String, dynamic>{'scope': scope};
    if (status != null) data['status'] = status;
    await db.collection('access_profiles').doc(id).set(data);
  }

  /// Resolve pela cadeia canônica. `user: null` é coberto separadamente;
  /// aqui exercitamos a lógica de perfil com claims controladas.
  Future<HealthScheduleExperience> resolve(Map<String, dynamic> claims) {
    return FirestoreHealthScheduleExperienceGateway(
      firestore: db,
      user: null,
    ).resolveWithClaims(claims);
  }

  group('perfil global não-admin agora é suportado', () {
    test('gestor com profile scope=global → global', () async {
      await seedUser('600001', profileId: 'gestor_global');
      await seedProfile('gestor_global', scope: 'global');

      expect(
        await resolve({'ra': '600001'}),
        HealthScheduleExperience.global,
        reason: 'perfil global sem claim admin deve habilitar a Agenda Global',
      );
    });

    test('aceita accessProfileId camelCase', () async {
      await seedUser('600002', profileId: 'gestor', camelCaseProfile: true);
      await seedProfile('gestor', scope: 'global');

      expect(await resolve({'ra': '600002'}), HealthScheduleExperience.global);
    });

    test('status ausente é tolerado como ativo', () async {
      await seedUser('600003', profileId: 'gestor');
      await seedProfile('gestor', scope: 'global');

      expect(await resolve({'ra': '600003'}), HealthScheduleExperience.global);
    });

    test('status active explícito → global', () async {
      await seedUser('600004', profileId: 'gestor');
      await seedProfile('gestor', scope: 'global', status: 'active');

      expect(await resolve({'ra': '600004'}), HealthScheduleExperience.global);
    });
  });

  group('restrição vence em qualquer camada', () {
    test('perfil own_records → perDog', () async {
      await seedUser('691755', profileId: 'operador_k9');
      await seedProfile('operador_k9', scope: 'own_records');

      expect(await resolve({'ra': '691755'}), HealthScheduleExperience.perDog);
    });

    test('claim own_records vence perfil global (sem I/O)', () async {
      await seedUser('600005', profileId: 'gestor');
      await seedProfile('gestor', scope: 'global');

      expect(
        await resolve({'ra': '600005', 'access_scope': 'own_records'}),
        HealthScheduleExperience.perDog,
      );
    });

    test('user.access_scope own_records vence perfil global', () async {
      await seedUser('600006', profileId: 'gestor', accessScope: 'own_records');
      await seedProfile('gestor', scope: 'global');

      expect(await resolve({'ra': '600006'}), HealthScheduleExperience.perDog);
    });

    test('perfil inativo → perDog', () async {
      await seedUser('600007', profileId: 'gestor');
      await seedProfile('gestor', scope: 'global', status: 'inactive');

      expect(await resolve({'ra': '600007'}), HealthScheduleExperience.perDog);
    });

    test('usuário soft-deleted → perDog', () async {
      await seedUser('600008', profileId: 'gestor', deletedAt: DateTime.now());
      await seedProfile('gestor', scope: 'global');

      expect(await resolve({'ra': '600008'}), HealthScheduleExperience.perDog);
    });
  });

  group('fail-closed', () {
    test('claim ra ausente → perDog (sem I/O)', () async {
      await seedProfile('gestor', scope: 'global');
      expect(await resolve(const {}), HealthScheduleExperience.perDog);
    });

    test('usuário inexistente → perDog', () async {
      expect(await resolve({'ra': '999999'}), HealthScheduleExperience.perDog);
    });

    test('usuário sem access_profile_id → perDog', () async {
      await seedUser('600009');
      expect(await resolve({'ra': '600009'}), HealthScheduleExperience.perDog);
    });

    test('perfil inexistente → perDog', () async {
      await seedUser('600010', profileId: 'perfil_fantasma');
      expect(await resolve({'ra': '600010'}), HealthScheduleExperience.perDog);
    });

    test('scope malformado no perfil → perDog', () async {
      await seedUser('600011', profileId: 'quebrado');
      await seedProfile('quebrado', scope: 'TODOS');
      expect(await resolve({'ra': '600011'}), HealthScheduleExperience.perDog);
    });

    test('scope ausente no perfil → perDog', () async {
      await seedUser('600012', profileId: 'sem_scope');
      await db.collection('access_profiles').doc('sem_scope').set({
        'status': 'active',
      });
      expect(await resolve({'ra': '600012'}), HealthScheduleExperience.perDog);
    });
  });

  group('admin curto-circuita sem I/O', () {
    test('admin → global mesmo sem documentos', () async {
      // Nenhum seed: prova que admin não depende da leitura do perfil.
      expect(
        await resolve({'ra': '1', 'role': 'admin'}),
        HealthScheduleExperience.global,
      );
    });

    test('admin com own_records declarado → perDog', () async {
      expect(
        await resolve({
          'ra': '1',
          'role': 'admin',
          'access_scope': 'own_records',
        }),
        HealthScheduleExperience.perDog,
      );
    });
  });
}
