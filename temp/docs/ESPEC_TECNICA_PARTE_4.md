# ESPECIFICAÇÃO TÉCNICA — PARTE 4
# Formação de Detecção · Protocolo Ragonha

> Especificação do fluxo de **formação** do cão de detecção (Protocolo Ragonha).
>
> **Sobre "real, não mockado":** isso vale para a *implementação no app*. As telas em Flutter devem **ler e gravar dados reais do Firestore** — nada de valores fixos/hardcoded ou de exemplo dentro da tela (como a lista de comandos hardcoded que a auditoria encontrou em Obediência). Já os arquivos `.html` citados aqui são **protótipos de design (mockups)**: servem só de referência visual e **não viram código**. As telas vão existir — mas alimentadas pelo banco, não com dados chumbados.
>
> Tudo persiste no Firestore com trilha de auditoria e soft delete.
>
> **Protótipos de referência** em `temp/mockups/`:
> - `formacao_deteccao_seletor_fase.html` — seletor de fase
> - `formacao_deteccao_aovivo_caixas.html` — sessão ao vivo (3v · odor variável)
> - `formacao_deteccao_aovivo_2b_fixo.html` — sessão modo fixo + bola
> - `formacao_deteccao_aovivo_4c_quadrado.html` — fase 4c (quadrado)
> - `formacao_deteccao_fase_concluida.html` — mensagem de conclusão de fase

---

## 4.0 — Escopo e relação com a Parte 3

Esta parte **detalha e substitui** o que a Parte 3 trazia sobre a *formação* de detecção (o protocolo e suas fases). Permanecem válidas na Parte 3:
- **3.11 Manutenção de Detecção** — já refinada (mockup `tela_3_11_manutencao_deteccao.html`, com condições ambientais e mídias).
- **3.12 Triagem (Fase 0)** — porta de entrada; decide se o cão segue para a formação.

A **formação** (Fases 1 a Final) é o que esta Parte 4 especifica em detalhe.

Detecção tem dois mundos distintos, **não confundir**:
- **Formação** (esta parte) — o cão *subindo* pelo protocolo. Regras duras, contador de consecutivas, avanço de fase, registro repetição-a-repetição.
- **Manutenção** (3.11) — o cão já *operacional*, mantendo o faro. Sem fases; foco em frescor, cenários e condições ambientais.

**Filosofia (filtro central do app):** se um gestor questionar a confiabilidade do cão seis meses depois, o registro da formação deve **defender o binômio** — mostrando *como* o cão chegou lá (a série de acertos, a posição do odor em cada repetição, onde errou), não só que chegou.

---

## 4.1 — Glossário (termos do ofício)

Para quem implementa entender o domínio:

- **Binômio** — a dupla condutor + cão.
- **Linha** — a especialidade de detecção: Drogas, Armas ou Cadáver.
- **Indicação passiva** — o cão **senta** ao localizar o odor (resposta-padrão deste canil). Não é ativa (arranhar/latir).
- **Drive de presa** — o instinto de caça pela bola; é o **motor de aprendizado** nas fases iniciais.
- **Caixa de faro / caixa-alvo** — caixa quadrada (~30 cm) com buraco no topo. A **caixa-alvo** é a que contém o odor naquela repetição.
- **Nose-MP** — pseudo-odor de **treino** (substância de treinamento), usada antes de migrar para o odor real.
- **Scentlogix** — marca de odores de treinamento (material alternativo).
- **Repetição (rep)** — uma busca individual: o cão procura e indica uma caixa.
- **Consecutivas** — acertos **seguidos sem nenhum erro** no meio. Um erro zera a contagem.
- **Fase "b" / "v" / "c"** — variações dentro de um nível de caixas: **b** = odor fixo na última caixa; **v** = odor varia de posição; **c** = caixas em quadrado (busca circular).

---

## 4.2 — O método físico (contexto do instrutor)

