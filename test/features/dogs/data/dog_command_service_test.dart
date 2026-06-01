import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/dogs/data/dog_command_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog_command.dart';

void main() {
  group('DogCommandService', () {
    late FakeFirebaseFirestore firestore;
    late DogCommandService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = DogCommandService(firestore: firestore);
    });

    test('remove comando por soft delete e preserva documento', () async {
      final commandId = await service.addCommand(
        'dog-1',
        DogCommand(
          name: 'Junto',
          category: 'operacional',
          lastUpdatedAt: DateTime(2026, 5, 31, 10),
          lastUpdatedBy: '691755',
        ),
      );

      await service.deleteCommand('dog-1', commandId, reason: 'Teste');

      final snap = await firestore
          .collection('dogs')
          .doc('dog-1')
          .collection('commands')
          .doc(commandId)
          .get();
      final visible = await service.getCommands('dog-1');

      expect(snap.exists, isTrue);
      expect(snap.data()!['deleted_at'], isNotNull);
      expect(snap.data()!['delete_reason'], 'Teste');
      expect(visible, isEmpty);
    });

    test('commandExists ignora comandos removidos por soft delete', () async {
      final commandId = await service.addCommand(
        'dog-1',
        DogCommand(
          name: 'Platz',
          category: 'postural',
          lastUpdatedAt: DateTime(2026, 5, 31, 10),
          lastUpdatedBy: '691755',
        ),
      );

      expect(await service.commandExists('dog-1', 'Platz'), isTrue);

      await service.deleteCommand('dog-1', commandId, reason: 'Teste');

      expect(await service.commandExists('dog-1', 'Platz'), isFalse);
    });
  });
}
