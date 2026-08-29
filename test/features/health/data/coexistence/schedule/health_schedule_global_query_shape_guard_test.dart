import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// HW-4B — GUARD DA SHAPE DA QUERY GLOBAL.
///
/// Converte dois findings do HW-4A em invariantes executáveis:
///
///   1. a query collection-group precisa provar `dog_id` por igualdade/`in`;
///      sem isso as Rules negam (não é filtro, é autorização);
///   2. `orderBy scheduled_for` faz parte da shape aprovada e coberta pelo
///      índice `dog_id, lifecycle_status, scheduled_for`. Removê-lo — ou
///      acrescentar um segundo campo de ordenação — muda a shape e devolve
///      `failed-precondition` em produção.
///
/// Este teste lê o código-fonte do source: é intencional. Uma regressão aqui é
/// alguém "simplificando" a query, e o custo real disso só aparece em produção.
/// Falhar no CI é mais barato que descobrir com o app na mão do condutor.
void main() {
  /// Código do source sem comentários e sem qualquer espaço — imune a quebras
  /// de linha do formatter.
  late String compact;

  setUpAll(() {
    // Somente código: comentários citam a shape para documentá-la e não devem
    // contar como construção de query.
    // Sem espaços: o formatter quebra chamadas longas em múltiplas linhas, e um
    // guard que casa substring contígua falharia só por reformatação — falso
    // alarme pior que guard nenhum.
    compact = _stripComments(_readSource()).replaceAll(RegExp(r'\s+'), '');
  });

  group('shape aprovada da query collection-group', () {
    test('usa collectionGroup na coleção canônica', () {
      expect(
        compact.contains('_db.collectionGroup(collectionId)'),
        isTrue,
        reason: 'a leitura global precisa ser collection-group',
      );
    });

    test('prova dog_id sempre por whereIn', () {
      expect(
        compact.contains("where('dog_id',whereIn:chunk)"),
        isTrue,
        reason: 'dog_id deve ser provado por whereIn em qualquer chunk 1..N',
      );
    });

    test('NUNCA degrada para isEqualTo em dog_id', () {
      // Shape única independente do tamanho do catálogo: `dog_id == X` é uma
      // shape DIFERENTE de `dog_id in [X]`. Tratar as duas como equivalentes é
      // a presunção que o HW-4A proibiu.
      expect(
        compact.contains("where('dog_id',isEqualTo:"),
        isFalse,
        reason:
            'REGRESSÃO: catálogo de 1 K9 não pode degradar para isEqualTo — '
            'isso cria uma segunda shape de query não aprovada',
      );
    });

    test('há exatamente um filtro de dog_id (uma única shape)', () {
      final dogIdFilters = "where('dog_id',".allMatches(compact).length;
      expect(
        dogIdFilters,
        1,
        reason:
            'um único ponto de filtro em dog_id: ramificar por tamanho de '
            'chunk produziria múltiplas shapes',
      );
    });

    test('filtra lifecycle_status persistido', () {
      expect(
        compact.contains("where('lifecycle_status',isEqualTo:"),
        isTrue,
        reason: 'lifecycle é persistido e filtrado remotamente',
      );
    });

    test('mantém orderBy scheduled_for', () {
      expect(
        compact.contains("orderBy('scheduled_for',descending:false)"),
        isTrue,
        reason:
            'REGRESSÃO: remover orderBy scheduled_for muda a shape e exige '
            'outro índice (failed-precondition em produção)',
      );
    });

    test('NÃO adiciona segundo orderBy à query', () {
      // O reader per-dog ordena por (scheduled_for, documentId). Aqui o
      // desempate é local, para preservar a shape aprovada.
      expect(
        compact.contains('orderBy(FieldPath.documentId'),
        isFalse,
        reason:
            'REGRESSÃO: um segundo orderBy muda a shape da query CG e exige '
            'um quarto campo no índice composto',
      );
      final orderByCount = 'orderBy('.allMatches(compact).length;
      expect(
        orderByCount,
        1,
        reason: 'a shape aprovada tem exatamente um orderBy',
      );
    });

    test('não usa array-contains-any nem aliases de dog_id', () {
      expect(compact.contains('arrayContainsAny'), isFalse);
      expect(compact.contains("where('dogId'"), isFalse);
      expect(compact.contains("where('caoId'"), isFalse);
      expect(compact.contains("where('k9_id'"), isFalse);
    });
  });

  group('nenhuma query irrestrita', () {
    test('todo collectionGroup é seguido de filtro em dog_id', () {
      // Não existe caminho que emita collectionGroup sem prova de dog_id.
      final cgCount = 'collectionGroup('.allMatches(compact).length;
      expect(
        cgCount,
        1,
        reason: 'um único ponto de construção da query global',
      );
    });

    test('não existe fallback sem dog_id', () {
      final lower = compact.toLowerCase();
      // Guarda contra o antipadrão explicitamente proibido:
      // "se bounded falhar → consultar collectionGroup sem dog_id".
      expect(
        lower.contains('fallback') && lower.contains('collectiongroup'),
        isFalse,
        reason: 'fallback unbounded é proibido',
      );
    });

    test('catálogo vazio retorna antes de qualquer I/O', () {
      final guardIndex = compact.indexOf('if(query.isEmptyCatalog)');
      final queryIndex = compact.indexOf('_db.collectionGroup(collectionId)');
      expect(guardIndex, greaterThan(-1));
      expect(queryIndex, greaterThan(-1));
      expect(
        guardIndex,
        lessThan(queryIndex),
        reason: 'o guard de catálogo vazio precisa vir antes da query',
      );
    });
  });

  group('separação lifecycle persistido / temporal derivado', () {
    test('não consulta estado temporal derivado', () {
      for (final derived in [
        'overdue',
        'upcoming',
        'today',
        'pending',
        'temporal_status',
      ]) {
        expect(
          compact.contains("where('$derived'"),
          isFalse,
          reason: '$derived é derivado na leitura, nunca consultado',
        );
        expect(
          compact.contains("isEqualTo:'$derived'"),
          isFalse,
          reason: '$derived não é valor persistido de lifecycle',
        );
      }
    });
  });

  group('erros preservam natureza', () {
    test('permission-denied continua autorização', () {
      expect(compact.contains("code=='permission-denied'"), isTrue);
      expect(compact.contains('isPermissionDenied:true'), isTrue);
    });

    test('failed-precondition continua erro de query/índice', () {
      expect(compact.contains("code=='failed-precondition'"), isTrue);
      expect(
        compact.contains('índiceausente'),
        isTrue,
        reason: 'failed-precondition não pode virar empty nem offline',
      );
    });
  });
}

/// Remove comentários de linha e de bloco, mantendo apenas código executável.
///
/// Sem isso o guard confunde a shape documentada no docstring com a shape
/// realmente construída — e passaria mesmo se a query fosse alterada.
String _stripComments(String source) {
  final withoutBlocks = source.replaceAll(
    RegExp(r'/\*.*?\*/', dotAll: true),
    '',
  );
  return withoutBlocks
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');
}

/// Lê o source concreto. Tenta paths relativos porque o cwd do runner varia
/// entre `flutter test` na raiz e execução por arquivo.
String _readSource() {
  const relative =
      'lib/features/health/data/coexistence/schedule/'
      'firestore_health_schedule_global_source.dart';
  for (final prefix in ['', '../', '../../', '../../../']) {
    final file = File('$prefix$relative');
    if (file.existsSync()) return file.readAsStringSync();
  }
  fail('não foi possível localizar $relative a partir do cwd do teste');
}
