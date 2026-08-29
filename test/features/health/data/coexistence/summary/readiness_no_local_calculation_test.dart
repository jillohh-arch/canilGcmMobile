import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// READINESS-V1 Gate 6 — guarda arquitetural.
///
/// O Mobile é LEITOR de prontidão, nunca avaliador. Estes testes falham se
/// alguém reintroduzir cálculo clínico local no caminho de runtime do Resumo.
///
/// A autoridade única é `functions/src/health_readiness_policy.ts`.
void main() {
  /// Arquivos de runtime que compõem o caminho de Prontidão no Resumo.
  const readinessRuntimePath = [
    'lib/features/health/data/coexistence/summary/health_summary_readiness_reader.dart',
    'lib/features/health/data/coexistence/summary/readiness_snapshot_parser.dart',
    'lib/features/health/data/coexistence/summary/readiness_callable.dart',
    'lib/features/health/data/coexistence/summary/coexistence_health_summary_source.dart',
    'lib/features/health/domain/readiness_snapshot.dart',
  ];

  String read(String relative) {
    final file = File(relative);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'arquivo de runtime ausente: $relative',
    );
    return file.readAsStringSync();
  }

  /// Percorre `lib/` procurando importadores de um caminho.
  List<String> importersOf(String needle) {
    final out = <String>[];
    final dir = Directory('lib');
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      // Considera apenas linhas de import/export reais, não comentários.
      for (final line in content.split('\n')) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        if (trimmed.contains(needle)) {
          out.add(entity.path.replaceAll(r'\', '/'));
          break;
        }
      }
    }
    return out;
  }

  group('ARCH — nenhum cálculo local de prontidão', () {
    test('a policy Dart deprecada não tem importador de runtime', () {
      final importers = importersOf('domain/readiness_policy.dart');
      expect(
        importers,
        isEmpty,
        reason:
            'ReadinessPolicy é LEGADO NÃO AUTORITATIVO e não pode ganhar '
            'caller de runtime. Importadores encontrados: $importers',
      );
    });

    test('o caminho de runtime não invoca avaliador clínico local', () {
      // Símbolos que indicariam decisão clínica sendo tomada no cliente.
      const forbidden = [
        'ReadinessPolicy',
        'evaluateReadiness',
        'calculateReadiness',
        'computeReadiness',
        'readinessScore',
        'readinessStreak',
      ];

      for (final path in readinessRuntimePath) {
        final content = read(path);
        for (final symbol in forbidden) {
          expect(
            content.contains(symbol),
            isFalse,
            reason: '$path não pode referenciar $symbol',
          );
        }
      }
    });

    test('o leitor não deriva prontidão de evidência clínica bruta', () {
      final reader = read(readinessRuntimePath.first);

      // O leitor pode citar estes nomes em comentários explicativos, mas não
      // pode consultar as coleções de evidência: isso seria recalcular.
      const forbiddenCollections = [
        "collection('weight_records')",
        "collection('health_events')",
        "collection('nutrition_plans')",
        "collection('operational_restrictions')",
        "collection('vaccination_records')",
        "collection('health_timeline')",
      ];

      for (final call in forbiddenCollections) {
        expect(
          reader.contains(call),
          isFalse,
          reason:
              'o leitor de Prontidão só pode ler health_summary/current; '
              'encontrou acesso a $call',
        );
      }

      // E lê exatamente o documento canônico de projeção.
      expect(reader.contains("collection('health_summary')"), isTrue);
      expect(reader.contains("doc('current')"), isTrue);
    });

    test('o Mobile nunca escreve em health_summary', () {
      for (final path in readinessRuntimePath) {
        final content = read(path);
        // Nenhuma escrita no caminho de projeção.
        for (final write in ['.set(', '.update(', '.delete(']) {
          if (!content.contains('health_summary')) continue;
          // Se o arquivo menciona health_summary, nenhuma escrita pode
          // aparecer nele.
          expect(
            content.contains(write),
            isFalse,
            reason: '$path menciona health_summary e contém $write',
          );
        }
      }
    });

    test('exame não é gate de completude em runtime', () {
      for (final path in readinessRuntimePath) {
        final content = read(path);
        // `has_recent_exam` pode ser citado em comentário explicando a
        // exclusão, mas nunca lido como chave de contrato.
        expect(
          content.contains("['has_recent_exam']"),
          isFalse,
          reason: '$path não pode ler has_recent_exam como gate',
        );
      }
    });

    test('placeholder unsafe saiu do caminho de runtime', () {
      final source = read(
        'lib/features/health/data/coexistence/summary/coexistence_health_summary_source.dart',
      );
      // Nem import nem uso das constantes.
      expect(
        source.contains('health_summary_unsafe_sections.dart'),
        isFalse,
        reason: 'a fonte de Resumo não deve mais importar o placeholder',
      );
      expect(
        source.contains('HealthSummaryUnsafeSections.readiness'),
        isFalse,
      );
      expect(
        source.contains('HealthSummaryUnsafeSections.attention'),
        isFalse,
      );

      // E as seções reais estão ligadas.
      expect(source.contains('readinessSections.readiness'), isTrue);
      expect(source.contains('readinessSections.attention'), isTrue);
    });

    test('nenhum importador de runtime do placeholder resta em lib/', () {
      final importers = importersOf('health_summary_unsafe_sections.dart');
      expect(
        importers,
        isEmpty,
        reason: 'placeholder ainda importado por: $importers',
      );
    });
  });

  group('ARCH — Prontidão não autoriza ação no cliente', () {
    test('o leitor não bloqueia turno nem associação', () {
      final reader = read(readinessRuntimePath.first);

      // Gate 6 é DISPLAY. Autorização crítica é do backend sobre
      // operational_restrictions e é auditada separadamente.
      const forbiddenGuards = [
        'canStartShift',
        'blockShift',
        'denyShift',
        'canAssociate',
        'blockAssociation',
        'isAuthorized',
        'authorize',
      ];

      for (final guard in forbiddenGuards) {
        expect(
          reader.contains(guard),
          isFalse,
          reason: 'o leitor de exibição não pode conter $guard',
        );
      }
    });
  });
}
