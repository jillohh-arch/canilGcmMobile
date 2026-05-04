import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/models/health_log_model.dart';
import 'package:canil_gcm/models/routine_model.dart';
import 'package:canil_gcm/models/training_session_model.dart';
import 'package:canil_gcm/utils/firestore_date.dart';

void main() {
  group('parseFirestoreDate', () {
    test('accepts Firestore Timestamp', () {
      final date = DateTime.utc(2026, 4, 20, 10, 30);

      expect(parseFirestoreDate(Timestamp.fromDate(date)).toUtc(), date);
    });

    test('accepts ISO strings from legacy or web clients', () {
      expect(
        parseFirestoreDate('2026-04-20T10:30:00.000Z').toUtc(),
        DateTime.utc(2026, 4, 20, 10, 30),
      );
    });
  });

  group('operational models date contract', () {
    test('TrainingSessionModel reads ISO strings and writes Timestamp', () {
      final model = TrainingSessionModel.fromJson({
        'dogId': 'dog-1',
        'handlerId': '12345',
        'date': '2026-04-20T10:30:00.000Z',
        'trainingType': 'Faro',
        'location': 'Base GCM',
        'weather': 'Limpo',
        'handlerNotes': 'Treino importado do web',
      });

      expect(model.date.toUtc(), DateTime.utc(2026, 4, 20, 10, 30));
      expect(model.toJson()['date'], isA<Timestamp>());
    });

    test('HealthLogModel reads ISO strings and writes Timestamp', () {
      final model = HealthLogModel.fromJson({
        'dogId': 'dog-1',
        'date': '2026-04-20T10:30:00.000Z',
        'logType': 'Consulta',
        'healthObservations': 'Retorno importado do web',
      });

      expect(model.date.toUtc(), DateTime.utc(2026, 4, 20, 10, 30));
      expect(model.toJson()['date'], isA<Timestamp>());
    });

    test('RoutineModel reads ISO strings and writes Timestamp', () {
      final model = RoutineModel.fromJson({
        'dogId': 'dog-1',
        'handlerId': '12345',
        'activityType': 'Passeio',
        'status': 'Concluído',
        'timestamp': '2026-04-20T10:30:00.000Z',
      });

      expect(model.timestamp.toUtc(), DateTime.utc(2026, 4, 20, 10, 30));
      expect(model.toJson()['timestamp'], isA<Timestamp>());
    });
  });
}
