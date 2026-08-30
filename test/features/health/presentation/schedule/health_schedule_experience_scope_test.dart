import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_experience_scope.dart';

/// HW-4C — gate de EXPERIÊNCIA (não de autorização).
///
/// A autoridade final permanece nas Rules. Este resolver apenas decide qual
/// experiência apresentar, e é deliberadamente fail-closed: escopo não
/// conclusivo pela identidade cai para per-dog.
void main() {
  group('own_records restringe (nunca ampliável)', () {
    test('access_scope own_records → perDog', () {
      expect(
        HealthScheduleExperienceClaims.fromClaims({
          'access_scope': 'own_records',
        }),
        HealthScheduleExperience.perDog,
      );
    });

    test('accessScope camelCase own_records → perDog', () {
      expect(
        HealthScheduleExperienceClaims.fromClaims({
          'accessScope': 'own_records',
        }),
        HealthScheduleExperience.perDog,
      );
    });

    test('own_records vence admin (restrição prevalece)', () {
      // Espelha authState() nas Rules: qualquer camada que declare
      // own_records restringe; ampliar é impossível.
      expect(
        HealthScheduleExperienceClaims.fromClaims({
          'role': 'admin',
          'access_scope': 'own_records',
        }),
        HealthScheduleExperience.perDog,
      );
    });
  });

  group('admin é conclusivamente global-capable', () {
    test('role admin → global', () {
      expect(
        HealthScheduleExperienceClaims.fromClaims({'role': 'admin'}),
        HealthScheduleExperience.global,
      );
    });

    test('role administrador → global', () {
      expect(
        HealthScheduleExperienceClaims.fromClaims({'role': 'administrador'}),
        HealthScheduleExperience.global,
      );
    });

    test('claim admin booleana → global', () {
      expect(
        HealthScheduleExperienceClaims.fromClaims({'admin': true}),
        HealthScheduleExperience.global,
      );
    });

    test('roles list contendo admin → global', () {
      expect(
        HealthScheduleExperienceClaims.fromClaims({
          'roles': ['condutor', 'administrador'],
        }),
        HealthScheduleExperience.global,
      );
    });
  });

  group('fail-closed em escopo indeterminado', () {
    test('claims vazias → perDog', () {
      expect(
        HealthScheduleExperienceClaims.fromClaims(const {}),
        HealthScheduleExperience.perDog,
      );
    });

    test('claims nulas → perDog', () {
      expect(
        HealthScheduleExperienceClaims.fromClaims(null),
        HealthScheduleExperience.perDog,
      );
    });

    test('condutor sem escopo declarado → perDog', () {
      // O escopo canônico vive em access_profiles/{id}.scope no Firestore.
      // O cliente não replica essa resolução.
      expect(
        HealthScheduleExperienceClaims.fromClaims({'role': 'condutor'}),
        HealthScheduleExperience.perDog,
      );
    });

    test('claim access_scope global NÃO basta para habilitar', () {
      // Nas Rules, `global` vem do PERFIL, não da claim: a claim só restringe.
      // Preferimos gestor global vendo per-dog a condutor vendo Agenda Global
      // falhar inteira com permission-denied.
      expect(
        HealthScheduleExperienceClaims.fromClaims({'access_scope': 'global'}),
        HealthScheduleExperience.perDog,
      );
    });

    test('tipo inesperado em role não quebra nem amplia', () {
      expect(
        HealthScheduleExperienceClaims.fromClaims({'role': 42}),
        HealthScheduleExperience.perDog,
      );
    });

    test('gateway per-dog nunca habilita global', () async {
      expect(
        await const PerDogHealthScheduleExperienceGateway().resolve(),
        HealthScheduleExperience.perDog,
      );
    });
  });
}