- **4 caixas de faro**, ~30 cm, quadradas, com um buraco no topo (cabe bola de tênis + focinho do cão).
- **Caixa-alvo** = a que contém o odor. Frasco com ~20 g de **Nose-MP** (odor de treino) ou, em estágios avançados, o **odor real** (maconha, cocaína, etc).
- **Indicação passiva = sentar.** O cão chega na caixa-alvo e senta sozinho.
- **Bola (drive de presa)** é o motor no início: jogada na caixa, o cão fareja pelo buraco, sente o odor junto, senta, e é pago com a bola. A bola **sai de dentro da caixa-alvo na fase 3v** — daí em diante o cão fareja o odor puro, não a bola.

---

## 4.3 — As fases do protocolo

Eixo da progressão: **número de caixas (1 → 4)**. Dentro de cada nível, variações **"b"** (odor fixo na última caixa, ensina o conceito) e **"v"** (odor varia de posição, generaliza). A regra de avanço é **N acertos consecutivos sem erro**, e **um único erro zera o contador**.

| Fase | Caixas | Posição do odor | Bola | O que ensina | Critério de avanço |
|------|--------|-----------------|------|--------------|--------------------|
| **1b** | 1 | única (alvo) | sim | Resposta (indicação passiva) | 3 consecutivas |
| **2b** | 2 | fixa na última | sim | Processo de busca | 3 consecutivas |
| **2v** | 2 | variável (1ª ou 2ª) | sim | Generaliza a busca | 3 consecutivas |
| **3b** | 3 | fixa na última | sim | Independência (instrutor se afasta) | 3 consecutivas |
| **3v** | 3 | variável (1ª/2ª/3ª) | **não (sai a bola)** | **Independência total — ponto de virada** | **10 consecutivas** |
| **4b** | 4 | fixa na última | não | Distância + comando verbal "Busca" | 3 consecutivas |
| **4v** | 4 | variável (qualquer) | não | Generaliza em 4 caixas | 3 consecutivas |
| **4c** | 4 (quadrado) | variável | não | Busca circular (horário + anti-horário) | 3 horário + 3 anti-horário |
| **Final** | — | ambientes reais | não | Cenários reais, dificuldade progressiva | progressivo (sem contador fixo) |

**Critérios confirmados pelo instrutor:** 3 consecutivas em todas as fases, exceto a **3v (10 consecutivas)**.

### Descrição fase a fase
- **1b — Resposta.** Uma caixa-alvo, com bola dentro. O cão fareja pelo buraco, sente bola + odor, aprende a sentar (indicação passiva) e é pago com a bola. Avança quando chega e senta **sozinho** 3× seguidas.
- **2b — Processo de busca.** Duas caixas: 1ª vazia, 2ª (última) é a alvo. Odor sempre na última. O cão é levado a cheirar em ordem (1ª, depois 2ª) e sentar na alvo. Ensina a *sequência* de busca.
- **2v — Generalização.** Duas caixas, odor alternando entre 1ª e 2ª. O cão não pode decorar posição — tem que farejar de fato.
- **3b — Independência (afastamento).** Três caixas, odor fixo na última, ainda com bola. O instrutor começa a **se afastar** durante a indicação, reduzindo a dependência de auxílio.
- **3v — Independência total (ponto de virada).** Três caixas, odor variável, **sem bola**. O cão caça o odor puro, sem reforço dentro da caixa e sem decorar posição. É o salto de confiabilidade — por isso exige **10 consecutivas**.
- **4b — Distância + comando.** Quatro caixas, odor fixo na última. O instrutor manda o cão a uma **distância** e cria o **comando verbal "Busca"**.
- **4v — Generalização em 4 caixas.** Quatro caixas, odor variável em qualquer posição.
- **4c — Busca circular.** Quatro caixas em **quadrado**, instrutor no centro. Ensina a varredura em sentido **horário** (3 consecutivas) e depois **anti-horário** (3 consecutivas).
- **Final — Ambientes reais.** Sem caixas: veículos, salas, bagagens, áreas abertas. Dificuldade progressiva. (Tela ainda não especificada — ver 4.11.)

### Regras transversais
- **1 erro zera** o contador de consecutivas em qualquer fase.
- **Bola:** presente em 1b/2b/2v/3b; **sai na 3v** (a partir daí o cão caça só o odor).
- **3v é o salto** (10 consecutivas) — onde o cão prova confiabilidade sem decorar posição e sem bola.

