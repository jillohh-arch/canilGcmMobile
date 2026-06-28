# Relatório técnico — Funcionalidades de IA do app Canil K9 GCM

Data: 2026-06-27
Escopo: somente leitura. Nenhum arquivo de código foi alterado.
Todas as afirmações têm evidência em `arquivo:linha`. Onde a linha aponta para um
trecho de várias linhas, indico o intervalo.

> Observação metodológica: durante a investigação, uma fonte automática reportou um
> prompt de "nutricionista canino" e uma callable `suggestFeeding` em
> `nutrition_full_screen.dart`. **Isso não existe no código real** e foi descartado.
> A funcionalidade de alimentação real é a callable `generateNutritionAiInsight`
> com o prompt `nutritionAiPrompt`. Tudo abaixo foi conferido lendo o fonte.

---

## Parte A — Infra geral de IA

### 1. Provedor / modelo e onde a chamada é feita

- **Provedor/modelo:** Google **Gemini** via API REST `generativelanguage`
  (Google AI Studio / Generative Language API), **não** Vertex AI, OpenAI ou Anthropic.
- **Modelo padrão:** `gemini-2.5-flash`, sobrescrevível pela env `GEMINI_MODEL`.
- **Onde:** 100% **server-side**, em Cloud Functions (`functions/src/index.ts`),
  região `southamerica-east1`. O app Flutter **não** fala com a IA diretamente —
  ele só chama as Cloud Functions via `httpsCallable`.

Pontos de chamada à IA (endpoint Gemini):

| Função | Endpoint montado | Modelo | Evidência |
|---|---|---|---|
| Ocorrência (minuta) | `https://generativelanguage.googleapis.com/v1beta/${modelPath}:generateContent?key=...` | `gemini-2.5-flash` (env `GEMINI_MODEL`) | `functions/src/index.ts:4964-4982` |
| Nutrição (insight) | mesmo endpoint | `gemini-2.5-flash` (env `GEMINI_MODEL`) | `functions/src/index.ts:5538-5556` |

Callables expostas (entrada do app):

- `generateOccurrenceAiDraft` — `functions/src/index.ts:5002`
- `generateNutritionAiInsight` — `functions/src/index.ts:5579`

Pontos de chamada no Flutter (cliente → Cloud Function):

- Ocorrência: `lib/features/occurrences/data/occurrence_ai_service.dart:56`
  (`_functions.httpsCallable('generateOccurrenceAiDraft')`)
- Nutrição: `lib/features/nutrition/data/nutrition_ai_service.dart:91`
  (`_functions.httpsCallable('generateNutritionAiInsight')`)
- Região fixada no cliente: `southamerica-east1`
  (`occurrence_ai_service.dart:48`, `nutrition_ai_service.dart:83`)

(a) Como funciona hoje: o app envia dados mínimos (IDs + relato bruto) para a Cloud
Function; a function carrega o restante do Firestore, monta o prompt e chama o Gemini.
(b) Evidência: tabelas acima.
(c) Problema: nenhum no desenho de localização da chamada — manter a key fora do
cliente é correto.

### 2. Gerenciamento da API key / credencial

- Mecanismo: **variável de ambiente**, lida em runtime via
  `occurrenceAiEnv(name)` → `process.env[name]`.
  Evidência: `functions/src/index.ts:4634-4637`.
- Nomes lidos (ordem de precedência): `GEMINI_API_KEY`, com fallback
  `GOOGLE_GENAI_API_KEY`.
  Evidência (ocorrência): `functions/src/index.ts:4960`;
  (nutrição): `functions/src/index.ts:5535`.
- Não há chave hardcoded nem uso de Secret Manager explícito no código; depende do
  ambiente em que a function roda definir essas envs. (Valor da chave **não** impresso
  aqui por segurança.)

(c) Problema/observação: a key vai concatenada na **URL** como query param
(`?key=${encodeURIComponent(apiKey)}`, `index.ts:4966` e `5540`). Funciona, mas
expõe a chave em logs de URL caso algum log de rede capture o endpoint. Não é
vazamento no código, mas é um ponto de atenção operacional.

