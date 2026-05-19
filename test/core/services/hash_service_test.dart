import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/core/services/hash_service.dart';

void main() {
  group('HashService.computeHash', () {
    test('retorna string hex de 64 caracteres (SHA-256)', () {
      final hash = HashService.computeHash({'key': 'value'});
      expect(hash.length, equals(64));
      expect(RegExp(r'^[a-f0-9]+$').hasMatch(hash), isTrue);
    });

    test('mesmo input gera mesmo hash', () {
      final data = {'name': 'Bono', 'age': 5, 'active': true};
      final hash1 = HashService.computeHash(data);
      final hash2 = HashService.computeHash(data);
      expect(hash1, equals(hash2));
    });

    test('ordem das keys não afeta o hash', () {
      final data1 = {'b': 2, 'a': 1, 'c': 3};
      final data2 = {'a': 1, 'c': 3, 'b': 2};
      expect(HashService.computeHash(data1), equals(HashService.computeHash(data2)));
    });

    test('dados diferentes geram hashes diferentes', () {
      final hash1 = HashService.computeHash({'status': 'active'});
      final hash2 = HashService.computeHash({'status': 'finalized'});
      expect(hash1, isNot(equals(hash2)));
    });

    test('normaliza DateTime para UTC ISO string', () {
      final local = DateTime(2026, 5, 18, 10, 30);
      final utc = local.toUtc();
      final hash1 = HashService.computeHash({'date': local});
      final hash2 = HashService.computeHash({'date': utc});
      expect(hash1, equals(hash2));
    });

    test('normaliza Timestamp do Firestore', () {
      final dt = DateTime.utc(2026, 5, 18, 10, 30);
      final ts = Timestamp.fromDate(dt);
      final hash1 = HashService.computeHash({'date': dt});
      final hash2 = HashService.computeHash({'date': ts});
      expect(hash1, equals(hash2));
    });

    test('lida com maps aninhados', () {
      final data = {
        'outer': {'inner_b': 2, 'inner_a': 1},
        'list': [1, 2, 3],
      };
      final hash = HashService.computeHash(data);
      expect(hash.length, equals(64));
    });

    test('lida com valores null', () {
      final data = {'key': null, 'other': 'value'};
      final hash = HashService.computeHash(data);
      expect(hash.length, equals(64));
    });
  });

  group('HashService.verify', () {
    test('retorna true para dados inalterados', () {
      final data = {'nature': 'furto', 'events': 3, 'finalized': true};
      final hash = HashService.computeHash(data);
      expect(HashService.verify(data, hash), isTrue);
    });

    test('retorna false para dados alterados', () {
      final data = {'nature': 'furto', 'events': 3};
      final hash = HashService.computeHash(data);
      data['events'] = 4;
      expect(HashService.verify(data, hash), isFalse);
    });

    test('retorna false para hash arbitrário', () {
      final data = {'key': 'value'};
      expect(HashService.verify(data, 'abc123'), isFalse);
    });
  });
}
