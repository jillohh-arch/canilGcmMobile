import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_transitions_v2.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_presentation_policy.dart';
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
    ScheduleType scheduleType = ScheduleType.vaccination,
    ScheduleSourceType sourceType = ScheduleSourceType.manual,
    DateTime? dueUntil,
    DateTime? scheduledFor,
    String timezone = 'America/Sao_Paulo',
    DateTime? completedAt,
    DateTime? cancelledAt,
    String? cancelReason,
    String id = 's1',
  }) {
    final scheduled = scheduledFor ?? now.add(const Duration(hours: 2));
    return HealthScheduleItem(
      id: id,
      dogId: 'dog-1',
      scheduleType: scheduleType,
      title: 'V10',
      scheduledFor: scheduled,
      timezone: timezone,
      lifecycleStatus: status,
      sourceType: sourceType,
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

  /// Config padrão de teste: 24h de tolerância, 7 dias de upcoming.
  final defaultConfig = MapHealthScheduleTemporalConfig.uniform(
    HealthScheduleTypeTemporalConfig(
      toleranceAfterScheduled: const Duration(hours: 24),
      upcomingWindow: const Duration(days: 7),
    ),
  );

  HealthScheduleTemporalPolicy policyWith(
    HealthScheduleTemporalConfigResolver config,
  ) => HealthScheduleTemporalPolicy(config: config);

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

  group('enums / parsing', () {
    test('todos os schedule_type oficiais possuem wire names', () {
      const expected = {
        ScheduleType.dose: 'dose',
        ScheduleType.vaccination: 'vaccination',
        ScheduleType.exam: 'exam',
        ScheduleType.consultation: 'consultation',
        ScheduleType.weighing: 'weighing',
        ScheduleType.reevaluation: 'reevaluation',
        ScheduleType.deworming: 'deworming',
        ScheduleType.bath: 'bath',
        ScheduleType.general: 'general',
      };
      expect(ScheduleType.values, hasLength(expected.length));
      for (final entry in expected.entries) {
        expect(entry.key.wireName, entry.value);
        final parsed = ScheduleType.parse(entry.value);
        expect(parsed.isKnown, isTrue);
        expect(parsed.value, entry.key);
      }
    });

    test('todos os source_type oficiais possuem wire names', () {
      const expected = {
        ScheduleSourceType.treatmentProtocol: 'treatment_protocol',
        ScheduleSourceType.clinicalCase: 'clinical_case',
        ScheduleSourceType.examProcess: 'exam_process',
        ScheduleSourceType.preventive: 'preventive',
        ScheduleSourceType.manual: 'manual',
      };
      expect(ScheduleSourceType.values, hasLength(expected.length));
      for (final entry in expected.entries) {
        expect(entry.key.wireName, entry.value);
        final parsed = ScheduleSourceType.parse(entry.value);
        expect(parsed.isKnown, isTrue);
        expect(parsed.value, entry.key);
      }
    });

    test('lifecycle_status oficiais', () {
      expect(ScheduleLifecycleStatus.open.wireName, 'open');
      expect(ScheduleLifecycleStatus.completed.wireName, 'completed');
      expect(ScheduleLifecycleStatus.cancelled.wireName, 'cancelled');
      expect(
        ScheduleLifecycleStatus.parse('open').value,
        ScheduleLifecycleStatus.open,
      );
    });

    test('parse defensivo: desconhecido não lança', () {
      final unknownType = ScheduleType.parse('future_type_v99');
      expect(unknownType.isUnknown, isTrue);
      expect(unknownType.raw, 'future_type_v99');
      expect(unknownType.value, isNull);

      final absent = ScheduleType.parse(null);
      expect(absent.isAbsent, isTrue);

      final unknownSource = ScheduleSourceType.parse('legacy_source');
      expect(unknownSource.isUnknown, isTrue);

      final unknownLifecycle = ScheduleLifecycleStatus.parse('archived');
      expect(unknownLifecycle.isUnknown, isTrue);
    });
  });

  group('HealthScheduleTemporalPolicy — lifecycle terminal', () {
    final policy = policyWith(defaultConfig);

    test('completed sempre → completed', () {
      final item = build(
        status: ScheduleLifecycleStatus.completed,
        scheduledFor: now.subtract(const Duration(days: 10)),
        dueUntil: now.subtract(const Duration(days: 9)),
        completedAt: now.subtract(const Duration(hours: 1)),
      );
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.completed,
      );
    });

    test('cancelled sempre → cancelled', () {
      final item = build(
        status: ScheduleLifecycleStatus.cancelled,
        scheduledFor: now.subtract(const Duration(days: 5)),
        cancelledAt: now.subtract(const Duration(hours: 1)),
        cancelReason: 'cancelado',
      );
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.cancelled,
      );
    });

    test('datas atrasadas não alteram estados terminais', () {
      final completed = build(
        status: ScheduleLifecycleStatus.completed,
        scheduledFor: now.subtract(const Duration(days: 30)),
        dueUntil: now.subtract(const Duration(days: 29)),
        completedAt: now.subtract(const Duration(days: 20)),
      );
      final cancelled = build(
        status: ScheduleLifecycleStatus.cancelled,
        scheduledFor: now.subtract(const Duration(days: 30)),
        dueUntil: now.subtract(const Duration(days: 29)),
        cancelledAt: now.subtract(const Duration(days: 1)),
        cancelReason: 'x',
      );
      expect(
        policy.evaluate(completed, now: now),
        HealthScheduleTemporalStatus.completed,
      );
      expect(
        policy.evaluate(cancelled, now: now),
        HealthScheduleTemporalStatus.cancelled,
      );
    });
  });

  group('HealthScheduleTemporalPolicy — overdue / pending', () {
    final policy = policyWith(defaultConfig);

    test('now > effective_due_until → overdue', () {
      final item = build(
        scheduledFor: now.subtract(const Duration(days: 3)),
        dueUntil: now.subtract(const Duration(hours: 1)),
      );
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.overdue,
      );
    });

    test('now == effective_due_until → NÃO overdue (pending)', () {
      final scheduled = now.subtract(const Duration(hours: 2));
      final item = build(scheduledFor: scheduled, dueUntil: now);
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.pending,
      );
      expect(
        policy.evaluate(item, now: now),
        isNot(HealthScheduleTemporalStatus.overdue),
      );
    });

    test('now == scheduled_for → pending', () {
      final item = build(scheduledFor: now);
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.pending,
      );
    });

    test('scheduled_for < now <= effective_due_until → pending', () {
      final item = build(
        scheduledFor: now.subtract(const Duration(minutes: 30)),
        dueUntil: now.add(const Duration(hours: 1)),
      );
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.pending,
      );
    });

    test('sem due_until: tolerância configurada define effective_due_until', () {
      // scheduled = now - 12h; tolerância 24h → effective = now + 12h → pending
      final item = build(scheduledFor: now.subtract(const Duration(hours: 12)));
      expect(
        policy.effectiveDueUntil(item),
        now.add(const Duration(hours: 12)),
      );
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.pending,
      );

      // scheduled = now - 25h; tolerância 24h → overdue
      final late = build(scheduledFor: now.subtract(const Duration(hours: 25)));
      expect(
        policy.evaluate(late, now: now),
        HealthScheduleTemporalStatus.overdue,
      );
    });

    test('due_until explícito prevalece sobre tolerância configurada', () {
      // tolerância seria 24h, mas due_until é +1h
      final item = build(
        scheduledFor: now.subtract(const Duration(hours: 1)),
        dueUntil: now.add(const Duration(hours: 1)),
      );
      expect(policy.effectiveDueUntil(item), now.add(const Duration(hours: 1)));
      expect(
        policy.evaluate(item, now: now.add(const Duration(hours: 2))),
        HealthScheduleTemporalStatus.overdue,
      );
    });
  });

  group('HealthScheduleTemporalPolicy — today / upcoming / scheduled', () {
    final policy = policyWith(defaultConfig);

    test('item futuro no mesmo dia e timezone → today', () {
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

    test('dentro da janela configurada → upcoming', () {
      final item = build(scheduledFor: now.add(const Duration(days: 3)));
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.upcoming,
      );
    });

    test('fora da janela → scheduled', () {
      final item = build(scheduledFor: now.add(const Duration(days: 30)));
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.scheduled,
      );
    });

    test('janela upcoming diferente por schedule_type', () {
      final config = MapHealthScheduleTemporalConfig({
        ScheduleType.vaccination: HealthScheduleTypeTemporalConfig(
          toleranceAfterScheduled: const Duration(hours: 24),
          upcomingWindow: const Duration(days: 3),
        ),
        ScheduleType.weighing: HealthScheduleTypeTemporalConfig(
          toleranceAfterScheduled: const Duration(hours: 6),
          upcomingWindow: const Duration(days: 14),
        ),
        // demais tipos com default de teste
        for (final t in ScheduleType.values)
          if (t != ScheduleType.vaccination && t != ScheduleType.weighing)
            t: HealthScheduleTypeTemporalConfig(
              toleranceAfterScheduled: const Duration(hours: 24),
              upcomingWindow: const Duration(days: 7),
            ),
      });
      final p = policyWith(config);
      final inFiveDays = now.add(const Duration(days: 5));

      final vax = build(
        scheduleType: ScheduleType.vaccination,
        scheduledFor: inFiveDays,
      );
      final weight = build(
        scheduleType: ScheduleType.weighing,
        scheduledFor: inFiveDays,
      );

      // 5 dias: fora da janela de 3 da vacina → scheduled
      expect(p.evaluate(vax, now: now), HealthScheduleTemporalStatus.scheduled);
      // 5 dias: dentro da janela de 14 da pesagem → upcoming
      expect(
        p.evaluate(weight, now: now),
        HealthScheduleTemporalStatus.upcoming,
      );
    });
  });

  group('HealthScheduleTemporalPolicy — configuração', () {
    test('ausência de configuração obrigatória falha explicitamente', () {
      final config = MapHealthScheduleTemporalConfig({
        ScheduleType.dose: HealthScheduleTypeTemporalConfig(
          toleranceAfterScheduled: const Duration(hours: 2),
          upcomingWindow: const Duration(days: 1),
        ),
      });
      final policy = policyWith(config);
      final item = build(scheduleType: ScheduleType.vaccination);

      expect(
        () => policy.evaluate(item, now: now),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'missing_schedule_type_temporal_config',
          ),
        ),
      );
      expect(
        () => policy.effectiveDueUntil(item),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'missing_schedule_type_temporal_config',
          ),
        ),
      );
    });

    test('não existe fallback universal silencioso', () {
      final empty = MapHealthScheduleTemporalConfig(const {});
      final policy = policyWith(empty);
      for (final type in ScheduleType.values) {
        final item = build(scheduleType: type);
        expect(
          () => policy.evaluate(item, now: now),
          throwsA(isA<HealthDomainException>()),
          reason: type.wireName,
        );
      }
    });

    group('tolerância ausente (contrato dose aprovado HW-4A.2B)', () {
      /// dose configurada como aprovado: janela upcoming presente,
      /// tolerância pós-vencimento AUSENTE.
      final doseConfig = MapHealthScheduleTemporalConfig({
        for (final t in ScheduleType.values)
          t: HealthScheduleTypeTemporalConfig(
            toleranceAfterScheduled: t == ScheduleType.dose
                ? null
                : const Duration(hours: 24),
            upcomingWindow: const Duration(days: 7),
          ),
      });

      test('dose sem due_until falha fechada, sem tolerância inventada', () {
        final policy = policyWith(doseConfig);
        final item = build(scheduleType: ScheduleType.dose);

        expect(
          () => policy.effectiveDueUntil(item),
          throwsA(
            isA<HealthDomainException>().having(
              (e) => e.code,
              'code',
              'incomplete_schedule_temporal_config',
            ),
          ),
        );
        expect(
          () => policy.evaluate(item, now: now),
          throwsA(
            isA<HealthDomainException>().having(
              (e) => e.code,
              'code',
              'incomplete_schedule_temporal_config',
            ),
          ),
        );
      });

      test('dose com due_until explícito é autoritativo e válido', () {
        final policy = policyWith(doseConfig);
        final scheduled = now.subtract(const Duration(hours: 3));
        final due = now.add(const Duration(hours: 1));
        final item = build(
          scheduleType: ScheduleType.dose,
          scheduledFor: scheduled,
          dueUntil: due,
        );

        expect(policy.effectiveDueUntil(item), due);
        expect(
          policy.evaluate(item, now: now),
          HealthScheduleTemporalStatus.pending,
        );
        expect(
          policy.evaluate(item, now: due.add(const Duration(minutes: 1))),
          HealthScheduleTemporalStatus.overdue,
        );
      });

      test('dose mantém janela upcoming de 7 dias', () {
        final policy = policyWith(doseConfig);
        final scheduled = now.add(const Duration(days: 3));
        final item = build(
          scheduleType: ScheduleType.dose,
          scheduledFor: scheduled,
          // due_until obrigatório para dose ser avaliável.
          dueUntil: scheduled.add(const Duration(hours: 1)),
        );

        expect(
          policy.evaluate(item, now: now),
          HealthScheduleTemporalStatus.upcoming,
        );
      });

      test('tipos não-dose seguem com fallback de 24h', () {
        final policy = policyWith(doseConfig);
        final scheduled = now.subtract(const Duration(hours: 3));
        final exam = build(
          scheduleType: ScheduleType.exam,
          scheduledFor: scheduled,
        );

        expect(
          policy.effectiveDueUntil(exam),
          scheduled.add(const Duration(hours: 24)),
        );
        expect(
          policy.evaluate(exam, now: now),
          HealthScheduleTemporalStatus.pending,
        );
      });

      test('estado terminal vence tolerância ausente', () {
        final policy = policyWith(doseConfig);
        // completed/cancelled precedem qualquer derivação temporal, então
        // uma dose sem due_until NÃO deve explodir quando já é terminal.
        final completed = build(
          status: ScheduleLifecycleStatus.completed,
          scheduleType: ScheduleType.dose,
          completedAt: now,
        );
        final cancelled = build(
          status: ScheduleLifecycleStatus.cancelled,
          scheduleType: ScheduleType.dose,
          cancelledAt: now,
          cancelReason: 'erro de agendamento',
        );

        expect(
          policy.evaluate(completed, now: now),
          HealthScheduleTemporalStatus.completed,
        );
        expect(
          policy.evaluate(cancelled, now: now),
          HealthScheduleTemporalStatus.cancelled,
        );
      });
    });

    test('política aprovada de produção: dose sem tolerância genérica', () {
      final snapshot = healthSchedulePresentationPolicySnapshot();
      expect(
        snapshot[ScheduleType.dose]!.toleranceAfterScheduled,
        isNull,
        reason: 'dose não pode ter fallback genérico (decisão humana)',
      );
      expect(
        snapshot[ScheduleType.dose]!.upcomingWindow,
        const Duration(days: 7),
      );
      for (final type in ScheduleType.values) {
        expect(
          snapshot[type]!.upcomingWindow,
          const Duration(days: 7),
          reason: type.wireName,
        );
        if (type != ScheduleType.dose) {
          expect(
            snapshot[type]!.toleranceAfterScheduled,
            const Duration(hours: 24),
            reason: type.wireName,
          );
        }
      }
    });

    test('tolerância distinta por tipo quando due_until ausente', () {
      final config = MapHealthScheduleTemporalConfig({
        for (final t in ScheduleType.values)
          t: HealthScheduleTypeTemporalConfig(
            toleranceAfterScheduled: t == ScheduleType.dose
                ? const Duration(hours: 2)
                : const Duration(hours: 48),
            upcomingWindow: const Duration(days: 7),
          ),
      });
      final policy = policyWith(config);
      final scheduled = now.subtract(const Duration(hours: 3));

      final dose = build(
        scheduleType: ScheduleType.dose,
        scheduledFor: scheduled,
      );
      final exam = build(
        scheduleType: ScheduleType.exam,
        scheduledFor: scheduled,
      );

      // dose: effective = scheduled+2h = now-1h → overdue
      expect(
        policy.evaluate(dose, now: now),
        HealthScheduleTemporalStatus.overdue,
      );
      // exam: effective = scheduled+48h → pending
      expect(
        policy.evaluate(exam, now: now),
        HealthScheduleTemporalStatus.pending,
      );
    });
  });

  group('HealthScheduleTemporalPolicy — timezone e clock', () {
    final policy = policyWith(defaultConfig);

    test(
      'mesmo instante absoluto em timezones diferentes → dia civil do item',
      () {
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
      },
    );

    test('mudança de dia no timezone é respeitada', () {
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

    test('relógio é totalmente controlável (sem DateTime.now interno)', () {
      final item = build(scheduledFor: DateTime.utc(2026, 7, 20, 12));
      expect(
        policy.evaluate(item, now: DateTime.utc(2026, 7, 10)),
        HealthScheduleTemporalStatus.scheduled,
      );
      expect(
        policy.evaluate(item, now: DateTime.utc(2026, 7, 18)),
        HealthScheduleTemporalStatus.upcoming,
      );
      expect(
        policy.evaluate(item, now: DateTime.utc(2026, 7, 20, 12)),
        HealthScheduleTemporalStatus.pending,
      );
      expect(
        policy.evaluate(item, now: DateTime.utc(2026, 7, 22)),
        HealthScheduleTemporalStatus.overdue,
      );
    });

    test('timezone IANA inválido falha explicitamente', () {
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

  group('HealthScheduleTemporalPolicy — precedência absoluta', () {
    final policy = policyWith(defaultConfig);

    test('nenhum item é simultaneamente pending e overdue', () {
      // Varre fronteiras em torno de scheduled_for e due_until.
      final scheduled = DateTime.utc(2026, 7, 14, 10);
      final due = DateTime.utc(2026, 7, 15, 10);
      final item = build(scheduledFor: scheduled, dueUntil: due);
      final samples = <DateTime>[
        scheduled.subtract(const Duration(seconds: 1)),
        scheduled,
        scheduled.add(const Duration(hours: 1)),
        due,
        due.add(const Duration(seconds: 1)),
      ];
      for (final t in samples) {
        final status = policy.evaluate(item, now: t);
        final pendingAndOverdue =
            status == HealthScheduleTemporalStatus.pending &&
            status == HealthScheduleTemporalStatus.overdue;
        expect(pendingAndOverdue, isFalse, reason: 'now=$t status=$status');
        // Mutual exclusion: exatamente um estado.
        expect(
          HealthScheduleTemporalStatus.values.where((s) => s == status),
          hasLength(1),
        );
      }
    });

    test('today não vence pending', () {
      // now == scheduled_for no mesmo dia → pending (regra 4 antes da 5)
      final scheduled = DateTime.utc(2026, 7, 14, 15);
      final item = build(
        scheduledFor: scheduled,
        timezone: 'America/Sao_Paulo',
      );
      expect(
        policy.evaluate(item, now: scheduled),
        HealthScheduleTemporalStatus.pending,
      );
    });

    test('upcoming não vence today', () {
      // Futuro no mesmo dia civil: today, mesmo dentro da janela upcoming.
      final item = build(
        scheduledFor: now.add(const Duration(hours: 5)),
        timezone: 'America/Sao_Paulo',
      );
      expect(
        policy.evaluate(item, now: now),
        HealthScheduleTemporalStatus.today,
      );
    });

    test('estados terminais vencem tudo', () {
      final completed = build(
        status: ScheduleLifecycleStatus.completed,
        scheduledFor: now.add(const Duration(days: 1)),
        completedAt: now,
      );
      final cancelled = build(
        status: ScheduleLifecycleStatus.cancelled,
        scheduledFor: now.add(const Duration(hours: 1)),
        cancelledAt: now,
        cancelReason: 'x',
      );
      expect(
        policy.evaluate(completed, now: now),
        HealthScheduleTemporalStatus.completed,
      );
      expect(
        policy.evaluate(cancelled, now: now),
        HealthScheduleTemporalStatus.cancelled,
      );
    });
  });
}