---

## 4.4 — Linhas e material de odor

- **Linhas:** Drogas, Armas, Cadáver. São **independentes** — o cão progride separadamente em cada. Drogas e Armas podem ser **treinadas combinadas** numa mesma sessão; Cadáver é linha à parte.
- **Material de odor:** Nose-MP (treino) → odor real → Scentlogix. Registrado por sessão.
- O progresso de fase é **por linha**: o cão pode estar em 4b em Drogas e não ter iniciado Armas.

---

## 4.5 — Estados e ciclo de vida

### Estado da linha (`detection_lines/{lineId}.status`)
```
not_started → triagem → in_formation → operational
```
- **not_started** — o cão ainda não começou essa linha.
- **triagem** — passou (ou está) na Triagem Fase 0 (3.12). Aprovação ("continuar formação") move para `in_formation` iniciando na fase **1b**.
- **in_formation** — subindo as fases (1b … 4c / Final). `current_phase` indica onde está.
- **operational** — concluiu a formação (passou da fase Final). A partir daqui o cão entra no fluxo de **Manutenção (3.11)**; não há mais fases de formação.

### Estado da sessão de formação (`training_sessions/{id}.status`)
- **in_progress** — sessão ativa, registrando repetições. Deve ser **auto-salva** (ver 4.9).
- **completed_by_criterion** — o contador atingiu o critério; a fase foi concluída e o cão avançou.
- **ended_without_criterion** — o instrutor encerrou antes de atingir o critério. A sessão é **salva normalmente** (registro de treino válido), mas a fase **não avança**.
- **deleted** — soft delete (mantém o documento com `deleted_at`).

---

## 4.6 — Regras de negócio

**Contador de consecutivas.** É **por sessão — zera ao iniciar cada nova sessão** (não acumula de um dia para o outro). Durante a sessão, cada repetição é acerto ou erro: acerto incrementa, **erro zera**. O critério da fase precisa ser atingido **dentro de uma única sessão**.

**Conclusão de fase ao atingir o critério.** No instante em que o contador bate o critério (3 consecutivas — ou 10 na 3v), o app **exibe a mensagem de conclusão de fase** (4.10.4) e **encerra a fase ali mesmo**: a sessão é finalizada com `status = completed_by_criterion`, `current_phase` avança para a próxima fase do protocolo e a fase vencida entra em `phases_completed`. Não há repetições adicionais após atingir. Como o critério é objetivo (X acertos sem erro), a conclusão é **automática**; o reconhecimento da mensagem fica na trilha de auditoria.

**Encerrar sem atingir o critério.** O instrutor pode encerrar a sessão a qualquer momento. A sessão é gravada com `status = ended_without_criterion`, aparece no histórico como treino realizado, mas **a fase não avança** e o progresso de consecutivas **não é guardado** para a próxima sessão (zera). É um registro legítimo de trabalho — defende o binômio mesmo sem progressão.

**Avanço de fase.** Sempre da fase atual para a **próxima na ordem** (1b→2b→2v→3b→3v→4b→4v→4c→Final). Concluir a **4c** (ambas as etapas, horário e anti-horário) libera a **Final**. Concluir a **Final** move a linha para `operational`.

**Reabrir fase concluída.** O instrutor pode iniciar uma sessão numa fase já concluída (revisão/reforço) sem perder o progresso geral. A sessão de revisão é registrada, mas não altera `current_phase`.

**Início de nova formação.** Ao iniciar, o app apresenta o **seletor de fase** (4.10.1) lendo o progresso **real** do cão na linha: fases concluídas marcadas, fase atual selecionável, fases seguintes bloqueadas.

**Triagem → formação.** Um cão só entra em formação após a Triagem (3.12) com decisão "continuar formação". Nesse momento a linha vai para `in_formation` com `current_phase = "1b"`.

---

## 4.7 — Modelo de dados (Firestore)

