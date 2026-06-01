import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/active_shift_identity_service.dart';

void main() {
  test(
    'usa o RA do documento active_shifts mesmo quando handlerId legado esta incorreto',
    () async {
      final firestore = FakeFirebaseFirestore();

      await firestore.collection('active_shifts').doc('691755').set({
        'handlerId': 'firebase-uid-legado',
        'dogId': 'bono',
        'service_dog_id': 'bono',
        'status': 'active',
      });

      final identity = await ActiveShiftIdentityService.resolve(
        firestore: firestore,
        preferredRa: '691755',
      );

      expect(identity?.handlerId, '691755');
      expect(identity?.dogId, 'bono');
    },
  );
}
