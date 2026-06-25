import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/shifts/domain/active_shift_session.dart';

void main() {
  group('ActiveShiftSession', () {
    test('considera ativo quando o K9 vem em service_dog_id', () {
      final session = ActiveShiftSession.fromJson({
        'handlerId': '691755',
        'service_dog_id': 'bono',
        'status': 'active',
      });

      expect(session.isActive, isTrue);
      expect(session.dogId, 'bono');
      expect(session.effectiveServiceDogId, 'bono');
    });

    test('usa currentDogId como compatibilidade para logs e docs antigos', () {
      final session = ActiveShiftSession.fromJson({
        'handlerId': '691755',
        'currentDogId': 'apolo',
        'status': 'active',
      });

      expect(session.isActive, isTrue);
      expect(session.dogId, 'apolo');
      expect(session.effectiveServiceDogId, 'apolo');
    });
  });
}
