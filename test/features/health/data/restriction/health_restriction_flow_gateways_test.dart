import 'package:canil_gcm/features/health/data/restriction/firebase_functions_health_document_gateway.dart';
import 'package:canil_gcm/features/health/data/restriction/firebase_functions_health_restriction_issue_gateway.dart';
import 'package:canil_gcm/features/health/data/restriction/health_restriction_flow_callables.dart';
import 'package:canil_gcm/features/health/domain/health_document_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_evidence_file.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_flow_errors.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_issue_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captura o request e devolve uma resposta ou lança um erro controlado.
final class _Invoker {
  _Invoker(this._responder);

  final Future<Map<String, dynamic>> Function(
    String name,
    Map<String, dynamic> data,
  )
  _responder;

  final List<String> names = <String>[];
  final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[];

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async {
    names.add(name);
    payloads.add(data);
    return _responder(name, data);
  }
}

_Invoker _ok(Map<String, dynamic> response) =>
    _Invoker((_, _) async => response);

_Invoker _throws(Object error) => _Invoker((_, _) async => throw error);

void main() {
  group('PREPARE', () {
    test('request exato: apenas dogId e operationId', () async {
      final invoker = _ok(<String, dynamic>{
        'dog_id': 'dog-1',
        'document_id': 'hd_abc',
        'upload_path': 'health_document_uploads/dog-1/hd_abc',
        'max_bytes': 20971520,
      });
      final gateway = FirebaseFunctionsHealthDocumentGateway(
        invoker: invoker.call,
      );

      final result = await gateway.prepareUpload(
        const PrepareHealthDocumentCommand(dogId: 'dog-1', operationId: 'op-1'),
      );

      expect(result, isA<PrepareHealthDocumentSuccess>());
      expect(
        invoker.names.single,
        HealthRestrictionFlowCallables.documentPrepareUpload,
      );
      expect(invoker.payloads.single, {
        'dogId': 'dog-1',
        'operationId': 'op-1',
      });
      // Nenhuma metadata clínica nesta etapa.
      expect(invoker.payloads.single.containsKey('documentType'), isFalse);
      expect(invoker.payloads.single.containsKey('title'), isFalse);
    });

    test('aceita resposta camelCase (espelho do backend)', () async {
      final gateway = FirebaseFunctionsHealthDocumentGateway(
        invoker: _ok(<String, dynamic>{
          'dogId': 'dog-1',
          'documentId': 'hd_abc',
          'uploadPath': 'health_document_uploads/dog-1/hd_abc',
          'maxBytes': 20971520,
        }).call,
      );

      final result = await gateway.prepareUpload(
        const PrepareHealthDocumentCommand(dogId: 'dog-1', operationId: 'op-1'),
      );
      final prepared = (result as PrepareHealthDocumentSuccess).prepared;
      expect(prepared.uploadPath, 'health_document_uploads/dog-1/hd_abc');
      expect(prepared.documentId, 'hd_abc');
      expect(prepared.maxBytes, 20971520);
    });

    test('resposta malformada falha fechado', () async {
      final cases = <String, Map<String, dynamic>>{
        'document_id vazio': {
          'dog_id': 'dog-1',
          'document_id': '  ',
          'upload_path': 'p',
          'max_bytes': 1,
        },
        'upload_path ausente': {
          'dog_id': 'dog-1',
          'document_id': 'hd_abc',
          'max_bytes': 1,
        },
        'max_bytes inválido': {
          'dog_id': 'dog-1',
          'document_id': 'hd_abc',
          'upload_path': 'p',
          'max_bytes': 0,
        },
        'dog_id ausente': {
          'document_id': 'hd_abc',
          'upload_path': 'p',
          'max_bytes': 1,
        },
      };

      for (final entry in cases.entries) {
        final gateway = FirebaseFunctionsHealthDocumentGateway(
          invoker: _ok(entry.value).call,
        );
        final result = await gateway.prepareUpload(
          const PrepareHealthDocumentCommand(
            dogId: 'dog-1',
            operationId: 'op-1',
          ),
        );
        expect(
          result,
          isA<PrepareHealthDocumentError>(),
          reason: entry.key,
        );
        expect(
          (result as PrepareHealthDocumentError).failure,
          isA<HealthRestrictionFlowIntegrity>(),
          reason: entry.key,
        );
      }
    });
  });

  group('FINALIZE', () {
    test('request exato e mapeamento de natureza', () async {
      final invoker = _ok(<String, dynamic>{
        'dog_id': 'dog-1',
        'document_id': 'hd_abc',
        'reference': {'health_document_id': 'hd_abc'},
        'was_no_op': false,
      });
      final gateway = FirebaseFunctionsHealthDocumentGateway(
        invoker: invoker.call,
      );

      await gateway.finalizeUpload(
        const FinalizeHealthDocumentCommand(
          dogId: 'dog-1',
          operationId: 'op-1',
          nature: HealthEvidenceNature.report,
          title: 'Laudo veterinário — Bono',
        ),
      );

      expect(invoker.payloads.single, {
        'dogId': 'dog-1',
        'operationId': 'op-1',
        'documentType': 'report',
        'title': 'Laudo veterinário — Bono',
      });
      // Storage nunca é enviado: o FINALIZE é a autoridade sobre os bytes.
      for (final forbidden in [
        'storagePath',
        'uploadPath',
        'mimeType',
        'generation',
        'url',
      ]) {
        expect(
          invoker.payloads.single.containsKey(forbidden),
          isFalse,
          reason: forbidden,
        );
      }
    });

    test('usa a reference devolvida, não reconstrói', () async {
      final gateway = FirebaseFunctionsHealthDocumentGateway(
        invoker: _ok(<String, dynamic>{
          'dog_id': 'dog-1',
          'document_id': 'hd_interno',
          'storage_path': 'health_documents/dog-1/hd_interno',
          'reference': {'health_document_id': 'hd_oficial'},
          'was_no_op': true,
        }).call,
      );

      final result = await gateway.finalizeUpload(
        const FinalizeHealthDocumentCommand(
          dogId: 'dog-1',
          operationId: 'op-1',
          nature: HealthEvidenceNature.certificate,
          title: 'Atestado',
        ),
      );
      final doc = (result as FinalizeHealthDocumentSuccess).document;
      expect(
        doc.reference.healthDocumentId,
        'hd_oficial',
        reason: 'reference é a superfície oficial',
      );
      expect(doc.wasNoOp, isTrue);
    });

    test('reference ausente ou vazia falha fechado', () async {
      final cases = <String, Map<String, dynamic>>{
        'sem reference': {
          'dog_id': 'dog-1',
          'document_id': 'hd_abc',
          'was_no_op': false,
        },
        'reference não-mapa': {
          'dog_id': 'dog-1',
          'document_id': 'hd_abc',
          'reference': 'hd_abc',
          'was_no_op': false,
        },
        'health_document_id vazio': {
          'dog_id': 'dog-1',
          'document_id': 'hd_abc',
          'reference': {'health_document_id': '   '},
          'was_no_op': false,
        },
        'was_no_op ausente': {
          'dog_id': 'dog-1',
          'document_id': 'hd_abc',
          'reference': {'health_document_id': 'hd_abc'},
        },
      };

      for (final entry in cases.entries) {
        final gateway = FirebaseFunctionsHealthDocumentGateway(
          invoker: _ok(entry.value).call,
        );
        final result = await gateway.finalizeUpload(
          const FinalizeHealthDocumentCommand(
            dogId: 'dog-1',
            operationId: 'op-1',
            nature: HealthEvidenceNature.other,
            title: 'Documento',
          ),
        );
        expect(
          (result as FinalizeHealthDocumentError).failure,
          isA<HealthRestrictionFlowIntegrity>(),
          reason: entry.key,
        );
      }
    });
  });

  group('ISSUE payload', () {
    ProfessionalIdentity prof({String? specialty}) => ProfessionalIdentity(
      name: 'Dra. Ana Souza',
      registrationType: ProfessionalRegistrationType.crmv,
      registrationNumber: 'SP-12345',
      clinic: 'Clínica Central',
      specialty: specialty,
    );

    test('payload exato com professional em snake_case interno', () async {
      final invoker = _ok(<String, dynamic>{
        'dog_id': 'dog-1',
        'restriction_id': 'or_xyz',
        'was_no_op': false,
      });
      final gateway = FirebaseFunctionsHealthRestrictionIssueGateway(
        invoker: invoker.call,
      );

      await gateway.issue(
        IssueOperationalRestrictionCommand(
          dogId: 'dog-1',
          operationId: 'op-issue',
          level: RestrictionLevel.absolute,
          category: RestrictionCategory.injury,
          description: 'Lesão em membro anterior',
          professional: prof(specialty: 'Ortopedia'),
          sourceDocument: const HealthDocumentRef(
            healthDocumentId: 'hd_abc',
          ),
        ),
      );

      expect(
        invoker.names.single,
        HealthRestrictionFlowCallables.restrictionIssue,
      );
      expect(invoker.payloads.single, {
        'dogId': 'dog-1',
        'operationId': 'op-issue',
        'level': 'absolute',
        'category': 'injury',
        'description': 'Lesão em membro anterior',
        'professional': {
          'name': 'Dra. Ana Souza',
          'registration_type': 'CRMV',
          'registration_number': 'SP-12345',
          'clinic': 'Clínica Central',
          'specialty': 'Ortopedia',
        },
        'sourceDocument': {'health_document_id': 'hd_abc'},
      });
    });

    test('specialty omitida quando ausente', () async {
      final invoker = _ok(<String, dynamic>{
        'dog_id': 'dog-1',
        'restriction_id': 'or_xyz',
        'was_no_op': false,
      });
      final gateway = FirebaseFunctionsHealthRestrictionIssueGateway(
        invoker: invoker.call,
      );
      await gateway.issue(
        IssueOperationalRestrictionCommand(
          dogId: 'dog-1',
          operationId: 'op-1',
          level: RestrictionLevel.attention,
          category: RestrictionCategory.other,
          description: 'Observação',
          professional: prof(),
          sourceDocument: const HealthDocumentRef(healthDocumentId: 'hd_a'),
        ),
      );
      final professional =
          invoker.payloads.single['professional'] as Map<String, dynamic>;
      expect(professional.containsKey('specialty'), isFalse);
    });

    test('activities e expectedEnd só quando presentes', () async {
      final invoker = _ok(<String, dynamic>{
        'dog_id': 'dog-1',
        'restriction_id': 'or_xyz',
        'was_no_op': false,
      });
      final gateway = FirebaseFunctionsHealthRestrictionIssueGateway(
        invoker: invoker.call,
      );

      // Sem atividades e sem previsão: chaves ausentes.
      await gateway.issue(
        IssueOperationalRestrictionCommand(
          dogId: 'dog-1',
          operationId: 'op-1',
          level: RestrictionLevel.absolute,
          category: RestrictionCategory.injury,
          description: 'd',
          professional: prof(),
          sourceDocument: const HealthDocumentRef(healthDocumentId: 'hd_a'),
        ),
      );
      expect(
        invoker.payloads.last.containsKey('activitiesRestricted'),
        isFalse,
      );
      expect(invoker.payloads.last.containsKey('expectedEnd'), isFalse);

      // Com ambos: presentes e em ISO-8601 UTC.
      await gateway.issue(
        IssueOperationalRestrictionCommand(
          dogId: 'dog-1',
          operationId: 'op-2',
          level: RestrictionLevel.partial,
          category: RestrictionCategory.injury,
          description: 'd',
          activitiesRestricted: const ['busca', 'guarda'],
          expectedEnd: DateTime.utc(2026, 9, 15),
          professional: prof(),
          sourceDocument: const HealthDocumentRef(healthDocumentId: 'hd_a'),
        ),
      );
      expect(invoker.payloads.last['activitiesRestricted'], [
        'busca',
        'guarda',
      ]);
      expect(invoker.payloads.last['expectedEnd'], '2026-09-15T00:00:00.000Z');
    });

    test('nenhum campo server-owned é enviado', () async {
      final invoker = _ok(<String, dynamic>{
        'dog_id': 'dog-1',
        'restriction_id': 'or_xyz',
        'was_no_op': false,
      });
      final gateway = FirebaseFunctionsHealthRestrictionIssueGateway(
        invoker: invoker.call,
      );
      await gateway.issue(
        IssueOperationalRestrictionCommand(
          dogId: 'dog-1',
          operationId: 'op-1',
          level: RestrictionLevel.absolute,
          category: RestrictionCategory.injury,
          description: 'd',
          professional: prof(),
          sourceDocument: const HealthDocumentRef(healthDocumentId: 'hd_a'),
        ),
      );

      for (final forbidden in [
        'status',
        'restrictionId',
        'restriction_id',
        'issued_at',
        'issuedAt',
        'recorded_by',
        'recordedBy',
        'schema_version',
        'schemaVersion',
        'revision',
        'actual_end',
        'ended_by',
        'end_professional',
        'end_source_document',
        'end_reason',
        'cancelled_at',
        'cancelled_by',
        'cancel_reason',
      ]) {
        expect(
          invoker.payloads.single.containsKey(forbidden),
          isFalse,
          reason: forbidden,
        );
      }
    });

    test('todos os wireNames de level e category', () async {
      for (final level in RestrictionLevel.values) {
        for (final category in RestrictionCategory.values) {
          final invoker = _ok(<String, dynamic>{
            'dog_id': 'dog-1',
            'restriction_id': 'or_xyz',
            'was_no_op': false,
          });
          final gateway = FirebaseFunctionsHealthRestrictionIssueGateway(
            invoker: invoker.call,
          );
          await gateway.issue(
            IssueOperationalRestrictionCommand(
              dogId: 'dog-1',
              operationId: 'op-1',
              level: level,
              category: category,
              description: 'd',
              activitiesRestricted: level == RestrictionLevel.partial
                  ? const ['busca']
                  : const <String>[],
              professional: prof(),
              sourceDocument: const HealthDocumentRef(healthDocumentId: 'hd'),
            ),
          );
          expect(invoker.payloads.single['level'], level.wireName);
          expect(invoker.payloads.single['category'], category.wireName);
        }
      }
    });

    test('todos os tipos de registro profissional', () async {
      for (final type in ProfessionalRegistrationType.values) {
        final invoker = _ok(<String, dynamic>{
          'dog_id': 'dog-1',
          'restriction_id': 'or_xyz',
          'was_no_op': false,
        });
        final gateway = FirebaseFunctionsHealthRestrictionIssueGateway(
          invoker: invoker.call,
        );
        await gateway.issue(
          IssueOperationalRestrictionCommand(
            dogId: 'dog-1',
            operationId: 'op-1',
            level: RestrictionLevel.absolute,
            category: RestrictionCategory.injury,
            description: 'd',
            professional: ProfessionalIdentity(
              name: 'Prof',
              registrationType: type,
              registrationNumber: '1',
              clinic: 'C',
            ),
            sourceDocument: const HealthDocumentRef(healthDocumentId: 'hd'),
          ),
        );
        final professional =
            invoker.payloads.single['professional'] as Map<String, dynamic>;
        expect(professional['registration_type'], type.wireName);
      }
    });

    test('resposta malformada falha fechado', () async {
      for (final response in <Map<String, dynamic>>[
        {'dog_id': 'dog-1', 'was_no_op': false},
        {'dog_id': 'dog-1', 'restriction_id': '  ', 'was_no_op': false},
        {'dog_id': 'dog-1', 'restriction_id': 'or_x'},
      ]) {
        final gateway = FirebaseFunctionsHealthRestrictionIssueGateway(
          invoker: _ok(response).call,
        );
        final result = await gateway.issue(
          IssueOperationalRestrictionCommand(
            dogId: 'dog-1',
            operationId: 'op-1',
            level: RestrictionLevel.absolute,
            category: RestrictionCategory.injury,
            description: 'd',
            professional: prof(),
            sourceDocument: const HealthDocumentRef(healthDocumentId: 'hd'),
          ),
        );
        expect(
          (result as IssueOperationalRestrictionError).failure,
          isA<HealthRestrictionFlowIntegrity>(),
        );
      }
    });
  });

  group('mapeamento de erro', () {
    Future<HealthRestrictionFlowFailure> issueWith(Object error) async {
      final gateway = FirebaseFunctionsHealthRestrictionIssueGateway(
        invoker: _throws(error).call,
      );
      final result = await gateway.issue(
        IssueOperationalRestrictionCommand(
          dogId: 'dog-1',
          operationId: 'op-1',
          level: RestrictionLevel.absolute,
          category: RestrictionCategory.injury,
          description: 'd',
          professional: ProfessionalIdentity(
            name: 'P',
            registrationType: ProfessionalRegistrationType.crmv,
            registrationNumber: '1',
            clinic: 'C',
          ),
          sourceDocument: const HealthDocumentRef(healthDocumentId: 'hd'),
        ),
      );
      return (result as IssueOperationalRestrictionError).failure;
    }

    test('details.code tem precedência sobre o code de transporte', () async {
      final failure = await issueWith(
        FirebaseFunctionsException(
          code: 'internal',
          message: 'x',
          details: const {'code': 'permission-denied'},
        ),
      );
      expect(failure, isA<HealthRestrictionFlowPermissionDenied>());
    });

    test('permission-denied usa linguagem operacional', () async {
      final failure = await issueWith(
        FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'missing health.issue_restriction',
        ),
      );
      expect(failure, isA<HealthRestrictionFlowPermissionDenied>());
      expect(failure.message, contains('autorização'));
      // Não expõe capability técnica ao operador.
      expect(failure.message, isNot(contains('issue_restriction')));
      expect(failure.message, isNot(contains('health.')));
    });

    test('cada código semântico mapeia para a falha certa', () async {
      final expectations = <String, Matcher>{
        'unauthenticated': isA<HealthRestrictionFlowUnauthenticated>(),
        'not-found': isA<HealthRestrictionFlowNotFound>(),
        'conflict': isA<HealthRestrictionFlowConflict>(),
        'idempotency-conflict':
            isA<HealthRestrictionFlowIdempotencyConflict>(),
        'validation': isA<HealthRestrictionFlowValidation>(),
        'integrity': isA<HealthRestrictionFlowIntegrity>(),
        'unavailable': isA<HealthRestrictionFlowOffline>(),
        'deadline-exceeded': isA<HealthRestrictionFlowOffline>(),
        'network-request-failed': isA<HealthRestrictionFlowOffline>(),
        'internal': isA<HealthRestrictionFlowUnexpected>(),
        'codigo-desconhecido': isA<HealthRestrictionFlowUnexpected>(),
      };
      for (final entry in expectations.entries) {
        final failure = await issueWith(
          FirebaseFunctionsException(code: entry.key, message: 'x'),
        );
        expect(failure, entry.value, reason: entry.key);
      }
    });

    test('invalid-argument de transporte vira validation', () async {
      final failure = await issueWith(
        FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'category inválida',
        ),
      );
      expect(failure, isA<HealthRestrictionFlowValidation>());
      // Mensagem do backend é preservada: aponta o campo recusado.
      expect(failure.message, 'category inválida');
    });

    test('erro não-Firebase vira unexpected', () async {
      final failure = await issueWith(StateError('boom'));
      expect(failure, isA<HealthRestrictionFlowUnexpected>());
    });

    test('etapa é preservada em cada gateway', () async {
      final issueFailure = await issueWith(
        FirebaseFunctionsException(code: 'unavailable', message: 'x'),
      );
      expect(issueFailure.step, HealthRestrictionFlowStep.restrictionIssue);

      final docGateway = FirebaseFunctionsHealthDocumentGateway(
        invoker: _throws(
          FirebaseFunctionsException(code: 'unavailable', message: 'x'),
        ).call,
      );
      final prepare = await docGateway.prepareUpload(
        const PrepareHealthDocumentCommand(dogId: 'd', operationId: 'o'),
      );
      expect(
        (prepare as PrepareHealthDocumentError).failure.step,
        HealthRestrictionFlowStep.documentPrepare,
      );

      final finalize = await docGateway.finalizeUpload(
        const FinalizeHealthDocumentCommand(
          dogId: 'd',
          operationId: 'o',
          nature: HealthEvidenceNature.other,
          title: 't',
        ),
      );
      expect(
        (finalize as FinalizeHealthDocumentError).failure.step,
        HealthRestrictionFlowStep.documentFinalize,
      );
    });

    test('retryable só para offline e unexpected', () async {
      expect(
        (await issueWith(FirebaseFunctionsException(code: 'unavailable', message: 'x')))
            .isRetryable,
        isTrue,
      );
      expect(
        (await issueWith(
          FirebaseFunctionsException(code: 'idempotency-conflict', message: 'x'),
        )).isRetryable,
        isFalse,
        reason: 'repetir a mesma chave com payload divergente não resolve',
      );
      expect(
        (await issueWith(FirebaseFunctionsException(code: 'permission-denied', message: 'x')))
            .isRetryable,
        isFalse,
      );
    });
  });

  group('nomes de callable', () {
    test('exatos e região correta', () {
      expect(
        HealthRestrictionFlowCallables.documentPrepareUpload,
        'healthDocumentPrepareUpload',
      );
      expect(
        HealthRestrictionFlowCallables.documentFinalizeUpload,
        'healthDocumentFinalizeUpload',
      );
      expect(
        HealthRestrictionFlowCallables.restrictionIssue,
        'healthRestrictionIssue',
      );
      expect(
        HealthRestrictionFlowCallables.region,
        'southamerica-east1',
      );
    });
  });
}
