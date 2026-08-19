# ADR-009 — Consistência Causal da Projeção de Prontidão

| Campo | Valor |
|-------|-------|
| Status | **Aprovado — Implementado no backend** |
| Data | 2026-08-19 |
| Branch | `feature/health-mobile-uiux-refinement` |
| Baseline B4-R.C1 | `7af9a3bff98f622030623efd19450665e3095024` |
| Baseline B4-R.C2 | `002009a77e6326edd8e4bf3029698c8b267b6741` |
| Origem da decisão | B4-R.A (auditoria), B4-R.B (desenho aprovado), B4-R.C1, B4-R.C2 + C2.R |
| Deploy | **NÃO APLICADO EM PRODUÇÃO** |
| Documentos relacionados | ADR-004 (projeções), ADR-005 (prontidão e restrições), HEALTH_V1_READINESS_POLICY.md |
| Escopo | Ordenação causal de projeções de prontidão, estado de coordenação server-only, contrato de convergência do refresh |
| Fora de escopo | Consumo no Mobile (B4-R.C3), regressão de integração (B4-R.C4), UI de ciclo de vida, Rules, índices, deploy |

---

## 1. Contexto

Uma mutation canônica de restrição (`healthRestrictionIssue`, `healthRestrictionEnd`,
`healthRestrictionCancel`) commita em `operational_restrictions`. A projeção de
prontidão que alimenta `dogs/{dogId}/health_summary/current` é assíncrona: roda a
partir de triggers Firestore e do callable explícito de refresh.

O Mobile lê a projeção, não a fonte canônica. Logo existe uma janela em que a
mutation já está commitada e a projeção observável ainda descreve o estado
anterior.

---

## 2. Problema

Dois problemas distintos foram identificados. Confundi-los foi o que atrasou o
diagnóstico original.

**A. Leitura obsoleta após a mutation.**
O Mobile relê `health_summary/current` depois de uma mutation bem-sucedida e pode
observar a projeção anterior. Pior: essa projeção anterior pode estar dentro da
janela de frescor (5 minutos, ADR-005 §266), portanto o cliente a considera
válida e renderiza estado clínico obsoleto — por exemplo, uma restrição
encerrada continuando a aparecer como ativa.

**B. Sobrescrita obsoleta entre projeções concorrentes.**
Problema mais profundo, descoberto durante a auditoria. Toda execução do
projector relê todas as fontes canônicas, então nunca deriva estado de um payload
de evento obsoleto. Mas a **escrita** não tinha guarda de ordenação: uma execução
que leu estado antigo podia commitar **depois** de uma execução que leu estado
novo, sobrescrevendo-a silenciosamente.

O problema B não é específico de restrições. Afeta as cinco entradas da
infraestrutura de prontidão.

```text
A. mutation commitada → cliente lê projeção anterior       (leitura obsoleta)
B. execução antiga commita depois da nova                   (escrita obsoleta)
```

---

## 3. Alternativas rejeitadas

### 3.1 Frescor não é causalidade

`readiness_updated_at` é marcador de **frescor**, não de causalidade. Uma
projeção pode ser simultaneamente recente e anterior à mutation:

```text
mutation commitada em T
projeção executada em T-2s, gravada em T+1s
readiness_updated_at = T+1s   → parece recente
conteúdo                      → anterior à mutation
```

Portanto `frescor != causalidade`. A semântica de `readiness_updated_at`
permanece inalterada: continua sendo apenas frescor.

### 3.2 Presença/ausência de restrição não é prova causal

Verificar se a restrição X aparece em `active_restrictions` é asserção de
conteúdo, não barreira causal:

- **ISSUE**: a presença de X pode coincidir com um estado anterior ou concorrente
  que já a continha;
- **END/CANCEL**: a ausência de X pode já ser verdadeira antes da mutation;
- uma projeção `unavailable` também altera o que é observável, sem que isso
  signifique que a mutation foi projetada.

Membership permanece asserção secundária de conteúdo, nunca a prova causal.

### 3.3 `operationId` não foi escolhido

`operationId` pertence à idempotência da mutation. Um único
`last_operation_id` no summary não possui ordenação:

```text
operation A, depois operation B
summary contém B
um waiter de A não pode inferir causalidade por igualdade
```

Manter histórico de `operationId` para resolver isso seria construir um relógio
lógico paralelo ao que a generation já oferece. Rejeitado.

