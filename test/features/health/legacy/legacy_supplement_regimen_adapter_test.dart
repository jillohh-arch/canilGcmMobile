import 'package:canil_gcm/features/health/domain/legacy_nutrition_views.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/legacy/legacy_health_adapters.dart';
import 'package:canil_gcm/features/health/legacy/legacy_supplement_regimen_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adapter = LegacySupplementRegimenAdapter();

  test('nutrition_supplements → LegacySupplementRegimenView NÃO SupplementLog', () {
    final result = adapter.parse(
      sourceId: 'sup-1',
      dogId: 'dog-1',
      data: {
        'name': 'Ômega 3',
        'dose': '1 cápsula',
        'started_at': '2026-01-01T00:00:00Z',
        'status': 'active',
        'notes': 'com ração',
      },
    );
    expect(result.hasValue, isTrue);
    expect(result.value, isA<LegacySupplementRegimenView>());
    expect(result.value, isNot(isA<SupplementLog>()));
    final view = result.value!;
    expect(view.doseText, '1 cápsula');
    expect(view.isAdministration, isFalse);
    expect(view.startedAt, isNotNull);
    expect(
      result.issues.any((i) => i.code == 'not_administration_log'),
      isTrue,
    );
  });

  test('nome ausente → failure', () {
    final result = adapter.parse(
      sourceId: 'sup-2',
      dogId: 'dog-1',
      data: const {'dose': '10ml'},
    );
    expect(result.state, LegacyParseState.failure);
  });
}
