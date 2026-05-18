# 📘 ESPECIFICAÇÃO TÉCNICA — PARTE 2

## App Canil K9 GCM Limeira — Domínios Operacionais

> Documento técnico de referência para implementação no Claude Code.
> Cobre Ocorrências (fluxo completo), Histórico, Prontuário do Cão e sub-telas detalhadas.

---

## 📋 ÍNDICE DA PARTE 2

### Bloco A — Ocorrências
1. [Tela 2.1 — Iniciar Ocorrência](#tela-21--iniciar-ocorrência)
2. [Tela 2.2 — Ocorrência em Andamento](#tela-22--ocorrência-em-andamento)
3. [Tela 2.3 — Edição de Evento](#tela-23--edição-de-evento)
4. [Tela 2.4 — Wizard de Finalização (3 passos)](#tela-24--wizard-de-finalização)
5. [Tela 2.5 — Confirmação Final](#tela-25--confirmação-final)
6. [Documento 2.6 — PDF da Ocorrência](#documento-26--pdf-da-ocorrência)

### Bloco B — Histórico
7. [Tela 2.7 — Histórico (Lista Filtrada)](#tela-27--histórico-lista-filtrada)
8. [Tela 2.8 — Detalhe Expandido do Histórico](#tela-28--detalhe-expandido-do-histórico)

### Bloco C — Cão/Prontuário
9. [Tela 2.9 — Cão / Prontuário](#tela-29--cão--prontuário)
10. [Tela 2.10 — Carteira de Vacinação Completa](#tela-210--carteira-de-vacinação-completa)
11. [Tela 2.11 — Histórico de Peso Completo](#tela-211--histórico-de-peso-completo)
12. [Tela 2.12 — Nutrição Completa](#tela-212--nutrição-completa)

---

# 🛡 BLOCO A — OCORRÊNCIAS

## TELA 2.1 — INICIAR OCORRÊNCIA

### 📌 Identificação
- **Mockup de referência:** `01_iniciar_ocorrencia.html`
- **Rota no app:** `/ocorrencia/iniciar`
- **Prioridade:** ALTA (uso operacional crítico)

### 🚪 Como se chega
- Tap no FAB 🛡 do Bottom Navigation
- Tap no card "🛡 Ocorrência" do acesso rápido do Dashboard
- Tap em alerta de retomar rascunho (caso haja ocorrência em finalização)

### 🎯 Propósito
Criar registro de ocorrência operacional rapidamente, com mínima fricção. Captura natureza, local e dados iniciais. Em poucos segundos o condutor tem tudo pronto pra começar a documentar.

### 🗄️ Dados do Firestore consumidos

**Leitura:**
| Coleção | Filtro | Campos |
|---------|--------|--------|
| `/users/{uid}` | usuário ativo | name, ra |
| `/dogs/{active_dog_id}` | cão ativo | name, photo_url |
| `/shifts/{active_shift_id}` | turno ativo | id |
| `/occurrence_types` (**NOVA**) | `active == true` | name, icon, color, default_fields |

**Escrita ao confirmar:**
| Coleção | Operação | Dados |
|---------|----------|-------|
| `/occurrences` | create | id (gerado), shift_id, primary_handler_id, dog_id, type, location, started_at, status: 'in_progress', created_at |

### 🎨 Estrutura visual

```
[Header contextual]
  [‹]  Nova Ocorrência  [✕]
       Bono · GCM Ragonha · 14/05 14:32

[Scroll area]

  NATUREZA DA OCORRÊNCIA
  ┌──────┬──────┬──────┐
  │ 🛡   │ 🚗   │ 🏠   │  
  │Patru-│Faro  │Vist. │
  │lha   │veíc. │residz│
  ├──────┼──────┼──────┤
  │ 🌳   │ 👤   │ 🔍   │
  │Busca │Apoio │Outra │
  │mata  │      │      │
  └──────┴──────┴──────┘

  LOCAL                                  [GPS]
  ┌────────────────────────────────────────┐
  │ 📍 Av. Brasil, 1245 · Centro          │
  │    -22.5642, -47.4019 · ± 4,2m         │
  │    ✓ GPS capturado · agora             │
  └────────────────────────────────────────┘
  
  [Editar local manualmente]

  HORÁRIO DE INÍCIO
  [Agora · 14:32] [Há 5min] [Há 15min] [Editar]

  OBSERVAÇÃO INICIAL · opcional
  ┌────────────────────────────────────────┐
  │ Acionamento via rádio · suspeita de... │
  └────────────────────────────────────────┘

[CTA sticky]
  [▶ INICIAR OCORRÊNCIA]
```

### 🔧 Estrutura técnica

- **Header contextual:** mostra binômio e timestamp, sem Header Universal
- **Grid 3x2 de naturezas:** cards 100x100, selecionado ganha borda ciano
- **GPS automático:** ao abrir a tela, tenta obter localização em background
- **Chips de horário:** "Agora", "Há 5min", "Há 15min", "Editar" (abre time picker)
- **CTA desabilitado** até natureza + local estarem preenchidos

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Botão ‹ | Pop · pergunta confirmação se há campos preenchidos |
| Botão ✕ | Pop direto · descarta dados (com confirmação se houver dados) |
| Card de natureza | Seleciona · destaca em ciano |
| Botão GPS | Re-captura localização |
| "Editar local manualmente" | Abre modal de edição (CEP + endereço completo) |
| Chips de horário | Define `started_at` (Agora = `DateTime.now()`, "Há 5min" = `now - 5min`, etc) |
| Campo Observação | Input multiline opcional |
| CTA "INICIAR" | Cria documento em `/occurrences` · navega pra `/ocorrencia/{id}/andamento` |

### 🧭 Navegação de saída

- **Após criar:** → `/ocorrencia/{id}/andamento` (Tela 2.2)
- **Cancelar:** → `/turno` (Dashboard)

### 🚨 Estados especiais

- **GPS negado/falhou:** mostra "GPS indisponível · preencha local manualmente" e botão de retry
- **Sem internet:** salva localmente, sincroniza depois (offline-first)
- **Já tem ocorrência em andamento:** modal "Você tem uma ocorrência em andamento. Finalizar ou continuar?"
- **Localização aproximada:** mostra precisão acima de ±50m com aviso amarelo

### ⚙️ Regras de negócio

- **Captura GPS automática** ao abrir (não bloqueia preenchimento)
- **Precisão GPS armazenada** junto com coordenadas pra defesa profissional
- **Naturezas configuráveis** via `/occurrence_types` (gestor pode editar no painel web)
- **started_at não pode ser futuro** — validação local
- **Endereço derivado de GPS** via geocoding reverso (Google Maps) se disponível
- **Status inicial:** `in_progress`
- **Sempre vinculado ao turno ativo** (`shift_id`)

### 📊 Estado atual vs Novo

**Estado atual:**
- ✅ Existe `features/occurrences/` (presumido pela estrutura)
- ⚠️ Implementação visual provavelmente diferente

**O que muda:**
- 🔨 Layout completo conforme mockup
- 🔨 Captura GPS automática
- 🔨 Chips de horário pra registrar retroativamente
- 🔨 Validação de campos antes de habilitar CTA
- 🔨 Geocoding reverso pra mostrar endereço legível
- ⚠️ Criar coleção `/occurrence_types` se não existir (NOVA)

---

## TELA 2.2 — OCORRÊNCIA EM ANDAMENTO

### 📌 Identificação
- **Mockup de referência:** `02_ocorrencia_andamento.html`
- **Rota no app:** `/ocorrencia/{id}/andamento`
- **Prioridade:** ALTA (centro operacional)

### 🚪 Como se chega
- Após criar nova ocorrência (Tela 2.1)
- Tap no banner "Ocorrência em andamento" do Dashboard
- Tap em rascunho de ocorrência no Histórico

### 🎯 Propósito
Documentar eventos da ocorrência em tempo real. Cada evento (chegada, abordagem, indicação do cão, apreensão, etc) vira um item da timeline. Auto-save permite que o condutor não perca dados se algo acontecer.

### 🗄️ Dados do Firestore consumidos

**Leitura:**
| Coleção | Filtro | Campos |
|---------|--------|--------|
| `/occurrences/{id}` | a ocorrência atual | todos os campos |
| `/occurrences/{id}/events` | subcoleção, ordem cronológica | timestamp, type, description, photos, gps |

**Escrita:**
| Coleção | Operação | Dados |
|---------|----------|-------|
| `/occurrences/{id}/events` | create/update/delete | event data |
| `/occurrences/{id}` | update | duration_so_far, updated_at |

### 🎨 Estrutura visual

```
[Header contextual]
  [‹]  Faro em Veículo               [⋮]
       Em andamento · 1h12min · 5 eventos

[Resumo top]
  🛡 Faro em veículo
  📍 Av. Brasil, 1245 · Centro
  ⏱ Iniciada às 09:42

[Timeline scroll]

  [+ ADICIONAR EVENTO]

  10:09  ━━●━━ Indicação positiva
         │     Bono apresentou indicação...
         │     [📷] [📷]
         │     ⚙ editar
  
  10:02  ━━●━━ Bono inicia varredura
         │     ...

  09:48  ━━●━━ Abordagem ao condutor
         │     ...

  09:42  ━━●━━ Início da ocorrência

[CTA sticky]
  [✓ FINALIZAR OCORRÊNCIA]
```

### 🔧 Estrutura técnica

- **Header contextual:** mostra natureza + duração + contador de eventos
- **Botão ⋮:** menu com "Editar dados da ocorrência" e "Descartar"
- **Card de resumo:** dados imutáveis da ocorrência (natureza, local, início)
- **Timeline vertical:** linha ciano com pontos, eventos ordenados por timestamp decrescente
- **Botão "+ ADICIONAR EVENTO":** sticky no topo da lista, sempre visível
- **Cada evento:** card com timestamp, título, descrição, fotos inline (até 4), botão editar
- **CTA "FINALIZAR":** sticky no rodapé, habilitado sempre (mas pede confirmação se 0 eventos)

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Botão ‹ | Pop · volta pro Dashboard · ocorrência permanece em andamento |
| Botão ⋮ | Menu: "Editar dados" / "Descartar ocorrência" |
| "+ ADICIONAR EVENTO" | Abre modal/tela de novo evento (subforma) |
| Tap em evento | Vai pra `/ocorrencia/{id}/evento/{eventId}/editar` (Tela 2.3) |
| Tap em foto | Abre viewer fullscreen |
| Botão editar do evento | Mesmo que tap no evento |
| CTA "FINALIZAR" | Vai pro Wizard de Finalização (Tela 2.4) |

### 🧭 Navegação de saída

- **‹ Voltar:** → `/turno` (ocorrência permanece em andamento, banner no dashboard)
- **Finalizar:** → `/ocorrencia/{id}/finalizar` (Wizard - Tela 2.4)
- **Descartar:** confirma → deleta ocorrência → volta pro dashboard

### 🚨 Estados especiais

- **Sem eventos ainda:** mostra estado vazio "Adicione o primeiro evento desta ocorrência"
- **Auto-save:** badge "Salvo agora" aparece após cada mudança
- **Sem internet:** badge "Salvo localmente · sincronizando..."
- **Tentativa de finalizar com 0 eventos:** modal "Esta ocorrência não tem eventos. Finalizar mesmo assim?"
- **Edição posterior:** evento mostra timestamp da última edição em microcopy

### ⚙️ Regras de negócio

- **Auto-save:** toda mudança em evento dispara update no Firestore (debounced 1s)
- **Duração calculada:** `now - started_at`, atualizada em tempo real (timer interno)
- **Timeline ordenada DESC:** mais recente em cima
- **Soft delete de evento:** marca `deleted_at` em vez de remover (auditoria)
- **Trilha de auditoria:** cada edit registra `edits: [{at, by, field, old_value, new_value}]`
- **Foto preserva EXIF:** data, GPS, dispositivo (defesa profissional)

### 📊 Estado atual vs Novo

**Estado atual:**
- ✅ Provavelmente existe fluxo básico
- ⚠️ Pode não ter timeline visual rica
- ⚠️ Pode não ter trilha de auditoria robusta

**O que muda:**
- 🔨 Timeline visual com linha conectora
- 🔨 Auto-save explícito (badges de status)
- 🔨 Trilha de auditoria em cada evento
- 🔨 Botão "+ ADICIONAR EVENTO" sticky
- 🔨 Soft delete em vez de hard delete
- 🔨 Suporte offline com sincronização posterior

---

## TELA 2.3 — EDIÇÃO DE EVENTO

### 📌 Identificação
- **Mockup de referência:** `03_edicao_evento.html`
- **Rota no app:** `/ocorrencia/{id}/evento/{eventId}/editar`
- **Prioridade:** ALTA (parte do fluxo crítico)

### 🚪 Como se chega
- Tap em evento existente na Tela 2.2
- Tap em "+ ADICIONAR EVENTO" (modo criação)

### 🎯 Propósito
Criar ou editar um evento da timeline. Captura timestamp, tipo, descrição detalhada, fotos com EXIF preservado.

### 🗄️ Dados do Firestore consumidos

**Leitura (se editando):**
- `/occurrences/{id}/events/{eventId}` — dados atuais
- `/occurrences/{id}/events/{eventId}/audit_trail` — histórico de edições

**Escrita:**
- Update no documento do evento (com novo registro na trilha)
- Upload de novas fotos pro Storage: `/incidents/{id}/photos/{eventId}/{photoId}.jpg`

### 🎨 Estrutura visual

```
[Header contextual]
  [‹]  Editar evento                   [🗑]
       Faro em Veículo · evento 4 de 5

[Form scroll]

  HORÁRIO DO EVENTO
  [Agora · 10:09] [Há 5min] [Editar manualmente]

  TIPO DE EVENTO
  ○ Chegada/posicionamento
  ○ Abordagem
  ○ Trabalho do cão
  ● Indicação positiva
  ○ Apreensão
  ○ Encerramento
  ○ Outro

  DESCRIÇÃO
  ┌────────────────────────────────────────┐
  │ Bono apresentou indicação passiva      │
  │ (postura sentada) no banco do passag.. │
  └────────────────────────────────────────┘

  FOTOS · 2 anexadas
  ┌──────┐ ┌──────┐ ┌──────┐
  │ [📷] │ │ [📷] │ │ + ADC│
  │ 10:09│ │ 10:09│ │      │
  └──────┘ └──────┘ └──────┘

  ⚙ TRILHA DE AUDITORIA
  ┌────────────────────────────────────────┐
  │ Criado · 10:09 por você                │
  │ Editado · 10:11 por você               │
  │   Descrição alterada                   │
  └────────────────────────────────────────┘

[CTA sticky]
  [💾 SALVAR EVENTO]
```

### 🔧 Estrutura técnica

- **Header contextual:** botão lixeira pra deletar evento
- **Chips de horário** similar à Tela 2.1
- **Lista de tipos:** radio button vertical, ícone à esquerda
- **Campo descrição:** TextArea multiline, mínimo 50 caracteres recomendado (mas não obrigatório)
- **Galeria de fotos:** horizontal scroll com thumbnails 80x80
- **Cada foto** tem timestamp embaixo (do EXIF), tap abre viewer
- **Trilha de auditoria:** card expansível mostrando edições

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Botão ‹ | Confirma se houver mudanças não salvas |
| Botão 🗑 | Confirma + soft delete + volta pra ocorrência em andamento |
| Tap em foto | Abre fullscreen viewer com swipe entre fotos |
| Botão "+ ADC" | Câmera ou galeria (modal action sheet) |
| Long press em foto | Opção de remover |
| CTA "SALVAR" | Update no Firestore com novo registro de auditoria |

### 🧭 Navegação de saída

- **Salvar:** → `/ocorrencia/{id}/andamento` (Tela 2.2)
- **Cancelar:** → `/ocorrencia/{id}/andamento` (descarta mudanças)
- **Deletar:** confirma → soft delete → volta pra Tela 2.2

### 🚨 Estados especiais

- **Sem fotos:** placeholder "Adicione fotos como evidência"
- **Foto sem EXIF:** aviso amarelo "Foto sem metadata · adicione manualmente o horário"
- **Modal de confirmação ao deletar:** "Excluir este evento? Esta ação é registrada na auditoria."

### ⚙️ Regras de negócio

- **EXIF preservado:** ao tirar foto, salva todo metadata original
- **Soft delete obrigatório:** evento deletado fica no Firestore com `deleted_at` + `deleted_by` + `deleted_reason`
- **Trilha de auditoria:**
  - Cada edição cria entrada com `field`, `old_value`, `new_value`, `at`, `by`
  - Visível na própria tela e no PDF final
- **Foto compactada:** ao salvar, comprime pra max 1920x1920 mantendo EXIF
- **Múltiplas fotos por evento:** até 10 fotos
- **Timestamp do evento independente** do `created_at` (pode registrar evento retroativamente)

### 📊 Estado atual vs Novo

**Estado atual:**
- ⚠️ Pode existir mas sem trilha de auditoria visível

**O que muda:**
- 🔨 Trilha de auditoria visível na própria tela
- 🔨 Soft delete em vez de hard delete
- 🔨 Botão lixeira no header (não no rodapé)
- 🔨 Preservação de EXIF nas fotos
- 🔨 Compressão inteligente das fotos
- 🔨 Galeria horizontal com thumbnails

---

## TELA 2.4 — WIZARD DE FINALIZAÇÃO

### 📌 Identificação
- **Mockup de referência:** `19_finalizacao_ocorrencia.html` (3 passos)
- **Rota no app:** `/ocorrencia/{id}/finalizar`
- **Prioridade:** ALTA (cristaliza o registro institucional)

### 🚪 Como se chega
- CTA "✓ FINALIZAR OCORRÊNCIA" da Tela 2.2

### 🎯 Propósito
Wizard linear de 3 passos pra registrar relato final, marcar resultado e preencher detalhes específicos. Cristaliza o registro institucional antes de gerar PDF.

### 🎨 Estrutura geral do Wizard

```
[Header de wizard]
  [✕]  FINALIZAR OCORRÊNCIA           [─]
       Passo 1 de 3

[Progress bar]
  ━━━━━●─────────────────────
  RELATO  RESULTADO  DETALHES

[Card de contexto fixo]
  🛡 Faro em veículo · 1h36min · 5 eventos

[Conteúdo do passo atual]

[Rodapé de navegação]
  [‹ Voltar]    [PRÓXIMO ›]
```

### 🔧 Estrutura técnica geral

- **PageView controlado:** swipe desabilitado, só botões navegam
- **Progress bar:** 3 segmentos, atual em ciano, completos em verde, futuros em cinza
- **Card de contexto fixo:** sempre visível no topo
- **Botão Voltar:** disabled no passo 1
- **Botão Próximo:** muda pra "✓ CONCLUIR" no passo 3
- **Rascunho automático** se usuário sair (botão ✕)

---

### PASSO 1 — RELATO FINAL

#### Dados do Firestore

**Escrita:**
- `/occurrences/{id}.final_report` (text)
- `/occurrences/{id}.final_report_audio_url` (Storage URL opcional)

#### Estrutura visual

```
RELATO INSTITUCIONAL

🎙 GRAVAR ÁUDIO              [● Iniciar]
ou digite diretamente:

┌────────────────────────────────────────┐
│ Equipe foi acionada às 09:42 para      │
│ abordagem de veículo VW Gol...         │
│                                         │
│ (transcrição automática do áudio       │
│  aparece aqui em tempo real)            │
│                                         │
└────────────────────────────────────────┘

Caracteres: 287 · texto válido ✓
```

#### Interações

| Elemento | Ação |
|----------|------|
| Botão "● Iniciar" gravação | Inicia captura de áudio + transcrição em tempo real |
| Botão pausa/parar | Para gravação · texto transcrito fica no campo |
| Campo de texto | Editável a qualquer momento (transcrição é ponto de partida) |
| Botão "PRÓXIMO ›" | Valida texto · vai pro Passo 2 |

#### Regras

- **Texto é obrigatório** — passo 1 não avança com campo vazio
- **Áudio é opcional** — serve apenas como fonte de transcrição
- **Não armazena o áudio** (sua decisão) — só o texto transcrito
- **Transcrição via `speech_to_text` ou similar** já no pubspec
- **Mínimo 50 caracteres** sugerido mas não bloqueante

---

### PASSO 2 — RESULTADO (Multi-Select)

#### Dados do Firestore

**Escrita:**
- `/occurrences/{id}.results` (array de strings)
- Exemplo: `['drug_seized', 'person_detained', 'bo_created']`

#### Estrutura visual

```
RESULTADO DA OCORRÊNCIA
(marque todos que se aplicam)

┌──────────────┬──────────────┐
│  ●           │              │
│ 💊 Droga     │ 🔫 Arma      │
│ apreendida   │ apreendida   │
├──────────────┼──────────────┤
│  ●           │  ●           │
│ 👤 Indivíduo │ 📄 BO        │
│ detido       │ elaborado    │
├──────────────┼──────────────┤
│              │              │
│ ⊘ Sem        │ ✋ Apoio     │
│ ocorrência   │ prestado     │
└──────────────┴──────────────┘

3 resultados selecionados
```

#### Interações

| Elemento | Ação |
|----------|------|
| Tap em card | Toggle seleção (multi-select) |
| Tap em "Sem ocorrência" | Se selecionado, desmarca todos os outros (mutuamente exclusivo) |
| Botão "PRÓXIMO ›" | Valida pelo menos 1 selecionado · vai pro Passo 3 |
| Botão "‹ Voltar" | Volta pro Passo 1 mantendo dados |

#### Regras

- **Pelo menos 1 resultado obrigatório**
- **"Sem ocorrência" é mutuamente exclusivo** com outros (lógico: ou houve algo, ou não)
- **Cada resultado abre subseções no Passo 3** com campos específicos

---

### PASSO 3 — DETALHES POR RESULTADO

#### Dados do Firestore

**Escrita por tipo de resultado:**

```
/occurrences/{id}.details: {
  drug_seized: {
    type: 'maconha',
    quantity: 18,
    unit: 'g',
    photo_url: '...'
  },
  person_detained: {
    count: 1,
    referral: 'DP'
  },
  bo_created: {
    bo_number: '2026/05/8721',
    bo_type: 'flagrante'
  }
}
```

#### Estrutura visual (campos condicionais)

```
DETALHES DOS RESULTADOS

══════ 💊 DROGA APREENDIDA ══════
  Tipo: [Maconha ▼]
  Quantidade: [18] [g ▼]
  Foto da apreensão:
  ┌────────┐
  │  📷    │
  └────────┘

══════ 👤 INDIVÍDUO DETIDO ══════
  Quantidade: [1]
  Encaminhamento: [DP ▼]

══════ 📄 BO ELABORADO ══════
  Número: [2026/05/8721]
  Tipo: [Flagrante ▼]

═════════════════════════════════
```

#### Interações

| Elemento | Ação |
|----------|------|
| Dropdowns | Listas pré-definidas (tipo de droga, encaminhamentos) |
| Campos numéricos | Teclado numérico |
| Botão "+ FOTO" | Câmera ou galeria |
| Botão "✓ CONCLUIR" | Valida todos os campos obrigatórios · vai pra Confirmação Final (Tela 2.5) |

#### Regras

- **Campos obrigatórios variam por tipo**:
  - Droga apreendida: tipo + quantidade obrigatórios, foto recomendada
  - Indivíduo detido: quantidade + encaminhamento obrigatórios
  - BO elaborado: número obrigatório
- **Validação visual** mostra campos faltando em vermelho
- **Botão ✓ CONCLUIR só ativa** quando tudo válido

### 🚨 Estados especiais do Wizard

- **Sair sem terminar (botão ✕):** confirma "Salvar como rascunho?" · marca `status: 'finalizing'`
- **Retomar rascunho:** abre direto no passo onde parou (estado salvo)
- **Conexão perdida:** salva localmente, retoma quando voltar

### 📊 Estado atual vs Novo

**Estado atual:**
- ⚠️ Provavelmente não tem wizard estruturado em 3 passos

**O que muda:**
- 🔨 Implementar `PageView` com controle por botões
- 🔨 Progress bar de 3 segmentos
- 🔨 Card de contexto fixo
- 🔨 Multi-select de resultados
- 🔨 Campos condicionais no passo 3
- 🔨 Transcrição de áudio integrada no passo 1
- 🔨 Rascunho automático

---

## TELA 2.5 — CONFIRMAÇÃO FINAL

### 📌 Identificação
- **Mockup de referência:** `19_finalizacao_ocorrencia.html` (última tela)
- **Rota no app:** `/ocorrencia/{id}/concluida`
- **Prioridade:** ALTA

### 🚪 Como se chega
- Após "✓ CONCLUIR" no Passo 3 do Wizard

### 🎯 Propósito
Tela de sucesso e prestação de contas. Mostra resumo do que foi registrado e oferece ações pós-finalização (PDF, compartilhar, voltar ao turno).

### 🗄️ Dados do Firestore

**Escrita ao chegar nessa tela:**
- `/occurrences/{id}`: 
  - `status: 'finalized'`
  - `finalized_at: timestamp`
  - `duration_total: minutes`
  - Hash SHA-256 calculado e armazenado em `integrity_hash`

### 🎨 Estrutura visual

```
[Header de sucesso]
  ✓ OCORRÊNCIA REGISTRADA
  Documento institucional criado

[Card de resumo]
  ┌────────────────────────────────────────┐
  │ 🛡 Faro em Veículo                     │
  │ 📅 12/05/2026 · 09:42 — 11:18         │
  │ ⏱ Duração: 1h 36min                   │
  │ 📍 Av. Brasil, 1245                   │
  │ 📋 5 eventos · 4 fotos                │
  │                                         │
  │ Resultados:                            │
  │   ✓ Droga apreendida · 18g maconha   │
  │   ✓ Indivíduo detido · DP            │
  │   ✓ BO elaborado · 2026/05/8721      │
  └────────────────────────────────────────┘

[Hash do documento]
  ⚙ Integridade verificada
  SHA-256: a7f3c2e8b9d4f1c6...

[Ações grandes]
  ┌────────────────────────────────┐
  │ 📄 GERAR PDF                   │
  └────────────────────────────────┘
  ┌────────────────────────────────┐
  │ 📤 COMPARTILHAR                │
  └────────────────────────────────┘
  ┌────────────────────────────────┐
  │ ◀ VOLTAR AO TURNO              │
  └────────────────────────────────┘
```

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Botão "📄 GERAR PDF" | Renderiza PDF via package (printing/pdf) · armazena no Storage · abre viewer |
| Botão "📤 COMPARTILHAR" | Share intent nativo · compartilha PDF |
| Botão "◀ VOLTAR AO TURNO" | → `/turno` |

### 🧭 Navegação de saída

- **Voltar ao turno:** → `/turno`
- **Gerar PDF:** → viewer interno (`pdfx` ou nativo)
- **Compartilhar:** → share sheet do sistema

### ⚙️ Regras de negócio

- **Hash SHA-256 calculado** a partir do JSON serializado da ocorrência
- **PDF gerado on-demand** (não pré-renderizado pra economizar storage)
- **PDF salvo no Storage** após primeira geração: `/incidents/{id}/pdf_final.pdf`
- **URL do PDF salva em** `occurrences.{id}.pdf_export_url`
- **Ocorrência fica imutável** após chegar nessa tela (`status: 'finalized'`)
- **Trilha de auditoria continua** registrando acessos ao PDF (quem baixou, quando)

### 📊 Estado atual vs Novo

**O que muda:**
- 🔨 Geração de PDF via `printing` ou `pdf` package
- 🔨 Cálculo de hash SHA-256
- 🔨 Upload do PDF pro Storage
- 🔨 Imutabilidade da ocorrência após finalização
- 🔨 Trilha de acessos ao PDF

---

## DOCUMENTO 2.6 — PDF DA OCORRÊNCIA

### 📌 Identificação
- **Mockup de referência:** `24_pdf_ocorrencia.html`
- **Tipo:** Documento gerado (não tela)
- **Localização sugerida:** `core/services/pdf_generator/occurrence_pdf.dart`
- **Prioridade:** ALTA (produto institucional final)

### 🎯 Propósito
Documento institucional formal que vai pra auditor, comandante, promotor, defesa. **É a defesa profissional materializada.**

### 🗄️ Dados consumidos

Toda a árvore do documento `/occurrences/{id}` incluindo:
- Dados básicos (natureza, local, horários)
- Subcoleção `events` com fotos
- Dados do condutor (`/users/{primary_handler_id}`)
- Dados do cão (`/dogs/{dog_id}`)
- Dados do turno (`/shifts/{shift_id}`)

### 🎨 Estrutura do PDF (6 páginas)

**Página 1 — CAPA**
- Brasão GCM Limeira (placeholder até ter o real)
- "GUARDA CIVIL MUNICIPAL DE LIMEIRA"
- Tipo: REGISTRO DE OCORRÊNCIA
- Título: nome da natureza
- Card com metadata (data, horários, duração, local)
- ID do registro destacado
- Identificação do binômio

**Página 2 — IDENTIFICAÇÃO**
- Cards lado a lado: condutor + cão
- Tabela administrativa: plantão, viatura, equipe, apoio, comando

**Página 3 — OCORRÊNCIA E LOCALIZAÇÃO**
- Mapa estático (Google Maps Static API)
- Coordenadas precisas com precisão GPS
- 2 boxes destacados: Natureza e Duração
- Tabela de localização completa

**Página 4 — LINHA DO TEMPO**
- Timeline vertical com pontos ciano
- Cada evento: horário, título, descrição, foto inline, EXIF preservado

**Página 5 — RELATO E RESULTADO**
- Relato Institucional em card com badge "🎙 TRANSCRIÇÃO DE ÁUDIO · REVISADA"
- Result-sections em verde institucional pra cada resultado

**Página 6 — AUDITORIA E ASSINATURA**
- Trilha de auditoria completa (transparente sobre edições)
- Hash SHA-256 em card destacado
- QR Code pra verificação online
- Caixa de assinatura tradicional

### 🔧 Estrutura técnica

- **Geração:** package `pdf` (escrita imperativa) ou `printing` (preview + share)
- **Fontes:** Inter (sans-serif) + SF Mono (monospace pra IDs/timestamps)
- **Paleta:** light mode com ciano #0a8e9d como detalhe
- **Mapa:** Google Maps Static API (chamada autenticada com API key)
- **QR Code:** package `qr_flutter` gerando link pro Firebase Hosting
- **Hash:** `crypto` package, SHA-256 do JSON serializado

### ⚙️ Regras de negócio

- **PDF gerado on-demand** (não pré-renderizado)
- **Hash calculado UMA VEZ** ao finalizar (Tela 2.5) e armazenado
- **Toda regeneração usa o mesmo hash** se nada mudou
- **Link do QR aponta pra:** `https://canilk9.limeira.sp.gov.br/v/{occurrence_id}`
- **Trilha de auditoria registra cada download** com `{at, by, ip}`
- **Linguagem formal institucional** — "substância análoga à maconha" em vez de "maconha"

### 📊 Estado atual vs Novo

**O que muda:**
- 🔨 **Criar serviço `OccurrencePdfGenerator`** completo
- 🔨 Implementar geração de PDF com 6 páginas
- 🔨 Integrar Google Maps Static API
- 🔨 Implementar geração de QR code
- 🔨 Implementar cálculo de hash SHA-256
- 🔨 Sistema de tracking de downloads (auditoria)

---

# 📜 BLOCO B — HISTÓRICO

## TELA 2.7 — HISTÓRICO (Lista Filtrada)

### 📌 Identificação
- **Mockup de referência:** `13_historico.html` (tela 1)
- **Rota no app:** `/historico`
- **Prioridade:** ALTA

### 🚪 Como se chega
- Tap em "📜 Histórico" no Bottom Navigation

### 🎯 Propósito
Mostrar todo o histórico de eventos do cão ativo, organizado cronologicamente, com filtros por categoria e período. Permite exportar PDF do período.

### 🗄️ Dados do Firestore consumidos

| Coleção | Filtro | Campos |
|---------|--------|--------|
| `/occurrences` | `dog_id == active_dog_id`, `status != 'in_progress'` | todos |
| `/dogs/{id}/training_sessions` | por data | todos |
| `/dogs/{id}/feeding_events` | por data | todos |
| `/dogs/{id}/health_events` | por data | todos |
| `/dogs/{id}/weight_records` | por data | todos |

**Agregação:** todos os tipos viram uma única timeline ordenada por timestamp.

### 🎨 Estrutura visual

```
[Header Universal]
  [foto Bono] [foto RAG]  Bono · GCM Ragonha
                          ● Turno ativo · há 5h
                          [⇄] [👤]

[Filtros sticky]
  PERÍODO
  [Hoje] [Ontem] [Semana] [Mês] [Tudo] [📅]
  
  CATEGORIA
  [Tudo] [🛡 Ocor] [🎯 Trei] [🥩 Nutr] [⚕ Saúd]

[Botão exportar PDF]
  [📄 EXPORTAR PERÍODO COMO PDF]

[Timeline scroll]

  ━━ HOJE ━━━━━━━━━━━━━━━━━━━━

  14:32 ━━●━━ 🛡 Ocorrência iniciada
             Faro em veículo · em andamento
             ⟳ pulsando

  09:30 ━━●━━ 🎯 Treino · Obediência
             5 comandos · 25 minutos

  07:15 ━━●━━ 🥩 Alimentação
             400g · você

  ━━ ONTEM ━━━━━━━━━━━━━━━━━━

  19:42 ━━●━━ 🥩 Alimentação
             400g · você

  10:09 ━━●━━ 🛡 Ocorrência concluída
             Faro em veículo · com apreensão
             [editado às 10:46]

  ...

[Bottom Nav ativo: Histórico]
```

### 🔧 Estrutura técnica

- **Header Universal** persistente
- **Filtros sticky** no topo da área de scroll
- **Filtros são chips** com estado selected/unselected
- **Timeline com agrupamentos por dia** (HOJE, ONTEM, DD/MM)
- **Cada item:** hora monospace + ícone categórico + título + descrição + badges
- **Badge "editado"** quando o registro foi editado
- **Status pulsante** em ocorrências em andamento
- **Lazy loading:** carrega 30 itens, fetch mais ao scrollar

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Chips de período | Filtra timeline · refaz query Firestore |
| Chips de categoria | Filtra timeline · pode multi-select |
| Botão 📅 | Abre date range picker pra período custom |
| Botão "EXPORTAR" | Gera PDF do Histórico (ver Documento 4 da Parte futura) |
| Tap em item | → Detalhe expandido (Tela 2.8) |
| Pull to refresh | Recarrega dados |

### 🧭 Navegação de saída

- **Item:** → `/historico/{tipo}/{id}` (Tela 2.8)
- **Exportar:** → viewer de PDF · share sheet
- **Bottom Nav:** outras áreas

### 🚨 Estados especiais

- **Filtro sem resultados:** "Nenhum registro neste período"
- **Histórico totalmente vazio:** estado inicial "Comece a usar o app · seu histórico aparece aqui"
- **Loading:** skeleton de 5-10 itens
- **Ocorrência em andamento:** aparece no topo com badge ⟳ pulsante

### ⚙️ Regras de negócio

- **Período default:** Semana (últimos 7 dias)
- **Categoria default:** Tudo
- **Agregação multi-coleção** feita no cliente (mais simples) ou via query paralela
- **Ordenação:** timestamp DESC
- **Badge "editado":** se `audit_trail.length > 1`
- **PDF do histórico filtrado:** respeita os filtros aplicados
- **Item de ocorrência em andamento:** tap leva pra `/ocorrencia/{id}/andamento`, não pra detalhe

### 📊 Estado atual vs Novo

**Estado atual:**
- ⚠️ Provavelmente existe lista mas sem essa estrutura unificada
- ⚠️ Filtros podem ser limitados

**O que muda:**
- 🔨 Agregação multi-coleção numa timeline única
- 🔨 Filtros chips de período + categoria
- 🔨 Botão exportar PDF
- 🔨 Lazy loading
- 🔨 Agrupamentos por dia
- 🔨 Status pulsante em ocorrências em andamento

---

## TELA 2.8 — DETALHE EXPANDIDO DO HISTÓRICO

### 📌 Identificação
- **Mockup de referência:** `13_historico.html` (tela 2)
- **Rota no app:** `/historico/{tipo}/{id}`
- **Prioridade:** MÉDIA

### 🚪 Como se chega
- Tap em qualquer item da timeline da Tela 2.7

### 🎯 Propósito
Mostrar todos os detalhes de um registro específico. Cada tipo (ocorrência, treino, alimentação, saúde) tem seu detalhe específico mas com estrutura comum.

### 🗄️ Dados do Firestore

Depende do tipo:
- **Ocorrência:** `/occurrences/{id}` + subcoleção `events`
- **Treino:** `/dogs/{dogId}/training_sessions/{id}`
- **Alimentação:** `/dogs/{dogId}/feeding_events/{id}`
- **Saúde:** `/dogs/{dogId}/health_events/{id}`
- **Peso:** `/dogs/{dogId}/weight_records/{id}`

### 🎨 Estrutura visual (exemplo Ocorrência)

```
[Header contextual]
  [‹]  Detalhe                          [⋮]
       Ocorrência · 12/05/2026

[Card de resumo]
  🛡 Faro em Veículo
  📅 12/05/2026 · 09:42 — 11:18
  📍 Av. Brasil, 1245
  ⏱ 1h 36min

[Resultados]
  ✓ Droga apreendida · 18g maconha
  ✓ Indivíduo detido · DP
  ✓ BO 2026/05/8721

[Mini timeline de eventos]
  10:09 · Indicação positiva
  10:02 · Bono inicia varredura
  09:48 · Abordagem
  09:42 · Início

[Trilha de auditoria]
  ⚙ 7 entradas · ver completo →

[Ações grandes]
  [📄 ABRIR PDF]
  [📤 COMPARTILHAR]
```

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Botão ⋮ | Menu "Reabrir como rascunho" (se aplicável e permitido) |
| Tap em evento da timeline | Expande/colapsa descrição completa |
| Tap em "ver completo →" | Abre tela ou modal com trilha auditoria completa |
| Botão "ABRIR PDF" | Gera/exibe o PDF da ocorrência |
| Botão "COMPARTILHAR" | Share intent |

### 🧭 Navegação de saída

- **‹ Voltar:** → `/historico`
- **PDF:** viewer interno
- **Compartilhar:** share sheet

### 🚨 Estados especiais

- **Item deletado (soft delete):** mostra badge vermelho "REGISTRO EXCLUÍDO" + motivo + opção de "ver mesmo assim"
- **Item editado:** card "Histórico de alterações" com cada edição

### ⚙️ Regras de negócio

- **Ocorrências finalizadas são imutáveis** — nada de editar
- **Outros tipos podem ser editados** (alimentação, peso) por quem registrou ou supervisor
- **Trilha de auditoria sempre acessível**
- **PDF disponível só pra ocorrências** (outros tipos: PDF é gerado em telas dedicadas)

### 📊 Estado atual vs Novo

**O que muda:**
- 🔨 Tela unificada de detalhe pra diferentes tipos
- 🔨 Estrutura compartilhada com sections condicionais por tipo
- 🔨 Acesso à trilha de auditoria

---

# 🐕 BLOCO C — CÃO / PRONTUÁRIO

## TELA 2.9 — CÃO / PRONTUÁRIO

### 📌 Identificação
- **Mockup de referência:** `20_cao_nutricao_e_alimentacao.html` (Tela A)
- **Rota no app:** `/cao`
- **Prioridade:** ALTA

### 🚪 Como se chega
- Tap em "🐕 Cão" no Bottom Navigation
- Tap no card "Seu cão" do Perfil
- Tap no resumo do cão do Dashboard

### 🎯 Propósito
Prontuário completo do cão ativo. Centraliza identidade, status médico, especialidades, nutrição, peso, vacinação, laudos e ações de registro.

### 🗄️ Dados do Firestore

| Coleção | Filtro | Uso |
|---------|--------|-----|
| `/dogs/{active_dog_id}` | doc atual | foto, dados, status |
| `/dogs/{id}/specialties_state` | todos | mostrar chips operacionais/formação |
| `/dogs/{id}/health_events` | últimos por categoria | status médico cards |
| `/dogs/{id}/weight_records` | últimos 30 | mini gráfico de peso |
| `/dogs/{id}/feeding_events` | hoje | refeições do dia |
| `/dogs/{id}/nutritional_prescriptions` | vigente | prescrição atual |
| `/dogs/{id}/documents` | todos ativos | laudos e certificações |

### 🎨 Estrutura visual

```
[Header Universal]

[Ficha do cão]
  ┌────────────────────────────────────────┐
  │  [photo]  Bono                          │
  │           Malinois · 6 anos · 28kg      │
  │           [● OPERACIONAL HÁ 4 ANOS]    │
  └────────────────────────────────────────┘

STATUS MÉDICO
  ┌──────┬──────┐
  │ 💉   │ 🛡   │
  │ Vac. │ Antip│
  │ Em dia│ 15d │
  ├──────┼──────┤
  │ ⚖    │ 🔬   │
  │ 28.0 │ Em   │
  │ Estáv│ dia │
  └──────┴──────┘

ESPECIALIDADES
  [● Detecção (Drogas)]
  [● Busca & Captura]
  [◔ Guarda & Proteção]

🥩 NUTRIÇÃO                          [Ver tudo →]
  ┌────────────────────────────────────────┐
  │ 📋 PRESCRIÇÃO VIGENTE                  │
  │ 800g/dia · ração premium              │
  │ Laudo: Dra. Ana Souza                 │
  │                                         │
  │ [🌅 MANHÃ ✓]   [🌙 NOITE]             │
  │  400g · 07:15   pendente               │
  │                                         │
  │ ✓ Conformidade em dia                 │
  │ 100% da semana                         │
  └────────────────────────────────────────┘

EVOLUÇÃO DO PESO                     [Ver tudo →]
  [mini gráfico] 28.0kg · estável

CARTEIRA DE VACINAÇÃO               [Ver tudo →]
  V10 · em dia
  Raiva · em dia
  Antipulgas · vence 29/05

LAUDOS E DOCUMENTOS                 [Ver tudo →]
  📄 Laudo nutricional · Dra. Ana Souza
  📄 Certificação Detecção · 11/2024

EVENTOS RECENTES                    [Ver tudo →]
  💉 Antipulgas Bravecto · 02/03
  ⚖ Pesagem · 28.0kg · 10/05

[CTAs grandes]
  [🥩 REGISTRAR ALIMENTAÇÃO]
  [⚕ REGISTRAR EVENTO DE SAÚDE]

[Bottom Nav ativo: Cão]
```

### 🔧 Estrutura técnica

- **Header Universal** persistente
- **Ficha do cão:** gradient ciano sutil, foto 72x72, badge OPERACIONAL grande
- **Status médico grid 2x2:** cards compactos com ícone + status + valor + sub
- **Especialidades chips:** verde se operacional, amarelo se formação, cinza se não iniciada
- **Seção Nutrição em destaque:** card laranja maior, prescrição + refeições + conformidade
- **Mini gráfico de peso:** SVG inline simples
- **Listas com "Ver tudo →":** preview de 2-3 itens + link

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Card "Vacinas" do status | → `/cao/vacinacao` (Tela 2.10) |
| Card "Antipulgas" | → `/cao/vacinacao` (focada em antiparasitários) |
| Card "Peso" | → `/cao/peso` (Tela 2.11) |
| Chips de especialidade | → tela da especialidade (Bloco C da Parte 3) |
| "Ver tudo →" Nutrição | → `/cao/nutricao` (Tela 2.12) |
| "Ver tudo →" Peso | → `/cao/peso` (Tela 2.11) |
| "Ver tudo →" Vacinação | → `/cao/vacinacao` (Tela 2.10) |
| Card refeição "MANHÃ ✓" | → detalhe da refeição |
| Card refeição "NOITE pendente" | → registrar alimentação pré-preenchida |
| CTA "🥩 REGISTRAR ALIMENTAÇÃO" | → tela de registro de alimentação |
| CTA "⚕ REGISTRAR EVENTO SAÚDE" | → seletor de tipo (Bloco C Parte 3) |

### 🚨 Estados especiais

- **Cão sem laudo nutricional:** seção Nutrição mostra "Sem prescrição vigente · contate veterinário"
- **Cão sem pesagens recentes:** seção Peso mostra "Última pesagem há mais de 30 dias"
- **Cão recém-cadastrado:** maioria das seções vazias com CTAs pra cadastrar

### ⚙️ Regras de negócio

- **Conformidade alimentar calculada:** soma das refeições da semana / (prescrição/dia × 7)
- **Status médico:** cores dinâmicas (verde/amarelo/vermelho) baseado em prazos
- **Mini gráfico:** últimas 7 pesagens
- **Refeições do dia:** filtra por `timestamp >= startOfDay(now)`
- **"Ver tudo →"** sempre leva pra tela detalhada da seção

### 📊 Estado atual vs Novo

**Estado atual:**
- ✅ Existe `features/dogs/presentation/screens/dog_profile_screen.dart` provavelmente
- ⚠️ Estrutura visual provavelmente diferente

**O que muda:**
- 🔨 Reorganizar seções na ordem do mockup
- 🔨 **Adicionar seção Nutrição inteira** (NOVA — mais importante)
- 🔨 Status médico em 4 cards
- 🔨 Mini gráfico de peso inline
- 🔨 Seções com "Ver tudo →"
- 🔨 2 CTAs grandes ao final
- ⚠️ Criar coleção `/dogs/{id}/nutritional_prescriptions` (NOVA)
- ⚠️ Criar coleção `/dogs/{id}/feeding_events` (NOVA se não existe)

---

## TELA 2.10 — CARTEIRA DE VACINAÇÃO COMPLETA

### 📌 Identificação
- **Mockup de referência:** `23_telas_ver_tudo.html` (Tela A)
- **Rota no app:** `/cao/vacinacao`
- **Prioridade:** MÉDIA

### 🚪 Como se chega
- "Ver tudo →" da Carteira de Vacinação no Prontuário
- Tap em card "💉 Vacinas" do status médico

### 🎯 Propósito
Mostrar histórico completo de vacinação com timeline horizontal de próximas doses, lista agrupada por tipo, e exportar PDF formal.

### 🗄️ Dados do Firestore

- `/dogs/{id}/health_events` filtrado por `type IN ['vaccine', 'antiparasitic']`
- Agrupado por `subtype` (V10, Raiva, Bravecto, etc)

### 🎨 Estrutura visual

```
[Header contextual]
  [‹]  Carteira de Vacinação
       Bono · 12 vacinas registradas

[Botão exportar]
  [📄 EXPORTAR PDF]

PRÓXIMAS DOSES · 12 meses
[Timeline horizontal]
  ●─────────●────────●
  Antipulg  V10    Raiva
  15d       4m     8m
  HOJE              +12M

HISTÓRICO POR VACINA

▼ V10 — Polivalente
  ✓ V10 · 12/09/2025
    Dra. Ana Souza · CRMV 12345
    Lote: LK7821A · próx: 12/09/2026
    [📄 ver anexo]
  
  ✓ V10 · 15/09/2024
    Dra. Ana Souza · CRMV 12345
    cumprida em 12/09/2025

▼ Raiva
  ...

▼ Antiparasitário
  ...

[Sticky bottom]
  [+ REGISTRAR VACINAÇÃO]
```

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Botão "EXPORTAR PDF" | Gera PDF da carteira (ver Documento 4 da Parte 3) |
| Tap em ponto da timeline | Scroll até aquela vacina na lista |
| Tap em grupo (▼) | Expande/colapsa |
| Tap em vacina | Abre detalhe + anexo |
| "[📄 ver anexo]" | Abre PDF da vacina anexada |
| "REGISTRAR VACINAÇÃO" | → seletor de tipo de evento de saúde, pre-fill "vacinação" |

### 🧭 Navegação de saída

- **‹ Voltar:** → `/cao`
- **Registrar:** → fluxo de novo evento de saúde

### ⚙️ Regras de negócio

- **Timeline horizontal:** mostra apenas próximas 12 meses, baseado em `next_due_date`
- **Grupos colapsáveis:** facilitar navegação em históricos longos
- **Anexos:** PDFs, fotos da carteira física, atestados
- **Bravecto sem `next_due_date`:** mostra "próxima dose: condutor define" (sua decisão sobre antiparasitários)

### 📊 Estado atual vs Novo

**O que muda:**
- 🔨 Timeline horizontal de próximas doses
- 🔨 Lista agrupada por tipo
- 🔨 PDF dedicado da carteira
- 🔨 Suporte a anexos (PDF/foto)

---

## TELA 2.11 — HISTÓRICO DE PESO COMPLETO

### 📌 Identificação
- **Mockup de referência:** `23_telas_ver_tudo.html` (Tela B)
- **Rota no app:** `/cao/peso`
- **Prioridade:** MÉDIA

### 🚪 Como se chega
- "Ver tudo →" da Evolução do Peso no Prontuário
- Tap em card "⚖ Peso" do status médico

### 🎯 Propósito
Histórico completo de pesagens com gráfico ampliado, estatísticas, lista cronológica e botão pra registrar nova pesagem.

### 🗄️ Dados do Firestore

- `/dogs/{id}/weight_records` (todos, ordenado por data DESC)
- `/dogs/{id}/nutritional_prescriptions` (atual) — pra faixa ideal

### 🎨 Estrutura visual

```
[Header contextual]
  [‹]  Histórico de Peso
       Bono · 42 pesagens · 6 meses

[Botão exportar]
  [📄 EXPORTAR PDF]

[Chips de período]
  [30d] [6m] [1ano] [Tudo]

[Card de peso atual]
  PESO ATUAL
  28.0 kg
  ↑ Estável · faixa ideal

[Gráfico maior]
  Faixa ideal 26-30kg sombreada
  Linha azul com pontos
  Faixa real X-Y kg

[Estatísticas]
  MÍN | MÉD | MÁX
  27.4 | 27.8 | 28.0

[Lista cronológica]
  ●  28.0 kg · 10/05/2026
     Você · Canil · 📷 com foto
  ●  27.9 kg · 26/04/2026
     Você · Canil
  ●  27.8 kg · 12/04/2026
     GCM Silva · Canil
  ...

[Sticky bottom]
  [+ REGISTRAR NOVA PESAGEM]
```

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Chips de período | Filtra dados · refaz gráfico |
| Tap em ponto do gráfico | Tooltip com data + valor |
| Tap em item da lista | Detalhe (data, autor, observações, foto se houver) |
| Tap em 📷 | Abre foto da balança |
| "REGISTRAR NOVA PESAGEM" | Form de registro |

### 🔧 Form de nova pesagem (modal/sub-tela)

```
NOVA PESAGEM

Peso (kg)
[28.0]
[+] [-] (incremento ±0.1)

Data
[Hoje · 14:32]

Local
○ Canil
○ Clínica veterinária
○ Outro: [______]

📷 Foto da balança (opcional)

[SALVAR]
```

### 🚨 Estados especiais

- **Pesagem fora da faixa ideal:** alerta amarelo "Peso fora da faixa ideal · verificar"
- **Peso aumentou >5% em 30d:** alerta sobre tendência
- **Sem pesagens:** estado vazio "Registre a primeira pesagem"

### ⚙️ Regras de negócio

- **Foto opcional** (decisão sua) — destaque visual mas não obrigatória
- **Faixa ideal vem da prescrição vigente** (`min_weight`, `max_weight`)
- **Variação calculada:** comparação com pesagem anterior
- **Tendência:** linha de regressão simples ou apenas comparação de extremos
- **Quem registra:** qualquer condutor de plantão

### 📊 Estado atual vs Novo

**O que muda:**
- 🔨 Tela completa nova (provavelmente)
- 🔨 Gráfico maior com faixa ideal
- 🔨 Chips de período
- 🔨 Form de registro com foto opcional
- ⚠️ Criar coleção `/dogs/{id}/weight_records` se não existe (verificar)

---

## TELA 2.12 — NUTRIÇÃO COMPLETA

### 📌 Identificação
- **Mockup de referência:** `23_telas_ver_tudo.html` (Tela C)
- **Rota no app:** `/cao/nutricao`
- **Prioridade:** ALTA (defesa profissional crítica)

### 🚪 Como se chega
- "Ver tudo →" da seção Nutrição no Prontuário
- CTA "🥩 REGISTRAR ALIMENTAÇÃO" do Prontuário (pode ir direto pro registro)
- Tap card "🥩 Nutrição" do acesso rápido do Dashboard

### 🎯 Propósito
**Tela mais importante pra defesa profissional do condutor.** Mostra prescrição vigente, conformidade detalhada, gráfico de consumo, lista de refeições, divergências documentadas. **Resolve o caso 800g vs 300g.**

### 🗄️ Dados do Firestore

| Coleção | Filtro | Uso |
|---------|--------|-----|
| `/dogs/{id}/nutritional_prescriptions` | `active == true` | prescrição vigente |
| `/dogs/{id}/nutritional_prescriptions` | todas | histórico de prescrições |
| `/dogs/{id}/feeding_events` | últimos 90 dias | gráfico + lista |
| `/dogs/{id}/feeding_events` | divergentes | tabela de divergências |

### 🎨 Estrutura visual

```
[Header contextual]
  [‹]  Nutrição
       Bono · 180 refeições · 90 dias

[Botão exportar]
  [📄 EXPORTAR PDF]

PRESCRIÇÃO VIGENTE
  ┌────────────────────────────────────────┐
  │ 📋 800g/dia · ração premium            │
  │    Laudo: Dra. Ana Souza · CRMV-SP 123 │
  │    Vigente desde 04/2026               │
  │    [ver histórico de prescrições →]   │
  └────────────────────────────────────────┘

CONFORMIDADE
  ┌────────────────────────────────────────┐
  │      95%                                │
  │ 171 conformes · 9 divergências         │
  │ 90 dias monitorados                    │
  └────────────────────────────────────────┘

[Gráfico de barras · consumo diário 14d]
  Linha pontilhada = 800g (prescrição)
  Barras laranja = conformes
  Barras amarelas = divergentes

[Filtros]
  [Todas] [Conformes] [Divergências]
  [Esta semana] [Este mês]

LISTA DE REFEIÇÕES
  🌅 Manhã · 12/05 · 400g · você
  🌙 Noite · 11/05 · 400g · você
  🌅 Manhã · 11/05 · 500g · GCM Silva
       [+25% · pós-treino]
  ...

[Sticky bottom]
  [+ REGISTRAR ALIMENTAÇÃO]
```

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| "ver histórico de prescrições →" | Abre modal/lista de todas as prescrições vigentes |
| Tap em barra do gráfico | Tooltip com data + valor |
| Chips de filtro | Aplica filtros na lista |
| Tap em refeição | Detalhe expandido (com motivo da divergência se houver) |
| Tap em divergência | Mostra justificativa registrada |
| "REGISTRAR ALIMENTAÇÃO" | → form de registro (ver abaixo) |

### 🔧 Form de nova alimentação

```
NOVA ALIMENTAÇÃO

Refeição
○ Manhã
● Noite
○ Outro horário

Quantidade
[400] g
prescrito: 400g/refeição

Conforme prescrição? ✓ SIM

Horário
[Agora · 19:42]

📷 Foto (opcional)

Motivo da divergência (aparece se ≠ prescrição)
[__________________________]

[SALVAR]
```

### 🚨 Estados especiais

- **Sem prescrição vigente:** seção alerta "Cão sem laudo nutricional · registros não terão referência"
- **Divergência sem motivo:** sugere preencher (não bloqueia)
- **Divergência >50%:** aviso amarelo "Divergência significativa · verifique necessidade veterinária"

### ⚙️ Regras de negócio

- **Conformidade = quantidade dentro de ±10% da prescrição** (configurável)
- **Divergência precisa de motivo** (sugerido, não obrigatório)
- **Sistema NÃO bloqueia divergência** — condutor sabe o que faz
- **PDF é a arma de defesa:** exportar PDF mostra tudo organizado
- **Histórico de prescrições preservado:** quando uma vira `active: false`, fica visível como histórico
- **Foto sempre opcional**

### 📊 Estado atual vs Novo

**Estado atual:**
- ⚠️ Provavelmente NÃO existe — é seção nova

**O que muda:**
- 🔨 **Tela inteira nova**
- 🔨 Sistema de prescrições com vigência
- 🔨 Cálculo de conformidade
- 🔨 Gráfico de barras com linha de prescrição
- 🔨 Form de registro com detecção automática de divergência
- 🔨 PDF do relatório nutricional
- ⚠️ Criar coleção `/dogs/{id}/nutritional_prescriptions` (NOVA)
- ⚠️ Criar coleção `/dogs/{id}/feeding_events` (NOVA)

---

## 🎯 RESUMO DE PRIORIDADES PARTE 2

| Tela/Documento | Prioridade | Esforço estimado |
|----------------|-----------|------------------|
| 2.1 Iniciar Ocorrência | ALTA | Médio (2-3 dias) |
| 2.2 Em Andamento | ALTA | Alto (4 dias) |
| 2.3 Edição de Evento | ALTA | Médio (3 dias) |
| 2.4 Wizard Finalização | ALTA | Alto (5 dias com transcrição) |
| 2.5 Confirmação Final | ALTA | Baixo (1 dia) |
| 2.6 PDF da Ocorrência | ALTA | Alto (5-7 dias) |
| 2.7 Histórico | ALTA | Alto (4 dias) |
| 2.8 Detalhe do Histórico | MÉDIA | Médio (2 dias) |
| 2.9 Prontuário | ALTA | Alto (4 dias) |
| 2.10 Carteira Vacinação | MÉDIA | Médio (3 dias) |
| 2.11 Histórico de Peso | MÉDIA | Médio (3 dias) |
| 2.12 Nutrição Completa | ALTA | Alto (5 dias) |

**Total estimado da Parte 2:** ~8-10 semanas de trabalho focado.

---

## 📌 ORDEM DE IMPLEMENTAÇÃO SUGERIDA

```
SEMANA 1-2: Bloco A (Ocorrências) - Telas 2.1, 2.2, 2.3
SEMANA 3-4: Bloco A - Wizard de Finalização (2.4) + Confirmação (2.5)
SEMANA 5-6: Bloco A - PDF da Ocorrência (2.6) ← MARCO INSTITUCIONAL
SEMANA 7: Bloco B - Histórico (2.7, 2.8)
SEMANA 8-9: Bloco C - Prontuário (2.9) + Nutrição (2.12)
SEMANA 10: Bloco C - Vacinação (2.10) + Peso (2.11)
```

---

## ⚠️ COLEÇÕES FIRESTORE A CRIAR/VALIDAR

| Coleção | Status | Decisão |
|---------|--------|---------|
| `/occurrences` | EXISTENTE | Reutilizar |
| `/occurrences/{id}/events` | EXISTENTE? | Verificar |
| `/occurrence_types` | NOVA | Criar (catálogo de naturezas) |
| `/dogs/{id}/specialties_state` | NOVA | Criar (estado das especialidades) |
| `/dogs/{id}/health_events` | EXISTENTE? | Verificar |
| `/dogs/{id}/weight_records` | EXISTENTE? | Verificar |
| `/dogs/{id}/feeding_events` | NOVA | Criar |
| `/dogs/{id}/nutritional_prescriptions` | NOVA | Criar |
| `/dogs/{id}/training_sessions` | EXISTENTE? | Verificar |
| `/dogs/{id}/documents` | NOVA | Criar (laudos, certificações) |

---

## 📚 PRÓXIMA PARTE

**PARTE 3 — Treinos e Auxiliares (em breve)**
- Hub de Treinos
- Obediência (biblioteca de comandos + sessão)
- Busca & Captura (formação por módulos + manutenção + GPS)
- Detecção · Protocolo Ragonha (linhas + 5 fases + multi-linha + certificação)
- Guarda & Proteção (3 impulsos paralelos + sessão com figurante)
- Condicionamento Físico (catálogo de exercícios + sessão inteligente)
- Saúde (seletor de tipo + 8 formulários condicionais)
- Modais auxiliares (adicionar especialidade, comando, atualizar estágio)
- PDFs auxiliares (Carteira de Vacinação, Peso, Nutrição, Histórico Mensal)

---

**FIM DA PARTE 2 · 12 telas/documentos especificados**