### 3. Parâmetros de geração (valores atuais)

Idênticos nas duas chamadas:

| Parâmetro | Valor atual | Evidência |
|---|---|---|
| `model` | `gemini-2.5-flash` (default; env `GEMINI_MODEL`) | `index.ts:4964` / `5538` |
| `temperature` | `0.2` | `index.ts:4978` / `5552` |
| `responseMimeType` | `application/json` | `index.ts:4979` / `5553` |
| `max tokens` (`maxOutputTokens`) | **não configurado** | ausente em `4977-4980` / `5551-5554` |
| `top_p` | **não configurado** | idem |
| `top_k` | **não configurado** | idem |
| `system instruction` | **não usada** | só há um turno `role:"user"` — `index.ts:4971-4976` / `5545-5550` |

(c) Problema: não há `maxOutputTokens`, `topP`/`topK`, nem `systemInstruction`. Toda a
instrução vai dentro de um único turno de usuário junto com o contexto JSON. Para
geração de texto institucional, isso reduz o controle de tom/tamanho.

---

## Funcionalidade 1 — "Sugestão de alimentação" (Insight de nutrição)

> Nota importante de escopo: o que existe hoje **não** é uma "sugestão de quanto
> alimentar conforme as atividades do dia". É uma **análise operacional de nutrição
> por período** (7/30/60 dias), produzindo recomendação textual estruturada. Não há
> cálculo diário de ração em função da atividade do dia específico.

### 4. Disparo, dados de contexto e prompt

**Disparo (UI):**
- Tela: `lib/features/health/presentation/screens/dog_health_prontuario_screen.dart`,
  aba `_HealthNutritionTab`.
- Botão "Gerar" no card `_NutritionAiCard` chama `onGenerate` → `_generateInsight()`:
  `dog_health_prontuario_screen.dart:1361-1366` (wiring) e `:1159-1168` (método).
- Período selecionável: `[7, 30, 60]` dias, default `30`
  (`_periodDays = 30` em `:1156`; chips em `:1448`).
- Serviço: `NutritionAiService.generateInsight({dogId, periodDays})`
  → callable `generateNutritionAiInsight`: `nutrition_ai_service.dart:87-102` (call em `:91`).

**Dados que entram no contexto (carregados pela Cloud Function):**
Função `generateNutritionAiInsight` carrega, para `dogId` e janela de `periodDays`:
- Prescrição nutricional ativa — `loadActiveNutritionPrescription` (`index.ts:5217-5237`)
- Refeições (até 120) — `loadNutritionFeedings` (`index.ts:5239-5265`)
- Suplementos (até 30) — `loadNutritionSupplements` (`index.ts:5267-5278`)
- Sessões de treino (até 80) — `loadTrainingSessionsForNutrition` (`index.ts:5310-5346`)
- Pesagens (até 40) — `loadWeightRecords` (`index.ts:5280-5293`)
- Eventos de saúde (até 40) — `loadHealthEvents` (`index.ts:5295-5308`)
- Montagem do contexto: `index.ts:5592-5619`.

Dados do cão incluídos no prompt: `id`, `name`, `breed`/`raca`, `sex`, `weight`,
`idealWeightMin`, `idealWeightMax` (`index.ts:5468-5476`).
**Não inclui idade do cão** (`age`) nem peso atual normalizado fora desses campos.
A "intensidade da atividade do dia" entra apenas indiretamente, como a **lista de
sessões de treino do período** (não há classificação de intensidade).

Janela: `clampPeriodDays` força 7–90 dias, default 30 (`index.ts:5113-5117`);
`NUTRITION_AI_MAX_PERIOD_DAYS = 90` (`index.ts:5083`).

**Prompt atual — `nutritionAiPrompt` (íntegra), `functions/src/index.ts:5452-5485`:**

