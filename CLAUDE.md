# K9 Ops Mobile — Contexto e Regras de Trabalho

## Fonte da verdade

Antes de propor trabalho novo ou tomar decisões amplas sobre o projeto, consulte a documentação oficial vigente em `docs/`.

Prioridade de contexto:

1. instrução explícita da tarefa atual;
2. este `CLAUDE.md`;
3. `AGENTS.md`;
4. código atual da branch;
5. documentação oficial atual em `docs/`;
6. skills específicas aplicáveis à tarefa;
7. arquivos históricos ou temporários.

Arquivos em:

```text
temp/
temp/mockups/
temp/docs/
```

não são fonte de verdade por padrão.

Consulte-os somente quando a tarefa atual indicar explicitamente que são relevantes.

Não faça auditoria ou releitura geral do projeto por padrão para executar uma tarefa localizada.

## Escopo

Durante uma tarefa ou fase definida:

* trabalhe somente no escopo solicitado;
* não faça refactors paralelos sem necessidade;
* não modernize áreas vizinhas automaticamente;
* preserve alterações preexistentes do worktree;
* não faça cleanup destrutivo;
* reporte problemas externos ao escopo sem corrigi-los automaticamente.

A menor mudança segura é preferível.

Isso não significa aplicar correção superficial quando a causa raiz estiver em um ponto compartilhado.

## Preflight Git

Antes de alterações relevantes, verifique pelo menos:

```bash
git branch --show-current
git status --short
```

Quando necessário, verifique também:

```bash
git rev-parse HEAD
git diff --stat
```

Não atribua à tarefa atual arquivos que já estavam modificados anteriormente.

Não execute automaticamente:

```text
git reset
git restore
git checkout destrutivo
git clean
```

sem autorização explícita.

## Firestore compartilhado

O Firestore faz parte de um ecossistema compartilhado entre mobile, web e backend.

Antes de alterar:

```text
campos
tipos
coleções
subcoleções
semântica dos dados
firestore.rules
índices
```

consulte a skill:

```text
firestore-coexistence
```

Quando a operação envolver registros críticos ou histórico de alterações, consulte também:

```text
audit-trail
```

Não presuma que uma alteração é local apenas porque está sendo implementada no mobile.

## `firestore.rules` — fonte canônica

O arquivo canônico de Firestore Rules é o `firestore.rules` deste repositório mobile.

Este repositório é a fonte oficial das Rules.

O repositório web não deve ser utilizado como origem para alterações ou deploy de Firestore Rules.

Qualquer cópia existente em outro repositório deve ser tratada como espelho, não como fonte canônica.

## Deploy de `firestore.rules`

O deploy de Firestore Rules é sempre manual e realizado pelo usuário.

Nunca execute automaticamente:

```bash
firebase deploy --only firestore:rules
```

Prepare a alteração, valide o arquivo e apresente o diff quando fizer parte da tarefa.

Alterar localmente `firestore.rules` não significa que a mudança foi aplicada em produção.

## Deploys em geral

Não execute automaticamente deploy de:

```text
Firestore Rules
Cloud Functions
Hosting
Storage Rules
migrações
backfills
```

salvo quando a tarefa explicitamente autorizar a execução.

Sempre diferencie:

```text
implementado localmente
```

de:

```text
aplicado em produção
```

## Erros de Firestore nunca degradam silenciosamente

Operações Firestore críticas não devem transformar falha em sucesso aparente.

Evite:

```dart
catch (_) {}
```

ou qualquer fallback que esconda um erro real e permita que a interface trate a operação como concluída.

Padrão preferencial quando a camada superior precisa tratar o erro:

```dart
try {
  await operation();
} on FirebaseException catch (e) {
  debugPrint(
    '[Service] operação bloqueada [${e.code}]: ${e.message}',
  );
  rethrow;
}
```

A camada de estado ou interface deve receber informação suficiente para apresentar erro adequado.

Quando uma degradação controlada fizer parte do comportamento esperado, registre a falha de forma diagnóstica.

Nunca degrade silenciosamente.

## Estado vazio não é automaticamente sucesso

Não transforme automaticamente falhas de:

```text
permissão
rede
índice
parsing
backend
```

em:

```text
lista vazia
null
sem dados
```

quando isso impedir distinguir:

