import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_transitions_v2.dart';
import 'package:flutter_test/flutter_test.dart';

/// NÃO chama initializeTimeZones() no setUpAll.
/// A política Health deve inicializar a base IANA de forma autossuficiente.
void main() {
  final actor = RecordedBy(
    uid: 'u1',
    name: 'Condutor',
    internalRole: 'condutor',
  );
  final now = DateTime.utc(2026, 7, 14, 10);

  HealthScheduleItem build({
    ScheduleLifecycleStatus status = ScheduleLifecycleStatus.open,
    DateTime? dueUntil,
    DateTime? scheduledFor,
    String timezone = 'America/Sao_Paulo',
    DateTime? completedAt,
    DateTime? cancelledAt,
    String? cancelReason,
  }) {
    final scheduled = scheduledFor ?? now.add(const Duration(hours: 2));
    return HealthScheduleItem(
      id: 's1',
      dogId: 'dog-1',
      scheduleType: ScheduleType.vaccination,
      title: 'V10',
      scheduledFor: scheduled,
      timezone: timezone,
      lifecycleStatus: status,
      sourceType: ScheduleSourceType.manual,
      createdAt: now,
      recordedBy: actor,
      schemaVersion: 1,
      dueUntil: dueUntil,
      completedAt: completedAt,
      completedBy: completedAt == null ? null : actor,
      cancelledAt: cancelledAt,
      cancelledBy: cancelledAt == null ? null : actor,
      cancelReason: cancelReason,
    );
  }

  Duration fixedTolerance(ScheduleType _) => const Duration(hours: 24);

  group('HealthScheduleItem', () {
    test('rejeita due_until anterior a scheduled_for', () {
      expect(
        () => build(dueUntil: now.subtract(const Duration(days: 1))),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('completed exige completed_at e completed_by', () {
      expect(
        () => build(status: ScheduleLifecycleStatus.completed),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('timezone inválido é rejeitado (sem fallback UTC)', () {
      expect(
        () => build(timezone: 'Mars/Olympus'),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'invalid_schedule_timezone',
          ),
        ),
      );
    });

    test('timezone vazio é rejeitado', () {
      expect(
        () => build(timezone: '   '),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('America/Sao_Paulo funciona sem inicialização externa prévia', () {
      // Nenhuma chamada a initializeTimeZones neste arquivo de teste.
      expect(() => build(timezone: 'America/Sao_Paulo'), returnsNormally);
    });

    test('Etc/UTC funciona sem inicialização externa prévia', () {
      expect(() => build(timezone: 'Etc/UTC'), returnsNormally);
    });

    test('matriz de transições lifecycle', () {
      const expected = <ScheduleLifecycleStatus, Set<ScheduleLifecycleStatus>>{
        ScheduleLifecycleStatus.open: {
          ScheduleLifecycleStatus.completed,
          ScheduleLifecycleStatus.cancelled,
        },
        ScheduleLifecycleStatus.completed: {},
        ScheduleLifecycleStatus.cancelled: {},
      };
      for (final origin in ScheduleLifecycleStatus.values) {
        for (final destination in ScheduleLifecycleStatus.values) {
          final allowed = expected[origin]!.contains(destination);
          final reason = '${origin.wireName} → ${destination.wireName}';
          expect(
            HealthScheduleItemTransitions.canTransition(origin, destination),
            allowed,
            reason: reason,
          );
        }
      }
    });
  });

  group('HealthScheduleTemporalPolicy', () {
    final policy = HealthScheduleTemporalPolicy(
      resolveTolerance: fixedTolerance,
    );

    test('completed → completed terminal', () {
      final item = build(
        status: ScheduleLifecycleStatus.completed,
        scheduledFor: now.subtract(const Duration(days: 1)),
        completedAt: now.subtract(const Duration(hours: 1)),
      );
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.completed,
      );
    });

    test('cancelled → cancelled terminal', () {
      final item = build(
        status: ScheduleLifecycleStatus.cancelled,
        cancelledAt: now.subtract(const Duration(hours: 1)),
        cancelReason: 'cancelado',
      );
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.cancelled,
      );
    });

    test('vencido após due_until → overdue', () {
      final item = build(
        scheduledFor: now.subtract(const Duration(days: 3)),
        dueUntil: now.subtract(const Duration(hours: 1)),
      );
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.overdue,
      );
    });

    test('dentro da janela scheduled_for → pending', () {
      final item = build(
        scheduledFor: now.subtract(const Duration(minutes: 30)),
      );
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.pending,
      );
    });

    test('hoje no timezone America/Sao_Paulo → today', () {
      // now = 2026-07-14T10:00Z = 07:00 SP. scheduled = +5h ainda no mesmo dia SP.
      final item = build(
        scheduledFor: now.add(const Duration(hours: 5)),
        timezone: 'America/Sao_Paulo',
      );
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.today,
      );
    });

    test('mesmo instante em zonas distintas → dias civis diferentes', () {
      // now = 2026-07-14T15:00Z
      // scheduled = 2026-07-15T02:00Z
      // SP: 14 12:00 / 14 23:00 → today
      // UTC: 14 15:00 / 15 02:00 → upcoming
      final refNow = DateTime.utc(2026, 7, 14, 15);
      final scheduled = DateTime.utc(2026, 7, 15, 2);
      final itemUtc = build(scheduledFor: scheduled, timezone: 'Etc/UTC');
      final itemSp = build(
        scheduledFor: scheduled,
        timezone: 'America/Sao_Paulo',
      );
      expect(
        policy.evaluate(itemSp, now: refNow),
        HealthScheduleTemporalStatus.today,
      );
      expect(
        policy.evaluate(itemUtc, now: refNow),
        HealthScheduleTemporalStatus.upcoming,
      );
    });

    test('até 7 dias → upcoming', () {
      final item = build(scheduledFor: now.add(const Duration(days: 3)));
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.upcoming,
      );
    });

    test('mais de 7 dias → scheduled', () {
      final item = build(scheduledFor: now.add(const Duration(days: 30)));
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.scheduled,
      );
    });

    test('instante próximo da meia-noite em SP usa o dia do timezone', () {
      // now = 2026-07-14T03:30Z = 2026-07-14T00:30 SP.
      // scheduled = 2026-07-15T02:00Z = 2026-07-14T23:00 SP → today em SP.
      final item = build(
        scheduledFor: DateTime.utc(2026, 7, 15, 2),
        timezone: 'America/Sao_Paulo',
      );
      expect(
        policy.evaluate(item, now: DateTime.utc(2026, 7, 14, 3, 30)),
        HealthScheduleTemporalStatus.today,
      );
    });

    test('timezone IANA inválido na evaluate falha explicitamente', () {
      // Construtor já rejeita; validateTimezone isolado:
      expect(
        () => HealthScheduleTemporalPolicy.validateTimezone('Not/AZone'),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'invalid_schedule_timezone',
          ),
        ),
      );
    });
  });
}