```
Voce auxilia uma unidade K9 com uma analise operacional de nutricao.
Regras obrigatorias:
- Nao faca diagnostico veterinario.
- Nao prescreva medicamento, suplemento ou quantidade como ordem definitiva.
- Use somente os dados fornecidos.
- Escreva em portugues claro para condutor/gestor.
- Quando faltar dado, aponte como lacuna.
- Sugestoes de alimento/suplemento devem ser orientacoes para avaliacao tecnica, nunca prescricao.

Retorne somente JSON valido no formato:
{"summary":"...","recommendation_level":"manter_monitorando|avaliar_aumento|avaliar_reducao|atenção_clinica","food_adjustment":"...","supplement_notes":["..."],"hydration_notes":["..."],"operational_factors":["..."],"data_gaps":["..."],"veterinary_warnings":["..."],"next_actions":["..."],"source_summary":{"...":"..."}}

Contexto: ${JSON.stringify({
  source: nutritionSourceSummary(context),
  dog: {
    id: context.dogId,
    name: dogDisplayName(context.dogId, context.dog),
    breed: context.dog.breed ?? context.dog.raca ?? "",
    sex: context.dog.sex ?? "",
    weight: context.dog.weight ?? null,
    idealWeightMin: context.dog.idealWeightMin ?? context.dog.ideal_weight_min ?? null,
    idealWeightMax: context.dog.idealWeightMax ?? context.dog.ideal_weight_max ?? null,
  },
  prescription: context.prescription,
  feedings: context.feedings,
  supplements: context.supplements,
  trainings: context.trainings,
  weight_records: context.weightRecords,
  health_events: context.healthEvents,
})}
```

O `source` injetado (`nutritionSourceSummary`, `index.ts:5348-5381`) traz métricas
derivadas: média consumida/dia, contagem de refeições divergentes (>10%), nº de treinos,
último peso, faixa ideal, etc.

(c) Problemas:
- Prompt sem **idade** do cão e sem distinção de **intensidade** de treino (só lista bruta).
- Texto do prompt **sem acentuação** ("Voce", "analise", "nutricao") — inconsistência
  estilística que pode contaminar o tom da resposta.
- `recommendation_level` mistura valores sem acento com um acentuado (`atenção_clinica`),
  enquanto o fallback usa só os 3 sem acento (`index.ts:5397/5402/5405/5411/5414`) —
  risco de valor inconsistente vindo da IA.

### 5. Recepção, exibição, validação e tratamento de erro

- Parsing server-side: `nutritionInsightFromResponse` (`index.ts:5494-5532`). Extrai o
  primeiro bloco `{...}` do texto e exige `summary` **e** `food_adjustment` não-vazios,
  senão descarta o candidato (`index.ts:5512-5514`).
- Fallback determinístico local quando a IA falha/ausente:
  `nutritionFallbackInsight` (`index.ts:5383-5450`), modelo `local_nutrition_analysis_v1`
  (`NUTRITION_AI_FALLBACK_MODEL`, `index.ts:5082`). O `try/catch` em `:5621-5629` garante
  que sempre há um insight.
- Persistência: gravado em subcoleção `dogs/{id}/nutrition_ai_insights`
  (`index.ts:5631-5649`) + entrada de auditoria `nutrition_ai_insight_generated`
  (`index.ts:5650-5655`). Retorno ao app: `index.ts:5657-5673`.
- Cliente: `NutritionAiInsight.fromMap` (`nutrition_ai_service.dart:38-61`); valida
  vazio e lança `StateError` se `summary` e `foodAdjustment` ambos vazios
  (`nutrition_ai_service.dart:97-100`).
- Exibição: **somente leitura**, em modal `_showNutritionInsightSheet`
  (`dog_health_prontuario_screen.dart:1183`). Mostra período + se usou IA ou análise
  local (`:1241`). **Não é editável** pelo usuário.

(c) Problema: como é exibição estruturada e não-editável, qualquer texto fraco vai
direto para a tela sem possibilidade de correção manual.

---

## Funcionalidade 2 — Descrição da ocorrência (minuta institucional)

### 6. Função/serviço e ponto no fluxo de finalização

