# ESPECIFICAÇÃO TÉCNICA — PARTE 5
# Detecção · Entrada e Roteamento por Estado

> Especifica a **tela de entrada da Detecção** (seletor de linha) e o **roteamento por estado** — a "cola" que conecta triagem (3.12), formação (Parte 4) e manutenção (3.11) num lugar só.
>
> **Real, não mockado:** a tela lê **dados reais do Firestore** (o estado de cada linha). O `.html` citado é **protótipo visual (mockup)**, não vira código.
>
> Mockup de referência: `temp/mockups/tela_deteccao_entrada_linhas.html`.

---

## 5.0 — Escopo e o problema que resolve

Hoje o condutor entra na Detecção e **não tem onde decidir o que fazer** — qual linha treinar, e se é formação ou manutenção. Esta tela resolve: lista as linhas com o **estado real** de cada uma e **roteia automaticamente** para o fluxo certo. O condutor escolhe a **linha**, nunca "formação ou manutenção".

É a entrada que **despacha** para os três fluxos já especificados:
- **Triagem (3.12)** — porta de entrada de uma linha nova.
- **Formação (Parte 4)** — fases de caixas (1b → 4c).
- **Manutenção (3.11)** — trabalho em ambientes reais depois de formado.

---

## 5.1 — Navegação

`Aba Treino → Detecção → [esta tela: seletor de linha] → toca a linha → roteia conforme o estado`

- Breadcrumb no topo: **"Treino › Detecção"**.
- **Header Universal** no topo (binômio atual), idêntico ao resto do app.
- **Bottom nav** (Tratamento 2) com a aba **Treino** ativa.

---

## 5.2 — A tela (seletor de linha)

Um **card por linha**: Drogas, Armas, Cadáver. Cada card lê `dogs/{dogId}/detection_lines/{lineId}` e mostra:
- **Ícone de faro** + **nome da linha** + descrição curta (narcóticos / armamento / restos humanos).
- **Badge de estado** cor-codificado (ver 5.4).
- **Info contextual** conforme o estado (5.3).
- **CTA** indicando o destino do toque (ver 5.5).

As três linhas são **independentes**: o cão pode estar **operacional em Drogas** e **em formação em Armas** no mesmo dia — e os dois convivem na tela.

Tokens visuais no **idioma do app** (mesmos do Header Universal e dos cards): fundo de card `rgba(255,255,255,0.025)`, borda `rgba(255,255,255,0.07)`, radius 16.

---

## 5.3 — Info contextual por estado

| Estado | O que o card mostra |
|--------|---------------------|
| **operational** | "Manutenção em dia / atrasada" + **frescor** (dias desde a última sessão) |
| **in_formation** | **Fase atual** (código + nome, ex: `3v · independência total`) + progresso **X / 8 fases** + barra |
| **triagem** | "Triagem em andamento" |
| **not_started** | "Triagem ainda não realizada" |

---

## 5.4 — Estados visuais (cor = código)

| Estado | Cor | Badge |
|--------|-----|-------|
| `operational` | verde `#2ecc71` | OPERACIONAL |
| `in_formation` | âmbar `#f1c40f` | EM FORMAÇÃO |
| `triagem` | ciano `#4dd0e1` | EM TRIAGEM |
| `not_started` | cinza `#5a7280` | NÃO INICIADA |

A cor é aplicada ao ícone (tint), ao badge e (na formação) à barra de progresso. CTA/seta sempre em ciano (cor de ação do app).

---

## 5.5 — Roteamento por estado (o coração desta parte)

| Estado da linha | Toque leva para | Spec do destino |
|-----------------|-----------------|-----------------|
| `not_started` | **Triagem (Fase 0)** | 3.12 |
| `triagem` (não concluída) | **Continuar/concluir a triagem** | 3.12 |
| `in_formation` | **Formação** — abre o seletor de fase já na `current_phase` | Parte 4 (4.10.1) |
| `operational` | **Manutenção** — ambientes reais | 3.11 |

O app decide o destino pelo estado; o condutor **não escolhe o tipo de fluxo**. Triagem **reprovada/redirecionada** não vira `in_formation` — ver 3.12.

---

## 5.6 — Dados lidos

Por linha, de `dogs/{dogId}/detection_lines/{lineId}`:
- `status` → define cor, badge e roteamento.
- `current_phase` → fase atual (se `in_formation`).
- `phases_completed` → progresso **X / 8** (total de fases de formação = 8: 1b,2b,2v,3b,3v,4b,4v,4c).
- **Frescor** (se `operational`) → vem de **`last_session_at`** na linha (recomendado: campo atualizado a cada sessão de manutenção) ou da `training_session` mais recente daquela linha.
  - **Complementa a Parte 4 (4.7):** manter `last_session_at` em `detection_lines`.
  - Regra de frescor (parâmetro): **"em dia"** se última sessão ≤ **14 dias**; **"atrasada"** acima. (14 é sugestão — confirmar com o instrutor.)

A tela é **somente leitura** — não grava nada. A gravação acontece nos fluxos de destino (triagem, formação, manutenção).

---

## 5.7 — Casos de borda

- **Linha sem documento ainda** → tratar como `not_started`.
- **Cão sem nenhuma linha iniciada** → as três aparecem como "Não iniciada".
- **Triagem reprovada/redirecionada** → tratada na 3.12 (não aparece como `in_formation`).
- **Combinação Drogas + Armas** (treino combinado, 4.4) → a *sessão* pode combinar linhas; **a entrada continua mostrando uma linha por card** com seu próprio estado.

---

## 5.8 — Critério de pronto (definição de feito)

1. **Treino → Detecção** abre o seletor com as **3 linhas** e o **estado real** de cada uma (lido do Firestore).
2. Cores e badges corretos por estado (5.4).
3. **Tocar roteia para o destino certo** conforme a tabela 5.5.
4. `in_formation` mostra fase atual + **X/8** + barra; `operational` mostra **frescor**.
5. Linhas **independentes** — estados distintos convivem no mesmo cão.
6. **Nada hardcoded** — tudo lido do Firestore.
7. Header Universal + bottom nav (Tratamento 2) coerentes com o app.