> Antes de criar qualquer coisa, **ler o que já existe** — a auditoria indicou `detection_service.dart`, `detection_line.dart`, `dog_specialty.dart`, `detection_triagem_screen.dart`, `detection_maintenance_screen.dart`. **Estender/adaptar, não duplicar.** Os nomes abaixo são proposta; alinhar com as convenções do projeto e o que já existe.

### Progresso por linha
`dogs/{dogId}/detection_lines/{lineId}` — `lineId` ∈ { `drogas`, `armas`, `cadaver` }

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `status` | enum | `not_started` \| `triagem` \| `in_formation` \| `operational` |
| `current_phase` | string | código da fase atual: `1b`,`2b`,`2v`,`3b`,`3v`,`4b`,`4v`,`4c`,`final` |
| `phases_completed` | array\<string\> | códigos das fases já vencidas, em ordem |
| `phase_history` | array\<obj\> | `{ phase, completed_at, session_id }` por fase concluída |
| `updated_at` | timestamp | última atualização |
| `audit_trail` | array\<obj\> | conforme skill `audit-trail` |
| `deleted_at` | timestamp? | soft delete (null = ativo) |

### Sessão de formação
`dogs/{dogId}/training_sessions/{sessionId}`

| Campo | Tipo | Obrig. | Descrição |
|-------|------|--------|-----------|
| `type` | const | sim | `"detection_formation"` |
| `lines` | array\<string\> | sim | `["drogas"]` ou `["drogas","armas"]` (combinadas) |
| `phase` | string | sim | fase trabalhada na sessão (ex: `3v`) |
| `box_count` | int | sim | nº de caixas (deriva da fase: 1–4) |
| `odor_position_mode` | enum | sim | `fixed_last` (fase "b") \| `variable` (fase "v"/"c") |
| `used_ball` | bool | sim | deriva da fase (true até 3b, false da 3v) |
| `odor_material` | enum | sim | `nose_mp` \| `real` \| `scentlogix` |
| `direction` | enum? | só 4c | `clockwise` \| `counter_clockwise` (etapa atual da 4c) |
| `started_at` | timestamp | sim | início |
| `ended_at` | timestamp | sim | fim |
| `duration_seconds` | int | sim | duração calculada |
| `repetitions` | array\<obj\> | sim | ver abaixo |
| `total_reps` | int | sim | total de repetições |
| `longest_streak` | int | sim | maior sequência de consecutivas na sessão |
| `status` | enum | sim | `in_progress` \| `completed_by_criterion` \| `ended_without_criterion` |
| `criterion_met` | bool | sim | atingiu o critério da fase? |
| `phase_advanced` | bool | sim | houve avanço de fase nesta sessão? |
| `advanced_to` | string? | — | fase de destino (se avançou) |
| `media` | array\<string\> | — | paths no Storage |
| `notes` | string | — | observações |
| `created_by` | string | sim | condutor que registrou |
| `audit_trail` | array\<obj\> | sim | conforme skill |
| `deleted_at` | timestamp? | — | soft delete |

**Repetição** (item de `repetitions`):

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `order` | int | ordem da repetição (1, 2, 3…) |
| `odor_box` | int | caixa onde estava o odor (1…box_count). Em fase "b" = sempre a última |
| `result` | enum | `hit` \| `miss` |
| `ts` | timestamp | momento do registro |

`repetitions` é **array no doc da sessão** (são poucas dezenas — não justifica subcoleção). O erro é **binário**: não se registra qual caixa o cão indicou no erro — o cão precisa acertar independentemente.

### Mídias
`dogs/{dogId}/training_sessions/{sessionId}/media/{file}` no Storage. **Conferir as regras de Storage** para este path não cair no catchall `if false` (a auditoria anterior corrigiu paths parecidos em `occurrences/.../events` e `dogs/.../feeding_photos`).

---

## 4.8 — Validações