- Backend: `generateOccurrenceAiDraft` (`functions/src/index.ts:5002`).
- Serviço Flutter: `OccurrenceAiService.generateInstitutionalDraft`
  (`occurrence_ai_service.dart:52-66`, call em `:56`).
- Ponto no fluxo: tela de finalização
  `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart`,
  método `_generateAiDraft()` (`:160-194`), disparado por botão de "IA assistiva".
- **Não é automático** ao finalizar. O usuário precisa **acionar manualmente** e já
  ter um relato bruto digitado/ditado; se vazio, aborta com aviso
  (`finalize_occurrence_screen.dart:161-168`).
- Pré-condição no backend: só gera se `status ∈ {in_progress, finalizing}`
  (`index.ts:5013-5016`) e se o chamador é participante (`index.ts:5017-5019`).
- A finalização de fato (selo) é outra callable, `sealOccurrenceV4`
  (`index.ts:5676`; cliente em `occurrence_transition_service.dart:50`), que recebe o
  `final_report` já revisado. A IA **não** sela.

### 7. Dados da ocorrência no contexto + prompt íntegro

Contexto carregado em `generateOccurrenceAiDraft`:
- `raw_report` (texto bruto do condutor, vindo do app) — `index.ts:5006`.
- Eventos da ocorrência, ordenados por `timestamp`, **até 40**
  (`OCCURRENCE_AI_MAX_EVENTS = 40`, `index.ts:4596`; query `index.ts:5021-5028`).
- Campos resolvidos via `occurrenceAiResolvedFields` (`index.ts:4758-4804`):
  RA e nome operacional do condutor (cruzando `users`), nome do cão (cruzando `dogs`
  e o `team`), rótulo da viatura, endereço do local, data/hora de início formatada
  em pt-BR.

O JSON de contexto efetivamente enviado é `occurrenceAiNarrativeContext`
(`index.ts:4846-4869`):

```
{
  natureza: occurrence.type_name | "natureza não informada",
  data_hora_inicio: context.startedAtDisplay,
  local: context.locationAddress | "local não informado",
  viatura_apoio: context.vehicleLabel | "viatura não informada",
  condutor: { nome_operacional: context.handlerName, ra: context.handlerRa },
  cao_servico: context.dogName | "cão de serviço não informado",
  relato_bruto_condutor: context.rawReport,
  linha_do_tempo: [
    { ordem, horario, data_hora, evento, descricao, local, midias /* nº de fotos */ }
  ]
}
```

Campos **não** enviados ao texto por regra: IDs técnicos, hashes, coleções, ISO cru,
lat/long (proibidos explicitamente no prompt). Itens apreendidos / resultado **não**
têm campo dedicado no contexto — só aparecem se o condutor os escreveu no
`relato_bruto_condutor` ou nas `descricao` dos eventos.

**Prompt atual — `occurrenceAiPrompt` (íntegra), `functions/src/index.ts:4904-4923`:**

```
Você auxilia a GCM na redação institucional de uma ocorrência K9.
Regras obrigatorias:
- Não invente fatos, qualificações criminais, nomes, quantidades ou encaminhamentos.
- Use apenas o relato bruto e a linha do tempo fornecidos.
- Organize em linguagem objetiva, cronológica e institucional, como relato operacional da GCM.
- Use data e horário no formato brasileiro já fornecido no contexto.
- Use o nome operacional do GCM e o nome do K9 exatamente como fornecidos.
- Não cite IDs técnicos, caminhos de banco, hashes, nomes de coleção, ISO date cru, latitude ou longitude no texto final.
- Não transforme a linha do tempo em lista técnica longa; sintetize os principais atos em parágrafos claros.
- Preserve incertezas e lacunas como pontos de atenção.
- Não substitua a revisão humana: o condutor precisa revisar antes do fechamento.

Retorne somente JSON válido no formato:
{"draft_text":"...","attention_points":["..."],"source_summary":{"...":"..."}}

Contexto narrativo: ${JSON.stringify(occurrenceAiNarrativeContext(context))}
```

### 8. Tratamento da resposta, onde é salva/exibida, editabilidade

