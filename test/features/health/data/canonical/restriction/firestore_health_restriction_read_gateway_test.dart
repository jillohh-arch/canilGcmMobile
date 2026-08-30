// ignore_for_file: subtype_of_sealed_class, annotate_overrides
//
// O shim `_Throwing*` implementa as interfaces seladas do Firestore para
// exercitar o error mapping sem emulator — mesma convenção de
// `firestore_canonical_health_timeline_source_test.dart`.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:canil_gcm/features/health/data/canonical/restriction/firestore_health_restriction_read_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_read_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:flutter_test/flutter_test.dart';

/// Read gateway canônico: um `get()` de documento por identidade.
void main() {
  const dogId = 'dog-1';
  const restrictionId = 'r-abc123';

  final issuedAt = Timestamp.fromDate(DateTime.utc(2026, 7, 14, 12));

  Map<String, dynamic> activeDoc([Map<String, dynamic> overrides = const {}]) {
    return <String, dynamic>{
      'status': 'active',
      'level': 'partial',
      'category': 'post_surgical',
      'description': 'pós-operatório de membro anterior',
      'activities_restricted': <dynamic>['busca'],
      'issued_at': issuedAt,
      'recorded_by': <String, dynamic>{
        'uid': 'u1',
        'name': 'Condutor Silva',
        'internal_role': 'condutor',
      },
      'professional': <String, dynamic>{
        'name': 'Dra. Vet',
        'registration_type': 'CRMV',
        'registration_number': '12345',
        'clinic': 'Clínica Norte',
      },
      'source_document': <String, dynamic>{'health_document_id': 'hd-issue'},
      'schema_version': 1,
      ...overrides,
    };
  }

  Future<FakeFirebaseFirestore> seed({
    String dog = dogId,
    String id = restrictionId,
    Map<String, dynamic>? data,
  }) async {
    final db = FakeFirebaseFirestore();
    await db
        .collection('dogs')
        .doc(dog)
        .collection('operational_restrictions')
        .doc(id)
        .set(data ?? activeDoc());
    return db;
  }

  group('sucesso', () {
    test('lê o documento canônico por dogId + restrictionId', () async {
      final gateway = FirestoreHealthRestrictionReadGateway(
        firestore: await seed(),
      );

      final result = await gateway.getById(
        dogId: dogId,
        restrictionId: restrictionId,
      );

      final success = result as HealthRestrictionReadSuccess;
      expect(success.restriction.id, restrictionId);
      expect(success.restriction.dogId, dogId);
      expect(success.restriction.status, RestrictionStatus.active);
      expect(success.restriction.level, RestrictionLevel.partial);
      expect(success.restriction.description,
          'pós-operatório de membro anterior');
    });

    test('whitespace de borda nos ids é tolerado', () async {
      final gateway = FirestoreHealthRestrictionReadGateway(
        firestore: await seed(),
      );

      final result = await gateway.getById(
        dogId: '  $dogId  ',
        restrictionId: '  $restrictionId  ',
      );

      expect(result, isA<HealthRestrictionReadSuccess>());
    });
  });

  group('identidade — múltiplas restrições', () {
    test('getById(A) nunca devolve B, mesmo com campos idênticos', () async {
      final db = FakeFirebaseFirestore();
      final col = db
          .collection('dogs')
          .doc(dogId)
          .collection('operational_restrictions');
      // Level, category e description idênticos: só o document id difere.
      await col.doc('r-A').set(activeDoc());
      await col.doc('r-B').set(activeDoc());

      final gateway = FirestoreHealthRestrictionReadGateway(firestore: db);

      final a = await gateway.getById(dogId: dogId, restrictionId: 'r-A');
      final b = await gateway.getById(dogId: dogId, restrictionId: 'r-B');

      expect((a as HealthRestrictionReadSuccess).restriction.id, 'r-A');
      expect((b as HealthRestrictionReadSuccess).restriction.id, 'r-B');
    });

    test('restrição de outro K9 não é alcançável pelo mesmo id', () async {
      final db = FakeFirebaseFirestore();
      await db
          .collection('dogs')
          .doc('dog-9')
          .collection('operational_restrictions')
          .doc(restrictionId)
          .set(activeDoc());

      final gateway = FirestoreHealthRestrictionReadGateway(firestore: db);

      final result = await gateway.getById(
        dogId: dogId,
        restrictionId: restrictionId,
      );

      expect(
        (result as HealthRestrictionReadError).failure.code,
        HealthRestrictionReadErrorCode.notFound,
      );
    });

    test('prefixo de projeção é rejeitado por validação, não consultado',
        () async {
      final gateway = FirestoreHealthRestrictionReadGateway(
        firestore: await seed(),
      );

      // `restriction:<id>` pertence ao AttentionItem da projeção, não ao
      // documento canônico. O gateway rejeita ANTES de qualquer I/O — não
      // desembrulha, e não deixa o Firestore decidir por acaso via not-found.
      final result = await gateway.getById(
        dogId: dogId,
        restrictionId: 'restriction:$restrictionId',
      );

      final error = result as HealthRestrictionReadError;
      expect(error.failure.code, HealthRestrictionReadErrorCode.validation);
      expect(error.failure.field, 'restrictionId');
    });

    test('prefixo de projeção nunca chega a fazer get() no Firestore',
        () async {
      // Firestore que falharia com um código reconhecível se fosse tocado.
      // Se o resultado for validation (não permissionDenied/unexpected), a
      // rejeição aconteceu antes de qualquer I/O.
      final gateway = FirestoreHealthRestrictionReadGateway(
        firestore: _ThrowingFirestore(
          FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        ),
      );

      final result = await gateway.getById(
        dogId: dogId,
        restrictionId: 'restriction:$restrictionId',
      );

      final error = result as HealthRestrictionReadError;
      expect(error.failure.code, HealthRestrictionReadErrorCode.validation);
    });

    test('id vazio após remover o prefixo também seria rejeitado', () async {
      final gateway = FirestoreHealthRestrictionReadGateway(
        firestore: await seed(),
      );

      final result = await gateway.getById(
        dogId: dogId,
        restrictionId: 'restriction:',
      );

      expect(
        (result as HealthRestrictionReadError).failure.code,
        HealthRestrictionReadErrorCode.validation,
      );
    });
  });

  group('not found', () {
    test('documento ausente é notFound explícito', () async {
      final gateway = FirestoreHealthRestrictionReadGateway(
        firestore: FakeFirebaseFirestore(),
      );

      final result = await gateway.getById(
        dogId: dogId,
        restrictionId: restrictionId,
      );

      final error = result as HealthRestrictionReadError;
      expect(error.failure.code, HealthRestrictionReadErrorCode.notFound);
    });

    test('notFound não fabrica detalhe a partir de projeção', () async {
      final db = FakeFirebaseFirestore();
      // Projeção resumida existe e cita a restrição...
      await db
          .collection('dogs')
          .doc(dogId)
          .collection('health_summary')
          .doc('current')
          .set(<String, dynamic>{
            'active_restrictions': <dynamic>[
              <String, dynamic>{
                'id': restrictionId,
                'level': 'partial',
                'description': 'resumo da projeção',
              },
            ],
          });

      final gateway = FirestoreHealthRestrictionReadGateway(firestore: db);
      final result = await gateway.getById(
        dogId: dogId,
        restrictionId: restrictionId,
      );

      // ...mas o documento canônico não existe: not found é not found.
      expect(
        (result as HealthRestrictionReadError).failure.code,
        HealthRestrictionReadErrorCode.notFound,
      );
    });
  });

  group('validação local', () {
    test('dogId vazio falha antes de qualquer I/O', () async {
      final gateway = FirestoreHealthRestrictionReadGateway(
        firestore: FakeFirebaseFirestore(),
      );

      final result = await gateway.getById(
        dogId: '   ',
        restrictionId: restrictionId,
      );

      final error = result as HealthRestrictionReadError;
      expect(error.failure.code, HealthRestrictionReadErrorCode.validation);
      expect(error.failure.field, 'dogId');
    });

    test('restrictionId vazio falha antes de qualquer I/O', () async {
      final gateway = FirestoreHealthRestrictionReadGateway(
        firestore: FakeFirebaseFirestore(),
      );

      final result = await gateway.getById(dogId: dogId, restrictionId: '');

      final error = result as HealthRestrictionReadError;
      expect(error.failure.code, HealthRestrictionReadErrorCode.validation);
      expect(error.failure.field, 'restrictionId');
    });
  });

  group('integridade', () {
    test('documento malformado é integrity, não notFound', () async {
      final broken = activeDoc()..remove('professional');
      final gateway = FirestoreHealthRestrictionReadGateway(
        firestore: await seed(data: broken),
      );

      final result = await gateway.getById(
        dogId: dogId,
        restrictionId: restrictionId,
      );

      final error = result as HealthRestrictionReadError;
      expect(error.failure.code, HealthRestrictionReadErrorCode.integrity);
      expect(error.failure.field, 'professional');
    });

    test('schema_version futura é integrity com mensagem de atualização',
        () async {
      final gateway = FirestoreHealthRestrictionReadGateway(
        firestore: await seed(data: activeDoc({'schema_version': 2})),
      );

      final result = await gateway.getById(
        dogId: dogId,
        restrictionId: restrictionId,
      );

      final error = result as HealthRestrictionReadError;
      expect(error.failure.code, HealthRestrictionReadErrorCode.integrity);
      expect(error.failure.field, 'schema_version');
      expect(error.failure.message, contains('Atualize'));
    });

    test('dog_id persistido divergente é integrity', () async {
      final gateway = FirestoreHealthRestrictionReadGateway(
        firestore: await seed(data: activeDoc({'dog_id': 'dog-outro'})),
      );

      final result = await gateway.getById(
        dogId: dogId,
        restrictionId: restrictionId,
      );

      final error = result as HealthRestrictionReadError;
      expect(error.failure.code, HealthRestrictionReadErrorCode.integrity);
      expect(error.failure.field, 'dog_id');
    });

    test('malformado nunca degrada para sucesso vazio', () async {
      final gateway = FirestoreHealthRestrictionReadGateway(
        firestore: await seed(data: activeDoc({'status': 'suspended'})),
      );

      final result = await gateway.getById(
        dogId: dogId,
        restrictionId: restrictionId,
      );

      expect(result, isA<HealthRestrictionReadError>());
      expect(
        (result as HealthRestrictionReadError).failure.code,
        HealthRestrictionReadErrorCode.integrity,
      );
    });
  });

  group('erros de transporte', () {
    test('permission-denied é preservado, não vira notFound', () async {
      final gateway = FirestoreHealthRestrictionReadGateway(
        firestore: _ThrowingFirestore(
          FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        ),
      );

      final result = await gateway.getById(
        dogId: dogId,
        restrictionId: restrictionId,
      );

      final error = result as HealthRestrictionReadError;
      expect(error.failure.code, HealthRestrictionReadErrorCode.permissionDenied);
      expect(error.failure.message, contains('autorização'));
    });

    test('unavailable é transitório e distinto de integrity', () async {
      final gateway = FirestoreHealthRestrictionReadGateway(
        firestore: _ThrowingFirestore(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
      );

      final result = await gateway.getById(
        dogId: dogId,
        restrictionId: restrictionId,
      );

      expect(
        (result as HealthRestrictionReadError).failure.code,
        HealthRestrictionReadErrorCode.unavailable,
      );
    });

    test('deadline-exceeded também é unavailable', () async {
      final gateway = FirestoreHealthRestrictionReadGateway(
        firestore: _ThrowingFirestore(
          FirebaseException(plugin: 'cloud_firestore', code: 'deadline-exceeded'),
        ),
      );

      final result = await gateway.getById(
        dogId: dogId,
        restrictionId: restrictionId,
      );

      expect(
        (result as HealthRestrictionReadError).failure.code,
        HealthRestrictionReadErrorCode.unavailable,
      );
    });

    test('código desconhecido é unexpected e preserva o code', () async {
      final gateway = FirestoreHealthRestrictionReadGateway(
        firestore: _ThrowingFirestore(
          FirebaseException(plugin: 'cloud_firestore', code: 'resource-exhausted'),
        ),
      );

      final result = await gateway.getById(
        dogId: dogId,
        restrictionId: restrictionId,
      );

      final error = result as HealthRestrictionReadError;
      expect(error.failure.code, HealthRestrictionReadErrorCode.unexpected);
      expect(error.failure.field, 'resource-exhausted');
    });
  });
}

/// Firestore que falha no `get()` do documento, para exercitar o error mapping
/// sem emulator.
final class _ThrowingFirestore extends FakeFirebaseFirestore {
  _ThrowingFirestore(this.error);

  final Object error;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _ThrowingCollection(super.collection(path), error);
}

final class _ThrowingCollection implements CollectionReference<Map<String, dynamic>> {
  _ThrowingCollection(this._delegate, this._error);

  final CollectionReference<Map<String, dynamic>> _delegate;
  final Object _error;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _ThrowingDocument(_delegate.doc(path), _error);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('não usado neste teste');
}

final class _ThrowingDocument implements DocumentReference<Map<String, dynamic>> {
  _ThrowingDocument(this._delegate, this._error);

  final DocumentReference<Map<String, dynamic>> _delegate;
  final Object _error;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _ThrowingCollection(_delegate.collection(path), _error);

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      Future<DocumentSnapshot<Map<String, dynamic>>>.error(_error);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('não usado neste teste');
}
