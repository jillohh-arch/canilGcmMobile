import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/dogs/data/dog_service.dart';

void main() {
  group('DogService', () {
    test('usa o id do documento como identidade canonica do K9', () async {
      final firestore = FakeFirebaseFirestore();
      final service = DogService(firestore: firestore);

      await firestore.collection('dogs').doc('bono').set({
        'id': 'id-interno-legado',
        'name': 'Bono',
        'breed': 'Malinois',
        'sex': 'M',
        'dateOfBirth': '2020-01-01T00:00:00.000',
        'status': 'Ativo',
      });

      final dogs = await service.getDogs().first;

      expect(dogs, hasLength(1));
      expect(dogs.single.id, 'bono');
      expect(dogs.single.name, 'Bono');
    });
  });
}