- Parsing server-side: `geminiDraftFromResponse` (`index.ts:4925-4957`). Extrai o
  primeiro bloco `{...}` e exige `draft_text` não-vazio; `attention_points` e
  `source_summary` opcionais.
- Fallback local quando a IA falha/ausente: `occurrenceAiFallbackDraft`
  (`index.ts:4871-4902`), modelo `local_occurrence_template_v1`
  (`OCCURRENCE_AI_FALLBACK_MODEL`, `index.ts:4595`). `try/catch` em `:5040-5047`.
- Persistência: subcoleção `occurrences/{id}/ai_drafts` com `raw_report`, hash do
  relato, `draft_text`, pontos de atenção, `prompt_version`, modelo, autor
  (`index.ts:5049-5062`) + auditoria `ai_draft_generated` (`index.ts:5063-5068`).
  `OCCURRENCE_AI_PROMPT_VERSION = "occurrence-final-report-v2"` (`index.ts:4594`).
- Retorno ao app: `index.ts:5070-5078`.
- Cliente: `OccurrenceAiDraft.fromMap` (`occurrence_ai_service.dart:22-41`); lança
  `StateError` se `draftText` vazio (`:62-64`).
- Exibição: bottom sheet de revisão `_showAiDraftReviewSheet`
  (`finalize_occurrence_screen.dart:196`), com os `attentionPoints` (`:268-269`) e o
  texto em um widget `Text` **read-only** dentro do sheet (`:282-283`).
- **Editabilidade:** se o usuário aceitar ("usar"), o texto é jogado em
  `_reportController.text` (`finalize_occurrence_screen.dart:181`), que é o **campo de
  relato editável** da tela. Ou seja: a minuta **é editável** depois de inserida — o
  usuário pode ajustar livremente antes de selar via `sealOccurrenceV4`
  (`final_report` enviado a partir do controller, `:874`). Não vai direto e sozinha
  para o selo.

---

## 9. Diagnóstico de qualidade — por que a descrição sai "sofrível"

Hipóteses ordenadas por impacto provável, cada uma ligada ao código:

1. **Garbage-in / contexto pobre + proibição forte de inventar.**
   O prompt proíbe terminantemente inferir fatos (`index.ts:4908-4909`,
   "Use apenas o relato bruto e a linha do tempo"). Se o condutor digita um relato
   bruto curto/pobre (entrada em `_reportController`, `finalize_occurrence_screen.dart:161`),
   o modelo tem pouco material e o resultado fica raso. O contexto também não tem campos
   estruturados de **resultado/itens apreendidos/encaminhamento** — só o que estiver no
   texto livre ou nas `descricao` de eventos (`occurrenceAiNarrativeContext`, `index.ts:4846-4869`).

2. **Ausência de exemplos (few-shot) e de estrutura-alvo.**
   O prompt diz "linguagem objetiva, cronológica e institucional" (`index.ts:4910`)
   mas **não** dá nenhum exemplo de minuta boa nem seções esperadas (introdução,
   desenvolvimento cronológico, emprego do cão, desfecho). Sem âncora de formato, o
   `gemini-2.5-flash` produz prosa genérica. Evidência: prompt inteiro `index.ts:4904-4923`.

3. **Sem instrução de tamanho/tom/tempo verbal.**
   Não há diretriz de extensão mínima, registro (3ª pessoa, voz passiva institucional),
   nem tempo verbal. O único limite indireto é "não vire lista técnica longa"
   (`index.ts:4914`), que empurra para textos curtos. Evidência: `index.ts:4904-4923`.

4. **`responseMimeType: "application/json"` força JSON e tende a achatar a prosa.**
   Pedir JSON estrito (`index.ts:4979`) faz o modelo priorizar conformidade estrutural;
   somado a um modelo "flash", a qualidade narrativa do `draft_text` cai.

5. **Modelo possivelmente subdimensionado.**
   `gemini-2.5-flash` (`index.ts:4964`) é otimizado para custo/latência. Para redação
   institucional, um modelo "pro" tende a entregar texto mais coeso. É sobrescrevível
   por `GEMINI_MODEL`, mas o default é flash.