Antes de gravar / durante o fluxo:
- **Iniciar sessão** exige `line(s)` selecionada(s) e `odor_material` definido.
- `box_count`, `odor_position_mode` e `used_ball` devem ser **coerentes com a fase** (derivar da fase, não deixar o usuário divergir).
- **Fase "v"**: cada repetição exige `odor_box` informado **antes** de registrar `result`.
- **Fase "b"**: `odor_box` é preenchido automaticamente com a última caixa.
- **Não permitir** registrar repetição após `status` sair de `in_progress` (após atingir critério, a sessão está encerrada).
- **4c**: a etapa anti-horário só conta após a etapa horário ter atingido suas 3 consecutivas.
- `longest_streak` e `criterion_met` são **calculados** a partir de `repetitions` — não confiar em valor enviado pela UI sem recalcular.

---

## 4.9 — Offline, auto-save e recuperação

A formação acontece **em pista/campo**, frequentemente **sem sinal**. Portanto:
- O registro da sessão ao vivo deve funcionar **offline**, com **auto-save local** a cada repetição (mesmo padrão da Tela 2.2 — Ocorrência em Andamento).
- A sincronização com o Firestore ocorre quando a conexão volta.
- Se o app fechar no meio de uma sessão `in_progress`, ela deve ser **recuperável** (retomar de onde parou, com as repetições já registradas).
- O contador e a série são reconstruíveis a partir de `repetitions` salvas localmente.

---

## 4.10 — Telas e fluxo

### 4.10.1 — Seletor de fase
Mockup: `formacao_deteccao_seletor_fase.html`. Aparece ao **iniciar nova formação**.
- Trilha completa do protocolo, **agrupada por número de caixas**, lendo o progresso **real** do cão na linha.
- **Fases concluídas:** check + o critério atingido (3/3 ou 10/10).
- **Fase atual:** destacada, com botão **Iniciar sessão**.
- **Fases seguintes:** bloqueadas (cadeado) até a anterior ser concluída.
- Barra de **progresso geral** ("4 / 9 fases").
- **Linha a treinar** definida antes/junto (Drogas, Armas ou combinadas).
- Tocar uma fase **concluída** abre opção de reabrir para revisão (não altera o progresso).

### 4.10.2 — Sessão ao vivo (registro repetição-a-repetição)
Mockups: `formacao_deteccao_aovivo_caixas.html` (modo "v"), `formacao_deteccao_aovivo_2b_fixo.html` (modo "b" + bola).

**Configuração inicial** (rápida, antes de registrar): linha, material de odor. O resto (nº de caixas, modo, bola) deriva da fase.

**Cabeçalho:** faixa compacta da fase (código, nº caixas, modo, bola sim/não, meta de consecutivas).

**Desenho das caixas** conforme a fase:
- Fase **"b"**: N caixas, a **última travada/marcada** como alvo (odor fixo). Quando a fase tem bola, a **bolinha aparece** dentro da caixa-alvo. O instrutor **não toca** — só registra resultado.
- Fase **"v"**: N caixas **clicáveis**; a cada repetição o instrutor **toca a caixa onde pôs o odor** antes de registrar o resultado.

**Fluxo de cada repetição:**
1. (modo "v") instrutor toca a caixa do odor; (modo "b") posição já fixa.
2. instrutor toca **ACERTOU** ou **ERROU**.
3. o app grava a repetição (`order`, `odor_box`, `result`, `ts`), atualiza o **contador** (acerto incrementa, **erro zera**) e a **série visual**.
4. se o contador bate o critério → dispara a **conclusão de fase** (4.10.4).

**Elementos:** contador grande (X / critério) + barra + "faltam N"; série da sessão (verde/vermelho, mostrando onde zerou); botões grandes ACERTOU/ERROU (thumb-friendly, uso com uma mão); ação **"Encerrar e registrar sessão"** (encerra sem atingir → `ended_without_criterion`).

**Sem condições ambientais** nesta tela (temp/umidade é exclusivo da manutenção 3.11).

### 4.10.3 — Fase 4c (quadrado)
Mockup: `formacao_deteccao_aovivo_4c_quadrado.html`.
- 4 caixas em **quadrado**, vista de cima, com o instrutor no centro e a indicação do sentido.
- **Duas etapas sequenciais:** horário (3 consecutivas) e depois anti-horário (3 consecutivas). O toggle mostra o progresso de cada uma; `direction` registra a etapa atual.
- Odor **variável** (clicável), igual à fase "v".
- Concluir as duas etapas fecha a 4c e libera a Final.

