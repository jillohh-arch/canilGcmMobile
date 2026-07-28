// Copyright 2024 GCM Health. All rights reserved.
//
// RAW CANONICAL NUTRITION FIRST-PAGE RESULT UNION TESTS — 3 tests.
//
// Pure Dart. NO Firestore, NO network, NO Timer/sleep/timeout/Stopwatch.
// Contract-only: construction, exposure, and exhaustive pattern matching.

import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_first_page_merger.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/raw_canonical_nutrition_first_page_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RawCanonicalNutritionFirstPageResult', () {
    test('1. Success stores and exposes the exact page instance', () {
      final page = RawCanonicalNutritionFirstPage(
        entries: const [],
        hasMore: false,
      );

      final result = RawCanonicalNutritionFirstPageSuccess(page: page);

      expect(identical(result.page, page), isTrue);
    });

    test('2. Failure stores and exposes the exact failure kind', () {
      const result = RawCanonicalNutritionFirstPageFailure(
        kind: RawCanonicalNutritionSourceFailureKind.multipleReadersUnavailable,
      );

      expect(
        result.kind,
        RawCanonicalNutritionSourceFailureKind.multipleReadersUnavailable,
      );
    });

    test('3. sealed result can be exhaustively pattern-matched as success or '
        'failure', () {
      final RawCanonicalNutritionFirstPageResult success =
          RawCanonicalNutritionFirstPageSuccess(
            page: RawCanonicalNutritionFirstPage(
              entries: const [],
              hasMore: false,
            ),
          );
      const RawCanonicalNutritionFirstPageResult failure =
          RawCanonicalNutritionFirstPageFailure(
            kind: RawCanonicalNutritionSourceFailureKind.mealReaderUnavailable,
          );

      String describe(RawCanonicalNutritionFirstPageResult result) =>
          switch (result) {
            RawCanonicalNutritionFirstPageSuccess() => 'success',
            RawCanonicalNutritionFirstPageFailure() => 'failure',
          };

      expect(describe(success), 'success');
      expect(describe(failure), 'failure');
    });
  });
}
