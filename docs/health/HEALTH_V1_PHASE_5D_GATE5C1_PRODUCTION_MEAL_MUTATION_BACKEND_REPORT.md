# Health v1.0 — Fase 5D — Gate 5C.1 — Production Meal Mutation Backend Activation

Data: 2026-07-19

## 1. Executive summary

O callable `healthNutritionCreateMealLog` foi ativado em produção de forma
direcionada no projeto `canil-gcm`. A Function está `ACTIVE`, Gen 2, runtime
`nodejs22`, região `southamerica-east1` e aceita os modos backend `planned` e
`adhoc`. Esta ativação disponibiliza a capability server-side, mas não ativa UI,
não constitui cutover operacional ad hoc e não realizou escrita produtiva.

O endpoint real respondeu `HTTP 401 / UNAUTHENTICATED` ao smoke sem token. Os
postchecks administrativos repetiram exatamente o baseline: zero `meal_logs`,
zero `nutrition_operations`, zero audit canônico novo e collections legadas sem
mudança. `healthNutritionCreateSupplementLog` permaneceu ausente.

**Status: CONCLUÍDO, DEPLOYADO, DOCUMENTADO E SINCRONIZADO.**

- Function: `healthNutritionCreateMealLog`;
- region: `southamerica-east1`;
- generation: Gen 2;
- runtime: `nodejs22`;
- deploy: direcionado somente ao callable;
- production write: **ZERO**.

## 2. Preflight

- branch: `feature/health-v1-foundation`;
- HEAD: `166f28f8108243551827faa27f5988ee7f73cc09`;
- tracking: `origin/feature/health-v1-foundation`;
- divergência inicial: `0/0`;
- working tree inicial: limpo;
- commit funcional Gate 5B: `66cb6ed86a58beb6362b89dbee4b9322e8c1302a`.

Nenhum código foi alterado. O único commit desta rodada é o fechamento
documental deste relatório.

## 3. Firebase project verification

- `.firebaserc`: projeto default `canil-gcm`;
- `firebase use`: `canil-gcm`, verificado ao vivo;
- `firebase.json`: Functions source `functions`, com predeploy `npm run build`;
- Firebase CLI: `15.15.0`;
- project explícito em todos os comandos produtivos: `canil-gcm`.

## 4. Production Functions inventory before