### 4.10.4 — Mensagem de conclusão de fase
Mockup: `formacao_deteccao_fase_concluida.html`. Disparada **automaticamente** ao atingir o critério.
- Sóbria e institucional (**sem gamificação**): marca de conclusão, fase vencida, número objetivo atingido (3/3 ou 10/10 sem erro) e a progressão para a próxima fase (ex: 2b → 2v).
- Resumo da sessão (total de repetições, duração, erros).
- Ação única **"Concluir"**: encerra a sessão (`completed_by_criterion`) e persiste o avanço (`current_phase`, `phases_completed`, `phase_history`) com trilha de auditoria.
- Após concluir, a próxima sessão de formação já abre na nova fase.

### 4.10.5 — Telas relacionadas (já especificadas)
- **Manutenção** 3.11 — `tela_3_11_manutencao_deteccao.html`.
- **Detalhe no histórico** — `detalhe_historico_deteccao.html` (corpo mostra linha, fase, contador e série). Ver 4.12 sobre integridade (não exibir hash).

---

## 4.11 — Fase final (ambientes reais) — previsão

Conceito (a **tela ainda não foi desenhada** — pendência de design): sem caixas, o cão busca em **cenários reais** (veículos, salas, bagagens, áreas abertas), com dificuldade progressiva. O registro provavelmente trocará "caixas" por elementos como tipo de cenário, número de ocultações e localização — a definir com o instrutor.

**Para esta implementação:** deixar a fase Final **prevista no modelo de dados** (`current_phase = "final"`, e a transição para `operational` ao concluí-la), mas **não implementar a tela dela agora**.

---

## 4.12 — Auditoria, soft delete e integridade

- **Trilha de auditoria** na criação/edição/exclusão da sessão e em cada **avanço de fase**.
- **Soft delete** sempre (nada de hard delete).
- **Integridade:** uma sessão de **formação** é um registro de treino **editável** pelo condutor (com auditoria) — **não** carrega o hash imutável de uma ocorrência finalizada. Portanto, no detalhe de histórico de detecção, **não exibir bloco de hash/imutabilidade**. Mostrar "sincronizado" + trilha de auditoria. (Isto corrige o mockup de detalhe, que herdou o bloco de integridade da casca comum.)

---

## 4.13 — Critério de pronto (definição de feito)

1. **Iniciar nova formação** abre o seletor lendo o progresso **real** do cão na linha (concluídas, atual, bloqueadas).
2. A **sessão ao vivo** registra repetições com posição do odor (modo "v") e resultado; o contador **zera no erro**; funciona **offline** com auto-save e é **recuperável**.
3. Nas fases **"b"** a caixa-alvo fica travada/marcada (com bola quando aplicável); nas **"v"** exige tocar a caixa do odor.
4. A **4c** tem as duas etapas (horário, depois anti-horário).
5. Ao **atingir o critério**, a mensagem de conclusão aparece, encerra a sessão (`completed_by_criterion`) e avança `current_phase` / `phases_completed` automaticamente (com auditoria).
6. **Encerrar sem atingir** grava a sessão (`ended_without_criterion`) sem avançar a fase.
7. A sessão **persiste no Firestore** (repetições, status, auditoria, soft delete) e aparece no histórico.
8. **Nenhum dado mockado** — tudo lido/gravado do Firestore real.

---

## 4.14 — Decisões confirmadas e pendência de design

**Confirmado pelo instrutor:**
1. **Critérios** — 3 consecutivas em todas as fases, exceto a **3v (10)**. A 4c usa 3 horário + 3 anti-horário.
2. **Erro é binário** — não se registra a caixa indicada no erro.
3. **Contador zera entre sessões** — o critério é atingido dentro de uma única sessão.
4. **Bola sai na 3v** — presente em 1b/2b/2v/3b, removida a partir da 3v.

**Pendência de design (não de regra):**
5. **Fase final (ambientes reais)** — tela ainda não desenhada (ver 4.11). A fase fica prevista no modelo; a tela é trabalho futuro, a definir com o instrutor.