### 3.4 Timestamps de fonte e `updateTime` não foram escolhidos

`issued_at`, `actual_end`, `cancelled_at` e o `updateTime` do Firestore foram
considerados inadequados **como contrato primário** porque as respostas das
mutations não os expunham como barreira, múltiplos documentos não oferecem uma
revisão global simples, o relógio do cliente não pode participar da decisão, e
nenhum deles protegeria a ordenação das escritas do projector (problema B).

Isso não afirma que timestamps sejam inúteis em geral. A decisão é apenas que
não são o contrato causal escolhido.

---

## 4. Decisão — generation monotônica por K9

Três números, três papéis, deliberadamente separados:

```text
readiness_updated_at    → frescor
projection generation   → causalidade e ordenação de apply
operationId             → idempotência da mutation
```

Nenhum acumula o papel do outro.

---

## 5. Estado de coordenação server-only

Path implementado:

```text
_health_projection_state/health_readiness_v1/dogs/{dogId}
```

Campos:

| Campo | Semântica |
|---|---|
| `last_reserved_generation` | maior generation já reservada para este K9 |
| `last_applied_generation` | maior generation cujo apply foi aceito, READY **ou** UNAVAILABLE |

Ambos são server-only. O cliente nunca os lê: `firestore.rules` nega o namespace
inteiro (`match /_health_projection_state/{document=**} { allow read, write: if false }`,
linha 2257), e o Admin SDK ignora Rules por definição.

Ausência de campo faz bootstrap em `0`. Valor presente mas inutilizável (string,
float, negativo, `NaN`, fora do intervalo seguro) é documento de coordenação
corrompido: falha fechada, nunca reset silencioso — resetar entregaria uma
generation já aplicada e reabriria exatamente a janela que este contrato fecha.
`last_applied_generation > last_reserved_generation` é falha de integridade.

Teto: `Number.MAX_SAFE_INTEGER - 1`, para que `current + 1` nunca saia do
intervalo exatamente representável.

---

## 6. Invariante de reserva

A generation `G` é reservada **antes da primeira leitura de fonte canônica**.

```text
1. reserva G          (transação no doc de coordenação)
2. lê as fontes canônicas
3. avalia
4. apply guardado
```

Razão: assim uma generation maior significa sempre "começou depois", portanto
"leu estado ao menos tão novo".

**Distinção importante e deliberada:**

```text
ordenação causal de execuções de projeção
!=
snapshot atômico multi-fonte no Firestore
```

As leituras das cinco fontes não são um snapshot transacional único. A generation
ordena o **início** das execuções; não promete atomicidade de leitura.

---

## 7. Apply guardado e ordenação total

Para uma generation candidata `G`:

```text
se last_applied_generation >= G:
    → SUPERSEDED
    → zero mutação no summary
    → zero regressão de last_applied_generation

senão:
    → apply do summary
    → last_applied_generation = G
    (ambos na MESMA transação)
```

`>=` (não `>`) torna o replay do mesmo apply um no-op em vez de reescrita.
`superseded` é resultado saudável sob concorrência, não erro.

A guarda compara contra `last_applied_generation`, e **não** contra
`projection_generation`, precisamente para que escritas `unavailable` também
sejam ordenadas. As quatro classes ficam cobertas:

```text
READY antigo após READY novo ................ bloqueado
UNAVAILABLE antigo após READY novo .......... bloqueado
READY antigo após UNAVAILABLE novo .......... bloqueado
UNAVAILABLE antigo após UNAVAILABLE novo .... bloqueado
```

Sem isso, uma execução `unavailable` obsoleta ainda poderia mesclar
`projection_status`/`technical_blockers` sobre uma projeção READY mais nova — a
sobrescrita obsoleta mudaria de campo, não desapareceria.

---

## 8. Generation READY pública

Campo em `dogs/{dogId}/health_summary/current`:

```text
projection_generation
```

Semântica: generation da última projeção **READY** aplicada. Somente READY
avança esse valor. `unavailable` nunca avança. É o único dos três números que o
cliente pode usar como prova causal, porque só uma execução READY revalidou o
payload clínico.

### 8.1 Por que `unavailable` não avança

`unavailable_preserving` preserva os campos clínicos anteriores como
last-known-good, por merge. Se a generation pública avançasse em `unavailable`,
publicaríamos:

```text
payload clínico antigo + generation causal nova
```

e um waiter convergiria sobre estado clínico não revalidado. Combinação esperada
e correta:

```text
READY G=41, depois UNAVAILABLE G=42

last_applied_generation = 42
projection_status       = unavailable
projection_generation   = 41
```

Isso **não** é convergência para `required G=42`.

### 8.2 Compatibilidade de schema

`projection_generation` foi adicionado **sem** bump de `schema_version`, que
permanece `1` (`READINESS_SCHEMA_VERSION`, `health_readiness_policy.ts:29`).

Razão verificável: `ReadinessSnapshotParser` fixa `supportedSchemaVersion = 1` e
rejeita explicitamente `rawSchema > supportedSchemaVersion` como
`unsupportedSchema`
(`lib/features/health/data/coexistence/summary/readiness_snapshot_parser.dart:62,77`).
Um bump degradaria silenciosamente para "indisponível" todo cliente já
distribuído. Um campo extra desconhecido, ao contrário, é simplesmente ignorado
por esse parser. Portanto backend novo + Mobile antigo é compatível.

---

## 9. Entry points protegidos

O protocolo de generation é central — vive na camada de `applyProjection`, não
replicado por trigger.

Terminologia congelada, para evitar leitura errada:

```text
PROJECTOR ENTRY POINTS
  4 triggers Firestore
+ 1 callable explícito de refresh
= 5

CANONICAL EVIDENCE SOURCES
  não possuem trigger 1:1
```

As cinco entradas:

| Entry point | Documento |
|---|---|
| `healthReadinessProjectWeightRecord` | `dogs/{dogId}/weight_records/{recordId}` |
| `healthReadinessProjectHealthEvent` | `dogs/{dogId}/health_events/{eventId}` |
| `healthReadinessProjectNutritionPlan` | `dogs/{dogId}/nutrition_plans/{planId}` |
| `healthReadinessProjectRestriction` | `dogs/{dogId}/operational_restrictions/{restrictionId}` |
| `healthReadinessRefresh` | callable explícito |

Não existe helper de escrita não guardada: todo caminho de produção para
`health_summary/current` passa por `applyProjection`.

> **Observação factual, fora do escopo deste ADR:** o projector lê **cinco**
> fontes canônicas — as quatro acima mais `vaccination_records` — mas
> `vaccination_records` não possui trigger dedicado. Uma escrita direta nessa
> subcoleção não dispara reprojeção por si só. Isso é anterior a B4-R e não
> afeta a ordenação causal; fica registrado como item aberto.

---

## 10. Refresh explícito como barreira causal

Contrato de sequenciamento:

```text
mutation de restrição retorna sucesso
        ↓  (transação canônica já commitada)
Mobile invoca healthReadinessRefresh
        ↓
refresh reserva a generation G
        ↓
projeção lê estado canônico posterior à mutation
        ↓
apply guardado
        ↓
observação causal no reread
```

A resposta da mutation **não** carrega generation. O ordenamento das chamadas RPC
(mutation retorna, depois refresh começa) é o que garante que a execução do
refresh começa após o commit canônico.

### 10.1 Writers de mutation permanecem congelados

`healthRestrictionIssue`, `healthRestrictionEnd` e `healthRestrictionCancel` não
foram alterados por B4-R. Suas respostas continuam sendo a autoridade do
resultado da mutation; os receipts continuam sendo a autoridade de
idempotência/replay. Causalidade de projeção é domínio separado.

---

## 11. Contrato do wire do refresh

Metadado **aditivo** em `healthReadinessRefresh`:

```json
{
  "ok": true,
  "result": {
    "...campos legados...": "...",
    "convergence": {
      "status": "confirmed",
      "requiredGeneration": 42,
      "observedGeneration": 43
    }
  }
}
```

Literais de status, exaustivos:

```text
confirmed
not_confirmed
unavailable
```

### 11.1 Tipos

| Campo | Tipo |
|---|---|
| `requiredGeneration` | inteiro positivo, **sempre presente**, gerado no servidor; é a generation reservada por esta execução do refresh |
| `observedGeneration` | inteiro positivo quando existe generation READY observável; `null` quando não existe |

