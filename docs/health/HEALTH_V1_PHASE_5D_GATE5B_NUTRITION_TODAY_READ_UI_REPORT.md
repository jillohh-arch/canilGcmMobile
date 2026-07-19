# Health v1.0 — Fase 5D — Gate 5B — Nutrição Hoje Read UI

Data: 2026-07-19  
Branch: `feature/health-v1-foundation`  
Base HEAD: `26c6bcd6fc78a2fb6d819e5ff05641e26d8182fc`

## 1. Executive summary

A UI read-only **Nutrição Hoje** foi ligada ao fluxo real
`CoexistenceNutritionReadSourceFactory.forFirestore()` →
`HealthNutritionReadController` → Health v1. O smoke em Pixel físico, com a
sessão já autenticada e o K9 Bono autorizado, leu Firestore de produção e
exibiu registros legados sem `permission-denied`, crash ou mutation.

Durante o smoke foram encontrados e corrigidos dois gaps reais do adapter
legado: `Timestamp` do SDK atravessando a fronteira do domínio puro e
refeições com autoria textual incompleta sendo descartadas. Quantidade
oferecida foi preservada; consumo, acceptance, slot e occurrence não foram
inventados.

**Status: FASE 5D — GATE 5B APROVADO PARA COMMIT.**

## 2. Preflight

| Item | Resultado |
|---|---|
| Branch | `feature/health-v1-foundation` |
| HEAD | `26c6bcd6fc78a2fb6d819e5ff05641e26d8182fc` |
| Tracking | `origin/feature/health-v1-foundation` |
| Divergência | `0/0` |
| Working tree | **não limpa no início** |

O preflight encontrou seis alterações não commitadas já existentes exatamente
na área do Gate 5B. Elas foram preservadas e auditadas; esta execução continuou
sobre esse trabalho, sem reset ou sobrescrita destrutiva.

## 3. Existing UI audit

- Health v1: o slot `nutricao` ainda era placeholder no entry screen.
- Legado: `NutritionFullScreen`, `NutritionViewModel`, `NutritionService` e
  `FeedingRegistrationScreen` permanecem no fluxo antigo.
- A tela legada serviu apenas como referência conceitual/visual; não houve
  redirecionamento nem alteração de comportamento legado.

## 4. Files changed

- `lib/features/health/presentation/nutrition/health_nutrition_today_screen.dart`
- `lib/features/health/presentation/nutrition/health_nutrition_today_formatters.dart`
- `lib/features/health/presentation/screens/health_v1_entry_screen.dart`
- `lib/features/health/data/coexistence/nutrition/firestore_nutrition_legacy_readers.dart`
- `lib/features/health/data/coexistence/nutrition/nutrition_firestore_error.dart`
- testes correspondentes em `test/features/health/...`
- este relatório

`health_nutrition_pending_intent.dart` já estava modificado no preflight apenas
por formatação e não integra a mudança funcional deste Gate.

## 5. Composition root

Produção continua compondo `CoexistenceNutritionReadSourceFactory.forFirestore()`.
Não foi usado fake ou empty source no runtime real.

## 6. Read prime lifecycle

O controller permanece lazy. Abrir o app ou o Resumo não prima Nutrição.
Selecionar a seção `Nutrição` chama `selectDog(dogId)` uma única vez por ciclo
do entry. Teste do entry comprova antes/depois do acesso.

## 7. Dog switch behavior

Após prime, `didUpdateWidget` seleciona o novo `dogId`. O controller entra em
loading, incrementa generation e rejeita respostas antigas. Widget test
completou dog A depois de dog B e confirmou que A nunca voltou à tela.

## 8. UI state model

Estados representados separadamente: `loading`, `data`, `empty`, `degraded`,
`offline` e `error`. Nenhum erro/offline é convertido em empty.

## 9. Loading

Usa `HealthLoadingView` com “Carregando nutrição…”. “Sem plano” não aparece
antes da conclusão da leitura.

## 10. Canonical data

Plano ativo, vigência, meta diária, refeições/dia, slots, horários, metas,
suplementos e logs são apresentados apenas quando presentes. A tela não edita
dados.

## 11. Legacy fallback

O smoke de produção carregou oito registros recentes na lista para Bono. A
viewport inicial mostrou o primeiro registro e parte do segundo; a rolagem até
o fim confirmou todos os oito, marcados como `legado`. Os readers preservam
`amount_grams` como quantidade oferecida e mantêm `consumedGrams == null` e
acceptance unknown.

## 12. Plan presentation

