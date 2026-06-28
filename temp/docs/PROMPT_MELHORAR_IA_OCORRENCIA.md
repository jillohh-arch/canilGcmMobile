# Prompt para o Claude Code — Melhorar a geração de minuta de ocorrência (IA)

> Cole tudo abaixo no Claude Code. É uma tarefa de implementação com escopo restrito.
> Ative o ponytail se quiser: comece a mensagem com "ponytail full:".

---

**Tarefa: melhorar a qualidade da minuta de ocorrência gerada por IA (Gemini), sem refatorar a arquitetura.**

Contexto verificado (relatório `RELATORIO_IA_CANIL.md`): a geração roda 100% server-side em `functions/src/index.ts`, modelo `gemini-2.5-flash` via Generative Language API, região `southamerica-east1`. A callable é `generateOccurrenceAiDraft`. O problema NÃO é a infra (key protegida, fallback, persistência, minuta editável já existem e devem ser preservados). O problema é o PROMPT e o CONTEXTO. A minuta sai genérica, seca, às vezes em português de Portugal, e o modelo tende a "tagarelar".

NÃO mude: o fluxo de chamada, o cliente Flutter (`occurrence_ai_service.dart`), o sheet de revisão, a persistência em `occurrences/{id}/ai_drafts`, o fallback `occurrenceAiFallbackDraft`, nem o contrato de retorno (`draft_text`, `attention_points`, `source_summary`). A minuta deve continuar editável e NÃO selar sozinha.

## Mudança 1 — Reescrever `occurrenceAiPrompt` (`functions/src/index.ts:4904-4923`)

Substitua o prompt atual (que é só uma lista de proibições) por um prompt que ENSINA o formato com exemplos. Mova as regras de comportamento para uma `systemInstruction` separada (ver Mudança 3). O novo prompt do turno `user` deve conter, nesta ordem: (a) a tarefa, (b) a estrutura-alvo, (c) as regras de estilo, (d) os exemplos few-shot, (e) o contexto JSON.

Requisitos de conteúdo do novo prompt:

**Idioma e registro:**
- Português do BRASIL, registro policial-administrativo brasileiro. Proibir explicitamente termos de Portugal: usar "placa" (não "matrícula"), "calçada" (não "passeio"), "freada brusca" (não "travagem"), "fatos" (não "factos"), "equipe" (não "equipa"), "a seguir" (não "de seguida"), "registrados" (não "registados").
- 3ª pessoa, voz institucional. Tempo verbal no pretérito.

**Estrutura-alvo (formato ADAPTATIVO):**
- Ocorrência simples (um fato central, até ~3 atos): TEXTO CORRIDO em parágrafos.
- Ocorrência complexa (vítima + autor + arma + prisão; ou múltiplas partes; ou desdobramentos como menor/Conselho Tutelar; ou prisão em flagrante formal): BLOCOS com subtítulos numerados.
- Espinha dorsal sempre: abertura institucional → desenvolvimento cronológico → [emprego do K9, se houver] → desfecho com encaminhamento/registro.

**Atuação do K9 (regra forte):**
- SEMPRE que o cão tiver atuado, dar destaque com ênfase própria (parágrafo ou bloco dedicado), nomeando o cão e descrevendo a atuação ("com o emprego do cão de faro K9 [nome], que indicou a presença de..."). Esse é o diferencial do app — nunca diluir o K9 no meio de outro parágrafo quando ele foi empregado.

**Regras técnico-jurídicas:**
- A GCM não faz perícia: usar "substância análoga à cocaína/maconha", nunca afirmar a substância como certa.
- Quantidades por extenso + numeral: "86 (oitenta e seis) pinos"; valores: "R$ 337,00 (trezentos e trinta e sete reais)".
- Declarações das partes como declaração, não como fato provado: "alegou", "declarou", "informou" — nunca o sistema endossando.
- Múltiplos envolvidos não-qualificados: usar "Parte 01", "Parte 02", etc., se o relato bruto seguir essa convenção.
- Vocabulário de elevação quando o fato existir (sem forçar): "patrulhamento ostensivo/preventivo", "atitude suspeita", "diligências", "incursão", "logramos êxito em localizar", "voz de prisão em flagrante delito", "procedimentos de polícia judiciária". Para algema, citar Súmula Vinculante nº 11 do STF SOMENTE se houver uso de algema relatado.

**Proibições (críticas):**
- NÃO inventar nada: nem COPOM, nem testemunhas, nem motivação, nem hospital, nem qualquer fato que o condutor não tenha relatado. Usar apenas `relato_bruto_condutor` + linha do tempo + campos resolvidos.
- NÃO usar placeholders tipo `[NOME]`/`[COLCHETE]` no corpo do texto. Dado faltante e relevante → vai para `attention_points`, nunca para o `draft_text`.
- NÃO tagarelar/tutorar: nada de "Aqui está a sugestão", "Principais melhorias", "Precisa de ajuda?", dicas ou perguntas. Só a minuta no `draft_text`.
- NÃO deixar placeholders ruidosos do contexto ("natureza não informada", "viatura não informada") aparecerem no texto. Se um campo está ausente, simplesmente não mencioná-lo, ou levá-lo a `attention_points`.

