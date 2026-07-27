import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';
import 'package:canil_gcm/features/health/data/config/local_health_timeline_flag_provider.dart';

void main() {
  group('LocalHealthTimelineFlagProvider', () {
    test('provider local retorna legacyOnly', () async {
      const provider = LocalHealthTimelineFlagProvider();
      final resolution = await provider.resolveMode();
      expect(resolution.mode, equals(HealthTimelineMode.legacyOnly));
    });

    test(
      'provider local retorna missingDefault de forma determinística',
      () async {
        const provider = LocalHealthTimelineFlagProvider();
        final res1 = await provider.resolveMode();
        final res2 = await provider.resolveMode();

        expect(
          res1.kind,
          equals(HealthTimelineModeResolutionKind.missingDefault),
        );
        expect(res1.wasDefaulted, isTrue);
        expect(res1, equals(res2));
      },
    );
  });
}