Campos do plano são condicionais. Na evidência real de 2026-07-19 não havia
plano ativo utilizável para Bono; a UI informou isso sem impedir os registros
legados recentes.

## 13. Meal schedule presentation

Slots só existem para plano canônico. Status `pending`, `late` e `completed` é
derivado no cliente. Planos/refeições legados não ganham horário, slot,
`planned_meal_id` ou `meal_occurrence_id` artificiais.

## 14. Today summary

Meta, oferecido, consumido conhecido e contagem de refeições são separados.
Agregação testada: todos os consumos null resultam em desconhecido, nunca zero.

## 15. Supplement regimen presentation

Regimes canônicos do plano e `nutrition_supplements` legados aparecem em
“Suplementos em uso”, somente consulta.

## 16. Supplement administration presentation

`supplement_logs` aparece em “Administrações registradas”. Ausência de log não
é apresentada como ausência de suplemento em uso.

## 17. Degraded

Falha parcial com fonte alternativa utilizável mantém os dados e exibe banner
“Leitura parcial”. Coberto por widget test.

## 18. Offline

Exibe “Sem conexão” e “Tentar novamente”; não exibe empty.

## 19. Error

Exibe erro explícito e retry, sem stack trace. Conflito de integridade mantém
mensagem segura e não escolhe arbitrariamente um plano ativo.

## 20. Empty

Só ocorre quando as fontes utilizáveis estão vazias e não há falha. Não oferece
CTA de write.

## 21. Real authenticated production smoke

Execução real:

- dispositivo: Pixel 10 Pro XL físico, Android 17;
- build: APK debug instalado com `adb install -r`, preservando sessão;
- app/package: `com.example.canil_gcm`;
- sessão real já existente, sem criação de usuário;
- K9: Bono (`4DDeRe7CCjTte6nbUbrC`);
- caminho: app → Firebase Auth existente → FirebaseFirestore plugin → Rules de
  produção → canonical/legacy readers → coexistence → controller → UI;
- resultado: Nutrição abriu e exibiu fallback legado;
- `permission-denied`: zero no log do smoke;
- missing-index do fluxo Nutrição: zero;
- crash/Flutter exception: zero.

Nenhum token bruto foi lido ou registrado.

## 22. G5A-NO-APP-ID-TOKEN closure

**FECHADO.** A sessão autenticada real abriu o K9 autorizado, atravessou Rules
via cliente Firestore e apresentou registros de produção sem
`permission-denied`. A evidência é comportamental e de log; não expõe ID token.

## 23. Zero-write proof

- A tela não importa/invoca `createPlannedMeal`, `createAdhocMeal` ou
  `createSupplement`.
- Nenhum CTA funcional de mutation foi montado.
- Navegação automatizada tocou apenas Saúde e Nutrição.
- Logcat do intervalo não contém callable de mutation.
- Nenhum deploy foi executado.

Assim, o smoke foi exclusivamente read-only. A prova é de caminho/observação;
não foi feita consulta administrativa invasiva nem escrita sentinela.

## 24. Widget tests

Cobertura adicionada/confirmada:

- loading, canonical data, legacy fallback, degraded, offline, error e empty;
- dog switch sem stale snapshot;
- lazy prime no entry;
- consumed null diferente de zero;
- regimen legado diferente de administration;
- plano legado sem slot inventado;
- status canônico de slot derivado;
- acceptance em português;
- payload Firestore legado com Timestamp nested;
- refeição legada com autoria textual incompleta continua visível.

## 25. Visual review

Revisão visual real executada no Pixel físico. A tela preserva navy/petróleo,
cyan, superfícies arredondadas e hierarquia operacional. Não houve overflow,
bloco cinza ou conteúdo cortado na viewport grande. A captura local de trabalho
ficou em `build/health_gate5b_smoke4.png` (artefato não versionado).

## 26. Responsiveness

- smartphone grande: validado visualmente no Pixel físico;
- 360×640 e 430×932: validados por widget test;
- o teste em 360 px com text scale 1.3 encontrou um overflow inicial no header
  do resumo; o `Row` foi tornado `Wrap` e o cenário passou.

Não se alega revisão manual em um segundo aparelho compacto.

## 27. Accessibility

Text scale 1.3 passa em 360/430 px. Labels estão disponíveis na árvore de
semântica do Android; retry é botão; contraste segue tokens Health v1. Não foi
feito redesign global nem auditoria assistiva completa com TalkBack.

## 28. Health regression

