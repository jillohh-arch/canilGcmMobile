import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/canonical/restriction/firestore_health_restriction_history_reader.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/memory_timeline_source_reader.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/domain/operational_restriction.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_resolution.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_resolver.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_period_preset.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_history_item.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_history_presentation_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_state.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';

void main() {
  final actor = RecordedBy(
    uid: 'u-1',
    name: 'GCM Oliveira',
    internalRole: 'condutor',
  );

  final vet = ProfessionalIdentity(
    name: 'Dra. Beatriz Santos',
    registrationType: ProfessionalRegistrationType.crmv,
    registrationNumber: 'SP-12345',
    clinic: 'Clínica Veterinária Central',
  );

  final vetRelease = ProfessionalIdentity(
    name: 'Dr. Roberto Lima',
    registrationType: ProfessionalRegistrationType.crmv,
    registrationNumber: 'SP-67890',
    clinic: 'Hospital Veterinário Municipal',
  );

  final sourceDoc = const HealthDocumentRef(healthDocumentId: 'doc-issue-1');
  final endDoc = const HealthDocumentRef(healthDocumentId: 'doc-release-1');

  OperationalRestriction buildRestriction({
    required String id,
    required String dogId,
    RestrictionLevel level = RestrictionLevel.absolute,
    RestrictionCategory category = RestrictionCategory.medicationEffect,
    String description = 'Sedação para procedimento odontológico',
    required DateTime issuedAt,
    RestrictionStatus status = RestrictionStatus.active,
    List<String> activities = const [],
    DateTime? actualEnd,
    RecordedBy? endedBy,
    String? endReason,
    ProfessionalIdentity? endProfessional,
    HealthDocumentRef? endSourceDocument,
    DateTime? cancelledAt,
    RecordedBy? cancelledBy,
    String? cancelReason,
  }) {
    return OperationalRestriction(
      id: id,
      dogId: dogId,
      level: level,
      category: category,
      description: description,
      issuedAt: issuedAt,
      recordedBy: actor,
      professional: vet,
      sourceDocument: sourceDoc,
      status: status,
      schemaVersion: 1,
      activitiesRestricted: activities,
      actualEnd: actualEnd,
      endedBy: endedBy,
      endReason: endReason,
      endProfessional: endProfessional,
      endSourceDocument: endSourceDocument,
      cancelledAt: cancelledAt,
      cancelledBy: cancelledBy,
      cancelReason: cancelReason,
    );
  }

  OperationalRestriction buildActive({
    required String id,
    required String dogId,
    required DateTime issuedAt,
    RestrictionLevel level = RestrictionLevel.absolute,
    RestrictionCategory category = RestrictionCategory.medicationEffect,
    String description = 'Repouso absoluto por efeito de medicação',
    List<String> activities = const [],
  }) {
    final effectiveActivities =
        level == RestrictionLevel.partial && activities.isEmpty
            ? const ['atividades de impacto']
            : activities;
    return buildRestriction(
      id: id,
      dogId: dogId,
      level: level,
      category: category,
      description: description,
      issuedAt: issuedAt,
      status: RestrictionStatus.active,
      activities: effectiveActivities,
    );
  }

  OperationalRestriction buildEnded({
    required String id,
    required String dogId,
    required DateTime issuedAt,
    required DateTime actualEnd,
    String endReason = 'Recuperação clínica completa comprovada',
  }) {
    return buildRestriction(
      id: id,
      dogId: dogId,
      issuedAt: issuedAt,
      status: RestrictionStatus.ended,
      actualEnd: actualEnd,
      endedBy: actor,
      endReason: endReason,
      endProfessional: vetRelease,
      endSourceDocument: endDoc,
    );
  }

  OperationalRestriction buildCancelled({
    required String id,
    required String dogId,
    required DateTime issuedAt,
    required DateTime cancelledAt,
    String cancelReason = 'Lançamento em duplicidade para o mesmo K9',
  }) {
    return buildRestriction(
      id: id,
      dogId: dogId,
      issuedAt: issuedAt,
      status: RestrictionStatus.cancelled,
      cancelledAt: cancelledAt,
      cancelledBy: actor,
      cancelReason: cancelReason,
    );
  }

  HealthTimelineEntryView buildCanonicalEntry({
    required String id,
    required String dogId,
    required DateTime occurredAt,
    required String title,
    HealthTimelineType type = HealthTimelineType.consultation,
    String sourceType = 'health_events',
  }) {
    return HealthTimelineEntryView(
      id: id,
      dogId: dogId,
      type: HealthTimelineTypeView.known(type),
      occurredAt: occurredAt,
      recordedAt: occurredAt,
      title: title,
      status: HealthTimelineEntryStatus.finalised,
      detailReference: HealthTimelineDetailReference(
        sourceType: sourceType,
        sourceId: id,
      ),
    );
  }

  HealthTimelineSource createPrimarySource(List<HealthTimelineEntryView> items) {
    return CoexistenceHealthTimelineSourceFactory.forReaders([
      MemoryTimelineSourceReader(sourceKey: 'canonical', items: items),
    ]);
  }

  group('CT3.F20.MOBILE-RESTRICTION-HISTORY-PRESENTATION-R1 — 12 Pontos Canônicos', () {
    // Ponto 1: restriction issue appears in History
    test('1. restriction issue appears in History', () async {
      final issuedAt = DateTime.utc(2026, 7, 10, 9, 30);
      final restriction = buildActive(
        id: 'rst-1',
        dogId: 'dog-thor',
        issuedAt: issuedAt,
      );

      final primarySource = createPrimarySource(const []);
      final reader = MemoryHealthRestrictionHistoryReader(
        restrictionsByDogId: {
          'dog-thor': [restriction],
        },
      );

      final presentationSource = HealthHistoryPresentationTimelineSource(
        primarySource: primarySource,
        restrictionReader: reader,
      );

      final controller = HealthTimelineController(source: presentationSource);
      addTearDown(controller.dispose);

      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-thor'));

      expect(controller.state, isA<HealthTimelineData>());
      final data = controller.state as HealthTimelineData;
      expect(data.items, hasLength(1));

      final item = data.items.first;
      expect(item.id, 'restriction_rst-1_issued');
      expect(item.title, 'Restrição operacional aplicada');
      expect(item.type.known, HealthTimelineType.restriction);
      expect(item.occurredAt, issuedAt);
      expect(item.subtitle, contains('Restrição absoluta'));
      expect(item.subtitle, contains('Efeito de medicação'));
    });

    // Ponto 2: restriction end appears in History
    test('2. restriction end appears in History', () async {
      final issuedAt = DateTime.utc(2026, 7, 5, 8, 0);
      final endedAt = DateTime.utc(2026, 7, 12, 14, 0);
      final restriction = buildEnded(
        id: 'rst-end-1',
        dogId: 'dog-thor',
        issuedAt: issuedAt,
        actualEnd: endedAt,
      );

      final primarySource = createPrimarySource(const []);
      final reader = MemoryHealthRestrictionHistoryReader(
        restrictionsByDogId: {
          'dog-thor': [restriction],
        },
      );

      final presentationSource = HealthHistoryPresentationTimelineSource(
        primarySource: primarySource,
        restrictionReader: reader,
      );

      final controller = HealthTimelineController(source: presentationSource);
      addTearDown(controller.dispose);

      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-thor'));

      expect(controller.state, isA<HealthTimelineData>());
      final data = controller.state as HealthTimelineData;
      // Emite tanto ISSUED quanto ENDED
      expect(data.items, hasLength(2));

      final endedItem = data.items.firstWhere(
        (e) => e.id == 'restriction_rst-end-1_ended',
      );
      expect(endedItem.title, 'Restrição liberada clinicamente');
      expect(endedItem.occurredAt, endedAt);
      expect(endedItem.subtitle, contains('Recuperação clínica completa'));
      expect(endedItem.professional?.name, 'Dr. Roberto Lima');
    });

    // Ponto 3: cancelled restriction appears in History
    test('3. cancelled restriction appears in History', () async {
      final issuedAt = DateTime.utc(2026, 7, 8, 10, 0);
      final cancelledAt = DateTime.utc(2026, 7, 9, 11, 0);
      final restriction = buildCancelled(
        id: 'rst-cnc-1',
        dogId: 'dog-thor',
        issuedAt: issuedAt,
        cancelledAt: cancelledAt,
      );

      final primarySource = createPrimarySource(const []);
      final reader = MemoryHealthRestrictionHistoryReader(
        restrictionsByDogId: {
          'dog-thor': [restriction],
        },
      );

      final presentationSource = HealthHistoryPresentationTimelineSource(
        primarySource: primarySource,
        restrictionReader: reader,
      );

      final controller = HealthTimelineController(source: presentationSource);
      addTearDown(controller.dispose);

      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-thor'));

      expect(controller.state, isA<HealthTimelineData>());
      final data = controller.state as HealthTimelineData;
      expect(data.items, hasLength(2));

      final cancelledItem = data.items.firstWhere(
        (e) => e.id == 'restriction_rst-cnc-1_cancelled',
      );
      expect(cancelledItem.title, 'Restrição invalidada');
      expect(cancelledItem.occurredAt, cancelledAt);
      expect(cancelledItem.isCancelled, isTrue);
      expect(cancelledItem.subtitle, contains('Lançamento em duplicidade'));
      expect(cancelledItem.professional, isNull);
    });

    // Ponto 4: dog A never receives dog B restriction events
    test('4. dog A never receives dog B restriction events', () async {
      final rA = buildActive(
        id: 'rst-A',
        dogId: 'dog-A',
        issuedAt: DateTime.utc(2026, 7, 10),
      );
      final rB = buildActive(
        id: 'rst-B',
        dogId: 'dog-B',
        issuedAt: DateTime.utc(2026, 7, 11),
      );

      final primarySource = createPrimarySource(const []);
      final reader = MemoryHealthRestrictionHistoryReader(
        restrictionsByDogId: {
          'dog-A': [rA],
          'dog-B': [rB],
        },
      );

      final presentationSource = HealthHistoryPresentationTimelineSource(
        primarySource: primarySource,
        restrictionReader: reader,
      );

      final controller = HealthTimelineController(source: presentationSource);
      addTearDown(controller.dispose);

      // Consulta Dog A
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-A'));
      final dataA = controller.state as HealthTimelineData;
      expect(dataA.items.map((e) => e.id), ['restriction_rst-A_issued']);
      expect(dataA.items.any((e) => e.dogId == 'dog-B'), isFalse);

      // Consulta Dog B
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-B'));
      final dataB = controller.state as HealthTimelineData;
      expect(dataB.items.map((e) => e.id), ['restriction_rst-B_issued']);
      expect(dataB.items.any((e) => e.dogId == 'dog-A'), isFalse);
    });

    // Ponto 5: switching dog updates restriction history
    test('5. switching dog updates restriction history', () async {
      final rA = buildActive(
        id: 'rst-A',
        dogId: 'dog-A',
        issuedAt: DateTime.utc(2026, 7, 10),
      );
      final rB = buildActive(
        id: 'rst-B',
        dogId: 'dog-B',
        issuedAt: DateTime.utc(2026, 7, 12),
      );

      final primarySource = createPrimarySource(const []);
      final reader = MemoryHealthRestrictionHistoryReader(
        restrictionsByDogId: {
          'dog-A': [rA],
          'dog-B': [rB],
        },
      );

      final presentationSource = HealthHistoryPresentationTimelineSource(
        primarySource: primarySource,
        restrictionReader: reader,
      );

      final controller = HealthTimelineController(source: presentationSource);
      addTearDown(controller.dispose);

      await controller.selectDog('dog-A');
      expect((controller.state as HealthTimelineData).items.first.id, 'restriction_rst-A_issued');

      // Troca para Dog B
      await controller.selectDog('dog-B');
      final dataB = controller.state as HealthTimelineData;
      expect(dataB.items.first.id, 'restriction_rst-B_issued');
      expect(reader.queriedDogIds, contains('dog-B'));
    });

    // Ponto 6: entries merge chronologically with canonical timeline
    test('6. entries merge chronologically with canonical timeline', () async {
      final c1 = buildCanonicalEntry(
        id: 'can-1',
        dogId: 'dog-1',
        occurredAt: DateTime.utc(2026, 7, 10, 14, 0),
        title: 'Consulta de Rotina',
      );
      final c2 = buildCanonicalEntry(
        id: 'can-2',
        dogId: 'dog-1',
        occurredAt: DateTime.utc(2026, 7, 10, 10, 0),
        title: 'Pesagem Trimestral',
      );

      final r1 = buildActive(
        id: 'rst-1',
        dogId: 'dog-1',
        issuedAt: DateTime.utc(2026, 7, 10, 12, 0),
      );

      final primarySource = createPrimarySource([c1, c2]);
      final reader = MemoryHealthRestrictionHistoryReader(
        restrictionsByDogId: {
          'dog-1': [r1],
        },
      );

      final presentationSource = HealthHistoryPresentationTimelineSource(
        primarySource: primarySource,
        restrictionReader: reader,
      );

      final controller = HealthTimelineController(source: presentationSource);
      addTearDown(controller.dispose);

      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-1'));

      final data = controller.state as HealthTimelineData;
      expect(data.items, hasLength(3));
      // Ordem cronológica decrescente: c1 (14h) -> r1 (12h) -> c2 (10h)
      expect(data.items.map((e) => e.id), [
        'can-1',
        'restriction_rst-1_issued',
        'can-2',
      ]);
    });

    // Ponto 7: 7-day filter includes/excludes restriction events correctly
    test('7. 7-day filter includes/excludes restriction events correctly', () async {
      final now = DateTime.utc(2026, 7, 20, 12, 0);
      final period7d = HealthTimelinePeriodPresets.resolve(
        HealthTimelinePeriodPreset.days7,
        now: now,
      );

      // Evento recente (há 3 dias): DEVE ser incluído
      final rRecent = buildActive(
        id: 'rst-recent',
        dogId: 'dog-1',
        issuedAt: DateTime.utc(2026, 7, 17, 10, 0),
      );

      // Evento antigo (há 15 dias): DEVE ser excluído no filtro de 7 dias
      final rOld = buildActive(
        id: 'rst-old',
        dogId: 'dog-1',
        issuedAt: DateTime.utc(2026, 7, 5, 10, 0),
      );

      final primarySource = createPrimarySource(const []);
      final reader = MemoryHealthRestrictionHistoryReader(
        restrictionsByDogId: {
          'dog-1': [rRecent, rOld],
        },
      );

      final presentationSource = HealthHistoryPresentationTimelineSource(
        primarySource: primarySource,
        restrictionReader: reader,
      );

      final controller = HealthTimelineController(source: presentationSource);
      addTearDown(controller.dispose);

      // Consulta com filtro de 7 dias
      await controller.setQuery(
        HealthTimelineQuery(dogId: 'dog-1', period: period7d),
      );

      final data7d = controller.state as HealthTimelineData;
      expect(data7d.items, hasLength(1));
      expect(data7d.items.first.id, 'restriction_rst-recent_issued');

      // Consulta sem restrição de período (todo histórico)
      await controller.setQuery(
        HealthTimelineQuery(dogId: 'dog-1', period: HealthTimelinePeriod()),
      );

      final dataAll = controller.state as HealthTimelineData;
      expect(dataAll.items, hasLength(2));
      expect(dataAll.items.map((e) => e.id), containsAll([
        'restriction_rst-recent_issued',
        'restriction_rst-old_issued',
      ]));
    });

    // Ponto 8: raw snake_case values are not primary UI labels
    test('8. raw snake_case values are not primary UI labels', () async {
      final restriction = buildActive(
        id: 'rst-raw-check-1',
        dogId: 'dog-1',
        level: RestrictionLevel.partial,
        category: RestrictionCategory.medicationEffect,
        description: 'Repouso parcial após sedativo',
        issuedAt: DateTime.utc(2026, 7, 10),
      );

      final items = HealthRestrictionLifecycleDeriver.derive(restriction);
      final item = items.first;

      // Título em PT-BR limpo
      expect(item.title, 'Restrição operacional aplicada');
      expect(item.title.contains('_'), isFalse);

      // Subtítulo não contém raw snake_case
      expect(item.subtitle, contains('Restrição relativa'));
      expect(item.subtitle, contains('Efeito de medicação'));
      expect(item.subtitle?.contains('medication_effect'), isFalse);
      expect(item.subtitle?.contains('partial'), isFalse);

      // Sem doc ID como título ou label primário
      expect(item.title.contains('rst-raw-check-1'), isFalse);
      expect(item.subtitle?.contains('rst-raw-check-1'), isFalse);
    });

    // Ponto 9: ended restriction uses canonical persisted end timestamp
    test('9. ended restriction uses canonical persisted end timestamp', () async {
      final issuedAt = DateTime.utc(2026, 7, 1, 8, 0);
      final persistedActualEnd = DateTime.utc(2026, 7, 15, 16, 45);

      final restriction = buildEnded(
        id: 'rst-end-ts',
        dogId: 'dog-1',
        issuedAt: issuedAt,
        actualEnd: persistedActualEnd,
      );

      final items = HealthRestrictionLifecycleDeriver.derive(restriction);
      final endedItem = items.firstWhere(
        (i) => i.phase == HealthRestrictionLifecyclePhase.ended,
      );

      // Usa estritamente o timestamp canônico persistido
      expect(endedItem.occurredAt, persistedActualEnd);
      expect(endedItem.recordedAt, persistedActualEnd);
      expect(endedItem.occurredAt, isNot(issuedAt));
    });

    // Ponto 10: restriction query failure does not destroy existing Health timeline
    test('10. restriction query failure does not destroy existing Health timeline', () async {
      final c1 = buildCanonicalEntry(
        id: 'can-safe-1',
        dogId: 'dog-1',
        occurredAt: DateTime.utc(2026, 7, 10, 10, 0),
        title: 'Consulta Salva',
      );

      final primarySource = createPrimarySource([c1]);
      final failingReader = MemoryHealthRestrictionHistoryReader(
        shouldFail: true,
        failureException: Exception('Erro simulado de rede no Firestore'),
      );

      final presentationSource = HealthHistoryPresentationTimelineSource(
        primarySource: primarySource,
        restrictionReader: failingReader,
      );

      final controller = HealthTimelineController(source: presentationSource);
      addTearDown(controller.dispose);

      // A falha na leitura de restrições degrada suavemente e não explode o controller
      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-1'));

      expect(controller.state, isA<HealthTimelineData>());
      final data = controller.state as HealthTimelineData;
      expect(data.items, hasLength(1));
      expect(data.items.first.id, 'can-safe-1');
      expect(data.items.first.title, 'Consulta Salva');
    });

    // Ponto 11: no synthetic ClinicalEvent is created or expected
    test('11. no synthetic ClinicalEvent is created or expected', () async {
      final restriction = buildActive(
        id: 'rst-no-clinical-event',
        dogId: 'dog-1',
        issuedAt: DateTime.utc(2026, 7, 10),
      );

      final items = HealthRestrictionLifecycleDeriver.derive(restriction);
      expect(items, hasLength(1));

      final historyItem = items.first;
      // Abstração de apresentação pura
      expect(historyItem, isA<HealthRestrictionLifecycleHistoryItem>());
      expect(historyItem, isA<HealthHistoryItem>());

      final entryView = historyItem.toEntryView();
      expect(entryView.type.known, HealthTimelineType.restriction);
      // DetailReference aponta para a collection canônica de restrições
      expect(entryView.detailReference?.sourceType, 'operational_restrictions');
      expect(entryView.detailReference?.sourceId, 'rst-no-clinical-event');
    });

    // Ponto 12: no duplicate lifecycle item is rendered for same restriction + phase
    test('12. no duplicate lifecycle item is rendered for same restriction + phase', () async {
      final restriction = buildActive(
        id: 'rst-dup-1',
        dogId: 'dog-1',
        issuedAt: DateTime.utc(2026, 7, 10),
      );

      final primarySource = createPrimarySource(const []);
      // Reader simulando retorno duplicado da mesma restrição
      final reader = MemoryHealthRestrictionHistoryReader(
        restrictionsByDogId: {
          'dog-1': [restriction, restriction],
        },
      );

      final presentationSource = HealthHistoryPresentationTimelineSource(
        primarySource: primarySource,
        restrictionReader: reader,
      );

      final controller = HealthTimelineController(source: presentationSource);
      addTearDown(controller.dispose);

      await controller.setQuery(HealthTimelineQuery(dogId: 'dog-1'));

      final data = controller.state as HealthTimelineData;
      // Exatamente UM item apresentado para a mesma (restrição + fase)
      expect(data.items, hasLength(1));
      expect(data.items.first.id, 'restriction_rst-dup-1_issued');
    });

    // Ponto 13: detail navigation resolves to RestrictionDetailTarget
    test('13. detail navigation resolves to RestrictionDetailTarget', () {
      final entry = HealthTimelineEntryView(
        id: 'restriction_rst-nav-1_issued',
        dogId: 'dog-1',
        type: HealthTimelineTypeView.known(HealthTimelineType.restriction),
        occurredAt: DateTime.utc(2026, 7, 10),
        recordedAt: DateTime.utc(2026, 7, 10),
        title: 'Restrição operacional aplicada',
        status: HealthTimelineEntryStatus.finalised,
        detailReference: const HealthTimelineDetailReference(
          sourceType: 'operational_restrictions',
          sourceId: 'rst-nav-1',
        ),
      );

      expect(HealthTimelineDetailResolver.isNavigable(entry), isTrue);

      final resolution = HealthTimelineDetailResolver.resolveEntry(entry);
      expect(resolution, isA<HealthTimelineDetailResolved>());

      final target = (resolution as HealthTimelineDetailResolved).target;
      expect(target, isA<RestrictionDetailTarget>());
      expect(target.dogId, 'dog-1');
      expect(target.sourceId, 'rst-nav-1');
      expect(target.navigationActionLabel, 'Abrir detalhe da restrição');
    });
  });
}
