import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/health/data/config/firebase_health_timeline_remote_config_client.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_remote_config_client.dart';

void main() {
  group('FirebaseHealthTimelineRemoteConfigClient.mapValueSource', () {
    test('ValueSource.valueStatic -> staticValue', () {
      final res = FirebaseHealthTimelineRemoteConfigClient.mapValueSource(
        ValueSource.valueStatic,
      );
      expect(res, equals(HealthTimelineRemoteValueSource.staticValue));
    });

    test('ValueSource.valueDefault -> defaultValue', () {
      final res = FirebaseHealthTimelineRemoteConfigClient.mapValueSource(
        ValueSource.valueDefault,
      );
      expect(res, equals(HealthTimelineRemoteValueSource.defaultValue));
    });

    test('ValueSource.valueRemote -> remoteValue', () {
      final res = FirebaseHealthTimelineRemoteConfigClient.mapValueSource(
        ValueSource.valueRemote,
      );
      expect(res, equals(HealthTimelineRemoteValueSource.remoteValue));
    });
  });
}