`flutter test test/features/health`: **PASS** — 1059 testes, 4 skips
condicionais previstos.

## 29. Full regression

`flutter test`: **PASS** — 1242 testes, 5 skips condicionais previstos.

## 30. Analyze

- análise focada das áreas Gate 5B: **No issues found**;
- novos errors Gate 5B: **0**;
- novos warnings Gate 5B: **0**;
- `flutter analyze` global: 46 achados preexistentes (infos/warnings) fora do
  escopo; nenhum novo achado nos arquivos Gate 5B após a limpeza final.

## 31. Git diff

`git diff --check`: **OK**.  
Nenhum commit ou push foi realizado.

## 32. Findings

| Severidade | Finding | Estado |
|---|---|---|
| MAJOR | `G5B-RECENT-TIME-CONTEXT`: registro antigo aparecia apenas como `Noite · 18:57`, sem contexto de data | **CORRIGIDO** — `Hoje`, `Ontem` ou `dd/MM`, sempre em `America/Sao_Paulo` |
| ACCEPTED LEGACY | Refeições antigas têm apenas autoria textual; adapter técnico permite leitura sem apresentar autoria sintética | aceito e testado |
| MINOR | Consulta antiga `health_events` do módulo History emite missing-index ao iniciar o app | aberto, fora do fluxo Nutrição/Gate 5B |
| MINOR | Analyze global mantém 46 achados preexistentes | aberto, sem regressão Gate 5B |

Não há BLOCKER ou MAJOR aberto para o Gate 5B.

## 33. Deferred Gate 5C

Permanecem fora deste Gate: execução de refeição planejada, ativação de
mutation canônica, smoke real de write controlado, read-after-write e UX de
idempotência. Cutover ad hoc legado não é incluído automaticamente.

## 34. Final readiness

**FASE 5D — GATE 5B NUTRIÇÃO HOJE READ UI IMPLEMENTADA.**

**CANONICAL / LEGACY COEXISTENCE VISÍVEL NA UI.**

**READ CONTROLLER PRIMADO PELO FLUXO REAL.**

**FIREBASE AUTH E FIREBASEFIRESTORE CLIENT REAIS VALIDADOS CONTRA RULES DE
PRODUÇÃO.**

**G5A-NO-APP-ID-TOKEN FECHADO.**

**ZERO CANONICAL MUTATION UI ATIVADA. ZERO PRODUCTION WRITE. ZERO LEGACY
CUTOVER. ZERO DEPLOY.**

**GATE 5B APROVADO PARA COMMIT.**

**NENHUM COMMIT OU PUSH REALIZADO.**

## 35. Auditoria temporal adversarial dos registros recentes

O registro real inicialmente mostrado como `Noite · 18:57 · 250 g` foi
inspecionado diretamente, em modo somente leitura, nas coleções legadas:

- fonte primária: `feeding_events/CzaO6BIlmltzauyasoJN`;
- espelho deduplicado: `feedings/CzaO6BIlmltzauyasoJN`;
- campo bruto: `fed_at`, tipo Firestore `Timestamp`;
- instante UTC: `2026-07-16T21:57:15.041Z`;
- instante em `America/Sao_Paulo`: `2026-07-16 18:57:15`;
- service date da tela: `2026-07-19`.

Conclusão: **causa A**. O parsing e a agregação de hoje estavam corretos; era
um registro de dia anterior — e não de ontem — cuja UI omitia a data. O finding
`G5B-RECENT-TIME-CONTEXT` foi classificado como **MAJOR** e está **CORRIGIDO**.

Os registros recentes agora usam a mesma semântica civil IANA da agregação:

- mesmo service date: `Hoje · HH:mm`;
- service date imediatamente anterior: `Ontem · HH:mm`;
- mais antigo: `dd/MM · HH:mm`.

Testes de fronteira cobrem `23:30 UTC` como hoje local, `00:30 UTC` como dia
anterior local e o registro real antigo. O teste da fonte também prova que a
agregação inclui/exclui os mesmos instantes segundo `America/Sao_Paulo`.

No smoke pós-correção, autenticado no Pixel físico e sem escrita, o item foi
exibido como `16/07 · 18:57 · 250 g oferecidos · legado`. A tela também mostrou
`Sem meta ativa`, a cópia de administração vazia orientada ao produto e permitiu
rolar o oitavo item integralmente acima da navegação inferior. Não houve
`permission-denied`, crash, mutation, deploy ou missing-index do fluxo de
Nutrição; o missing-index conhecido de `health_events` continua isolado no
módulo History.