Snapshot seguro preservado externamente ao worktree em
`C:\Users\Ji&Fer\.codex\gate5c1-audit\2026-07-19\`, fora do commit:

- total: 60 Functions;
- runtimes observados: `nodejs22`;
- estados observados: `ACTIVE`;
- `healthNutritionCreateMealLog`: ausente;
- `healthNutritionCreateSupplementLog`: ausente;
- fingerprint seguro do inventário:
  `31120cd98a99473c67d5fcb75dead14e95cd536180d9eb9258397969ef29cbe6`.

Tokens, credenciais, secrets e valores de environment não foram persistidos.
A stop condition de Function preexistente não foi acionada.

## 5. Local callable audit

O código vigente confirma:

- export `onCall` na região `southamerica-east1`;
- autenticação obrigatória via `requireHealthCreate`;
- permissão `health.create` e acesso ao K9 antes do engine;
- ator resolvido no servidor e rejeição de campos server-authoritative injetados;
- receipt durável verificado antes da dependência do plano;
- recheck do receipt dentro da transaction;
- idempotency conflict e meal occurrence conflict explícitos;
- MealLog, receipt e audit escritos atomicamente;
- audit determinístico e único na criação real;
- zero escrita em `feeding_events` ou `feedings`;
- modos `planned` e `adhoc` tecnicamente preservados.

O deploy torna a capability backend disponível, mas não constitui cutover
operacional ad hoc. A UI de mutation permanece inativa.

De forma inequívoca: o callable ativo suporta tecnicamente `planned` e `adhoc`.
Neste Gate, nenhuma UI de mutation foi ativada, nenhum fluxo operacional ad hoc
foi migrado, nenhum authenticated success foi executado e nenhum cutover ad hoc
ocorreu. Portanto, capability backend disponível não equivale a cutover
operacional ad hoc. O estado correto é **ad hoc operational UI/cutover ainda não
ativado**, e não “ad hoc backend ausente”.

## 6. Node 22 parity

- `functions/package.json`: `engines.node = 22`;
- Node real usado em build, testes, E2E e deploy: `v22.23.1`;
- npm: `11.9.0`;
- Functions Emulator confirmou `Using node@22 from host`;
- deploy criou `Node.js 22 (2nd Gen)`.

Finding `G2-N22` — MINOR: **FECHADO**.

## 7. Pre-deploy test matrix

Todos os comandos foram executados em `functions/` com Node 22:

| Comando | Resultado |
|---|---|
| `npm run build` | PASS |
| `npm run test:health-nutrition` | PASS |
| `npm run test:health-schedule` | PASS |
| `npm test` | PASS |
| `npm run test:health-nutrition-callable-transport` | PASS |

O E2E oficial terminou com `REAL_CALLABLE_TRANSPORT_E2E: OK` e
`ZERO_PRODUCTION: confirmed`. Permaneceram cobertos planned happy path, replay,
replay durável após mudança do plano, idempotency conflict, meal occurrence
conflict, `fed_at` inválido/futuro, auth/permission/dog access denied, zero
legacy write, um audit na criação e zero audit duplicado no replay.

O CLI emitiu warning de versão não mais recente de `firebase-functions`. É
MINOR e fora do escopo; nenhuma dependência foi alterada para este deploy.

## 8. Production data precheck

Leitura administrativa mínima do K9 já aprovado para smoke, sem expor conteúdo:

| Contagem | Antes |
|---|---:|
| `meal_logs` | 0 |
| `nutrition_operations` | 0 |
| audits planned meal | 0 |
| audits adhoc meal | 0 |
| `feeding_events` | 12 |
| `feedings` | 12 |

## 9. Exact deploy scope

Comando registrado antes e executado uma única vez:

```text
firebase deploy --only functions:healthNutritionCreateMealLog --project canil-gcm --non-interactive
```

Escopo efetivo: somente `healthNutritionCreateMealLog`. Não foram incluídos
supplement callable, outras Functions, Rules, índices, Storage ou Hosting.

## 10. Deploy

- início: `2026-07-19T17:23:54.9739382-03:00`;
- fim do comando: `2026-07-19T17:25:43.2918563-03:00`;
- project: `canil-gcm`;
- function: `healthNutritionCreateMealLog`;
- região: `southamerica-east1`;
- resultado: `Successful create operation` / exit code 0;
- deploy adicional automático: zero.

## 11. Production Functions inventory after

- total: 61 Functions;
- target: `ACTIVE`;
- generation: Gen 2;
- runtime: `nodejs22`;
- region: `southamerica-east1`;
- entry point: `healthNutritionCreateMealLog`;
- timeout: 60 segundos;
- memory: 256 Mi;
- all traffic on latest revision: true;
- update time: `2026-07-19T20:27:38.935787788Z`;
- source generation: `1784492790031554`;
- deployed hash: `c57189b2ff743778b28c574890946ffb87a2e004`.

Removendo somente a nova Function da comparação, o fingerprint das 60
Functions anteriores permaneceu exatamente
`31120cd98a99473c67d5fcb75dead14e95cd536180d9eb9258397969ef29cbe6`.
Portanto, nenhuma outra Function apresentou drift de deployment neste Gate.

## 12. Unauthenticated production smoke

Foi enviado um único payload sintaticamente plausível, com IDs sintéticos e sem
dados sensíveis, sem header de autenticação, ao endpoint real onCall.

Resultado:

```text
HTTP_STATUS=401
ERROR_STATUS=UNAUTHENTICATED
ERROR_MESSAGE=Autenticacao obrigatoria.
```

Isso prova endpoint alcançável, transporte onCall e Auth enforcement ativo. Não
foi executado authenticated success nem read-after-write produtivo.

## 13. Zero-write postcheck

| Contagem | Antes | Depois | Delta |
|---|---:|---:|---:|
| `meal_logs` | 0 | 0 | 0 |
| `nutrition_operations` | 0 | 0 | 0 |
| audits planned meal | 0 | 0 | 0 |
| audits adhoc meal | 0 | 0 | 0 |

Zero MealLog, zero receipt e zero audit inesperado.

## 14. Legacy collections postcheck

| Collection | Antes | Depois | Delta |
|---|---:|---:|---:|
| `feeding_events` | 12 | 12 | 0 |
| `feedings` | 12 | 12 | 0 |

Zero legacy write e zero cutover.

## 15. Supplement callable unchanged

`healthNutritionCreateSupplementLog` estava ausente antes e permaneceu ausente
depois. Não foi incluída no comando de deploy.

## 16. Rollback readiness

Como a Function era inexistente antes do Gate, o rollback previsto é remover
somente `healthNutritionCreateMealLog` em `southamerica-east1`. Nenhum critério
objetivo de rollback ocorreu: região/runtime corretos, zero drift externo, Auth
enforced e zero write no smoke negativo. Rollback não executado.

## 17. Findings

| Classe | Finding | Estado |
|---|---|---|
| MINOR | `G2-N22`: validação anterior usava Node 24 | **FECHADO** — build/test/E2E/deploy com Node 22 |
| ACCEPTED HARDENING | `G2-AC`: App Check enforcement OFF | preservado; não alterado neste Gate |
| MINOR | `firebase-functions` não está na versão mais recente | aberto, fora do escopo; sem impacto observado |
| DEFERRED 5C.2 | authenticated success, UI e read-after-write | corretamente adiado |

BLOCKER aberto: **0**. MAJOR aberto: **0**.

## 18. Deferred Gate 5C.2

Permanecem para o Gate 5C.2: planned meal execution UI, CTA e formulário
operacional, stable operationId, proteção de double-submit, replay/idempotency
UX, primeiro write autenticado real, read-after-write, visibilidade canônica,
validação de receipt/audit e revisão visual.

Continuam fora: ad hoc cutover, supplement administration UI e retirada de
dual-write/compatibilidade legacy.

## 19. Final readiness

**FASE 5D — GATE 5C.1 PRODUCTION MEAL MUTATION BACKEND ACTIVATION CONCLUÍDA.**

**GATE 5C.1 CONCLUÍDO, DEPLOYADO, DOCUMENTADO E SINCRONIZADO.**

**HEALTHNUTRITIONCREATEMEALLOG ATIVA EM PRODUÇÃO.**

**DEPLOY DIRECIONADO VALIDADO. REGION SOUTHAMERICA-EAST1 VALIDADA.**

**GEN 2 / NODE.JS 22 VALIDADO.**

**NODE 22 PARITY VALIDADA. AUTH ENFORCEMENT VALIDADO NO ENDPOINT REAL.**

**ZERO PRODUCTION MEAL WRITE. ZERO RECEIPT. ZERO AUDIT INESPERADO.**

**ZERO LEGACY WRITE. ZERO RULES/INDEXES/STORAGE DEPLOY.**

**PLANNED E ADHOC EXISTEM COMO CAPABILITIES BACKEND DO CALLABLE.**

**ZERO ADHOC OPERATIONAL UI OU CUTOVER ATIVADO.**

**HEALTHNUTRITIONCREATESUPPLEMENTLOG NÃO FOI ATIVADA.**

**G2-N22 FECHADO. G2-AC PERMANECE ACCEPTED HARDENING DEBT.**

**ZERO BLOCKER. ZERO MAJOR.**

**BRANCH LIMPA E SINCRONIZADA.**

**FASE 5D — GATE 5C.2 NÃO INICIADO.**