**Exemplos few-shot:** inclua os 5 exemplos abaixo no prompt, cada um como par (relato bruto → minuta ideal), rotulados por tipo. Eles são o ativo mais importante desta mudança — não resuma, inclua na íntegra.

> NOTA AO CLAUDE CODE: os 5 exemplos completos estão no arquivo `EXEMPLOS_FEWSHOT_OCORRENCIA.md` que acompanha este prompt. Cole-os no template do prompt como few-shot. Use exatamente o texto fornecido (já está em pt-BR correto e revisado).

## Mudança 2 — Enriquecer o contexto (`occurrenceAiNarrativeContext` :4846-4869 e `occurrenceAiResolvedFields` :4758-4804)

Hoje resultado, itens apreendidos e encaminhamento só entram se o condutor escreveu no texto livre. Se já existirem campos estruturados na ocorrência (ex: itens apreendidos, destino/encaminhamento, classificação), inclua-os no JSON de contexto como campos próprios (`itens_apreendidos`, `encaminhamento`, `resultado`). Se NÃO existirem esses campos no modelo de dados, NÃO crie schema novo — apenas deixe um comentário `// ponytail: contexto limitado ao texto livre; enriquecer quando houver campos estruturados de apreensão/encaminhamento` e siga. Não inventar dados.

## Mudança 3 — Ajustar parâmetros de geração (`occurrenceAiGeminiDraft` generationConfig :4970-4981)

- Adicionar `systemInstruction` com as regras de comportamento/identidade (a persona: "assistente de redação institucional da GCM de Limeira, unidade K9"), separando-as do contexto que vai no turno `user`.
- Subir `temperature` de `0.2` para `0.45` (mais fluência sem soltar a rédea contra invenção).
- Adicionar `maxOutputTokens` suficiente para a minuta completa (sugiro 2048).
- Manter `responseMimeType: "application/json"` e o schema de saída atual — o cliente depende dele. (Se a qualidade da prosa ainda sofrer com JSON, avaliar depois; não mexer agora.)

## Mudança 4 — Modelo

Trocar o default de `gemini-2.5-flash` para **`gemini-3.5-flash`** SOMENTE nesta função de ocorrência. O 3.5-flash entrega raciocínio próximo ao Pro com latência/custo de Flash — ideal para uso em campo (GCM espera a minuta na viatura). Manter a env `GEMINI_MODEL` como override. NÃO mexer no modelo da função de nutrição.

Cuidado para NÃO confundir `gemini-3.5-flash` (GA, o correto) com `gemini-3-flash` (outro modelo da família). Use `gemini-3.5-flash`.

Como o 3.x é modelo de raciocínio ("thinking"), adicionar ao generationConfig:
- `thinkingConfig: { thinkingLevel: "medium" }` (default; redação estruturada não exige "high"). Se a latência incomodar em campo, testar `"low"` — qualidade ainda forte.

Deixe comentado `// ponytail: 3.5-flash p/ qualidade+velocidade; GEMINI_MODEL faz override` para fácil ajuste.

NOTA sobre o estilo do prompt: o Gemini 3.x responde melhor a instruções DIRETAS e CONCISAS e pode "over-analisar" prompts muito verbosos. Os exemplos few-shot continuam essenciais e devem ser mantidos na íntegra. Mas, se após o primeiro teste a saída parecer "engessada" ou sobre-explicada, PODE enxugar as regras redundantes da Mudança 1 (manter os exemplos, cortar instruções óbvias) — o modelo é mais capaz sozinho que o 2.5.

## Mudança 5 — Versão do prompt

Incrementar `OCCURRENCE_AI_PROMPT_VERSION` (`:4594`) de `"occurrence-final-report-v2"` para `"occurrence-final-report-v3"`, já que o registro de auditoria grava a versão.

## Verificação obrigatória

- `cd functions && npm run build` (ou `tsc`) deve compilar sem erro.
- NÃO faça deploy.
- Ao final, gere um teste/checagem mínima: uma função local que monta o prompt com um relato bruto de exemplo e imprime o prompt final, para confirmar que os 5 few-shot e o contexto entram corretamente (pode ser um `// demo()` ou um pequeno script). YAGNI: não criar suíte de testes.

Saída esperada: diff focado em `functions/src/index.ts` (+ os exemplos), build verde, e um resumo curto do que mudou e como reverter o modelo para flash.
