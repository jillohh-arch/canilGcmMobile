# FRENTE B — Editar a natureza da ocorrência
### Spec curta + prompt (frente pequena)

> O condutor precisa poder **alterar a natureza** de uma ocorrência (ex: começou como averiguação, virou tráfico). Hoje ele não encontrou como — pode não existir, ou existir mal posicionado.

---

## Spec

### B.0 — Escopo
Permitir editar a natureza de uma ocorrência, de forma **auditável**, respeitando a integridade (mesma regra da Frente A).

### B.1 — Diagnóstico primeiro
Antes de implementar, descobrir:
- Como a natureza é **definida na criação** — é **lista fixa** (enum de tipos) ou **texto livre**?
- Onde fica no **modelo** e como é **exibida**.
- **Já existe** alguma forma de editar a natureza? Se sim, **onde** — e por que o condutor não a encontrou (mal posicionada)?
Se já existe, o trabalho é **tornar acessível**; se não, **implementar**.

### B.2 — Edição
- **Ponto de entrada:** o "✎" ao lado da natureza no detalhe (já no mockup `ocorrencia_detalhe_grande.html`) e também na ocorrência **ativa**.
- **Reusar o seletor de natureza da criação** — mesma lista/campo, para consistência. Não criar um seletor paralelo.
- Ao salvar: gravar a nova natureza + **entrada de auditoria** (natureza anterior → nova, quando, por quem). Não apagar a anterior da trilha.

### B.3 — Integridade (mesma regra da Frente A)
- **Antes de selar:** editar livre.
- **Depois de selar:** via **retificação** (item 5 da integridade da Frente A). Enquanto a retificação não existir, após selar fica bloqueado, igual à edição de local.

### B.4 — Critério de pronto
1. Diagnóstico reportado (lista ou texto; já existia edição?).
2. Editar a natureza pelo "✎" no detalhe e na ocorrência ativa.
3. Mudança **registrada na auditoria** (anterior → nova).
4. Respeita a mutabilidade (livre antes de selar; retificação depois).

---

## Prompt (colar no Claude Code)

Vamos permitir **editar a natureza de uma ocorrência**. Leia esta spec (Frente B) e `temp/docs/ESPEC_TECNICA_PARTE_7.md`. Skills: `canil-k9-context`, `audit-trail`.

**Diagnostique e reporte primeiro:** como a natureza é definida na criação (lista fixa ou texto livre?), onde fica no modelo, como é exibida, e **se já existe alguma edição** — se existir, onde está e por que não é fácil de achar. Não implemente do zero algo que já exista; nesse caso, só torne acessível.

**Depois implemente:**
- Ponto de entrada pelo "✎" ao lado da natureza no detalhe e na ocorrência ativa.
- **Reuse o seletor de natureza da criação** (mesma lista/campo) — sem seletor paralelo.
- Ao salvar, gravar a nova natureza e uma **entrada de auditoria** (anterior → nova, timestamp, autor), sem apagar a anterior da trilha.
- **Mutabilidade:** livre antes de selar; após selar, bloqueado por ora (entrará na retificação da integridade da Frente A).

**Regras do projeto:** branch; `main` buildável; merge `--no-ff` após validado. Nada hardcoded.

**Validação (no celular):** alterar a natureza de uma ocorrência não selada, ver a mudança refletida no detalhe e no PDF, e confirmar a entrada na trilha de auditoria (anterior → nova). Prints + `git log`, não resumo.