6. **Sem `maxOutputTokens` / sem `systemInstruction`.**
   Não há teto explícito nem separação system/user (`index.ts:4977-4980`,
   turno único `4971-4976`). Sem `systemInstruction`, regras e contexto competem no
   mesmo turno; sem controle de tokens, não há garantia de desenvolvimento adequado.

7. **Temperatura 0.2 — baixa para texto narrativo.**
   `temperature: 0.2` (`index.ts:4978`) favorece consistência factual (bom para o
   risco de invenção), mas reduz fluência/variedade da redação. É um trade-off que
   contribui para o tom "seco/repetitivo".

8. **Truncamento do contexto de eventos.**
   Até 40 eventos (`OCCURRENCE_AI_MAX_EVENTS`, `index.ts:4596`; aplicado em
   `index.ts:5024`). Em ocorrências longas, eventos além de 40 ficam de fora da
   linha do tempo — perda de contexto. Menos crítico que os itens 1–3.

9. **Placeholders ruidosos quando faltam dados.**
   Campos ausentes viram strings como "natureza não informada", "local não informado",
   "viatura não informada", "cão de serviço não informado"
   (`index.ts:4849-4857`, `4790`, `4796-4802`). Esses literais entram no contexto e
   podem aparecer no texto, deixando a minuta com cara de formulário incompleto.

(Para o insight de nutrição, embora não seja o foco do problema relatado, valem
problemas análogos: prompt sem acentuação `index.ts:5452-5461`, ausência de idade do
cão no contexto `index.ts:5468-5476`, e `recommendation_level` com enum inconsistente.)

---

## 10. Arquivos e funções a tocar para melhorar cada funcionalidade

### Descrição da ocorrência (prioridade — é o problema relatado)
- `functions/src/index.ts`
  - `occurrenceAiPrompt` (`:4904-4923`) — adicionar exemplos few-shot, estrutura-alvo,
    instrução de tom/tamanho/tempo verbal, e mover regras para `systemInstruction`.
  - `occurrenceAiNarrativeContext` (`:4846-4869`) e `occurrenceAiResolvedFields`
    (`:4758-4804`) — enriquecer contexto (resultado, itens apreendidos, encaminhamentos)
    de forma estruturada, em vez de depender só do texto livre.
  - `occurrenceAiGeminiDraft` `generationConfig` (`:4970-4981`) — avaliar
    `systemInstruction`, `maxOutputTokens`, ajustar `temperature` (~0.4–0.6) e
    revisar o uso de `responseMimeType` JSON; seleção de modelo (`:4964`) —
    considerar `gemini-2.5-pro` para esta tarefa.
  - `OCCURRENCE_AI_MAX_EVENTS` (`:4596`) — avaliar elevar o teto / sumarizar eventos
    excedentes.
- Cliente (apenas se mudar o contrato): `occurrence_ai_service.dart:52-66` e o sheet
  de revisão em `finalize_occurrence_screen.dart:196-300` (já permite edição posterior
  via `:181`, então provavelmente sem mudança).

### Insight de nutrição
- `functions/src/index.ts`
  - `nutritionAiPrompt` (`:5452-5485`) — corrigir acentuação, incluir **idade** do cão,
    padronizar enum de `recommendation_level`, e (se desejado) reorientar para
    sugestão diária por carga de atividade.
  - Contexto do cão no prompt (`:5468-5476`) — adicionar idade e demais campos relevantes.
  - `generationConfig` (`:5544-5555`) — mesmos ajustes de tokens/temperatura.
  - `clampPeriodDays` / `NUTRITION_AI_MAX_PERIOD_DAYS` (`:5113-5117`, `:5083`) se a janela
    de análise precisar mudar.
- Cliente: `nutrition_ai_service.dart:87-102` e exibição
  `dog_health_prontuario_screen.dart:1159-1366` (hoje read-only; avaliar permitir
  edição/ação a partir do insight).