```text
não existem registros
```

de:

```text
não foi possível carregar os registros
```

Preserve estados de erro quando forem relevantes para o fluxo.

## Diagnóstico de `PERMISSION_DENIED`

Ao investigar erro de Firestore Rules, não dependa apenas da leitura estática do código.

O payload real pode conter:

* campos adicionados por helpers;
* valores gerados condicionalmente;
* `FieldValue.delete()`;
* variáveis diferentes das esperadas;
* dados produzidos por merges.

Quando o erro não puder ser determinado objetivamente pela análise estática:

1. registre temporariamente o payload real antes da escrita;
2. execute o fluxo real;
3. capture o log;
4. compare os campos efetivamente enviados com as Rules;
5. remova logs temporários após o diagnóstico.

Não mantenha logs completos de payload quando puderem expor informação sensível.

## Whitelists de Firestore Rules

Ao trabalhar com validações baseadas em:

```text
keys().hasOnly()
```

verifique o payload real de cada operação.

Uma operação com:

```dart
set(
  data,
  SetOptions(merge: true),
)
```

pode resultar em comportamento diferente de um `update()` simples.

Campos utilizados com:

```dart
FieldValue.delete()
```

também precisam ser considerados conforme o tipo real da operação e as Rules aplicáveis.

Não altere whitelist por tentativa e erro sem compreender o payload.

## `active_shifts`, `shift_logs` e membros de guarnição

No contrato atual, preserve a distinção entre os payloads utilizados pelas diferentes estruturas.

Antes de alterar helpers compartilhados, confira as Rules e os consumidores atuais.

Historicamente:

```text
active_shifts
shift_logs
```

utilizam o conjunto básico de identificação do handler permitido pelas respectivas Rules.

Já:

```text
vehicle_crews/{crewId}/members/{memberId}
```

pode utilizar um conjunto de campos diferente.

Não reutilize automaticamente o mesmo payload entre estruturas apenas porque representam o mesmo operador.

O contrato atual do código e das Rules é a fonte definitiva.

## Logs

Logs permanentes devem ajudar diagnóstico de falhas reais.

Exemplos úteis:

```text
falha de batch
falha de stream
erro de permissão
erro de backend
```

Logs temporários utilizados para investigação devem ser removidos após a validação.

Não registre:

* tokens;
* credenciais;
* payloads sensíveis completos;
* dados pessoais desnecessários.

## Skills locais

Use as skills locais conforme o domínio da tarefa.

### `canil-k9-context`

Contexto institucional e princípios estáveis do K9 Ops.

### `flutter-canil-conventions`

Convenções gerais de desenvolvimento Flutter.

### `firestore-coexistence`

Obrigatória para mudanças de contrato de dados compartilhados.

### `audit-trail`

Obrigatória para decisões envolvendo rastreabilidade de registros críticos.

### `flutter-visual-fidelity`

Use somente quando explicitamente trabalhando a partir de uma referência visual vigente.

### `pdf-generation`

Use quando a tarefa envolver documentos PDF.

### `ponytail`

Somente por invocação explícita.

Não permita que uma skill genérica sobrescreva:

```text
escopo atual
código vigente
documentação oficial
decisões aprovadas
```

## Validação

Execute validações proporcionais ao escopo.

Exemplos:

```bash
dart format <arquivos alterados>
flutter analyze
flutter test
git diff --check
```

Dependendo da tarefa, também podem ser necessários:

* testes específicos;
* build;
* validação visual;
* teste autenticado;
* validação em dispositivo real.

Nunca afirme que uma validação passou sem executá-la.

Quando houver falha preexistente, diferencie claramente da regressão introduzida pela tarefa atual.

## Commits

Não faça commit automaticamente salvo quando a tarefa ou workflow atual pedir explicitamente.

Antes de commit:

1. confira `git status`;
2. revise o diff;
3. confirme o escopo;
4. não inclua alterações preexistentes por acidente.

## Regra final

O K9 Ops é um produto operacional real com múltiplos sistemas compartilhando dados.

Priorize sempre:

```text
correção
segurança
compatibilidade
rastreabilidade
escopo
clareza
```

Não invente arquitetura.

Não confie em contexto histórico quando o código atual pode responder.

Não expanda uma tarefa localizada para uma revisão geral do projeto.
