import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/core/services/audit_service.dart';

void main() {
  group('AuditService.isDeleted', () {
    test('retorna true quando deleted_at está presente', () {
      final doc = {'deleted_at': DateTime.now(), 'name': 'test'};
      expect(AuditService.isDeleted(doc), isTrue);
    });

    test('retorna false quando nenhum campo de deleção existe', () {
      final doc = {'name': 'test', 'status': 'active'};
      expect(AuditService.isDeleted(doc), isFalse);
    });

    test('retorna true com Timestamp-like no deleted_at', () {
      final doc = {'deleted_at': '2026-05-18T10:00:00.000Z'};
      expect(AuditService.isDeleted(doc), isTrue);
    });
  });

  group('AuditEntry.fromJson', () {
    test('lê formato novo (snake_case)', () {
      final json = {
        'action': 'updated',
        'entity_type': 'occurrence',
        'entity_id': 'abc123',
        'summary': 'Campo alterado',
        'field_name': 'status',
        'reason': 'Correção',
        'actor': {'uid': 'u1', 'email': 'a@b.com', 'ra': 'a', 'name': 'Ana'},
      };

      final entry = AuditEntry.fromJson(json, docId: 'doc1');

      expect(entry.id, equals('doc1'));
      expect(entry.action, equals('updated'));
      expect(entry.entityType, equals('occurrence'));
      expect(entry.entityId, equals('abc123'));
      expect(entry.fieldName, equals('status'));
      expect(entry.reason, equals('Correção'));
      expect(entry.actor?['name'], equals('Ana'));
    });

    test('lê formato legado (camelCase)', () {
      final json = {
        'action': 'created',
        'entityType': 'training',
        'entityId': 'xyz789',
        'summary': 'Sessão criada',
      };

      final entry = AuditEntry.fromJson(json);

      expect(entry.entityType, equals('training'));
      expect(entry.entityId, equals('xyz789'));
    });

    test('actorName retorna RA formatado', () {
      final json = {
        'action': 'created',
        'entity_type': 'health',
        'entity_id': '1',
        'summary': 'test',
        'actor': {'uid': 'u1', 'email': 'j@gcm.com', 'ra': '12345'},
      };

      final entry = AuditEntry.fromJson(json);
      expect(entry.actorName, equals('RA 12345'));
    });

    test('actorName retorna Desconhecido sem actor', () {
      final json = {
        'action': 'deleted',
        'entity_type': 'occurrence',
        'entity_id': '2',
        'summary': 'test',
      };

      final entry = AuditEntry.fromJson(json);
      expect(entry.actorName, equals('Desconhecido'));
    });

    test('performedAt parseia ISO string', () {
      final json = {
        'action': 'created',
        'entity_type': 'health',
        'entity_id': '1',
        'summary': 'test',
        'performed_at': '2026-05-18T10:30:00.000Z',
      };

      final entry = AuditEntry.fromJson(json);
      expect(entry.performedAt, isNotNull);
      expect(entry.performedAt!.year, equals(2026));
      expect(entry.performedAt!.month, equals(5));
    });

    test('isRegression detecta regressão', () {
      final json = {
        'action': 'updated',
        'entity_type': 'command',
        'entity_id': '1',
        'summary': 'Regressão',
        'before': {'stage': 'consolidated'},
        'after': {'stage': 'developing'},
        'reason': 'Falha em avaliação',
      };

      final entry = AuditEntry.fromJson(json);
      expect(entry.isRegression, isTrue);
    });
  });
}
