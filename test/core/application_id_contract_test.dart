import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('APP-ID-01.M1 — Android Application Identity Contract Test', () {
    final rootDir = Directory.current;

    test('1. android/app/build.gradle.kts defines namespace as com.ragonha.k9ops', () {
      final gradleFile = File('${rootDir.path}/android/app/build.gradle.kts');
      expect(gradleFile.existsSync(), isTrue, reason: 'build.gradle.kts must exist');
      final content = gradleFile.readAsStringSync();
      expect(content, contains('namespace = "com.ragonha.k9ops"'));
    });

    test('2. android/app/build.gradle.kts defines applicationId as com.ragonha.k9ops', () {
      final gradleFile = File('${rootDir.path}/android/app/build.gradle.kts');
      expect(gradleFile.existsSync(), isTrue, reason: 'build.gradle.kts must exist');
      final content = gradleFile.readAsStringSync();
      expect(content, contains('applicationId = "com.ragonha.k9ops"'));
      expect(content.contains('applicationId = "com.example.canil_gcm"'), isFalse,
          reason: 'Legacy com.example.canil_gcm must not remain in applicationId');
    });

    test('3. MainActivity.kt exists in com/ragonha/k9ops and declares package com.ragonha.k9ops', () {
      final mainActivityFile = File('${rootDir.path}/android/app/src/main/kotlin/com/ragonha/k9ops/MainActivity.kt');
      expect(mainActivityFile.existsSync(), isTrue,
          reason: 'MainActivity.kt must exist at android/app/src/main/kotlin/com/ragonha/k9ops/MainActivity.kt');
      final content = mainActivityFile.readAsStringSync();
      expect(content, contains('package com.ragonha.k9ops'));
      expect(content.contains('package com.example.canil_gcm'), isFalse);
    });

    test('4. Old kotlin com/example package directory is retired', () {
      final legacyDir = Directory('${rootDir.path}/android/app/src/main/kotlin/com/example');
      expect(legacyDir.existsSync(), isFalse,
          reason: 'Old kotlin com/example directory must not exist');
    });

    test('5. proguard-rules.pro preserves com.ragonha.k9ops classes', () {
      final proguardFile = File('${rootDir.path}/android/app/proguard-rules.pro');
      expect(proguardFile.existsSync(), isTrue);
      final content = proguardFile.readAsStringSync();
      expect(content, contains('-keep class com.ragonha.k9ops.** { *; }'));
      expect(content.contains('-keep class com.example.canil_gcm.**'), isFalse);
    });

    test('6. Zero active production Android source files reference com.example.canil_gcm (excluding google-services.json boundary)', () {
      final mainSrcDir = Directory('${rootDir.path}/android/app/src/main');
      expect(mainSrcDir.existsSync(), isTrue);
      final files = mainSrcDir.listSync(recursive: true).whereType<File>();
      for (final f in files) {
        // Exclude google-services.json which remains protected until remote Firebase registration supplies replacement
        if (f.path.endsWith('google-services.json')) continue;
        if (f.path.endsWith('.png') || f.path.endsWith('.jpg') || f.path.endsWith('.webp')) continue;

        final content = f.readAsStringSync();
        expect(
          content.contains('com.example.canil_gcm'),
          isFalse,
          reason: 'Active Android file ${f.path} must not reference com.example.canil_gcm',
        );
      }
    });
  });
}
