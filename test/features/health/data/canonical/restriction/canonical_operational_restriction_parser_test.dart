import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/features/health/data/canonical/restriction/canonical_operational_restriction_parser.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:flutter_test/flutter_test.dart';

/// Parser do documento canônico
/// `dogs/{dogId}/operational_restrictions/{restrictionId}`.
///
/// Os fixtures reproduzem o shape REALMENTE persistido pelo backend:
/// `health_restriction_callables.ts` grava o record do ISSUE e aplica patches de
/// END e CANCEL. Notavelmente, o backend NÃO persiste `id` nem `dog_id` — as
/// duas identidades vêm do path.
void main() {
  const dogId = 'dog-1';
  const restrictionId = 'r-abc123';

  final issuedAt = Timestamp.fromDate(DateTime.utc(2026, 7, 14, 12));
  final terminalAt = Timestamp.fromDate(DateTime.utc(2026, 7, 17, 9));

  Map<String, dynamic> professionalPayload() => <String, dynamic>{
    'name': 'Dra. Vet',
    'registration_type': 'CRMV',
    'registration_number': '12345',
    'clinic': 'Clínica Norte',
    'specialty': 'ortopedia',
  };

  Map<String, dynamic> actorPayload() => <String, dynamic>{
    'uid': 'u1',
    'name': 'Condutor Silva',
    'internal_role': 'condutor',
  };

  /// Record do ISSUE (status `active`).
  Map<String, dynamic> activeDoc([Map<String, dynamic> overrides = const {}]) {
    return <String, dynamic>{
      'status': 'active',
      'level': 'partial',
      'category': 'post_surgical',
      'description': 'pós-operatório de membro anterior',
      'activities_restricted': <dynamic>['busca', 'salto'],
      'issued_at': issuedAt,
      'recorded_by': actorPayload(),
      'professional': professionalPayload(),
      'source_document': <String, dynamic>{
        'health_document_id': 'hd-issue',
        'description': 'laudo cirúrgico',
      },
      'schema_version': 1,
      ...overrides,
    };
  }

  /// ISSUE + patch de END.
  Map<String, dynamic> endedDoc([Map<String, dynamic> overrides = const {}]) {
    return activeDoc(<String, dynamic>{
      'status': 'ended',
      'end_reason': 'alta veterinária',
      'actual_end': terminalAt,
      'ended_by': actorPayload(),
      'end_professional': <String, dynamic>{
        'name': 'Dr. Externo',
        'registration_type': 'CFMV',
        'registration_number': '999',
        'clinic': 'Clínica Sul',
        'specialty': null,
      },
      'end_source_document': <String, dynamic>{
        'health_document_id': 'hd-end',
        'description': null,
      },
      ...overrides,
    });
  }

  /// ISSUE + patch de CANCEL.
  Map<String, dynamic> cancelledDoc([
    Map<String, dynamic> overrides = const {},
  ]) {
    return activeDoc(<String, dynamic>{
      'status': 'cancelled',
      'cancel_reason': 'registro duplicado',
      'cancelled_at': terminalAt,
      'cancelled_by': actorPayload(),
      ...overrides,
    });
  }

  parse(Map<String, dynamic> data, {String? id, String? dog}) =>
      CanonicalOperationalRestrictionParser.parseDocument(
        documentId: id ?? restrictionId,
        queryDogId: dog ?? dogId,
        data: data,
      );

  Matcher throwsParse(
    CanonicalRestrictionParseErrorCode code, [
    String? field,
  ]) {
    var matcher = isA<CanonicalRestrictionParseException>().having(
      (e) => e.code,
      'code',
      code,
    );
    if (field != null) {
      matcher = matcher.having((e) => e.field, 'field', field);
    }
    return throwsA(matcher);
  }

  group('ACTIVE', () {
    test('documento realista do B1 produz agregado íntegro', () {
      final r = parse(activeDoc());
      expect(r.id, restrictionId);
      expect(r.dogId, dogId);
      expect(r.status, RestrictionStatus.active);
      expect(r.level, RestrictionLevel.partial);
      expect(r.category, RestrictionCategory.postSurgical);
      expect(r.description, 'pós-operatório de membro anterior');
      expect(r.activitiesRestricted, ['busca', 'salto']);
      expect(r.issuedAt, DateTime.utc(2026, 7, 14, 12));
      expect(r.recordedBy.uid, 'u1');
      expect(r.recordedBy.internalRole, 'condutor');
      expect(r.professional.registrationType, ProfessionalRegistrationType.crmv);
      expect(r.professional.registrationNumber, '12345');
      expect(r.professional.specialty, 'ortopedia');
      expect(r.sourceDocument.healthDocumentId, 'hd-issue');
      expect(r.schemaVersion, 1);
    });

    test('zero metadata terminal', () {
      final r = parse(activeDoc());
      expect(r.actualEnd, isNull);
      expect(r.endedBy, isNull);
      expect(r.endReason, isNull);
      expect(r.endProfessional, isNull);
      expect(r.endSourceDocument, isNull);
      expect(r.cancelledAt, isNull);
      expect(r.cancelledBy, isNull);
      expect(r.cancelReason, isNull);
    });

    test('expected_end é lido quando presente e não altera status', () {
      final expected = Timestamp.fromDate(DateTime.utc(2026, 7, 24));
      final r = parse(activeDoc({'expected_end': expected}));
      expect(r.expectedEnd, DateTime.utc(2026, 7, 24));
      expect(r.status, RestrictionStatus.active);
    });

    test('expected_end ausente é null, não erro', () {
      expect(parse(activeDoc()).expectedEnd, isNull);
    });

    test('alias since é aceito quando issued_at ausente', () {
      final doc = activeDoc()..remove('issued_at');
      doc['since'] = issuedAt;
      expect(parse(doc).issuedAt, DateTime.utc(2026, 7, 14, 12));
    });

    test('absolute com activities_restricted presente e vazia é aceito', () {
      final r = parse(
        activeDoc({'level': 'absolute', 'activities_restricted': <dynamic>[]}),
      );
      expect(r.activitiesRestricted, isEmpty);
    });

    test('attention com activities_restricted presente e vazia é aceito', () {
      final r = parse(
        activeDoc({'level': 'attention', 'activities_restricted': <dynamic>[]}),
      );
      expect(r.activitiesRestricted, isEmpty);
    });

    test('partial com activities_restricted presente e não vazia é aceito', () {
      final r = parse(
        activeDoc({
          'level': 'partial',
          'activities_restricted': <dynamic>['busca'],
        }),
      );
      expect(r.activitiesRestricted, ['busca']);
    });

    test('activities_restricted AUSENTE falha fechado (não vira [])', () {
      final doc = activeDoc({'level': 'absolute'})
        ..remove('activities_restricted');
      expect(
        () => parse(doc),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'activities_restricted',
        ),
      );
    });

    test('activities_restricted null falha fechado (não vira [])', () {
      expect(
        () => parse(
          activeDoc({'level': 'absolute', 'activities_restricted': null}),
        ),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'activities_restricted',
        ),
      );
    });
  });

  group('ENDED', () {
    test('documento realista do B2 END produz agregado íntegro', () {
      final r = parse(endedDoc());
      expect(r.status, RestrictionStatus.ended);
      expect(r.actualEnd, DateTime.utc(2026, 7, 17, 9));
      expect(r.endedBy!.uid, 'u1');
      expect(r.endReason, 'alta veterinária');
      expect(r.endProfessional!.name, 'Dr. Externo');
      expect(
        r.endProfessional!.registrationType,
        ProfessionalRegistrationType.cfmv,
      );
      expect(r.endProfessional!.specialty, isNull);
      expect(r.endSourceDocument!.healthDocumentId, 'hd-end');
      expect(r.endSourceDocument!.description, isNull);
    });

    test('campos materiais da emissão são preservados', () {
      final r = parse(endedDoc());
      expect(r.level, RestrictionLevel.partial);
      expect(r.category, RestrictionCategory.postSurgical);
      expect(r.description, 'pós-operatório de membro anterior');
      expect(r.professional.name, 'Dra. Vet');
      expect(r.sourceDocument.healthDocumentId, 'hd-issue');
      expect(r.issuedAt, DateTime.utc(2026, 7, 14, 12));
    });

    test('zero metadata de cancelamento', () {
      final r = parse(endedDoc());
      expect(r.cancelledAt, isNull);
      expect(r.cancelledBy, isNull);
      expect(r.cancelReason, isNull);
    });
  });

  group('CANCELLED', () {
    test('documento realista do B2 CANCEL produz agregado íntegro', () {
      final r = parse(cancelledDoc());
      expect(r.status, RestrictionStatus.cancelled);
      expect(r.cancelledAt, DateTime.utc(2026, 7, 17, 9));
      expect(r.cancelledBy!.uid, 'u1');
      expect(r.cancelReason, 'registro duplicado');
    });

    test('campos materiais da emissão são preservados', () {
      final r = parse(cancelledDoc());
      expect(r.level, RestrictionLevel.partial);
      expect(r.description, 'pós-operatório de membro anterior');
      expect(r.professional.name, 'Dra. Vet');
      expect(r.sourceDocument.healthDocumentId, 'hd-issue');
    });

    test('zero metadata de encerramento — não afirma liberação clínica', () {
      final r = parse(cancelledDoc());
      expect(r.actualEnd, isNull);
      expect(r.endedBy, isNull);
      expect(r.endReason, isNull);
      expect(r.endProfessional, isNull);
      expect(r.endSourceDocument, isNull);
    });
  });

  group('exclusividade terminal', () {
    test('active + metadata END é recusado', () {
      expect(
        () => parse(activeDoc({'actual_end': terminalAt})),
        throwsParse(CanonicalRestrictionParseErrorCode.malformed),
      );
    });

    test('active + metadata CANCEL é recusado', () {
      expect(
        () => parse(activeDoc({'cancel_reason': 'x'})),
        throwsParse(CanonicalRestrictionParseErrorCode.malformed),
      );
    });

    test('ended + metadata CANCEL é recusado', () {
      expect(
        () => parse(
          endedDoc({
            'cancelled_at': terminalAt,
            'cancelled_by': actorPayload(),
            'cancel_reason': 'registro duplicado',
          }),
        ),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'hybrid_terminal_metadata',
        ),
      );
    });

    test('cancelled + metadata END é recusado', () {
      expect(
        () => parse(
          cancelledDoc({
            'actual_end': terminalAt,
            'ended_by': actorPayload(),
            'end_reason': 'alta',
            'end_professional': professionalPayload(),
            'end_source_document': <String, dynamic>{
              'health_document_id': 'hd-end',
            },
          }),
        ),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'hybrid_terminal_metadata',
        ),
      );
    });

    test('ended sem end_professional é recusado', () {
      final doc = endedDoc()..remove('end_professional');
      expect(
        () => parse(doc),
        throwsParse(CanonicalRestrictionParseErrorCode.malformed),
      );
    });

    test('ended sem end_source_document é recusado', () {
      final doc = endedDoc()..remove('end_source_document');
      expect(
        () => parse(doc),
        throwsParse(CanonicalRestrictionParseErrorCode.malformed),
      );
    });

    test('ended sem actual_end é recusado', () {
      final doc = endedDoc()..remove('actual_end');
      expect(
        () => parse(doc),
        throwsParse(CanonicalRestrictionParseErrorCode.malformed),
      );
    });

    test('cancelled sem cancel_reason é recusado', () {
      final doc = cancelledDoc()..remove('cancel_reason');
      expect(
        () => parse(doc),
        throwsParse(CanonicalRestrictionParseErrorCode.malformed),
      );
    });

    test('cancelled sem cancelled_by é recusado', () {
      final doc = cancelledDoc()..remove('cancelled_by');
      expect(
        () => parse(doc),
        throwsParse(CanonicalRestrictionParseErrorCode.malformed),
      );
    });
  });

  group('identidade', () {
    test('restrictionId vem do document id', () {
      expect(parse(activeDoc(), id: 'outro-id').id, 'outro-id');
    });

    test('dogId vem do path da consulta', () {
      expect(parse(activeDoc(), dog: 'dog-9').dogId, 'dog-9');
    });

    test('id persistido divergente do document id falha fechado', () {
      expect(
        () => parse(activeDoc({'id': 'r-outro'})),
        throwsParse(CanonicalRestrictionParseErrorCode.identityMismatch, 'id'),
      );
    });

    test('dog_id persistido divergente do path falha fechado', () {
      expect(
        () => parse(activeDoc({'dog_id': 'dog-outro'})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.identityMismatch,
          'dog_id',
        ),
      );
    });

    test('id/dog_id redundantes mas iguais são tolerados', () {
      final r = parse(activeDoc({'id': restrictionId, 'dog_id': dogId}));
      expect(r.id, restrictionId);
      expect(r.dogId, dogId);
    });

    test('document id vazio falha fechado', () {
      expect(
        () => parse(activeDoc(), id: '  '),
        throwsParse(CanonicalRestrictionParseErrorCode.identityMismatch, 'id'),
      );
    });

    test('dogId da consulta vazio falha fechado', () {
      expect(
        () => parse(activeDoc(), dog: ''),
        throwsParse(
          CanonicalRestrictionParseErrorCode.identityMismatch,
          'dog_id',
        ),
      );
    });
  });

  group('schema_version', () {
    test('ausente é malformado', () {
      final doc = activeDoc()..remove('schema_version');
      expect(
        () => parse(doc),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'schema_version',
        ),
      );
    });

    test('versão futura é unsupported, não malformado', () {
      expect(
        () => parse(activeDoc({'schema_version': 2})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.unsupportedSchemaVersion,
          'schema_version',
        ),
      );
    });

    test('tipo inválido é malformado', () {
      expect(
        () => parse(activeDoc({'schema_version': '1'})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'schema_version',
        ),
      );
    });
  });

  group('enums fail-closed', () {
    test('status ausente', () {
      final doc = activeDoc()..remove('status');
      expect(
        () => parse(doc),
        throwsParse(CanonicalRestrictionParseErrorCode.malformed, 'status'),
      );
    });

    test('status desconhecido', () {
      expect(
        () => parse(activeDoc({'status': 'suspended'})),
        throwsParse(CanonicalRestrictionParseErrorCode.malformed, 'status'),
      );
    });

    test('level ausente', () {
      final doc = activeDoc()..remove('level');
      expect(
        () => parse(doc),
        throwsParse(CanonicalRestrictionParseErrorCode.malformed, 'level'),
      );
    });

    test('level desconhecido', () {
      expect(
        () => parse(activeDoc({'level': 'severe'})),
        throwsParse(CanonicalRestrictionParseErrorCode.malformed, 'level'),
      );
    });

    test('category ausente', () {
      final doc = activeDoc()..remove('category');
      expect(
        () => parse(doc),
        throwsParse(CanonicalRestrictionParseErrorCode.malformed, 'category'),
      );
    });

    test('category desconhecida NÃO cai em other', () {
      expect(
        () => parse(activeDoc({'category': 'zoonosis'})),
        throwsParse(CanonicalRestrictionParseErrorCode.malformed, 'category'),
      );
    });

    test('category literalmente other é válida', () {
      expect(
        parse(activeDoc({'category': 'other'})).category,
        RestrictionCategory.other,
      );
    });

    test('registration_type desconhecido falha fechado', () {
      final prof = professionalPayload()..['registration_type'] = 'CRO';
      expect(
        () => parse(activeDoc({'professional': prof})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'professional.registration_type',
        ),
      );
    });
  });

  group('description e activities', () {
    test('description ausente', () {
      final doc = activeDoc()..remove('description');
      expect(
        () => parse(doc),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'description',
        ),
      );
    });

    test('description em branco', () {
      expect(
        () => parse(activeDoc({'description': '   '})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'description',
        ),
      );
    });

    test('partial com activities vazias é recusado pelo invariante', () {
      expect(
        () => parse(activeDoc({'activities_restricted': <dynamic>[]})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'missing_activities_restricted',
        ),
      );
    });

    test('activities com item não textual', () {
      expect(
        () => parse(activeDoc({'activities_restricted': <dynamic>['busca', 7]})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'activities_restricted',
        ),
      );
    });

    test('activities com item vazio', () {
      expect(
        () =>
            parse(activeDoc({'activities_restricted': <dynamic>['busca', ' ']})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'activities_restricted',
        ),
      );
    });

    test('activities de tipo inválido', () {
      expect(
        () => parse(activeDoc({'activities_restricted': 'busca'})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'activities_restricted',
        ),
      );
    });
  });

  group('timestamps', () {
    test('issued_at e since ausentes', () {
      final doc = activeDoc()..remove('issued_at');
      expect(
        () => parse(doc),
        throwsParse(CanonicalRestrictionParseErrorCode.malformed, 'issued_at'),
      );
    });

    test('issued_at malformado não vira now()', () {
      expect(
        () => parse(activeDoc({'issued_at': 'ontem'})),
        throwsParse(CanonicalRestrictionParseErrorCode.malformed, 'issued_at'),
      );
    });

    test('expected_end malformado falha fechado', () {
      expect(
        () => parse(activeDoc({'expected_end': 42})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'expected_end',
        ),
      );
    });

    test('actual_end malformado falha fechado', () {
      expect(
        () => parse(endedDoc({'actual_end': 'hoje'})),
        throwsParse(CanonicalRestrictionParseErrorCode.malformed, 'actual_end'),
      );
    });

    test('cancelled_at malformado falha fechado', () {
      expect(
        () => parse(cancelledDoc({'cancelled_at': 0})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'cancelled_at',
        ),
      );
    });

    test('DateTime cru é aceito além de Timestamp', () {
      final r = parse(activeDoc({'issued_at': DateTime.utc(2026, 5, 1)}));
      expect(r.issuedAt, DateTime.utc(2026, 5, 1));
    });
  });

  group('ProfessionalIdentity', () {
    test('ausente', () {
      final doc = activeDoc()..remove('professional');
      expect(
        () => parse(doc),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'professional',
        ),
      );
    });

    test('tipo inválido', () {
      expect(
        () => parse(activeDoc({'professional': 'Dra. Vet'})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'professional',
        ),
      );
    });

    test('name em branco', () {
      final prof = professionalPayload()..['name'] = '  ';
      expect(
        () => parse(activeDoc({'professional': prof})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'professional.name',
        ),
      );
    });

    test('registration_number ausente', () {
      final prof = professionalPayload()..remove('registration_number');
      expect(
        () => parse(activeDoc({'professional': prof})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'professional.registration_number',
        ),
      );
    });

    test('clinic ausente', () {
      final prof = professionalPayload()..remove('clinic');
      expect(
        () => parse(activeDoc({'professional': prof})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'professional.clinic',
        ),
      );
    });

    test('specialty ausente é null, não erro', () {
      final prof = professionalPayload()..remove('specialty');
      expect(parse(activeDoc({'professional': prof})).professional.specialty,
          isNull);
    });

    test('vocabulário legado não é promovido', () {
      final legacy = <String, dynamic>{
        'vetName': 'Dra. Vet',
        'professionalCrmv': '12345',
        'professionalClinic': 'Clínica Norte',
      };
      expect(
        () => parse(activeDoc({'professional': legacy})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'professional.registration_type',
        ),
      );
    });
  });

  group('atores', () {
    test('recorded_by ausente', () {
      final doc = activeDoc()..remove('recorded_by');
      expect(
        () => parse(doc),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'recorded_by',
        ),
      );
    });

    test('recorded_by sem internal_role falha fechado', () {
      final actor = actorPayload()..remove('internal_role');
      expect(
        () => parse(activeDoc({'recorded_by': actor})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'recorded_by.internal_role',
        ),
      );
    });

    test('recorded_by reduzido a String falha fechado', () {
      expect(
        () => parse(activeDoc({'recorded_by': 'u1'})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'recorded_by',
        ),
      );
    });

    test('ended_by malformado falha fechado', () {
      final actor = actorPayload()..remove('uid');
      expect(
        () => parse(endedDoc({'ended_by': actor})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'ended_by.uid',
        ),
      );
    });

    test('cancelled_by malformado falha fechado', () {
      expect(
        () => parse(cancelledDoc({'cancelled_by': <String, dynamic>{}})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'cancelled_by.uid',
        ),
      );
    });
  });

  group('referências documentais', () {
    test('source_document ausente', () {
      final doc = activeDoc()..remove('source_document');
      expect(
        () => parse(doc),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'source_document',
        ),
      );
    });

    test('source_document sem health_document_id', () {
      expect(
        () => parse(
          activeDoc({
            'source_document': <String, dynamic>{'description': 'laudo'},
          }),
        ),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'source_document.health_document_id',
        ),
      );
    });

    test('source_document tipo inválido', () {
      expect(
        () => parse(activeDoc({'source_document': 'hd-issue'})),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'source_document',
        ),
      );
    });

    test('end_source_document sem health_document_id', () {
      expect(
        () => parse(
          endedDoc({
            'end_source_document': <String, dynamic>{'description': 'alta'},
          }),
        ),
        throwsParse(
          CanonicalRestrictionParseErrorCode.malformed,
          'end_source_document.health_document_id',
        ),
      );
    });

    test('nenhuma resolução de Storage: só identidade', () {
      final r = parse(endedDoc());
      // O agregado cita documentos por id. Storage path, URL e generation não
      // existem no read model — visualização é subgate futuro.
      expect(r.sourceDocument.healthDocumentId, 'hd-issue');
      expect(r.endSourceDocument!.healthDocumentId, 'hd-end');
    });
  });
}
