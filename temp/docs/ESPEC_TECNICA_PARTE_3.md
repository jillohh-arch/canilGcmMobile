# 📘 ESPECIFICAÇÃO TÉCNICA — PARTE 3

## App Canil K9 GCM Limeira — Treinos, Saúde e Auxiliares

> Documento técnico de referência para implementação no Claude Code.
> Cobre o sistema completo de treinos (especialidades + treinos gerais),
> registro de eventos de saúde, modais auxiliares e PDFs auxiliares.

---

## 📋 ÍNDICE DA PARTE 3

### Bloco D — Hub e Treinos Gerais
1. [Tela 3.1 — Hub de Treinos](#tela-31--hub-de-treinos)
2. [Tela 3.2 — Obediência (Biblioteca de Comandos)](#tela-32--obediência-biblioteca-de-comandos)
3. [Tela 3.3 — Sessão de Obediência](#tela-33--sessão-de-obediência)
4. [Tela 3.4 — Condicionamento Físico (Visão Geral)](#tela-34--condicionamento-físico-visão-geral)
5. [Tela 3.5 — Nova Sessão de Condicionamento](#tela-35--nova-sessão-de-condicionamento)

### Bloco E — Especialidade: Busca & Captura
6. [Tela 3.6 — Busca & Captura · Formação](#tela-36--busca--captura--formação)
7. [Tela 3.7 — Busca & Captura · Manutenção](#tela-37--busca--captura--manutenção)
8. [Tela 3.8 — Rastreador GPS (B&C ao vivo)](#tela-38--rastreador-gps-bc-ao-vivo)

### Bloco F — Especialidade: Detecção (Protocolo Ragonha)
9. [Tela 3.9 — Detecção · Tela de Linhas](#tela-39--detecção--tela-de-linhas)
10. [Tela 3.10 — Detecção · Formação por Fases](#tela-310--detecção--formação-por-fases)
11. [Tela 3.11 — Detecção · Manutenção](#tela-311--detecção--manutenção)
12. [Tela 3.12 — Triagem (Fase 0)](#tela-312--triagem-fase-0)

### Bloco G — Especialidade: Guarda & Proteção
13. [Tela 3.13 — Guarda & Proteção · Formação](#tela-313--guarda--proteção--formação)
14. [Tela 3.14 — Sessão com Figurante](#tela-314--sessão-com-figurante)

### Bloco H — Saúde
15. [Tela 3.15 — Seletor de Tipo de Evento de Saúde](#tela-315--seletor-de-tipo-de-evento-de-saúde)
16. [Tela 3.16 — Formulário de Evento de Saúde](#tela-316--formulário-de-evento-de-saúde)

### Bloco I — Modais Auxiliares
17. [Modal 3.17 — Adicionar Nova Especialidade](#modal-317--adicionar-nova-especialidade)
18. [Modal 3.18 — Adicionar Comando (Obediência)](#modal-318--adicionar-comando-obediência)
19. [Modal 3.19 — Atualizar Estágio do Comando](#modal-319--atualizar-estágio-do-comando)

### Bloco J — PDFs Auxiliares
20. [Documento 3.20 — PDF da Carteira de Vacinação](#documento-320--pdf-da-carteira-de-vacinação)
21. [Documento 3.21 — PDF do Histórico de Peso](#documento-321--pdf-do-histórico-de-peso)
22. [Documento 3.22 — PDF do Relatório Nutricional](#documento-322--pdf-do-relatório-nutricional)
23. [Documento 3.23 — PDF do Histórico Mensal](#documento-323--pdf-do-histórico-mensal)

---

# 🎯 BLOCO D — HUB E TREINOS GERAIS

## TELA 3.1 — HUB DE TREINOS

### 📌 Identificação
- **Mockup de referência:** `14_hub_treinos.html`
- **Rota no app:** `/treino`
- **Prioridade:** ALTA (centro do domínio de treinos)

### 🚪 Como se chega
- Tap em "🎯 Treino" no Bottom Navigation
- Tap em card "🎯 Treino" do acesso rápido do Dashboard

### 🎯 Propósito
Hub central de todos os treinos. Mostra resumo da semana, especialidades do cão com seus estados (operacional/formação/não iniciada), e treinos gerais (Obediência, Condicionamento). **O app sabe se uma sessão é formação ou manutenção pelo estado da especialidade — não pergunta ao usuário.**

### 🗄️ Dados do Firestore consumidos

| Coleção | Filtro | Campos |
|---------|--------|--------|
| `/dogs/{active_dog_id}/specialties_state` | todos | type, status, sub_lines |
| `/dogs/{id}/training_sessions` | últimos 7 dias | type, duration, created_at |
| `/dogs/{id}/training_sessions` | última de cada tipo | last_training_at |

### 🎨 Estrutura visual

```
[Header Universal]

[Resumo da semana]
  ESTA SEMANA
  ┌──────┬──────┬──────┐
  │ 12   │ 4h30 │ 3 esp│
  │ ses. │ total│ trab.│
  └──────┴──────┴──────┘

[Especialidades · 3 cards grandes]

  ┌────────────────────────────────────────┐
  │ 🎯 BUSCA & CAPTURA                     │
  │ ● OPERACIONAL · há 3 dias              │
  │ Manutenção ativa                       │
  │                              CONTINUAR │
  └────────────────────────────────────────┘
  
  ┌────────────────────────────────────────┐
  │ 👃 DETECÇÃO                            │
  │ ● OPERACIONAL · há 1 dia               │
  │ 2 linhas ativas: Drogas · Armas        │
  │                              CONTINUAR │
  └────────────────────────────────────────┘
  
  ┌────────────────────────────────────────┐
  │ 🛡 GUARDA & PROTEÇÃO                   │
  │ ◔ EM FORMAÇÃO · F2 desenvolvendo       │
  │ Caça aberto, Defesa em consolidação    │
  │                              CONTINUAR │
  └────────────────────────────────────────┘

  [+ INICIAR NOVA ESPECIALIDADE]

[Treinos gerais · chips]
  ┌──────────────┬──────────────┐
  │ 🐾 OBEDIÊNCIA │ 💪 CONDICIONAM│
  │ Contínuo      │ Contínuo      │
  │ 15 comandos   │ Último: ontem │
  └──────────────┴──────────────┘

[Bottom Nav ativo: Treino]
```

### 🔧 Estrutura técnica

- **Header Universal** persistente
- **Cards de especialidade:** grandes, com:
  - Ícone + nome
  - Badge de status (verde/amarelo/cinza)
  - Subtitle com contexto (última sessão · linhas ativas · módulo atual)
  - Botão "CONTINUAR" à direita
- **Botão "+ INICIAR NOVA ESPECIALIDADE":** aparece se há especialidade `status == 'not_started'`
- **Treinos gerais:** 2 cards menores em grid (Obediência + Condicionamento)

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Tap em card de Busca & Captura | Vai pra Manutenção (3.7) OU Formação (3.6) baseado em `status` |
| Tap em card de Detecção | Vai pra Tela de Linhas (3.9) |
| Tap em card de Guarda & Proteção | Vai pra Formação (3.13) OU Manutenção dependendo do status |
| Botão "+ INICIAR NOVA ESPECIALIDADE" | Abre Modal 3.17 |
| Tap em "🐾 OBEDIÊNCIA" | → `/treino/obediencia` (Tela 3.2) |
| Tap em "💪 CONDICIONAMENTO" | → `/treino/condicionamento` (Tela 3.4) |

### 🧭 Navegação de saída

Depende da especialidade e seu estado:

```
Busca & Captura · status == 'operational' → /treino/busca-captura/manutencao
Busca & Captura · status == 'in_formation' → /treino/busca-captura/formacao

Detecção · sempre → /treino/deteccao (Tela 3.9, tela de linhas)

Guarda & Proteção · status == 'operational' → manutenção
Guarda & Proteção · status == 'in_formation' → /treino/guarda-protecao/formacao
```

### 🚨 Estados especiais

- **Nenhuma especialidade ainda:** mostra mensagem "Inicie a primeira especialidade do binômio" com CTA grande
- **Todas especialidades operacionais:** parabéns implícito (sem mensagem chamativa, só status verde nos 3 cards)
- **Loading inicial:** skeleton dos 3 cards

### ⚙️ Regras de negócio

- **App detecta automaticamente** se é formação ou manutenção pelo `specialties_state.status`
- **Não pergunta ao usuário** "é formação ou manutenção?" — o estado define
- **Cada especialidade pode ter 3 estados:**
  - `not_started` (cinza) — não aparece no hub, mas no modal de adicionar
  - `in_formation` (amarelo) — mostra módulo/fase atual
  - `operational` (verde) — mostra última manutenção
- **Resumo da semana** soma `training_sessions` dos últimos 7 dias
- **Treinos gerais sempre disponíveis** (Obediência, Condicionamento) — não têm "estado"

### 📊 Estado atual vs Novo

**Estado atual:**
- ⚠️ Provavelmente existe `features/training/` mas com estrutura plana
- ⚠️ Não diferencia formação de manutenção automaticamente

**O que muda:**
- 🔨 Hub central novo que **agrupa** as 3 especialidades + treinos gerais
- 🔨 Roteamento inteligente baseado em `specialties_state`
- 🔨 Resumo da semana calculado em runtime
- 🔨 Cards visuais ricos por especialidade
- ⚠️ Criar coleção `/dogs/{id}/specialties_state` (NOVA) se não existe

---

## TELA 3.2 — OBEDIÊNCIA (BIBLIOTECA DE COMANDOS)

### 📌 Identificação
- **Mockup de referência:** `04_treino_v3.html`
- **Rota no app:** `/treino/obediencia`
- **Prioridade:** ALTA

### 🚪 Como se chega
- Tap em "🐾 OBEDIÊNCIA" no Hub de Treinos

### 🎯 Propósito
Biblioteca personalizada de comandos do cão ativo. Cada cão tem sua lista própria (Bono tem 15, Apolo tem outra). Cada comando tem estágio (do iniciante ao operacional). Permite iniciar sessão de treino selecionando comandos a treinar.

### 🗄️ Dados do Firestore consumidos

| Coleção | Filtro | Campos |
|---------|--------|--------|
| `/dogs/{id}/commands` | `archived != true` | name, category, stage, stage_updated_at, observations |
| `/dogs/{id}/training_sessions` | `type == 'obedience'`, últimas | preview |

**Estrutura do `commands`:**
```
/dogs/{dogId}/commands/{commandId}:
  name: "Aporta!"
  category: "operacional" | "posicional" | "postural" | "habilidade"
  stage: "nao_treinado" | "introduzido" | "em_desenvolvimento" | "consolidado" | "operacional"
  stage_updated_at: timestamp
  created_at: timestamp
  observations: string?
```

### 🎨 Estrutura visual

```
[Header contextual]
  [‹]  Obediência                       [+]
       Bono · 15 comandos · treino contínuo

[Resumo dos estágios]
  ●●●●● 8  ●●●●○ 4  ●●●○○ 2  ●●○○○ 1

[Filtros por categoria]
  [Tudo] [Operacional] [Posicional] [Postural] [Habilidades]

[Lista agrupada]

  OPERACIONAIS · 4 comandos
  
  ┌────────────────────────────────────────┐
  │ 🦮 Aporta!         ●●●●● OPERACIONAL  │
  │    Atualizado há 5 dias                │
  └────────────────────────────────────────┘
  ┌────────────────────────────────────────┐
  │ 🦮 Larga!          ●●●●○ CONSOLIDADO  │
  │    Atualizado há 12 dias               │
  └────────────────────────────────────────┘
  ...

  POSICIONAIS · 5 comandos
  ...

[Sticky bottom]
  [▶ INICIAR SESSÃO DE TREINO]
```

### 🔧 Estrutura técnica

- **Header contextual:** botão [+] no topo direito abre Modal 3.18
- **Resumo dos estágios:** mini-visual com bolinhas (5 níveis) e contadores
- **Filtros chips** por categoria
- **Lista agrupada por categoria** com headers
- **Cada item:** nome + estágio visual (5 bolinhas) + label + meta
- **CTA sticky:** "INICIAR SESSÃO DE TREINO"

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Botão [+] | Abre Modal 3.18 (adicionar comando) |
| Tap em comando | Abre detalhe + botão "Atualizar estágio" (Modal 3.19) |
| Long press em comando | Menu: editar nome / arquivar / remover |
| Chips de categoria | Filtra lista |
| "INICIAR SESSÃO" | Vai pra Tela 3.3 com pré-seleção opcional |

### 🧭 Navegação de saída

- **‹ Voltar:** → `/treino`
- **Iniciar sessão:** → `/treino/obediencia/sessao` (Tela 3.3)
- **Modal adicionar/atualizar:** permanece na tela após salvar

### 🚨 Estados especiais

- **Nenhum comando ainda:** estado vazio "Cadastre o primeiro comando do Bono" + CTA grande
- **Cão recém-cadastrado:** sugestões de comandos populares (ex: "Senta, Deita, Vem, Fica")

### ⚙️ Regras de negócio

- **Cada cão tem biblioteca própria** — `commands` é subcoleção de `dogs/{id}`
- **5 estágios discretos:**
  - `nao_treinado` ○○○○○ (cinza)
  - `introduzido` ●○○○○ (vermelho)
  - `em_desenvolvimento` ●●○○○ (laranja)
  - `consolidado` ●●●●○ (amarelo)
  - `operacional` ●●●●● (verde)
- **Apenas condutor titular edita** estágios e adiciona comandos
- **Cobertura pode ver mas não editar** estágios
- **Categoria define agrupamento:** Operacionais, Posicionais, Posturais, Habilidades
- **Arquivar não deleta** — mantém histórico

### 📊 Estado atual vs Novo

**Estado atual:**
- ⚠️ Provavelmente tem comandos genéricos hard-coded
- ⚠️ Não tem biblioteca por cão

**O que muda:**
- 🔨 **Biblioteca personalizada por cão** (subcoleção `commands`)
- 🔨 Sistema de 5 estágios discretos com visual de bolinhas
- 🔨 Filtros por categoria
- 🔨 Modais de adicionar e atualizar
- ⚠️ Criar subcoleção `/dogs/{id}/commands` (NOVA)

---

## TELA 3.3 — SESSÃO DE OBEDIÊNCIA

### 📌 Identificação
- **Mockup de referência:** `15_manutencao_deteccao_obediencia.html` (tela 2)
- **Rota no app:** `/treino/obediencia/sessao`
- **Prioridade:** ALTA

### 🚪 Como se chega
- CTA "▶ INICIAR SESSÃO DE TREINO" da Tela 3.2

### 🎯 Propósito
Registrar uma sessão prática de treino de obediência. Multi-select de comandos a treinar, captura de duração, observações.

### 🗄️ Dados do Firestore

**Leitura:**
- `/dogs/{id}/commands` (não arquivados)

**Escrita ao finalizar sessão:**
```
/dogs/{id}/training_sessions/{sessionId}:
  type: 'obedience'
  commands_trained: ['commandId1', 'commandId2', ...]
  duration_minutes: 25
  observations: string
  location: string?
  started_at: timestamp
  ended_at: timestamp
  created_by: uid
  created_at: timestamp
```

### 🎨 Estrutura visual

```
[Header contextual]
  [‹]  Sessão de Obediência              [⏱]
       Bono · iniciada agora · 00:00

[Lista de comandos selecionáveis]

  OPERACIONAIS
  ☑ Aporta!         (selecionado · 3 tentativas)
  ☐ Larga!

  POSICIONAIS
  ☑ Senta           (selecionado · 5 tentativas)
  ☐ Deita
  ...

[Resumo da sessão]
  COMANDOS TREINADOS: 2
  DURAÇÃO: 12:34

[Observações]
  ┌────────────────────────────────────────┐
  │ Senta com excelente foco · pequena    │
  │ hesitação no Aporta...                 │
  └────────────────────────────────────────┘

[CTA sticky]
  [✓ FINALIZAR SESSÃO]
```

### 🔧 Estrutura técnica

- **Cronômetro no header:** automático ao abrir a tela
- **Lista de comandos:** checkbox para selecionar, contador de tentativas opcional
- **Resumo dinâmico:** comandos selecionados + duração atual
- **Campo de observações:** texto livre opcional

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Botão ⏱ no header | Pausa/retoma cronômetro |
| Checkbox de comando | Marca/desmarca |
| Tap em "+ tentativa" | Incrementa contador (opcional) |
| Campo observações | Multiline |
| "FINALIZAR" | Salva sessão · retorna pra biblioteca |

### 🧭 Navegação de saída

- **‹ Voltar:** confirma se houver dados não salvos
- **Finalizar:** → `/treino/obediencia` (Tela 3.2)

### ⚙️ Regras de negócio

- **Cronômetro contínuo** durante a sessão
- **Comandos selecionados são registrados** como treinados
- **Mínimo 1 comando** pra finalizar
- **Duração mínima sugerida** 5 minutos (avisa mas não bloqueia)
- **Salvamento atualiza** `commands[].stage_updated_at` se houver progressão (opcional, manual)

### 📊 Estado atual vs Novo

**O que muda:**
- 🔨 Tela nova de sessão de obediência
- 🔨 Multi-select integrado à biblioteca
- 🔨 Cronômetro embutido
- 🔨 Contador de tentativas por comando

---

## TELA 3.4 — CONDICIONAMENTO FÍSICO (VISÃO GERAL)

### 📌 Identificação
- **Mockup de referência:** `17_condicionamento.html` (tela 1)
- **Rota no app:** `/treino/condicionamento`
- **Prioridade:** MÉDIA

### 🚪 Como se chega
- Tap em "💪 CONDICIONAMENTO" no Hub de Treinos

### 🎯 Propósito
Visão geral do condicionamento físico do cão. Mostra sessões recentes, catálogo de exercícios disponíveis (organizados em 3 categorias), e botão pra nova sessão.

### 🗄️ Dados do Firestore

| Coleção | Filtro | Campos |
|---------|--------|--------|
| `/dogs/{id}/conditioning_sessions` | últimas 10 | exercise_type, duration, intensity, created_at |

### 🎨 Estrutura visual

```
[Header contextual]
  [‹]  Condicionamento Físico
       Bono · treino contínuo

[Resumo recente]
  ÚLTIMAS 7 DIAS: 4 sessões · 2h30 total

[Catálogo · 3 categorias]

  ▼ 🫀 CARDIOVASCULAR
    🚶 Passeio
    🏃 Esteira (Bono: 2x2min vel máxima)
    🪂 Paraquedas
    🏊 Natação
    + Outro
  
  ▼ 💪 FORÇA
    🪢 Tração c/ peso
    🎯 Tração elástica
    🧗 Escalada
    + Outro
  
  ▼ 🤸 AGILIDADE / PLIOMETRIA
    ⚽ Bolinha em campo (diagonais 50m)
    🅰 A-Frame
    📏 Salto altura/distância
    🚧 Cavaletes
    + Outro

[Sessões recentes]
  Ontem · ⚽ Bolinha em campo · 25min
  Anteontem · 🏃 Esteira · 4min
  ...

[CTA sticky]
  [+ NOVA SESSÃO DE CONDICIONAMENTO]
```

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Tap em categoria (▼) | Expande/colapsa lista de exercícios |
| Tap em exercício do catálogo | Vai pra Tela 3.5 com exercício pré-selecionado |
| "+ Outro" | Vai pra Tela 3.5 com tipo "custom" |
| Tap em sessão recente | Detalhe da sessão |
| CTA "+ NOVA SESSÃO" | Vai pra Tela 3.5 sem pré-seleção |

### 🧭 Navegação de saída

- **‹ Voltar:** → `/treino`
- **Nova sessão:** → `/treino/condicionamento/nova` (Tela 3.5)
- **Detalhe de sessão:** → `/historico/conditioning/{id}` (Tela 2.8)

### ⚙️ Regras de negócio

- **Sem fases ou progressão estruturada** — condicionamento é treino contínuo
- **Catálogo de exercícios** é fixo no app (pode ser configurável no painel web)
- **"+ Outro"** permite registrar exercício customizado
- **Sem ranqueamento** de exercícios — todos têm peso igual no histórico

### 📊 Estado atual vs Novo

**O que muda:**
- 🔨 Tela completa nova
- 🔨 Catálogo de 11+ exercícios em 3 categorias
- 🔨 Suporte a exercício customizado
- ⚠️ Criar coleção `/dogs/{id}/conditioning_sessions` (NOVA)

---

## TELA 3.5 — NOVA SESSÃO DE CONDICIONAMENTO

### 📌 Identificação
- **Mockup de referência:** `17_condicionamento.html` (tela 2)
- **Rota no app:** `/treino/condicionamento/nova`
- **Prioridade:** MÉDIA

### 🚪 Como se chega
- Tap em exercício específico do catálogo (Tela 3.4)
- Tap em "+ NOVA SESSÃO" (Tela 3.4)

### 🎯 Propósito
Formulário inteligente que adapta seus campos conforme o exercício escolhido. Exemplo: Esteira pede velocidade + tempo; Bolinha pede repetições + distância; Tração pede peso.

### 🗄️ Dados do Firestore

**Escrita:**
```
/dogs/{id}/conditioning_sessions/{sessionId}:
  exercise_type: 'esteira' | 'bolinha' | 'tracao_peso' | 'custom'
  duration_minutes: 12
  intensity_data: {  // varia por tipo
    speed_kmh?: 25,
    weight_kg?: 5,
    repetitions?: 10,
    distance_m?: 50
  }
  location: 'canil' | 'externo'
  gps_track?: array of coords  // se GPS ativo
  observations: string?
  created_by: uid
  created_at: timestamp
```

### 🎨 Estrutura visual (exemplo Bolinha)

```
[Header contextual]
  [‹]  Nova Sessão · Bolinha em campo

[Tipo de exercício]
  ⚽ Bolinha em campo
  Agilidade · Pliometria

[Campos adaptáveis pro exercício]

  REPETIÇÕES
  [10]
  [- +] (incremento ±1)

  DISTÂNCIA (m)
  [50]
  [- +] (incremento ±5)

  PADRÃO
  ○ Linha reta
  ● Diagonais
  ○ Curvas

  DURAÇÃO TOTAL
  [25] min

  LOCAL
  ○ Canil
  ● Externo
    📍 Praça Toledo Barros
    [GPS rastreado · 480m percorridos]

[Switch GPS]
  Rastrear GPS  [ON]

[Aviso de lesão]
  ⚠ Notou algo? → [Registrar evento de saúde]

[Observações]
  ┌────────────────────────────────────────┐
  │ Bono executou com excelência ...       │
  └────────────────────────────────────────┘

[CTA sticky]
  [✓ SALVAR SESSÃO]
```

### 🔧 Estrutura técnica

- **Campos variáveis** por tipo de exercício
- **Esteira:** velocidade (km/h) + tempo (min)
- **Bolinha:** repetições + distância + padrão
- **Tração c/peso:** peso (kg) + duração
- **Escalada:** altura + duração
- **Switch GPS:** opcional pra exercícios externos
- **Banner de lesão** sempre presente

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Campos numéricos | Teclado numérico com botões ± |
| Radio de padrão/local | Selecionável |
| Switch GPS | Liga/desliga rastreamento |
| Banner "Notou algo?" | → Tela 3.15 (seletor de evento de saúde) com tipo "sintoma observado" pré-selecionado |
| "SALVAR SESSÃO" | Salva e volta |

### 🚨 Estados especiais

- **GPS negado:** desabilita switch · mostra "Permissão GPS necessária"
- **Exercício customizado:** campo de nome + campos genéricos (duração, intensidade subjetiva)

### ⚙️ Regras de negócio

- **Formulário adaptativo** baseado em `exercise_type`
- **GPS opcional** mas recomendado pra exercícios externos
- **Bono · Esteira tem preset** (2x2min velocidade máxima) — sugestão automática
- **Lesão suspeitada → evento de saúde separado** (sua decisão: só vet confirma lesão)

### 📊 Estado atual vs Novo

**O que muda:**
- 🔨 Tela nova
- 🔨 Formulário inteligente adaptativo
- 🔨 Suporte a GPS opcional
- 🔨 Integração com fluxo de saúde

---

# 🎯 BLOCO E — ESPECIALIDADE: BUSCA & CAPTURA

## TELA 3.6 — BUSCA & CAPTURA · FORMAÇÃO

### 📌 Identificação
- **Mockup de referência:** `06_formacao_bc.html`
- **Rota no app:** `/treino/busca-captura/formacao`
- **Prioridade:** ALTA

### 🚪 Como se chega
- Tap em card "Busca & Captura" do Hub quando `status == 'in_formation'`

### 🎯 Propósito
Estruturar a formação progressiva em Busca & Captura através de 3 módulos sequenciais. Mostra roadmap, módulo atual, histórico e estatísticas.

### 🗄️ Dados do Firestore

```
/dogs/{id}/specialties_state/busca_captura:
  status: 'in_formation'
  current_module: 1 | 2 | 3
  module_status: {
    m1: { started_at, sessions_count, completed_at? }
    m2: { ... }
    m3: { ... }
  }

/dogs/{id}/training_sessions:
  type: 'busca_captura_formacao'
  module: 1 | 2 | 3
  result: 'completa' | 'checagem' | 'perda_rastro'
  distance_m: number
  duration_minutes: number
```

### 🎨 Estrutura visual (4 abas)

```
[Header contextual]
  [‹]  Busca & Captura · Formação
       Bono · Módulo 2 ativo

[Tabs]
  [Roadmap] [Módulo atual] [Histórico] [Estatísticas]

═══ Tab "Roadmap" ═══

  ✓ MÓDULO 1 · PAREAMENTO
    Mata fechada · trilha 500m
    Concluído em 15/03/2026
  
  ▶ MÓDULO 2 · INDICAÇÕES ESTRUTURAIS
    Rasteira · ~100m
    Em andamento · 8 sessões
  
  ○ MÓDULO 3 · OPERACIONAL URBANO
    Até 3km
    Bloqueado

═══ Tab "Módulo atual" ═══

  MÓDULO 2 · INDICAÇÕES ESTRUTURAIS
  
  Objetivo: Cão localiza pista em terreno
  rasteiro até ~100m, com indicações
  estruturais consistentes.
  
  [Iniciar sessão]

═══ Tab "Histórico" ═══

  Lista cronológica das sessões

═══ Tab "Estatísticas" ═══

  Taxa de conclusão por tipo de resultado
  Distância média
  Duração média
  Evolução ao longo do tempo
```

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Tabs | Troca conteúdo |
| Tap em módulo do Roadmap | Vai pra tab "Módulo atual" se em andamento, ou mostra resumo se completo |
| "Iniciar sessão" | → tela de nova sessão B&C (com GPS) |
| Sessão do Histórico | Detalhe expandido |

### 🧭 Navegação de saída

- **‹ Voltar:** → `/treino`
- **Iniciar sessão:** → Tela 3.8 (Rastreador GPS)
- **Detalhe sessão:** → `/historico/training/{id}`

### ⚙️ Regras de negócio

- **Progressão linear:** M1 → M2 → M3
- **M2 só desbloqueia** quando M1 atinge critérios (X sessões com resultado "completa")
- **Resultados das sessões:**
  - `completa` — cão indicou alvo corretamente
  - `checagem` — cão indicou local incorreto (50-75m de erro)
  - `perda_rastro` — cão perdeu o rastro (100m+)
- **Critério de aprovação por módulo:** configurável (ex: 5 "completa" consecutivas)
- **Status muda pra `operational`** quando M3 é concluído

### 📊 Estado atual vs Novo

**O que muda:**
- 🔨 Estrutura por módulos sequenciais
- 🔨 Tabs internas (Roadmap, Módulo atual, Histórico, Estatísticas)
- 🔨 Lógica de progressão automática
- ⚠️ Atualizar `specialties_state.busca_captura` com module_status

---

## TELA 3.7 — BUSCA & CAPTURA · MANUTENÇÃO

### 📌 Identificação
- **Mockup de referência:** `08_manutencao_bc.html`
- **Rota no app:** `/treino/busca-captura/manutencao`
- **Prioridade:** ALTA

### 🚪 Como se chega
- Tap em card "Busca & Captura" do Hub quando `status == 'operational'`

### 🎯 Propósito
Sessão livre de manutenção pra cão já operacional. Sem módulos rígidos — escolhe terreno, distância, condições.

### 🗄️ Dados do Firestore

```
/dogs/{id}/training_sessions:
  type: 'busca_captura_manutencao'
  scenario: 'urbano' | 'rural' | 'mata'
  distance_target_m: number
  result: 'completa' | 'checagem' | 'perda_rastro'
  duration_minutes: number
  observations: string?
```

### 🎨 Estrutura visual

```
[Header contextual]
  [‹]  Busca & Captura · Manutenção
       Bono · operacional

[Última manutenção]
  Há 3 dias · Cenário urbano · 1.2km · Completa

[Nova sessão]
  
  CENÁRIO
  ○ Urbano
  ○ Rural
  ○ Mata fechada

  DISTÂNCIA ALVO
  [____] metros

  CONDIÇÕES
  ☐ Vento forte
  ☐ Multidão
  ☐ Pista contaminada

  [▶ INICIAR SESSÃO]

[Histórico recente]
  Lista das últimas 5 sessões
```

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Radio de cenário | Selecionável |
| Campo distância | Numérico |
| Checkboxes de condições | Multi-select |
| "INICIAR SESSÃO" | → Tela 3.8 (Rastreador GPS) |

### ⚙️ Regras de negócio

- **Sem módulos** — livre escolha de cenário
- **Condições registram dificuldade** pra análise posterior
- **Distância alvo opcional** mas recomendada
- **Resultado registrado ao finalizar** sessão GPS

---

## TELA 3.8 — RASTREADOR GPS (B&C AO VIVO)

### 📌 Identificação
- **Mockup de referência:** `07_rastreador.html`
- **Rota no app:** `/treino/busca-captura/sessao-ao-vivo`
- **Prioridade:** ALTA

### 🚪 Como se chega
- "▶ INICIAR SESSÃO" da Tela 3.6 (Formação) ou 3.7 (Manutenção)

### 🎯 Propósito
Tela ao vivo durante a sessão de B&C. Mapa GPS rastreando o trajeto, botões grandes pra marcar eventos importantes (Indicação, Checagem, Perda, Alvo), cronômetro.

### 🗄️ Dados do Firestore

**Em tempo real (Firestore stream):**
```
/dogs/{id}/training_sessions/{sessionId}:
  type: 'busca_captura_*'
  status: 'live' | 'finished'
  gps_track: [{lat, lng, timestamp, accuracy}]
  events: [{type, lat, lng, timestamp, label}]
  started_at: timestamp
```

### 🎨 Estrutura visual (3 estados)

**Estado 1 — Pré-trilha:**
```
[Header contextual]
  [‹]  Sessão · Pré-trilha

[Mapa centralizado]

[Configuração da pista]
  Ponto de partida: [📍 Atual]
  Ponto alvo: [Definir no mapa]

[Verificação]
  ✓ GPS ativo · precisão 4m
  ✓ Cão pareado
  ✓ Cronômetro pronto

[CTA]
  [▶ INICIAR SESSÃO AO VIVO]
```

**Estado 2 — Ao vivo (durante sessão):**
```
[Header minimalista]
  [⏱ 12:34]                          [⏸ Pausar]

[Mapa GRANDE com rastro em tempo real]

[Botões grandes na parte inferior]
  ┌────────┐ ┌────────┐
  │ 🔍 IND.│ │ ✋ CHEC│
  │ POSIT. │ │ KAGEM  │
  └────────┘ └────────┘
  ┌────────┐ ┌────────┐
  │ ⚠ PERD│ │ 🎯 ALVO│
  │  RASTR │ │ ENCONT │
  └────────┘ └────────┘

  [✓ FINALIZAR SESSÃO]
```

**Estado 3 — Pós-trilha:**
```
[Header contextual]
  Sessão concluída · 28min · 1.4km

[Mapa final com trajeto]

[Resumo]
  Distância: 1.4km
  Duração: 28min
  Velocidade média: 3km/h
  
  EVENTOS REGISTRADOS:
  10:15 · Indicação positiva
  10:23 · Checagem
  10:31 · Alvo encontrado

[Resultado da sessão]
  ○ Completa
  ● Checagem (erro de 60m)
  ○ Perda de rastro

[Observações]
  ┌────────────────────────────────────────┐

[CTA]
  [💾 SALVAR SESSÃO]
```

### 🔧 Estrutura técnica

- **Mapa:** `google_maps_flutter` ou `mapbox_gl`
- **GPS contínuo:** background location quando autorizado
- **Polyline animada:** trajeto se desenha em tempo real
- **Pins no mapa:** cada evento ganha pin com ícone
- **Cronômetro:** atualiza a cada segundo, persistente mesmo se app vai pra background
- **Salvamento offline:** GPS coletado mesmo sem internet, sincroniza depois

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| "▶ INICIAR" pré-trilha | Cria documento `status: 'live'` · começa rastreamento |
| Botão "INDICAÇÃO POSITIVA" | Adiciona evento ao track · pin no mapa |
| Botão "CHECAGEM" | Igual mas tipo diferente |
| Botão "PERDA DE RASTRO" | Igual |
| Botão "ALVO ENCONTRADO" | Adiciona evento + sugere finalizar |
| "⏸ PAUSAR" | Pausa GPS (relógio segue) |
| "FINALIZAR" | Para GPS · vai pro estado 3 |
| Radio de resultado | Define resultado final |
| "SALVAR SESSÃO" | Update final · volta pra Tela 3.6/3.7 |

### 🚨 Estados especiais

- **GPS negado:** modal "GPS necessário pra essa funcionalidade" + botão configurações
- **Bateria baixa:** banner "Bateria baixa · considere parar GPS pra economizar"
- **Sem sinal:** continua coletando local, mostra "Offline · 47 pontos salvos"
- **App vai pra background:** notificação persistente "Sessão em andamento · toque pra voltar"

### ⚙️ Regras de negócio

- **GPS em modo high accuracy** (5-10m precisão)
- **Frequência de coleta:** 1 ponto/segundo durante sessão ativa
- **Smoothing pós-finalização** pra suavizar trajeto
- **Mínimo 60s** pra sessão ser considerada válida
- **GPS contínuo consome bateria** — aviso ao iniciar
- **Track preservado mesmo offline**

### 📊 Estado atual vs Novo

**Estado atual:**
- ⚠️ Pode existir rastreamento básico mas sem essa estrutura

**O que muda:**
- 🔨 3 estados claros (pré/durante/pós)
- 🔨 4 botões grandes pra eventos importantes
- 🔨 Background tracking
- 🔨 Mapa interativo grande
- 🔨 Smoothing do trajeto

---

# 👃 BLOCO F — ESPECIALIDADE: DETECÇÃO (PROTOCOLO RAGONHA)

## TELA 3.9 — DETECÇÃO · TELA DE LINHAS

### 📌 Identificação
- **Mockup de referência:** `09_deteccao_v2.html` (parcial)
- **Rota no app:** `/treino/deteccao`
- **Prioridade:** ALTA

### 🚪 Como se chega
- Tap em card "Detecção" do Hub de Treinos

### 🎯 Propósito
Selecionar qual **linha de detecção** treinar. Cada cão pode ter múltiplas linhas paralelas (Drogas, Armas, Cadáver) em estados independentes. Sua arquitetura é única — o mesmo cão pode estar operacional em Drogas e em formação em Armas simultaneamente.

### 🗄️ Dados do Firestore

```
/dogs/{id}/specialties_state/deteccao:
  status: 'in_formation' | 'operational'  // status geral
  sub_lines: {
    drogas: {
      status: 'in_formation' | 'operational' | 'not_started',
      current_phase: 0 | 1 | 2 | 3 | 4 | 5,
      certification?: { issued_at, by, valid_until }
    },
    armas: { ... },
    cadaver: { ... }
  }
```

### 🎨 Estrutura visual

```
[Header contextual]
  [‹]  Detecção
       Bono · Protocolo Ragonha

[Resumo]
  3 linhas configuradas · 2 operacionais · 1 em formação

[Lista de linhas]

  ┌────────────────────────────────────────┐
  │ 💊 DROGAS                              │
  │ ● OPERACIONAL                          │
  │ Certificado externo válido · 11/2024   │
  │ Nose-MP: maconha, cocaína, crack,      │
  │ LSD, ecstasy, ópio, heroína, metanf.   │
  │                              CONTINUAR │
  └────────────────────────────────────────┘
  
  ┌────────────────────────────────────────┐
  │ 🔫 ARMAS                               │
  │ ● OPERACIONAL                          │
  │ Em manutenção · última há 5 dias       │
  │                              CONTINUAR │
  └────────────────────────────────────────┘
  
  ┌────────────────────────────────────────┐
  │ 🪦 CADÁVER                             │
  │ ◔ EM FORMAÇÃO · F3 desenvolvendo       │
  │ Próximo: Ponto de Virada (F3 → F4)    │
  │                              CONTINUAR │
  └────────────────────────────────────────┘

  [+ ADICIONAR NOVA LINHA]
```

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Tap em linha operacional | → Tela 3.11 (Manutenção) |
| Tap em linha em formação | → Tela 3.10 (Formação) |
| Botão "+ ADICIONAR NOVA LINHA" | Abre sub-modal de seleção de linha (ver Modal 3.17) |

### 🧭 Navegação de saída

- **Linha operacional:** → `/treino/deteccao/manutencao?linha=drogas` (Tela 3.11)
- **Linha em formação:** → `/treino/deteccao/formacao?linha=cadaver` (Tela 3.10)

### ⚙️ Regras de negócio

- **Cão pode estar em múltiplas linhas** com estados independentes
- **Linha "Drogas"** automaticamente inclui via Nose-MP: maconha, cocaína, crack, LSD, ecstasy, ópio, heroína, metanfetamina (tecnologia brasileira de Ribamar Pereira)
- **Outras linhas:** Armas e Cadáver (linhas separadas)
- **Status geral da Detecção** é `operational` se pelo menos 1 linha está operacional
- **Certificação externa** é evento separado dentro da linha

### 📊 Estado atual vs Novo

**O que muda:**
- 🔨 **Sistema completo de linhas paralelas** (NOVO)
- 🔨 Suporte a múltiplas linhas com estados independentes
- 🔨 Indicação da Nose-MP nas Drogas
- ⚠️ Estrutura `specialties_state.deteccao.sub_lines` (NOVA)

---

## TELA 3.10 — DETECÇÃO · FORMAÇÃO POR FASES

### 📌 Identificação
- **Mockup de referência:** `09_deteccao_v2.html` (formação)
- **Rota no app:** `/treino/deteccao/formacao?linha=X`
- **Prioridade:** ALTA — **núcleo pedagógico do app**

### 🚪 Como se chega
- Tap em linha em formação na Tela 3.9

### 🎯 Propósito
Tela do Protocolo Ragonha. Estrutura formação de detecção em 5 fases progressivas, com regras rígidas de progressão. **F3 é o ponto de virada crítico** (independência sem bola).

### 🗄️ Dados do Firestore

```
/dogs/{id}/specialties_state/deteccao/sub_lines/{linha}:
  current_phase: 0 | 1 | 2 | 3 | 4 | 5
  phase_progress: {
    f0: { completed_at, sessions_count }
    f1: { sessions_count, consecutive_hits, last_hit_at }
    f2: { sessions_count, consecutive_hits }
    f3: { sessions_count, consecutive_hits, current_streak }
    f4: { variants_completed: ['4a', '4b', '4c'] }
    f5: { sessions_count }
  }

/dogs/{id}/training_sessions:
  type: 'deteccao_formacao'
  linha: 'drogas' | 'armas' | 'cadaver'
  phase: number
  result: 'acerto' | 'erro'  // F1+
  variant?: '4a' | '4b' | '4c'  // F4
  environment?: string  // F5
```

### 🎨 Estrutura visual (5 tabs)

```
[Header contextual]
  [‹]  Detecção · Drogas · Formação
       Bono · Fase 2 ativa

[Tabs]
  [Roadmap] [Fase atual] [Sessões] [Estatísticas] [Documentos]

═══ Tab "Roadmap" ═══

  ✓ F0 · TRIAGEM
    Avaliação inicial · concluída
  
  ✓ F1 · ASSOCIAÇÃO
    3 acertos = 87.5% · concluída
  
  ▶ F2 · DISCRIMINAÇÃO
    Em andamento · 5 sessões
  
  ⭐ F3 · INDEPENDÊNCIA SEM BOLA
    PONTO DE VIRADA
    10 acertos consecutivos = 99,99983%
    Bloqueada
  
  ○ F4 · BUSCA SISTEMÁTICA (4 caixas)
    Variantes: 4A (estática), 4B (horário), 4C (anti-horário)
    Bloqueada
  
  ○ F5 · PROGRESSÃO AMBIENTAL
    Bloqueada

═══ Tab "Fase atual" ═══

  FASE 2 · DISCRIMINAÇÃO
  
  Objetivo: Cão diferencia o odor-alvo
  de odores distratores.
  
  Critério pra progressão: X acertos
  consecutivos sem erro.
  
  ESTATÍSTICAS:
  - Sessões: 5
  - Acertos consecutivos: 4 (de X)
  - Próximo erro zera contador!
  
  [▶ INICIAR NOVA SESSÃO]

═══ Tab "Sessões" ═══

  Lista cronológica

═══ Tab "Estatísticas" ═══

  Gráficos de evolução
  Taxa de acerto por fase
  Tempo médio por sessão

═══ Tab "Documentos" ═══

  Certificações externas
  Atestados de aprovação
  [+ ADICIONAR DOCUMENTO]
```

### 🔧 Estrutura técnica

- **Tabs:** Roadmap, Fase atual, Sessões, Estatísticas, Documentos
- **Visual de fases:** ícones especiais (estrela em F3 — ponto de virada)
- **Contador de "consecutivos":** super visível na fase atual
- **Aviso pré-erro:** se está perto do critério, mostra "Está perto! Não erre."

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Tabs | Troca conteúdo |
| Tap em fase do Roadmap | Detalhe da fase |
| "INICIAR NOVA SESSÃO" | → tela de sessão da fase atual |
| Tap em sessão da lista | Detalhe |
| "+ ADICIONAR DOCUMENTO" | Upload de PDF (certificado externo) |

### ⚙️ Regras de negócio (REGRAS DURAS DO PROTOCOLO RAGONHA)

**F0 — Triagem (Tela 3.12)**
- Separada das outras fases
- Decide se cão é apto pra continuar
- Se reprovado → recomendação de doação

**F1 — Associação**
- Cão aprende a associar odor com recompensa
- **3 acertos = 87,5% de confiança estatística**
- Erro zera contador, mas progride com poucos acertos

**F2 — Discriminação**
- Cão diferencia odor-alvo de distratores
- Erro zera contador

**F3 — INDEPENDÊNCIA SEM BOLA ⭐ PONTO DE VIRADA**
- Crítico: cão indica sem precisar de recompensa visual (bola)
- **10 acertos consecutivos = 99,99983% de confiança**
- **1 erro zera completamente o contador**
- É o filtro que separa cães prontos pra operação real

**F4 — Busca sistemática (4 caixas)**
- Cão busca em padrão estruturado
- 3 variantes:
  - **4A** — Caixas estáticas
  - **4B** — Horário (cão escolhe direção horária)
  - **4C** — Anti-horário
- Cada variante registrada separadamente

**F5 — Progressão ambiental**
- Ambientes reais (rua, veículos, malas)
- GPS pode ser ativado aqui (não nas fases anteriores)
- Certificação externa após F5 completa

**REGRAS GERAIS:**
- **1 erro zera contador consecutivo** em todas as fases
- **Linhas independentes** — Drogas e Armas progridem separadas
- **Multi-linha permitido** — pode treinar várias na mesma semana
- **Certificação externa** é evento documentado, não fase do app

### 📊 Estado atual vs Novo

**Estado atual:**
- ⚠️ Provavelmente NÃO existe sistema estruturado de fases

**O que muda:**
- 🔨 **Implementar Protocolo Ragonha completo** (NOVO)
- 🔨 Sistema de 5 fases com progressão
- 🔨 Contador de acertos consecutivos
- 🔨 Bloqueio de fases não atingidas
- 🔨 Subvariantes na F4
- 🔨 Tabs com Estatísticas e Documentos

---

## TELA 3.11 — DETECÇÃO · MANUTENÇÃO

### 📌 Identificação
- **Mockup de referência:** `15_manutencao_deteccao_obediencia.html` (tela 1)
- **Rota no app:** `/treino/deteccao/manutencao?linha=X`
- **Prioridade:** ALTA

### 🚪 Como se chega
- Tap em linha operacional na Tela 3.9

### 🎯 Propósito
Manter o cão treinado em uma linha operacional. Sessões mais livres, com cenários variados pra evitar perda de calibração.

### 🗄️ Dados do Firestore

```
/dogs/{id}/training_sessions:
  type: 'deteccao_manutencao'
  linha: 'drogas' | 'armas' | 'cadaver'
  scenario: 'veiculo' | 'mala' | 'ambiente_aberto' | 'multifoco'
  hits: number
  misses: number
  duration_minutes: number
  observations: string?
```

### 🎨 Estrutura visual

```
[Header contextual]
  [‹]  Detecção · Drogas · Manutenção
       Bono · operacional há 2 anos

[Última manutenção]
  Há 5 dias · Cenário veículos · 3/3 acertos

[Resumo recente · últimos 30d]
  6 sessões · 18/19 acertos · 94.7%

[Nova sessão]
  
  CENÁRIO
  ○ Veículo
  ○ Mala
  ○ Ambiente aberto
  ○ Multi-foco

  ALVO
  Quantidade de pistas: [____]
  Distratores: [____]

  [▶ INICIAR SESSÃO]

[Histórico recente]
  Lista das últimas 5 sessões
```

### ⚙️ Regras de negócio

- **Manutenção é livre** — sem progressão rígida
- **Calibração contínua** — taxa de acerto recente é o indicador-chave
- **Alerta se taxa cair abaixo de 90%** — sugere intensificar treino
- **GPS opcional** dependendo do cenário

---

## TELA 3.12 — TRIAGEM (FASE 0)

### 📌 Identificação
- **Mockup de referência:** ainda não mockado dedicadamente · pode usar estrutura geral
- **Rota no app:** `/treino/deteccao/triagem`
- **Prioridade:** MÉDIA

### 🚪 Como se chega
- Da Tela 3.10 (Formação) quando `current_phase == 0`
- Ao iniciar nova linha (Modal 3.17 com linha de Detecção)

### 🎯 Propósito
Avaliar se o cão tem perfil pra Detecção. Decisão institucional importante: cão reprovado pode ser doado (sua decisão na arquitetura).

### 🗄️ Dados do Firestore

```
/dogs/{id}/triagem_evaluations/{id}:
  type: 'deteccao_triagem'
  linha: 'drogas' | 'armas' | 'cadaver'
  evaluator: uid
  scores: {
    drive_pra_bola: 0-10,
    foco: 0-10,
    persistencia: 0-10,
    independencia: 0-10,
    nervo: 0-10
  }
  total_score: 0-50
  result: 'apto' | 'reprovado' | 'reavaliar'
  observations: string
  decision: 'continuar_formacao' | 'reavaliar_em_X' | 'sugerir_doacao'
  decided_at: timestamp
```

### 🎨 Estrutura visual

```
[Header contextual]
  [‹]  Triagem · Detecção · Drogas
       Bono · Avaliação inicial

[Aviso institucional]
  ⚠ Esta avaliação determina se Bono
  prosseguirá na formação. Reprovação
  pode resultar em recomendação de
  redirecionamento.

[Avaliação · 5 critérios]
  
  DRIVE PRA BOLA
  [○ ○ ○ ○ ○ ○ ○ ○ ○ ○]
   0  1  2  ...        10
  
  FOCO
  [...]
  
  PERSISTÊNCIA
  [...]
  
  INDEPENDÊNCIA
  [...]
  
  NERVO
  [...]

[Resumo]
  Pontuação total: 35/50
  Sugestão: ✓ APTO

[Decisão]
  ● Continuar formação (F1)
  ○ Reavaliar em 30 dias
  ○ Sugerir redirecionamento

[Observações]
  ┌────────────────────────────────────────┐

[CTA]
  [💾 REGISTRAR TRIAGEM]
```

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Sliders/seletores (0-10) | Define cada critério |
| Resultado calculado | Soma automática |
| Decisão | Radio buttons |
| "REGISTRAR" | Salva avaliação · atualiza `current_phase` se aprovado |

### ⚙️ Regras de negócio

- **Critérios sugeridos:**
  - Score total ≥ 35: APTO
  - Score 25-34: REAVALIAR
  - Score < 25: REPROVADO

- **Decisão é manual** — instrutor pode ignorar sugestão (registra divergência)
- **Reprovação documenta** com observações
- **Múltiplas triagens permitidas** (caso de reavaliação)
- **Triagem por linha** — Bono pode ser apto pra Drogas e reprovado pra Cadáver

### 📊 Estado atual vs Novo

**O que muda:**
- 🔨 Tela inteira nova
- 🔨 Sistema de scoring
- 🔨 Decisão institucional registrada
- ⚠️ Criar coleção `/dogs/{id}/triagem_evaluations` (NOVA)

---

# 🛡 BLOCO G — ESPECIALIDADE: GUARDA & PROTEÇÃO

## TELA 3.13 — GUARDA & PROTEÇÃO · FORMAÇÃO

### 📌 Identificação
- **Mockup de referência:** `12_guarda_protecao.html`
- **Rota no app:** `/treino/guarda-protecao/formacao`
- **Prioridade:** ALTA

### 🚪 Como se chega
- Tap em card "Guarda & Proteção" do Hub quando `status == 'in_formation'`

### 🎯 Propósito
Estruturar formação em Guarda & Proteção através de **3 impulsos paralelos** (Caça, Defesa, Agressão), cada um com seus estados próprios. Diferente de Detecção (que tem fases sequenciais), G&P tem progressão por impulsos que se desenvolvem em paralelo.

### 🗄️ Dados do Firestore

```
/dogs/{id}/specialties_state/guarda_protecao:
  status: 'in_formation' | 'operational'
  impulsos: {
    caca: {
      status: 'not_started' | 'opening' | 'developing' | 'consolidated',
      capabilities: ['material_inicial', 'mordida_firme', 'boca_cheia', ...],
      session_count: number,
      last_session_at: timestamp
    },
    defesa: { ... },
    agressao: { ... }
  }
  commands_specialty: {
    larga: stage,
    atencao_latir: stage
  }
```

### 🎨 Estrutura visual (4 tabs)

```
[Header contextual]
  [‹]  Guarda & Proteção · Formação
       Bono · 2 impulsos em desenvolvimento

[Tabs]
  [Trilhas] [Impulso atual] [Sessões] [Estatísticas]

═══ Tab "Trilhas" · 3 impulsos paralelos ═══

  ┌────────────────────────────────────────┐
  │ 🦌 CAÇA                                │
  │ ● CONSOLIDADO                          │
  │ Base prazerosa estabelecida            │
  │ 12 sessões · última há 3 dias          │
  └────────────────────────────────────────┘
  
  ┌────────────────────────────────────────┐
  │ 🛡 DEFESA                              │
  │ ◑ DESENVOLVENDO                        │
  │ Aberto há 1 mês · confronto direto    │
  │ 5 sessões · última há 5 dias           │
  └────────────────────────────────────────┘
  
  ┌────────────────────────────────────────┐
  │ ⚔ AGRESSÃO                            │
  │ ○ NÃO INICIADO                         │
  │ Aguardando consolidação dos outros     │
  └────────────────────────────────────────┘

[Capacidades · evolução]
  ✓ Material inicial
  ✓ Mordida firme
  ◑ Boca cheia (desenvolvendo)
  ○ Estabilização (não iniciado)
  ○ Mangas (jovem · adulta)
  ○ Traje
  ○ Vara

[Comandos da especialidade]
  Larga: ●●●●○ consolidado
  Atenção (latir): ●●●○○ desenvolvendo

[CTA]
  [▶ NOVA SESSÃO COM FIGURANTE]
```

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Tabs | Troca conteúdo |
| Tap em card de impulso | Detalhe + opções de avaliação |
| Tap em capacidade | Detalhe + opção de atualizar |
| "NOVA SESSÃO" | → Tela 3.14 (Sessão com figurante) |

### ⚙️ Regras de negócio (GUARDA & PROTEÇÃO — 3 IMPULSOS)

**🦌 CAÇA** — Equipamento se move
- Base prazerosa
- Cão persegue, captura, retorna
- Abre primeiro
- Estado de consolidação progride por experiência

**🛡 DEFESA** — Confronto direto
- Cão protege território/condutor
- Abre após maturação da Caça
- Foco no controle do cão

**⚔ AGRESSÃO** — Parceiro de luta
- Cão luta ativamente
- Entra por último
- Maior responsabilidade institucional

**4 ESTADOS por impulso:**
- `not_started` (cinza)
- `opening` (vermelho)
- `developing` (laranja)
- `consolidated` (verde)

**CAPACIDADES (progressão paralela):**
- Material inicial
- Mordida firme
- Boca cheia
- Estabilização
- Mangas (jovem · adulta)
- Traje (completo)
- Vara

**COMANDOS DA ESPECIALIDADE:**
- **Larga!** — crítico pra controle
- **Atenção!** (latir) — alerta sem agressão

**AVALIAÇÃO SUBJETIVA DO FIGURANTE** — pessoa que veste a manga e atua como "agressor" controlado.

### 📊 Estado atual vs Novo

**O que muda:**
- 🔨 Sistema de 3 impulsos paralelos
- 🔨 4 estados por impulso
- 🔨 Catálogo de capacidades
- 🔨 Comandos da especialidade integrados
- ⚠️ Estrutura `specialties_state.guarda_protecao.impulsos` (NOVA)

---

## TELA 3.14 — SESSÃO COM FIGURANTE

### 📌 Identificação
- **Mockup de referência:** `12_guarda_protecao.html` (tela 3)
- **Rota no app:** `/treino/guarda-protecao/sessao`
- **Prioridade:** ALTA

### 🚪 Como se chega
- "▶ NOVA SESSÃO COM FIGURANTE" da Tela 3.13

### 🎯 Propósito
Registrar sessão prática com figurante. Captura quem é o figurante, qual impulso, capacidades trabalhadas, avaliação subjetiva, pagamento por sessão.

### 🗄️ Dados do Firestore

```
/dogs/{id}/training_sessions:
  type: 'guarda_protecao_sessao'
  figurante_uid: string  // outro user
  impulso_focused: 'caca' | 'defesa' | 'agressao'
  capabilities_trained: ['mordida_firme', 'boca_cheia', ...]
  equipment: ['manga_jovem' | 'manga_adulta' | 'traje' | 'vara']
  payment_type: 'caca_padrao' | 'defesa' | 'agressao' | 'sem_pagamento'
  figurante_evaluation: {
    overall_score: 0-10,
    notes: string
  }
  duration_minutes: number
  observations: string?
  created_by: uid
  created_at: timestamp
```

### 🎨 Estrutura visual

```
[Header contextual]
  [‹]  Sessão com Figurante
       Bono · Guarda & Proteção

[Configuração]
  
  FIGURANTE
  [Selecionar pessoa ▼]
  
  IMPULSO FOCADO
  ○ 🦌 Caça
  ● 🛡 Defesa
  ○ ⚔ Agressão
  
  EQUIPAMENTO
  ☐ Manga jovem
  ☑ Manga adulta
  ☐ Traje completo
  ☐ Vara
  
  CAPACIDADES TRABALHADAS
  ☑ Mordida firme
  ☑ Boca cheia
  ☐ Estabilização
  ...

[Pagamento]
  TIPO DE PAGAMENTO
  ● Caça padrão (recompensa visual)
  ○ Defesa
  ○ Agressão
  ○ Sem pagamento (independência)

[Avaliação do figurante]
  PONTUAÇÃO GERAL (0-10)
  [    7    ]
  
  NOTAS DO FIGURANTE
  ┌────────────────────────────────────────┐
  │ Cão demonstrou boa contenção no...    │
  └────────────────────────────────────────┘

[Observações do condutor]
  ┌────────────────────────────────────────┐

[CTA]
  [✓ SALVAR SESSÃO]
```

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Selecionar figurante | Modal com lista de usuários ou input livre |
| Radio impulso | Seleciona um |
| Checkboxes equipamento | Multi-select |
| Checkboxes capacidades | Multi-select |
| Radio pagamento | Seleciona um |
| Slider 0-10 | Pontuação |
| "SALVAR" | Registra sessão · atualiza estados se aplicável |

### ⚙️ Regras de negócio

- **Figurante pode ser outro condutor ou pessoa externa**
- **Avaliação subjetiva** registrada com nota e observações
- **Pagamento por sessão** afeta perfil de treino:
  - `caca_padrao`: recompensa visual (bola/material)
  - `defesa`: sem recompensa visual, ativação por confronto
  - `agressao`: parceiro de luta, sem recompensa
  - `sem_pagamento`: testar independência
- **Capacidades trabalhadas** podem atualizar estado do impulso (manual ou automático)

### 📊 Estado atual vs Novo

**O que muda:**
- 🔨 Sistema de figurantes
- 🔨 Configuração multi-dimensional (impulso + equipamento + capacidades)
- 🔨 Avaliação subjetiva
- 🔨 Tipos de pagamento por sessão

---

# ⚕ BLOCO H — SAÚDE

## TELA 3.15 — SELETOR DE TIPO DE EVENTO DE SAÚDE

### 📌 Identificação
- **Mockup de referência:** `18_evento_saude.html` (tela 1)
- **Rota no app:** `/registrar/saude`
- **Prioridade:** ALTA

### 🚪 Como se chega
- CTA "⚕ REGISTRAR EVENTO DE SAÚDE" do Prontuário
- Tap em card "⚕ Saúde" do acesso rápido do Dashboard
- Tap em banner "Notou algo?" durante sessão de Condicionamento

### 🎯 Propósito
Tela seletora pra escolher qual tipo de evento de saúde registrar. 8 categorias com aviso institucional especial pra sintomas observados (sua decisão: condutor não diagnostica, só observa).

### 🗄️ Dados do Firestore

Apenas leitura de tipos (pode ser hardcoded ou via coleção `/health_event_types`).

### 🎨 Estrutura visual

```
[Header contextual]
  [‹]  Registrar Evento de Saúde
       Bono · 14/05/2026

[Grid 2x4 de tipos]

  ┌──────────┬──────────┐
  │ 💉       │ 🛡       │
  │ Vacinação│ Antipara-│
  │  (verde) │  sitário │
  │          │  (roxo)  │
  ├──────────┼──────────┤
  │ 🔬       │ ⚕       │
  │ Exame    │ Consulta │
  │ (azul)   │ (ciano)  │
  ├──────────┼──────────┤
  │ 💊       │ ⚠       │
  │ Medicação│ Sintoma  │
  │ (amarelo)│ observado│
  │          │ (vermelh)│
  ├──────────┼──────────┤
  │ ✂       │ 📋       │
  │ Cirurgia │ Outro    │
  │ (laranja)│ (cinza)  │
  └──────────┴──────────┘

[Aviso institucional em Sintomas]
  ⚠ Condutor registra sintomas observados.
  Diagnóstico de lesão ou condição médica
  é responsabilidade exclusiva do veterinário.
```

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Tap em qualquer card | → Tela 3.16 com tipo pré-selecionado |

### 🧭 Navegação de saída

- **‹ Voltar:** → tela anterior
- **Tap em card:** → `/registrar/saude/formulario?tipo=X` (Tela 3.16)

### ⚙️ Regras de negócio

- **8 categorias fixas** (não configuráveis pelo condutor)
- **Aviso institucional só aparece** no card de "Sintoma observado"
- **Cores semânticas distintas** pra cada categoria

### 📊 Estado atual vs Novo

**O que muda:**
- 🔨 Grid visual com 8 categorias
- 🔨 Cores semânticas
- 🔨 Aviso institucional em sintomas

---

## TELA 3.16 — FORMULÁRIO DE EVENTO DE SAÚDE

### 📌 Identificação
- **Mockup de referência:** `18_evento_saude.html` (tela 2)
- **Rota no app:** `/registrar/saude/formulario?tipo=X`
- **Prioridade:** ALTA

### 🚪 Como se chega
- Tap em qualquer card da Tela 3.15

### 🎯 Propósito
Formulário adaptativo por tipo de evento. Cada tipo tem campos específicos. **Antiparasitário tem regra especial:** próxima dose VAZIA por padrão (varia muito por medicamento).

### 🗄️ Dados do Firestore

```
/dogs/{id}/health_events/{id}:
  type: 'vaccination' | 'antiparasitic' | 'exam' | 'consultation' 
       | 'medication' | 'symptom' | 'surgery' | 'other'
  subtype: string  // V10, Bravecto, Hemograma, etc
  applied_at: timestamp
  next_due_date: timestamp?  // OPCIONAL · varia por tipo
  professional: {
    name: string,
    crmv: string,
    clinic: string
  }
  attachment_url: string?  // PDF anexo
  observations: string?
  cost_brl: number?  // opcional
  created_by: uid
```

### 🎨 Estrutura visual (exemplo Antiparasitário - Bravecto)

```
[Header contextual]
  [‹]  Antiparasitário
       Bono · 14/05/2026

[Form scroll]

  MEDICAMENTO
  [Bravecto ▼]
  
  PRINCÍPIO ATIVO (preenchido auto)
  Fluralaner

  DATA DE APLICAÇÃO
  [Hoje · 14/05/2026]

  PRÓXIMA DOSE  ← VAZIO por padrão (sua decisão)
  [_________________]
  
  💡 Bravecto: dose trimestral.
     Próxima dose sugerida: 14/08/2026
     [Aplicar sugestão]

  RESPONSÁVEL
  ● Condutor (você)
  ○ Veterinário
    Nome: [______]
    CRMV: [______]

  ANEXO (recomendado)
  [📎 Anexar PDF/foto]

  OBSERVAÇÕES
  ┌────────────────────────────────────────┐

[CTA]
  [✓ REGISTRAR EVENTO]
```

### 🔧 Estrutura técnica

- **Form adaptativo por tipo:**
  - Vacinação: subtipo (V10/Raiva/...), lote, validade, veterinário obrigatório, **próxima dose auto-calculada**
  - Antiparasitário: medicamento, **próxima dose VAZIA**, condutor pode aplicar
  - Exame: tipo (hemograma/raio-x/...), local, resultado anexo
  - Consulta: motivo, veterinário, diagnóstico, prescrição
  - Medicação: nome, dosagem, frequência, duração
  - Sintoma: descrição detalhada, gravidade subjetiva (1-5), foto opcional
  - Cirurgia: tipo, hospital, anestesia, recuperação prevista
  - Outro: campos livres

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Dropdown medicamento | Lista pré-definida + "Outro" |
| "Aplicar sugestão" | Preenche próxima dose com sugestão |
| Radio responsável | Mostra/esconde campos do veterinário |
| Botão "Anexar" | Galeria · câmera · arquivos |
| "REGISTRAR EVENTO" | Salva · volta pra tela anterior |

### ⚙️ Regras de negócio

- **Próxima dose por tipo:**
  - Vacinação: auto-calculada (V10 = +12 meses, Raiva = +12 meses)
  - Antiparasitário: **VAZIA por padrão** (varia por medicamento)
    - Bravecto: sugestão +3 meses
    - NexGard: sugestão +1 mês
    - Simparic: sugestão +1 mês
    - Frontline: sugestão +1 mês
    - **Condutor confirma manualmente** (sua decisão)
  - Outros: sem próxima dose automática

- **Anexo recomendado mas não obrigatório**
- **Veterinário obrigatório em:** Vacinação, Exame, Consulta, Cirurgia
- **Veterinário opcional em:** Antiparasitário, Medicação, Sintoma, Outro
- **Sintoma observado:** aviso visível no form de que não é diagnóstico

### 📊 Estado atual vs Novo

**Estado atual:**
- ⚠️ Provavelmente existe registro genérico mas sem adaptação

**O que muda:**
- 🔨 Form adaptativo por tipo
- 🔨 **Lógica especial de próxima dose** (antiparasitário fica vazio)
- 🔨 Sistema de anexos
- 🔨 Campos condicionais por tipo

---

# 🪟 BLOCO I — MODAIS AUXILIARES

## MODAL 3.17 — ADICIONAR NOVA ESPECIALIDADE

### 📌 Identificação
- **Mockup de referência:** `16_modais_auxiliares.html` (modal 1)
- **Localização sugerida:** `core/widgets/add_specialty_modal.dart`
- **Prioridade:** MÉDIA

### 🚪 Como se chega
- Botão "+ INICIAR NOVA ESPECIALIDADE" do Hub de Treinos
- Botão "+ ADICIONAR NOVA LINHA" da Tela de Linhas da Detecção

### 🎯 Propósito
Modal pra iniciar formação em especialidade ainda `not_started`. Se for Detecção, abre sub-modal com seleção de linha.

### 🎨 Estrutura visual

```
[Backdrop escurecido]

  ┌─────────────────────────────────────┐
  │  [handle drag]                       │
  │                                       │
  │  Iniciar nova especialidade           │
  │  Bono ainda não tem essa especialid.. │
  │                                       │
  │  ○ 🎯 Busca & Captura                │
  │     Trabalho com rastreio em terreno  │
  │                                       │
  │  ○ 👃 Detecção                       │
  │     Identificação de odores-alvo      │
  │     (escolha a linha após confirmar) │
  │                                       │
  │  ○ 🛡 Guarda & Proteção              │
  │     Trabalho com figurante            │
  │                                       │
  │  [CONTINUAR]    [Cancelar]            │
  └─────────────────────────────────────┘

  Se Detecção selecionada · sub-modal:
  
  ┌─────────────────────────────────────┐
  │  Linha de Detecção                    │
  │                                       │
  │  ○ 💊 Drogas (Nose-MP)               │
  │     Inclui: maconha, cocaína, crack,  │
  │     LSD, ecstasy, ópio, heroína,      │
  │     metanfetamina                     │
  │                                       │
  │  ○ 🔫 Armas                          │
  │  ○ 🪦 Cadáver                        │
  │                                       │
  │  [INICIAR FORMAÇÃO]   [Cancelar]      │
  └─────────────────────────────────────┘
```

### ⚙️ Regras de negócio

- **Filtra especialidades já iniciadas** (não aparecem na lista)
- **Detecção tem sub-modal** com seleção de linha
- **Início cria entrada em `specialties_state`** com `status: 'in_formation'`, `current_phase: 0` (pra detecção · vai pra Triagem)

---

## MODAL 3.18 — ADICIONAR COMANDO (OBEDIÊNCIA)

### 📌 Identificação
- **Mockup de referência:** `16_modais_auxiliares.html` (modal 3)
- **Localização sugerida:** `core/widgets/add_command_modal.dart`
- **Prioridade:** MÉDIA

### 🚪 Como se chega
- Botão [+] no header da Tela 3.2 (Biblioteca de Comandos)

### 🎨 Estrutura visual

```
[Backdrop escurecido]

  ┌─────────────────────────────────────┐
  │  Novo comando                         │
  │                                       │
  │  NOME DO COMANDO                      │
  │  [Aporta!____________________]        │
  │                                       │
  │  CATEGORIA                            │
  │  ● Operacional                        │
  │  ○ Posicional                         │
  │  ○ Postural                           │
  │  ○ Habilidade                         │
  │                                       │
  │  ESTÁGIO INICIAL                      │
  │  ●○○○○ Introduzido                   │
  │                                       │
  │  OBSERVAÇÕES                          │
  │  ┌─────────────────────────────────┐  │
  │  └─────────────────────────────────┘  │
  │                                       │
  │  [ADICIONAR]    [Cancelar]            │
  └─────────────────────────────────────┘
```

### ⚙️ Regras de negócio

- **Nome obrigatório**
- **Categoria obrigatória**
- **Estágio default: `introduzido`** (já tem o nome, então não é mais `nao_treinado`)
- **Observações opcionais**

---

## MODAL 3.19 — ATUALIZAR ESTÁGIO DO COMANDO

### 📌 Identificação
- **Mockup de referência:** `16_modais_auxiliares.html` (modal 4)
- **Localização sugerida:** `core/widgets/update_command_stage_modal.dart`
- **Prioridade:** MÉDIA

### 🚪 Como se chega
- Tap em comando da Tela 3.2 · escolher "Atualizar estágio"

### 🎨 Estrutura visual

```
[Backdrop escurecido]

  ┌─────────────────────────────────────┐
  │  Atualizar estágio                    │
  │  Comando: "Aporta!"                   │
  │                                       │
  │  ESTÁGIO ATUAL                        │
  │  ●●●○○ Em desenvolvimento             │
  │                                       │
  │  NOVO ESTÁGIO                         │
  │  ○ ○○○○○ Não treinado                │
  │  ○ ●○○○○ Introduzido                 │
  │  ● ●●○○○ Em desenvolvimento          │
  │  ○ ●●●●○ Consolidado                 │
  │  ○ ●●●●● Operacional                 │
  │                                       │
  │  Você pode marcar regressão se          │
  │  o cão perdeu calibração.             │
  │                                       │
  │  OBSERVAÇÕES (opcional)               │
  │  ┌─────────────────────────────────┐  │
  │  └─────────────────────────────────┘  │
  │                                       │
  │  [ATUALIZAR]    [Cancelar]            │
  └─────────────────────────────────────┘
```

### ⚙️ Regras de negócio

- **Permite regressão** (cão pode "perder" calibração)
- **Atualiza `stage_updated_at`**
- **Mantém histórico de mudanças** (subcoleção `commands/{id}/stage_history`)
- **Observações registram contexto** da mudança

---

# 📄 BLOCO J — PDFs AUXILIARES

## DOCUMENTO 3.20 — PDF DA CARTEIRA DE VACINAÇÃO

### 📌 Identificação
- **Mockup de referência:** `25_pdfs_auxiliares.html` (PDF 1)
- **Localização sugerida:** `core/services/pdf_generator/vaccination_pdf.dart`
- **Prioridade:** MÉDIA

### 🎯 Propósito
Documento institucional formal pra levar no veterinário ou auditoria sanitária. Formato digital moderno (não a carteira tradicional).

### 🗄️ Dados consumidos

- Toda a árvore `/dogs/{id}/health_events` filtrada por `type IN ['vaccination', 'antiparasitic']`
- Dados do cão

### 🎨 Estrutura (capa + páginas internas)

**Capa:**
- Brasão GCM
- "CARTEIRA DE VACINAÇÃO"
- Nome do cão
- Metadata (período · vacinas registradas · status · próxima)
- ID: VAC: 2026/05/0042-K9

**Páginas internas:**
- Aviso de próximas doses em destaque
- Tabela de histórico completo (Vacina · Data · Lote · Veterinário · Status)
- Lista de anexos
- Hash SHA-256 ao final

### 🔧 Estrutura técnica

- **Cor identidade:** ciano #0a8e9d
- **Tabela com zebra striping**
- **Status badges:** EM DIA (verde) · 15 DIAS (amarelo) · VENCIDA (vermelho)
- **Hash SHA-256** em integrity_mini ao final

---

## DOCUMENTO 3.21 — PDF DO HISTÓRICO DE PESO

### 📌 Identificação
- **Mockup de referência:** `25_pdfs_auxiliares.html` (PDF 2)
- **Localização sugerida:** `core/services/pdf_generator/weight_history_pdf.dart`
- **Prioridade:** MÉDIA

### 🎯 Propósito
Documento clínico de acompanhamento. Pra consulta veterinária ou auditoria nutricional.

### 🎨 Estrutura

**Capa:**
- Cor identidade: azul #2c6e91
- "HISTÓRICO DE PESO"
- Subtítulo: "42 PESAGENS · ÚLTIMOS 6 MESES"
- ID: PESO: 2026/05/0142-K9

**Páginas internas:**
- 4 boxes de estatísticas (Atual · Mín · Méd · Máx)
- Gráfico SVG da evolução com faixa ideal sombreada
- Tabela cronológica (Data · Peso · Variação · Registrado por)
- **Análise técnica em texto** (parágrafo automático sobre padrão observado)
- Hash SHA-256

---

## DOCUMENTO 3.22 — PDF DO RELATÓRIO NUTRICIONAL

### 📌 Identificação
- **Mockup de referência:** `25_pdfs_auxiliares.html` (PDF 3)
- **Localização sugerida:** `core/services/pdf_generator/nutrition_report_pdf.dart`
- **Prioridade:** ALTA — **DOCUMENTO DE DEFESA PROFISSIONAL**

### 🎯 Propósito
**Resolve o caso 800g vs 300g.** Documenta prescrição vigente, conformidade, divergências documentadas com motivos. Defesa institucional do condutor.

### 🎨 Estrutura

**Capa:**
- Cor identidade: laranja #c25e1f
- "RELATÓRIO NUTRICIONAL"
- Subtítulo: "90 DIAS · CONFORMIDADE 95%"
- ID: NUT: 2026/05/0089-K9

**Páginas internas:**
- **Prescrição vigente em box destacado** (laudo da Dra. Ana Souza + CRMV)
- **Card grande de conformidade** (95% em destaque + breakdown)
- Gráfico de barras com linha de prescrição
- **Tabela de divergências documentadas** (Data · Quantidade · Divergência · Justificativa)
- Hash SHA-256

### ⚙️ Decisões importantes

- **Linguagem institucional formal**
- **Divergências NÃO são apresentadas como falha** — são documentadas com transparência
- **Cada divergência mostra justificativa** registrada no momento
- **PDF defensivo:** quando questionado sobre nutrição, condutor entrega esse documento

---

## DOCUMENTO 3.23 — PDF DO HISTÓRICO MENSAL

### 📌 Identificação
- **Mockup de referência:** `25_pdfs_auxiliares.html` (PDF 4)
- **Localização sugerida:** `core/services/pdf_generator/monthly_history_pdf.dart`
- **Prioridade:** ALTA — prestação de contas mensal

### 🎯 Propósito
Relatório executivo do mês. Prestação de contas mensal do binômio. O "card de visita" do trabalho do condutor.

### 🎨 Estrutura

**Capa:**
- Cor identidade: roxo #5a4080
- "RELATÓRIO MENSAL · Maio 2026"
- Subtítulo: "BINÔMIO BONO · RAGONHA"
- ID: HIST: 2026/05/0012-K9

**Páginas internas:**
- 4 summary boxes (Plantões · Ocorrências · Treinos · Eventos de Saúde)
- Distribuição por categoria com dots e percentuais
- Timeline resumida agrupada por semana
- Eventos importantes em **negrito** (ocorrências · divergências)
- Hash SHA-256

### ⚙️ Quando é gerado

- **Botão "Exportar PDF" do Histórico** quando filtro mensal está aplicado
- Pode ser **agendado automaticamente** mensalmente (futuro)

---

## 🎯 RESUMO DE PRIORIDADES PARTE 3

| Item | Prioridade | Esforço estimado |
|------|-----------|------------------|
| 3.1 Hub de Treinos | ALTA | Médio (3 dias) |
| 3.2 Obediência (Biblioteca) | ALTA | Alto (4 dias) |
| 3.3 Sessão de Obediência | ALTA | Médio (2 dias) |
| 3.4 Condicionamento (Visão) | MÉDIA | Médio (2 dias) |
| 3.5 Nova Sessão Condicionamento | MÉDIA | Médio (3 dias) |
| 3.6 B&C Formação | ALTA | Alto (4 dias) |
| 3.7 B&C Manutenção | ALTA | Médio (2 dias) |
| 3.8 Rastreador GPS | ALTA | Muito alto (6-8 dias) |
| 3.9 Detecção Linhas | ALTA | Médio (2 dias) |
| 3.10 Detecção Formação | ALTA | **Muito alto (7-10 dias)** ← Protocolo Ragonha |
| 3.11 Detecção Manutenção | ALTA | Médio (2 dias) |
| 3.12 Triagem (F0) | MÉDIA | Médio (3 dias) |
| 3.13 Guarda & Proteção Formação | ALTA | Alto (4 dias) |
| 3.14 Sessão com Figurante | ALTA | Médio (3 dias) |
| 3.15 Seletor Saúde | ALTA | Baixo (1 dia) |
| 3.16 Form Saúde adaptativo | ALTA | Alto (5 dias) |
| 3.17 Modal Especialidade | MÉDIA | Baixo (1 dia) |
| 3.18 Modal Comando | MÉDIA | Baixo (1 dia) |
| 3.19 Modal Estágio | MÉDIA | Baixo (1 dia) |
| 3.20 PDF Vacinação | MÉDIA | Médio (3 dias) |
| 3.21 PDF Peso | MÉDIA | Médio (3 dias) |
| 3.22 PDF Nutricional | ALTA | Médio (3 dias) |
| 3.23 PDF Histórico Mensal | ALTA | Médio (3 dias) |

**Total estimado da Parte 3:** ~12-15 semanas de trabalho focado (parte mais densa do app).

---

## 📌 ORDEM DE IMPLEMENTAÇÃO SUGERIDA

```
SEMANA 1-2: Bloco D - Hub + Obediência (3.1, 3.2, 3.3)
SEMANA 3-4: Bloco D - Condicionamento (3.4, 3.5)
SEMANA 5-6: Bloco E - Busca & Captura (3.6, 3.7) + começar Rastreador
SEMANA 7-8: Bloco E - Rastreador GPS (3.8) ← MARCO TÉCNICO
SEMANA 9-11: Bloco F - Detecção · Protocolo Ragonha (3.9, 3.10, 3.11, 3.12) ← NÚCLEO PEDAGÓGICO
SEMANA 12: Bloco G - Guarda & Proteção (3.13, 3.14)
SEMANA 13: Bloco H - Saúde (3.15, 3.16) + Modais (3.17, 3.18, 3.19)
SEMANA 14-15: Bloco J - PDFs auxiliares (3.20, 3.21, 3.22, 3.23)
```

---

## ⚠️ COLEÇÕES FIRESTORE NOVAS PARA PARTE 3

| Coleção | Status | Decisão |
|---------|--------|---------|
| `/dogs/{id}/specialties_state` | NOVA | Criar (atualizar todas as 3 sub-docs) |
| `/dogs/{id}/commands` | NOVA | Criar (biblioteca de comandos por cão) |
| `/dogs/{id}/commands/{id}/stage_history` | NOVA | Criar (subcoleção de histórico de mudanças) |
| `/dogs/{id}/conditioning_sessions` | NOVA | Criar |
| `/dogs/{id}/triagem_evaluations` | NOVA | Criar |
| `/dogs/{id}/training_sessions` | EXISTENTE? | Verificar, adicionar campos `linha`, `phase`, `module`, `impulso`, etc |
| `/users` (para figurantes) | EXISTENTE | Pode adicionar role `figurante` |

---

## 🎯 MARCOS TÉCNICOS DA PARTE 3

1. **Marco 1 (Semana 4):** Hub + Treinos Gerais funcionando → cão pode treinar Obediência e Condicionamento básico
2. **Marco 2 (Semana 8):** Rastreador GPS funcional → primeira especialidade (B&C) com tracking ao vivo
3. **Marco 3 (Semana 11):** Protocolo Ragonha implementado → **núcleo pedagógico do app** completo
4. **Marco 4 (Semana 13):** Sistema de saúde completo → registro de eventos médicos
5. **Marco 5 (Semana 15):** PDFs auxiliares prontos → app pode emitir todos os documentos institucionais

---

## 🏁 CONCLUSÃO DAS 3 PARTES

Com as 3 partes completas, o app cobre:

**Parte 1 (Fundação):** 8 telas · entrada, identidade, navegação
**Parte 2 (Operacional):** 12 telas · ocorrências, histórico, prontuário
**Parte 3 (Treinos e Saúde):** 23 telas/documentos · sistema completo de treinos + saúde

**Total: ~43 telas, componentes e documentos especificados**

**Cronograma total estimado:** ~6-7 meses de desenvolvimento focado (1 desenvolvedor full-time).

---

## 📋 CHECKLIST DE PREPARAÇÃO PARA O DESENVOLVIMENTO

Antes de começar a desenvolver qualquer parte, verificar:

- [ ] Etapa 1 do `ROADMAP_REFATORACAO.txt` concluída (limpeza técnica)
- [ ] Sistema visual do `core/theme/` atualizado com tokens dos mockups
- [ ] Pacotes pubspec verificados:
  - [ ] `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`, `firebase_app_check`
  - [ ] `local_auth: ^2.3.0`
  - [ ] `flutter_secure_storage: ^10.0.0`
  - [ ] `google_maps_flutter` ou `mapbox_gl`
  - [ ] `pdf` + `printing`
  - [ ] `qr_flutter`
  - [ ] `crypto`
  - [ ] `speech_to_text` (já tem)
  - [ ] `image_picker`
  - [ ] `intl`
  - [ ] `geolocator`

- [ ] Estrutura de pastas reorganizada (features/ unificadas)
- [ ] Coleções Firestore novas criadas com regras de segurança
- [ ] Painel web React validado pra continuar funcionando após refatoração

---

**FIM DA PARTE 3 · 23 telas/documentos especificados**

**FIM DA ESPECIFICAÇÃO TÉCNICA COMPLETA · 43 itens em 3 partes**
