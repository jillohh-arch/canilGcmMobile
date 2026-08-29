import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';

void main() {
  group('HealthTimelineMode', () {
    test('wire value de legacyOnly', () {
      expect(HealthTimelineMode.legacyOnly.wireValue, equals('legacyOnly'));
    });

    test('wire value de shadowCompare', () {
      expect(
        HealthTimelineMode.shadowCompare.wireValue,
        equals('shadowCompare'),
      );
    });

    test('wire value de canonicalPrimary', () {
      expect(
        HealthTimelineMode.canonicalPrimary.wireValue,
        equals('canonicalPrimary'),
      );
    });

    test('parse válido de legacyOnly', () {
      final res = HealthTimelineModeResolution.parse('legacyOnly');
      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.configured));
      expect(res.wasDefaulted, isFalse);
    });

    test('parse válido de shadowCompare', () {
      final res = HealthTimelineModeResolution.parse('shadowCompare');
      expect(res.mode, equals(HealthTimelineMode.shadowCompare));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.configured));
      expect(res.wasDefaulted, isFalse);
    });

    test('parse válido de canonicalPrimary', () {
      final res = HealthTimelineModeResolution.parse('canonicalPrimary');
      expect(res.mode, equals(HealthTimelineMode.canonicalPrimary));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.configured));
      expect(res.wasDefaulted, isFalse);
    });

    test('parse válido com espaços externos', () {
      final res = HealthTimelineModeResolution.parse('   shadowCompare \t\n');
      expect(res.mode, equals(HealthTimelineMode.shadowCompare));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.configured));
      expect(res.wasDefaulted, isFalse);
    });

    test('null resulta em legacyOnly', () {
      final res = HealthTimelineModeResolution.parse(null);
      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
    });

    test('null resulta em missingDefault', () {
      final res = HealthTimelineModeResolution.parse(null);
      expect(res.kind, equals(HealthTimelineModeResolutionKind.missingDefault));
      expect(res.wasDefaulted, isTrue);
    });

    test('string vazia resulta em missingDefault', () {
      final res = HealthTimelineModeResolution.parse('');
      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.missingDefault));
      expect(res.wasDefaulted, isTrue);
    });

    test('somente espaços resulta em missingDefault', () {
      final res = HealthTimelineModeResolution.parse('   \t\n ');
      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.missingDefault));
      expect(res.wasDefaulted, isTrue);
    });

    test('valor desconhecido resulta em invalidDefault', () {
      final res = HealthTimelineModeResolution.parse('unrecognized_mode_key');
      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.invalidDefault));
      expect(res.wasDefaulted, isTrue);
    });

    test('capitalização incorreta resulta em invalidDefault', () {
      final res = HealthTimelineModeResolution.parse('LegacyOnly');
      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.invalidDefault));
      expect(res.wasDefaulted, isTrue);
    });

    test('resolução inválida não preserva o raw value', () {
      const secretRaw = 'SECRET_UNRECOGNIZED_FLAG_PAYLOAD_123';
      final res = HealthTimelineModeResolution.parse(secretRaw);
      expect(res.mode, equals(HealthTimelineMode.legacyOnly));
      expect(res.kind, equals(HealthTimelineModeResolutionKind.invalidDefault));
      expect(res.toString(), isNot(contains(secretRaw)));
    });
  });
}
