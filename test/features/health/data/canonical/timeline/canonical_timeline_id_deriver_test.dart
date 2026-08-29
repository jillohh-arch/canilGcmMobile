// Copyright 2024 GCM Health. All rights reserved.
//
// CANONICAL HEALTH TIMELINE ID DERIVER — Tests
//
// 12 tests validating cross-language ID derivation contract.

import 'package:canil_gcm/features/health/data/canonical/timeline/canonical_timeline_id_deriver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonicalHealthTimelineSourcePath', () {
    test('builds exact dog-scoped source paths for both collections', () {
      // Verify enum firestoreCollection values
      expect(
        CanonicalHealthTimelineSourceCollection.mealLogs.firestoreCollection,
        equals('meal_logs'),
      );
      expect(
        CanonicalHealthTimelineSourceCollection
            .supplementLogs
            .firestoreCollection,
        equals('supplement_logs'),
      );

      // Verify exact path construction
      expect(
        canonicalHealthTimelineSourcePath(
          dogId: 'dog123',
          sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
        ),
        equals('dogs/dog123/meal_logs'),
      );
      expect(
        canonicalHealthTimelineSourcePath(
          dogId: 'dog123',
          sourceCollection:
              CanonicalHealthTimelineSourceCollection.supplementLogs,
        ),
        equals('dogs/dog123/supplement_logs'),
      );
      expect(
        canonicalHealthTimelineSourcePath(
          dogId: 'dog-001',
          sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
        ),
        equals('dogs/dog-001/meal_logs'),
      );
    });
  });

  group('deriveCanonicalHealthTimelineId', () {
    // ─────────────────────────────────────────────────────────────────
    // GOLDEN VECTORS — must match TypeScript exactly
    // ─────────────────────────────────────────────────────────────────

    test('matches TypeScript golden vector for planned meal', () {
      // Vector 1: dogId=dog123, source=meal_logs, sourceId=mo1_test
      // Expected: tl1_7b4299c45102c070634956184e7dee96b5bb096e80f61f654ab69c993cbd066b
      final id = deriveCanonicalHealthTimelineId(
        dogId: 'dog123',
        sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
        sourceId: 'mo1_test',
      );
      expect(
        id,
        equals(
          'tl1_7b4299c45102c070634956184e7dee96b5bb096e80f61f654ab69c993cbd066b',
        ),
        reason: 'mealLogs golden vector must match TypeScript exactly',
      );
    });

    test('matches TypeScript golden vector for supplement', () {
      // Vector 2: dogId=dog123, source=supplement_logs, sourceId=sl1_test
      // Expected: tl1_4ba3abd4c0dfe87b1987049b4cecb68a25782b825793a6b301ab3f10a9d08a63
      final id = deriveCanonicalHealthTimelineId(
        dogId: 'dog123',
        sourceCollection:
            CanonicalHealthTimelineSourceCollection.supplementLogs,
        sourceId: 'sl1_test',
      );
      expect(
        id,
        equals(
          'tl1_4ba3abd4c0dfe87b1987049b4cecb68a25782b825793a6b301ab3f10a9d08a63',
        ),
        reason: 'supplementLogs golden vector must match TypeScript exactly',
      );
    });

    test('matches TypeScript golden vector for meal with shared source id', () {
      // Vector 3: dogId=dog-001, source=meal_logs, sourceId=same-id
      // Expected: tl1_35d4a55ecff81e213bca7fda08994a5015bf6e77d7c29e9d7c274709f56fb3a3
      final id = deriveCanonicalHealthTimelineId(
        dogId: 'dog-001',
        sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
        sourceId: 'same-id',
      );
      expect(
        id,
        equals(
          'tl1_35d4a55ecff81e213bca7fda08994a5015bf6e77d7c29e9d7c274709f56fb3a3',
        ),
        reason: 'mealLogs with shared id must match TypeScript exactly',
      );
    });

    test(
      'matches TypeScript golden vector for supplement with shared source id',
      () {
        // Vector 4: dogId=dog-001, source=supplement_logs, sourceId=same-id
        // Expected: tl1_0219ee87a7de83a01308f4febaafb9fcab8d2c435fba607410471f3f4710187c
        final id = deriveCanonicalHealthTimelineId(
          dogId: 'dog-001',
          sourceCollection:
              CanonicalHealthTimelineSourceCollection.supplementLogs,
          sourceId: 'same-id',
        );
        expect(
          id,
          equals(
            'tl1_0219ee87a7de83a01308f4febaafb9fcab8d2c435fba607410471f3f4710187c',
          ),
          reason: 'supplementLogs with shared id must match TypeScript exactly',
        );
      },
    );

    // ─────────────────────────────────────────────────────────────────
    // SEMANTIC TESTS
    // ─────────────────────────────────────────────────────────────────

    test('uses distinct ids for the same source id across collections', () {
      final mealId = deriveCanonicalHealthTimelineId(
        dogId: 'dog123',
        sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
        sourceId: 'mo1_shared',
      );
      final supplementId = deriveCanonicalHealthTimelineId(
        dogId: 'dog123',
        sourceCollection:
            CanonicalHealthTimelineSourceCollection.supplementLogs,
        sourceId: 'mo1_shared',
      );
      expect(mealId, isNot(equals(supplementId)));
    });

    test('uses distinct ids for different dog ids', () {
      final id1 = deriveCanonicalHealthTimelineId(
        dogId: 'dog123',
        sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
        sourceId: 'mo1_test',
      );
      final id2 = deriveCanonicalHealthTimelineId(
        dogId: 'dog456',
        sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
        sourceId: 'mo1_test',
      );
      expect(id1, isNot(equals(id2)));
    });

    test('uses distinct ids for different source ids', () {
      final id1 = deriveCanonicalHealthTimelineId(
        dogId: 'dog123',
        sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
        sourceId: 'mo1_aaa',
      );
      final id2 = deriveCanonicalHealthTimelineId(
        dogId: 'dog123',
        sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
        sourceId: 'mo1_bbb',
      );
      expect(id1, isNot(equals(id2)));
    });

    test('is deterministic across repeated calls', () {
      final id1 = deriveCanonicalHealthTimelineId(
        dogId: 'dog123',
        sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
        sourceId: 'mo1_test',
      );
      final id2 = deriveCanonicalHealthTimelineId(
        dogId: 'dog123',
        sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
        sourceId: 'mo1_test',
      );
      final id3 = deriveCanonicalHealthTimelineId(
        dogId: 'dog123',
        sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
        sourceId: 'mo1_test',
      );
      expect(id1, equals(id2));
      expect(id2, equals(id3));
    });

    test('uses tl1 prefix and lowercase 64-character hexadecimal digest', () {
      final id = deriveCanonicalHealthTimelineId(
        dogId: 'dog123',
        sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
        sourceId: 'mo1_test',
      );

      // Verificar prefixo
      expect(id.startsWith('tl1_'), isTrue);

      // Extrair digest
      final digest = id.substring(4);
      expect(digest.length, equals(64));

      // Verificar hexadecimal lowercase
      expect(digest, matches(RegExp(r'^[0-9a-f]{64}$')));

      // Total: 4 (prefix) + 64 (digest) = 68
      expect(id.length, equals(68));
    });

    // ─────────────────────────────────────────────────────────────────
    // VALIDATION TESTS
    // ─────────────────────────────────────────────────────────────────

    test('rejects blank whitespace or slash-containing dog ids', () {
      // Blank
      expect(
        () => deriveCanonicalHealthTimelineId(
          dogId: '',
          sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
          sourceId: 'mo1_test',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Whitespace-only
      expect(
        () => deriveCanonicalHealthTimelineId(
          dogId: '   ',
          sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
          sourceId: 'mo1_test',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Contains slash
      expect(
        () => deriveCanonicalHealthTimelineId(
          dogId: 'dogs/dog123',
          sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
          sourceId: 'mo1_test',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects blank whitespace or slash-containing source ids', () {
      // Blank
      expect(
        () => deriveCanonicalHealthTimelineId(
          dogId: 'dog123',
          sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
          sourceId: '',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Whitespace-only
      expect(
        () => deriveCanonicalHealthTimelineId(
          dogId: 'dog123',
          sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
          sourceId: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Contains slash
      expect(
        () => deriveCanonicalHealthTimelineId(
          dogId: 'dog123',
          sourceCollection: CanonicalHealthTimelineSourceCollection.mealLogs,
          sourceId: 'mo1/test',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
