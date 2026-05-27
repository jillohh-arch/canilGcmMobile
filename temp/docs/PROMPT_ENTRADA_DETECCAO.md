# PROMPT — Tela de Entrada da Detecção (roteamento por estado)

> Sessão focada do Claude Code. Cole o bloco abaixo.

---

Vamos implementar a **tela de entrada da Detecção** do app Canil K9 GCM Limeira — o seletor de linha que mostra o estado real de cada linha e **roteia** para o fluxo certo (triagem / formação / manutenção).

**Leia primeiro:**
- `temp/docs/ESPEC_TECNICA_PARTE_5.md` — esta tela + o roteamento por estado (é a spec principal desta sessão).
- Contexto dos destinos: **Parte 4** (formação/caixas), **3.11** (manutenção), **3.12** (triagem).
- Mockup: `temp/mockups/tela_deteccao_entrada_linhas.html` — **protótipo visual, não vira código** (guia o desenho; os dados vêm do Firestore).
- Skills: `canil-k9-context`, `firestore-coexistence`, `flutter-canil-conventions`, `flutter-visual-fidelity`.

**Antes de codar — mapeie o que já existe.** A auditoria apontou `detection_service.dart`, `detection_line.dart`, `detection_triagem_screen.dart`, `detection_maintenance_screen.dart`, `training_hub_screen.dart`. **Como a Detecção é acessada hoje** a partir do hub de treinos? Me mostre o fluxo atual e o plano de integração **antes** de escrever código novo. Estender/adaptar, não duplicar.

**Escopo:**
1. **Tela de entrada (seletor de linha)** — 3 cards (Drogas, Armas, Cadáver), cada um lendo `detection_lines/{lineId}` e exibindo o **estado real** (spec 5.2–5.4): ícone de faro, nome, badge cor-codificado, info contextual.
2. **Roteamento por estado** (spec 5.5):
   - `not_started` → Triagem (3.12)
   - `triagem` → continuar a triagem (3.12)
   - `in_formation` → Formação, abrindo o seletor de fase já na `current_phase` (Parte 4 · 4.10.1)
   - `operational` → Manutenção (3.11)
3. **Ligar ao hub:** `Treino → Detecção` abre esta tela (hoje não há como escolher — esta é a correção).
4. **Estados visuais cor-codificados** (verde operacional / âmbar em formação / cinza não iniciada), com os **tokens do Header Universal e dos cards** (não criar cores soltas).

**Dados (spec 5.6):**
- Por linha: `status`, `current_phase`, `phases_completed` (→ progresso **X/8**; total de fases = 8).
- Frescor (operacional): usar **`last_session_at`** em `detection_lines` (criar/atualizar esse campo a cada sessão de manutenção) ou a sessão mais recente da linha. Frescor "em dia" se ≤ 14 dias (parâmetro).

**Regras inegociáveis:**
- **Dados reais do Firestore** — nada hardcoded na tela.
- **Header Universal** + **bottom nav (Tratamento 2)** já existentes; reaproveitar.
- A tela é **somente leitura** — a gravação acontece nos fluxos destino.
- Branch; `main` sempre buildável; merge `--no-ff` só após validado.

**Pronto quando (spec 5.8):**
1. `Treino → Detecção` abre o seletor com as 3 linhas e os estados **reais**.
2. Cores e badges corretos por estado.
3. **Tocar roteia para o destino certo** (tabela 5.5).
4. `in_formation` mostra fase + X/8 + barra; `operational` mostra frescor.
5. Linhas independentes (estados distintos convivem).
6. Nada hardcoded.

**Valide com evidência** — `git log` da branch, **prints** da tela com linhas em estados diferentes, e a confirmação de que **o toque navega** para o fluxo correto de cada estado. Não aceite resumo narrativo como prova.