`0` **nunca** é usado como sentinela de ausência. Ausência, campo legado sem o
marcador e valor malformado produzem `null` — um `0` fabricado seria um número
que convida a aritmética e pode ser lido como generation real.

---

## 12. Semântica de `confirmed`

```text
confirmed

SE E SOMENTE SE o summary observado tem:

    projection_status == "ready"
  E observedGeneration é inteiro positivo válido
  E observedGeneration >= requiredGeneration
```

`>=`, **não** `==`.

### 12.1 Por que uma generation READY superior é prova válida

```text
refresh reserva G
projector concorrente reserva H > G

reserva de H ocorreu depois da reserva de G          (monotonicidade)
leituras de H ocorrem depois da reserva de H
reserva de G ocorreu depois do commit da mutation

∴ READY H é causalmente ao menos tão novo quanto G precisa
```

Portanto `observed H >= required G` é prova válida — inclusive quando a execução
`G` terminou `unavailable` ou foi `superseded`.

Exigir igualdade faria um refresh falhar para sempre sempre que outra entrada
ganhasse a corrida.

---

## 13. Precedência de classificação

Ordem implementada (correção C2.R). É load-bearing:

```text
1. existe READY observado com H >= G?
   → confirmed

2. não existe essa prova, e
   (o estado observado é unavailable OU a execução seguiu o caminho unavailable)?
   → unavailable

3. restante
   → not_confirmed
```

A prova observada é avaliada **primeiro**. A pergunta é sobre o estado
atualmente commitado, não sobre o que esta execução conseguiu escrever.

### 13.1 Por que uma execução `unavailable` ainda pode confirmar

```text
required G = 42
execução 42 → unavailable
projeção concorrente 43 → READY
summary observado → READY 43

resultado:
  status              = confirmed
  requiredGeneration  = 42
  observedGeneration  = 43
```

Avaliar o desfecho local primeiro produziria falso negativo exatamente quando a
concorrência favoreceu o chamador: um refresh com fontes momentaneamente
ilegíveis reportaria indisponibilidade enquanto uma projeção READY completa e
mais nova estava commitada à sua frente. Também contradiria o `>=`, ao fazer a
convergência depender de **qual** execução produziu a prova.

### 13.2 Por que o marcador READY sozinho não confirma

```text
required G = 42
summary observado:
  projection_status     = unavailable
  projection_generation = 42

resultado: unavailable   (NÃO confirmed)
```

`projection_generation >= required` só é prova enquanto o
`projection_status` observado ainda é `ready`. Uma escrita `unavailable` deixa o
marcador READY anterior intacto como last-known-good, então o par
`(unavailable, 42)` significa "42 não foi revalidada", não "42 está provada".
As duas condições são exigidas juntas.

---

## 14. Semântica de `not_confirmed` e `unavailable`

**`not_confirmed`** — a execução não produziu nem observou prova causal
suficiente, e não há indisponibilidade factual que explique o estado:

```text
READY observado com generation < required
summary READY sem projection_generation (rollout de backend anterior)
execução READY + falha no reread
marcador observado malformado
```

**`unavailable`** — indisponibilidade técnica factual:

```text
execução unavailable sem prova READY mais nova
summary atualmente observado é unavailable
execução unavailable + falha no reread → observedGeneration = null
```

Nenhum dos dois significa falha da mutation.

---

## 15. Semântica de `ok`

```text
ok                  = contrato legado do callable
convergence.status  = contrato causal novo
```

`response.ok` **não** significa convergência causal e nunca é derivado dela.
Combinações válidas e esperadas:

```text
ok = true  +  convergence.status = unavailable
ok = true  +  convergence.status = not_confirmed
```

O gateway Mobile já em produção lê apenas `response['ok']` e ignora chaves
desconhecidas, portanto o campo aditivo não afeta APK antigo. O Mobile novo deve
consumir `result.convergence` explicitamente.

### 15.1 Erros do callable

Falhas de autenticação, autorização, validação, integridade, transporte e
inesperadas continuam sendo erros normais do callable, segundo o contrato de erro
já existente.

Por isso o enum de convergência **não** possui membro genérico `failed`: ele
ficaria ambíguo entre "não há prova causal" e "a chamada em si quebrou". A
ausência é deliberada.

---

## 16. Modelo de falha

Regra load-bearing:

```text
sucesso da mutation + falha de convergência  ≠  falha da mutation
```

