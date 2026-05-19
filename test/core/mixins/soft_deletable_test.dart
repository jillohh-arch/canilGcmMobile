import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/core/mixins/soft_deletable.dart';

class _TestModel with SoftDeletable {
  @override
  final DateTime? deletedAt;
  @override
  final String? deletedBy;
  @override
  final String? deleteReason;

  _TestModel({this.deletedAt, this.deletedBy, this.deleteReason});
}

void main() {
  group('SoftDeletable', () {
    test('isDeleted retorna false quando deletedAt é null', () {
      final model = _TestModel();
      expect(model.isDeleted, isFalse);
    });

    test('isDeleted retorna true quando deletedAt está presente', () {
      final model = _TestModel(deletedAt: DateTime(2026, 5, 18));
      expect(model.isDeleted, isTrue);
    });

    test('softDeleteFields retorna campos nulos quando não deletado', () {
      final model = _TestModel();
      final fields = model.softDeleteFields();

      expect(fields['deleted_at'], isNull);
      expect(fields['deleted_by'], isNull);
      expect(fields['delete_reason'], isNull);
    });

    test('softDeleteFields retorna Timestamp quando deletado', () {
      final model = _TestModel(
        deletedAt: DateTime(2026, 5, 18, 10, 30),
        deletedBy: 'user123',
        deleteReason: 'Duplicado',
      );
      final fields = model.softDeleteFields();

      expect(fields['deleted_at'], isA<Timestamp>());
      expect(fields['deleted_by'], equals('user123'));
      expect(fields['delete_reason'], equals('Duplicado'));
    });
  });

  group('SoftDeletable.parseDeletedAt', () {
    test('retorna null para null', () {
      expect(SoftDeletable.parseDeletedAt(null), isNull);
    });

    test('parseia DateTime diretamente', () {
      final dt = DateTime(2026, 5, 18);
      expect(SoftDeletable.parseDeletedAt(dt), equals(dt));
    });

    test('parseia ISO string', () {
      final result = SoftDeletable.parseDeletedAt('2026-05-18T10:30:00.000Z');
      expect(result, isNotNull);
      expect(result!.year, equals(2026));
      expect(result.month, equals(5));
      expect(result.day, equals(18));
    });

    test('parseia Timestamp do Firestore', () {
      final ts = Timestamp.fromDate(DateTime(2026, 5, 18));
      final result = SoftDeletable.parseDeletedAt(ts);
      expect(result, isNotNull);
      expect(result!.year, equals(2026));
    });

    test('retorna null para tipo desconhecido', () {
      expect(SoftDeletable.parseDeletedAt(12345), isNull);
    });
  });
}
