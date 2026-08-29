import 'package:canil_gcm/features/health/domain/dose_administration.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final actor = RecordedBy(
    uid: 'u1',
    name: 'Condutor',
    internalRole: 'condutor',
  );
  final now = DateTime.utc(2026, 7, 14, 12);

  group('DoseIdentity', () {
    test('deriveDoseId é determinístico para mesma entrada', () {
      final a = DoseIdentity(
        protocolId: 'p1',
        plannedDoseId: 'd1',
      ).deriveDoseId();
      final b = DoseIdentity(
        protocolId: 'p1',
        plannedDoseId: 'd1',
      ).deriveDoseId();
      expect(a, b);
      expect(a.length, 64);
    });

    test('entradas diferentes produzem IDs diferentes', () {
      final a = DoseIdentity(
        protocolId: 'p1',
        plannedDoseId: 'd1',
      ).deriveDoseId();
      final b = DoseIdentity(
        protocolId: 'p1',
        plannedDoseId: 'd2',
      ).deriveDoseId();
      final c = DoseIdentity(
        protocolId: 'p2',
        plannedDoseId: 'd1',
      ).deriveDoseId();
      expect(a, isNot(b));
      expect(a, isNot(c));
      expect(b, isNot(c));
    });

    test('encoding length-prefix evita colisão de concatenação ambígua', () {
      // Sem length-prefix, "ab"+"c" e "a"+"bc" colidem em concatenação simples.
      final x = DoseIdentity(
        protocolId: 'ab',
        plannedDoseId: 'c',
      ).deriveDoseId();
      final y = DoseIdentity(
        protocolId: 'a',
        plannedDoseId: 'bc',
      ).deriveDoseId();
      expect(x, isNot(y));
    });

    test('idempotency_key coincide com doseId', () {
      final identity = DoseIdentity(protocolId: 'p1', plannedDoseId: 'd1');
      final admin = DoseAdministration(
        identity: identity,
        protocolId: 'p1',
        dogId: 'dog-1',
        scheduledFor: now.subtract(const Duration(hours: 1)),
        status: DoseStatus.administered,
        recordedBy: actor,
        recordedAt: now,
        schemaVersion: 1,
        administeredAt: now,
      );
      expect(admin.doseId, admin.idempotencyKey);
    });

    test('vetor estável p1/d1 (encoding privado length-prefix + sha256)', () {
      final id = DoseIdentity(protocolId: 'p1', plannedDoseId: 'd1');
      // Vetor independente: sha256(u32be(2)||"p1"||u32be(2)||"d1")
      expect(
        id.deriveDoseId(),
        'd214c74332127faf1e6cd2198436939782f15f430fc8a5d2436949672621dcb8',
      );
    });

    test('entradas UTF-8 preservadas e determinísticas', () {
      final a = DoseIdentity(
        protocolId: 'café',
        plannedDoseId: 'dose-1',
      ).deriveDoseId();
      final b = DoseIdentity(
        protocolId: 'café',
        plannedDoseId: 'dose-1',
      ).deriveDoseId();
      expect(a, b);
      expect(a.length, 64);
    });

    test('vetor multibyte UTF-8 independente (日本 / dose-α)', () {
      // Vetor calculado fora da implementação:
      // utf8("日本") = 6 bytes; utf8("dose-α") = 7 bytes
      // sha256(u32be(6)||utf8("日本")||u32be(7)||utf8("dose-α"))
      final id = DoseIdentity(protocolId: '日本', plannedDoseId: 'dose-α');
      expect(
        id.deriveDoseId(),
        '5f344b47fd0fabd9937cd69d13998cba0997c1344280c8bc7a71964569062465',
      );
    });

    test('protocolId vazio é rejeitado', () {
      expect(
        () => DoseIdentity(protocolId: '   ', plannedDoseId: 'd1'),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('plannedDoseId vazio é rejeitado', () {
      expect(
        () => DoseIdentity(protocolId: 'p1', plannedDoseId: ''),
        throwsA(isA<HealthDomainException>()),
      );
    });
  });

  group('DoseAdministration', () {
    DoseAdministration build({DoseStatus status = DoseStatus.administered}) =>
        DoseAdministration(
          identity: DoseIdentity(protocolId: 'p1', plannedDoseId: 'd1'),
          protocolId: 'p1',
          dogId: 'dog-1',
          scheduledFor: now.subtract(const Duration(hours: 1)),
          status: status,
          recordedBy: actor,
          recordedAt: now,
          schemaVersion: 1,
          administeredAt: status == DoseStatus.administered ? now : null,
          skipReason: status == DoseStatus.skipped ? 'animal ausente' : null,
        );

    test('administered exige administeredAt', () {
      expect(
        () => DoseAdministration(
          identity: DoseIdentity(protocolId: 'p1', plannedDoseId: 'd1'),
          protocolId: 'p1',
          dogId: 'dog-1',
          scheduledFor: now.subtract(const Duration(hours: 1)),
          status: DoseStatus.administered,
          recordedBy: actor,
          recordedAt: now,
          schemaVersion: 1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('skipped exige skipReason', () {
      expect(
        () => DoseAdministration(
          identity: DoseIdentity(protocolId: 'p1', plannedDoseId: 'd1'),
          protocolId: 'p1',
          dogId: 'dog-1',
          scheduledFor: now.subtract(const Duration(hours: 1)),
          status: DoseStatus.skipped,
          recordedBy: actor,
          recordedAt: now,
          schemaVersion: 1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('construção administered válida', () {
      final d = build();
      expect(d.status, DoseStatus.administered);
      expect(d.doseId.length, 64);
    });

    test('construção skipped válida', () {
      final d = build(status: DoseStatus.skipped);
      expect(d.status, DoseStatus.skipped);
      expect(d.skipReason, 'animal ausente');
    });

    test('protocolId inconsistente com identity é rejeitado', () {
      expect(
        () => DoseAdministration(
          identity: DoseIdentity(protocolId: 'p1', plannedDoseId: 'd1'),
          protocolId: 'p2',
          dogId: 'dog-1',
          scheduledFor: now.subtract(const Duration(hours: 1)),
          status: DoseStatus.skipped,
          recordedBy: actor,
          recordedAt: now,
          schemaVersion: 1,
          skipReason: 'x',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });
  });
}