Nunca repetir automaticamente ISSUE/END/CANCEL apenas porque a projeção não
confirmou. Retry de mutation e retry de convergência são operações distintas.

- **ISSUE**: mantém a dívida R-01 (intenção da operação não durável entre morte
  de processo). Se a mutation pode ter commitado e a convergência falhou, não
  criar novo ISSUE automaticamente. R-01 **não** está resolvido.
- **END/CANCEL**: podem já estar terminalmente commitados enquanto a
  convergência falha. Não repetir o comando só para atualizar a UI; um conflito
  de backend não é mecanismo de refresh.

---

## 17. Contrato de consumo no Mobile (B4-R.C3 — ainda não implementado)

Estados **client-side**, não literais do wire:

```text
idle
submittingMutation
mutationCommitted        (preserva restrictionId no ISSUE; resultado terminal em END/CANCEL)
convergingProjection
converged
convergenceFailed
```

Leitura esperada:

```text
confirmed      → pode reler e renderizar
not_confirmed  → mutation segue commitada; projeção não foi provada
unavailable    → mutation segue commitada; prontidão tecnicamente indisponível
```

`convergingProjection`, `converged` e `convergenceFailed` **nunca** aparecem na
resposta do servidor.

---

## 18. Ordem de rollout

Backend (generation, ordenação, refresh causal) deve estar disponível antes de o
Mobile depender do contrato causal.

```text
backend novo + APK antigo         → compatível (campo extra ignorado)
Mobile novo + backend sem generation → falha fechada na verificação causal
```

Nada deste ADR foi aplicado em produção.

---

## 19. Segurança

O estado de coordenação é server-only. O Mobile não lê
`last_reserved_generation`, `last_applied_generation` nem o path de coordenação.
A observação causal pública usa exclusivamente:

```text
health_summary/current.projection_generation
healthReadinessRefresh → result.convergence
```

Nenhum relógio de cliente participa de qualquer decisão causal.

---

## 20. Fora de escopo

```text
cálculo local de prontidão no Mobile
operationId como marcador de projeção
comparação por relógio de cliente
polling por tempo, sleep, timer
suporte a hard-delete no ciclo de vida
visualização de HealthDocument
UI de ciclo de vida (B4-C)
correção de R-01
mudanças de grant de rollout
```

---

## 21. Itens abertos

| Item | Situação |
|---|---|
| B4-R.C3 — consumidor de convergência no Mobile | pendente |
| B4-R.C4 — regressão de integração | pendente |
| B4-C — UI de ciclo de vida | pendente |
| B4-D/E — visual/plataforma Android | pendente |
| Gate A — Storage real B0 | pendente |
| Gate B — grants de perfil | pendente |
| Gate C — bypass de admin | pendente |
| R-01 — hardening de ISSUE contra morte de processo | **não resolvido** |
| `vaccination_records` sem trigger dedicado (§9) | registrado, anterior a B4-R |
| Rollout/cutover coordenado | pendente |
| Deploy em produção | **não realizado** |

---

## 22. Evidência de teste

**B4-R.C1** (`7af9a3b`): testes de reserva de generation, ordenação total nas
quatro combinações READY/UNAVAILABLE, suíte completa de prontidão, suíte de
backend e build.

**B4-R.C2 + C2.R** (`002009a`):

```text
health_readiness_callable_test ....... 32 / 32
npm run test:health-readiness ........ 5 suítes, all passed
npm test ............................. EXIT 0, 11 suítes, zero FAIL
npm run build ........................ limpo
git diff --check ..................... limpo
```

Provas de concorrência específicas, todas determinísticas e sem `sleep`:

```text
execução UNAVAILABLE + READY concorrente H>G ... confirmed
execução READY + UNAVAILABLE mais novo ........ unavailable
summary sem marcador .......................... not_confirmed
generation observada malformada ............... falha fechada
READY + falha de reread ....................... not_confirmed
UNAVAILABLE + falha de reread ................. unavailable
```

---

## 23. Baselines

```text
B4-R.C1 — generation + ordering guard
7af9a3bff98f622030623efd19450665e3095024

B4-R.C2 — causal refresh response (+ C2.R precedence)
002009a77e6326edd8e4bf3029698c8b267b6741

B4-B2 — contexto anterior de restrição
2856af0965762e54a644d3867b2fafebcc80803b
```
