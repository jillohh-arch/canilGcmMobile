# Canil GCM — Contexto e Padrões

> **PENDÊNCIAS CONHECIDAS:** consultar [BACKLOG.md](./BACKLOG.md) antes de
> propor trabalho novo. Lá estão as tasks pendentes em rules, mobile, web e
> produto — e o histórico do que já foi concluído.

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

---

## Lições de produção

### Erros de permissão nunca degradam silenciosamente

Falha de batch = falha da operação inteira. Não usar `catch (_) {}` vazio,
não fazer fallback que "grava só o log" e retorna como sucesso. O padrão:

```dart
try {
  await batch.commit();
} on FirebaseException catch (e) {
  debugPrint('[Servico] batch bloqueado [${e.code}]: ${e.message}');
  rethrow; // propaga até o ViewModel → UI mostra AppFeedback.error
}
```

Logs permanentes (`[ShiftService] batch bloqueado`, `[STREAM] falhou`) são
valiosos e devem ser mantidos. Logs de diagnóstico temporários (payload
completo impresso antes do commit) devem ser removidos após validação.

### Diagnóstico de rules com payload impresso, não com tabela interpretada

Ao investigar `PERMISSION_DENIED`, não reconstruir o payload "a olho" pelo
código. Campos como `name`, `auth_uid`, `FieldValue.delete()` ou variáveis
incorretas podem estar presentes sem serem visíveis na leitura estática.

O diagnóstico definitivo:

1. Adicionar `debugPrint` do payload completo antes do `batch.commit()`
2. Rodar o teste real e capturar o logcat
3. Confrontar cada campo real, linha a linha, com a whitelist da regra

### Deploy de firestore.rules: sempre manual

Sempre manual pelo usuário, sempre do repo mobile, nunca automático.
O deploy de rules é irreversível a curto prazo (pode bloquear todas as
escritas de todos os usuários simultaneamente). O usuário deploya após
conferir o diff.

---

## Roadmap / Visão de produto

### Composição de guarnição configurável por corporação
**Validação de mercado: 07/2026** — Em evento com corporações de outros
municípios, confirmou-se que a composição típica de guarnição K9 no mercado é
**2-3 humanos + cão**; 4 humanos é exceção de cidades grandes (onde o cão vai
em compartimento próprio).

**Objetivo:** permitir que cada corporação configure a exibição da guarnição sem
mudar o modelo de dados (roles).

| Configuração | Descrição |
|---|---|
| Postos exibidos | Quais roles aparecem no card e em qual ordem |
| Obratórios para OPERACIONAL | Hoje: motorista + encarregado |
| Postos condicionais | Hoje: Auxiliar 2 (só aparece se ocupado) |
| Posição do K9 | Hoje: baixo-direita na grade; pode variar |

**Arquitetura:**
- `lib/core/config/crew_composition.dart` — ponto central de configuração
- Domain continua com roles string (`motorista`, `encarregado`, `auxiliar_1`, etc.)
- UI (card, sheet) lê da configuração, não de listas hardcoded
- **Futuro:** doc de config da corporação lido no boot via Firestore ou JSON
- **Futuro:** tela de configuração para admin da corporação

**Implementado (07/2026):**
- `CrewComposition` com `gridPosts`, `compactPosts`, `requiredForOperational`
- Enum `CrewPost` com `role`, `displayName`, `shortLabel`
- Card unificado EM SERVIÇO com planta da viatura (MOT/ENC/AUX1/K9)
- AUX2 como linha compacta só quando ocupado
