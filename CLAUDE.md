# Canil GCM — Contexto e Padrões

## Lições aprendidas

### Erro de permissão nunca degrada silenciosamente

Qualquer `FirebaseException` com `code` em operações Firestore críticas
(turno, viatura, dog) **nunca** deve ser engolido com `catch (_) {}` ou
retornado como sucesso. Degradação silenciosa mascara o erro real por rodadas
de diagnóstico. O padrão correto:

1. `debugPrint('[Serviço] falhou [${e.code}]: ${e.message}')`
2. `rethrow` para que o ViewModel popule `_error`
3. A UI exibe `AppFeedback.error`

Se degradação for necessária por UX (ex: dashboard legado), logar SEMPRE com
`debugPrint` — nunca `catch (_) {}` vazio.

### Diagnóstico de rules com payload impresso, não com tabela interpretada

Ao investigar `PERMISSION_DENIED`, não confiar em tabela reconstruída a olho do
código. Campos como `name`, `auth_uid` ou `FieldValue.delete()` podem estar
presentes no payload sem serem visíveis na leitura estática. O diagnóstico
definitivo é:

1. Adicionar `debugPrint` do payload completo **antes** do `batch.commit()`
2. Rodar o teste real
3. Capturar o logcat com o payload impresso
4. Confrontar o payload real, campo a campo, com a whitelist da regra

Confrontos "estáticos" sem o payload real levaram a duas rodadas de diagnóstico
desnecessárias (campos que "pareciam" ausentes estavam presentes; campos que
"pareciam" corretos usavam a variável errada).

### Campo `name` em active_shifts vs members

- `active_shifts` e `shift_logs`: usar `handlerFieldsBasic` (só `auth_uid` +
  `handler_email`) — `name` NÃO está na whitelist de `isValidActiveShiftFor()`
  nem de `isValidShiftLogCreate()`
- `members` (vehicle_crews/{crewId}/members/{ra}`): usar `handlerFieldsWithName`
  (inclui `name`) — `name` está na whitelist dessa subcoleção

O bug recorrente é usar `handlerFieldsWithName` no `active_shifts` por
distração, achando que "o nome é útil ali". Não é — e quebra a regra.

### `FieldValue.delete()` precisa estar no whitelist do CREATE

Quando um documento pode ser criado ou atualizado (upsert via `merge: true`),
campos que usam `FieldValue.delete()` para limpar valores do documento
precisam constar no `keys().hasOnly()` do `allow create`, não só do
`allow update`. Exemplo: `ended_at` no `vehicle_crews`.
