# ESPEC TÉCNICA — PARTE 15
## Prontuário do cão (Saúde): abas + histórico + nutrição

> Filtro de sempre: *"se um gestor questionar o trabalho do condutor 6 meses depois, esse registro o defende?"* — o prontuário é parte da **defesa do cão**: provar que estava apto, vacinado e acompanhado.

---

## 0. Contexto e objetivo

A tela de Saúde hoje é uma **lista longa** — card do cão, status médico, evolução do peso, carteira de vacinação, laudos e eventos, tudo empilhado num scroll de três telas. Densidade demais.

Objetivo: reorganizar em **abas focadas**, com o **histórico embutido em cada tema**, adicionar a aba **Nutrição**, e garantir o padrão de auditoria do app. Referência visual: os mockups aprovados (Resumo / Vacinas / Peso / Nutrição / Docs).

**Duas ressalvas firmes sobre a referência visual:**
- **Não existe aba "Histórico"** (o histórico vive dentro de cada aba — ver §3/§4).
- O **tab bar inferior é o EXISTENTE do app.** Ignore qualquer tab bar novo que apareça nos mockups de referência — aquilo foi licença visual, não é pra implementar.

---

## 1. Estrutura geral da tela

- **Header global:** hamburguer à esquerda, sino à direita (já definido na Parte 14 — **reusar**, não recriar).
- **Card do cão (hero):** foto, emblema K9, nome, raça · sexo, idade, peso, status operacional.
- **Três status rápidos** fixos abaixo do card: Peso · Vacinas · Alertas.
- **Abas:** `Resumo · Vacinas · Peso · Nutrição · Docs` (seletor horizontal). **Sem aba Histórico.**

---

## 2. Conteúdo de cada aba

### Resumo (hub de entrada)
- **Próximas ações:** vacina próxima, antiparasitário, exame periódico (cada um com estado).
- **Evolução do peso** (gráfico compacto).
- **Últimos eventos** (preview misto) + **"Ver histórico"** → abre a **tela de histórico unificado** (§4).
- Ação: **Registrar evento**.

### Vacinas
- **Carteira de vacinação:** lista com estado (em dia / vencida) e próxima dose.
- **Próximas aplicações** (com contagem de dias).
- **Histórico de vacinas** embutido + **"Ver histórico"** → completo de vacinas.
- Ação: **Registrar vacina** (captura profissional + CRMV).

### Peso
- **Evolução do peso** (gráfico) + última pesagem · meta operacional · condição corporal.
- **Registros de pesagem** (com variação ↑↓) + ver histórico.
- **Insight de tendência** (ex.: "estável, dentro da faixa ideal").
- Ação: **Registrar pesagem**.

### Nutrição
- **Plano alimentar:** ração (tipo), refeições/dia, quantidade diária, hidratação.
- **Rotina do dia:** refeições programadas (horário, quantidade) com estado concluído / programado.
- **Suplementos:** nome, dose, estado (em uso).
- **Observações nutricionais:** apetite, restrições.
- Ação: **Registrar alimentação**.

### Docs
- **Laudos e documentos:** lista com filtro (Todos / Exames / Laudos / PDF).
- **Anexar laudo ou documento PDF** + **Novo documento**.

---

## 3. Histórico por aba

- Cada aba traz o histórico do **seu próprio tema** embutido (vacinas na aba Vacinas, pesagens na aba Peso, etc.).
- O **"Ver histórico"** de cada aba abre o histórico **completo daquela área**, filtrado.

## 4. Tela de histórico unificado (não é aba)

- Acessada pelo **"Ver histórico" do Resumo**.
- **Timeline** de todos os eventos do cão (vacina, peso, exame, nutrição) com **filtros** (Todos / Vacinas / Peso / Exames / Nutrição).
- É a visão cronológica geral — "o que foi feito com esse cão ao longo do tempo". Não ocupa aba; abre como tela sob demanda.

---

## 5. Regras de auditoria (não-negociáveis)

1. **Todo registro** (vacina, pesagem, exame, refeição, documento) carrega **autoria** (quem registrou; e o profissional + CRMV quando houver), **timestamp** e **soft delete**.
2. **Correção é com trilha:** registro errado se corrige criando nova versão com histórico, **nunca** sobrescrevendo ou apagando.
3. **Documentos/laudos anexados são imutáveis:** arquivar com histórico, nunca deletar de verdade.
4. O prontuário é prova: ele defende o condutor mostrando que o cão estava apto, vacinado e acompanhado.

---

## 6. Novo × existente (diagnosticar antes)

- **Já existe (reorganizar e reusar):** peso/pesagem, vacinas, eventos médicos, laudos/documentos.
- **Novo (criar modelo + UI):** aba **Nutrição** (plano alimentar, rotina de refeições, suplementos, observações) e a **tela de histórico unificado**.
- Diagnosticar os modelos/coleções atuais antes de mexer, pra reusar o que já está pronto e só estender o que falta.

---

## 7. Coerência com o app

- Header = Parte 14 (reusar). Tab bar = o **existente** (não o dos mockups).
- Reusar componentes: gráfico de peso, cards de status, padrão de registro de evento, anexo de PDF (laudos já existem).
- Nada hardcoded; dados no Firebase.

---

## 8. Critério de pronto

- Abas Resumo/Vacinas/Peso/Nutrição/Docs funcionando, cada uma enxuta, com histórico do tema embutido + "ver histórico" completo.
- Tela de histórico unificado acessível pelo Resumo.
- Nutrição nova operando (plano, rotina, suplementos, observações).
- Auditoria travada no código (autoria, soft delete, correção com trilha, documentos imutáveis).
- Header e tab bar coerentes com o app. Validado em aparelho real.
