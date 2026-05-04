import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/models/occurrence_nature.dart';

void main() {
  group('OccurrenceNature', () {
    test('normalizes accents and punctuation for search', () {
      expect(
        OccurrenceNature.normalizeForSearch('Tráfico / Injúria racial'),
        'trafico injuria racial',
      );
    });

    test('matches by partial text without accents', () {
      const nature = OccurrenceNature(
        code: 'A38',
        name: 'Injúria racial',
        group: 'Contra a pessoa e a vida',
      );

      expect(nature.matches('injuria'), isTrue);
      expect(nature.matches('racial'), isTrue);
      expect(nature.matches('A38'), isTrue);
      expect(nature.matches('patrimonio'), isFalse);
    });

    test('seed contains official GCM Limeira nature table', () {
      expect(OccurrenceNatureSeed.items, hasLength(202));
      expect(
        OccurrenceNatureSeed.items.any((nature) => nature.name == 'Furto'),
        isTrue,
      );
      expect(
        OccurrenceNatureSeed.items.any(
          (nature) => nature.name == 'Ocorrência com entorpecente',
        ),
        isTrue,
      );
      expect(
        OccurrenceNatureSeed.items.any(
          (nature) => nature.name == 'Acidente de trânsito',
        ),
        isTrue,
      );
      expect(
        OccurrenceNatureSeed.items.any(
          (nature) => nature.name == 'Apoio em ocorrências',
        ),
        isTrue,
      );
    });
  });
}
