# 📘 ESPECIFICAÇÃO TÉCNICA — PARTE 1

## App Canil K9 GCM Limeira — Fundação e Entrada

> Documento técnico de referência para implementação no Claude Code.
> Lista todas as telas com comportamento esperado, dados consumidos do
> Firestore, navegação, estados especiais e comparação com o estado atual.

---

## 📋 ÍNDICE DA PARTE 1

1. [Tela 1.1 — Splash Screen](#tela-11--splash-screen)
2. [Tela 1.2 — Login](#tela-12--login)
3. [Tela 1.3 — Seleção de Cão / Assumir Plantão](#tela-13--seleção-de-cão--assumir-plantão)
4. [Tela 1.4 — Dashboard (Turno)](#tela-14--dashboard-turno)
5. [Tela 1.5 — Perfil do Condutor](#tela-15--perfil-do-condutor)
6. [Componente 1.6 — Header Universal](#componente-16--header-universal)
7. [Componente 1.7 — Bottom Navigation](#componente-17--bottom-navigation)
8. [Componente 1.8 — Bottom Sheet de Trocar Cão](#componente-18--bottom-sheet-de-trocar-cão)

---

## TELA 1.1 — SPLASH SCREEN

### 📌 Identificação
- **Mockup de referência:** `22_login_e_selecao.html` (Tela A)
- **Rota no app:** `/` (rota raiz)
- **Prioridade:** ALTA (essencial pra entrada)

### 🚪 Como se chega
- Primeira tela que abre quando o app é iniciado
- Sempre que o app é morto e reaberto
- Após logout (redireciona aqui antes de ir pro login)

### 🎯 Propósito
Tela de transição enquanto o app decide pra onde levar o usuário. Verifica auth state, carrega dados do usuário, verifica turno ativo.

### 🗄️ Dados do Firestore consumidos

**Verificações que rodam em background:**

| Coleção | Documento | Campos usados |
|---------|-----------|---------------|
| Firebase Auth | `currentUser` | uid, email |
| `/users` | `{currentUser.uid}` | ra, name, role, active_dog_id, active_shift_id |
| `/shifts` | onde `handler_id == uid` AND `status == 'active'` | id, dog_id, started_at |

### 🎨 Estrutura visual

```
[Status bar do sistema]

[Espaço vertical centralizado]
  
  [Brasão GCM Limeira]
  (placeholder: ícone 🛡 em círculo ciano)
  
  CANIL K9
  GCM LIMEIRA-SP
  
  [3 dots animados pulsantes]

[Footer fixo no rodapé]
  Sistema Institucional
  v1.3.0
```

### 🔧 Estrutura técnica

- **Background:** `#050d10` com gradient radial ciano sutil no topo
- **Logo container:** 120x120px, border-radius 50%, borda ciano `#4dd0e1`
- **Título "CANIL K9":** 26px, weight 800, letter-spacing 1px
- **Subtítulo:** 11px, weight 600, letter-spacing 2px, cor ciano
- **Loading dots:** 3 círculos 6px ciano, animação pulsante sequencial
- **Footer:** absoluto na parte inferior, padding 30px

### 🧭 Navegação de saída

Lógica de roteamento após verificações (1-2 segundos):

```
SE auth.currentUser == null:
  → /login

SENÃO SE não existe documento em /users/{uid}:
  → /login (com mensagem de erro)

SENÃO SE active_shift_id == null OU shift.status != 'active':
  → /assumir-plantao

SENÃO:
  → /turno (dashboard)
```

### 🚨 Estados especiais

- **Sem internet:** mostra splash + mensagem discreta "Sem conexão" no footer (não bloqueia)
- **Firebase fora do ar:** após 5 segundos com timeout, vai pra /login com mensagem
- **Auth válido mas user doc não existe:** vai pra login com aviso "Usuário não cadastrado, contate administração"

### ⚙️ Regras de negócio

- Splash NÃO pode durar mais que 3 segundos visualmente
- Se as verificações falharem, ainda assim avança pra login
- Salva timestamp da última abertura em local storage (analytics futuro)
- AppCheck deve ser ativado AQUI antes de qualquer query Firestore

### 📊 Estado atual vs Novo

**Estado atual (baseado no `main.dart` que você compartilhou):**
- ✅ Existe lógica equivalente dentro de `GcmK9App` usando `Consumer3<AuthViewModel, ShiftViewModel, UserViewModel>`
- ✅ Já decide entre Login / LoadingSession / Assumption / Dashboard
- ⚠️ Não existe splash visual dedicada — vai direto pra tela de loading com `CircularProgressIndicator`

**O que muda:**
- 🔨 **Criar tela dedicada `SplashScreen`** com identidade visual do canil
- 🔨 Substituir o `Scaffold` de loading genérico pela splash visual
- 🔨 Manter a lógica de decisão de rota (já funciona) mas exibir splash enquanto decide
- 🔨 Sugestão: criar `features/splash/presentation/screens/splash_screen.dart`

---

## TELA 1.2 — LOGIN

### 📌 Identificação
- **Mockup de referência:** `22_login_e_selecao.html` (Tela B)
- **Rota no app:** `/login`
- **Prioridade:** ALTA (essencial pra entrada)

### 🚪 Como se chega
- Da Splash quando `auth.currentUser == null`
- Após logout (botão "Sair do app" no Perfil)
- Quando token expira (raro, mas pode acontecer)

### 🎯 Propósito
Autenticar o condutor por RA + senha, com biometria como opção rápida pra retornos.

### 🗄️ Dados do Firestore consumidos

**No login:**
- Firebase Auth: `signInWithEmailAndPassword` ou login customizado por RA

**Após login bem-sucedido:**

| Coleção | Documento | Campos lidos |
|---------|-----------|--------------|
| `/users` | onde `ra == {RA digitado}` | uid (pra fazer login no Firebase Auth) |

**Lógica de RA → email:**
Como Firebase Auth usa email, sugestão é mapear RA pra email institucional:
```
ra_691755@canilk9.gcm.limeira.sp.gov.br
```
Cadastro de novo condutor é feito pelo gestor no painel web (cria documento em `/users` + cria conta no Firebase Auth).

### 🎨 Estrutura visual

```
[Status bar]

[Brand compacto]
  🛡 CANIL K9
     GCM LIMEIRA-SP

[Welcome]
  Bem-vindo de volta
  Acesse com sua matrícula e senha institucional

[Form]
  🪪 [Matrícula (RA)        ]
  🔒 [Senha            ] 👁
                 Esqueci minha senha

  [👆 ENTRAR COM BIOMETRIA]  ← primário
  
  ─── OU ───
  
  [ENTRAR COM SENHA]         ← secundário

[Footer institucional]
  Acesso restrito a guardas da GCM Limeira
  Cadastros são feitos pela administração do canil
```

### 🔧 Estrutura técnica

- **Campo RA:** TextFormField com tipo `TextInputType.number`, formatter pra permitir só dígitos, max 7 caracteres
- **Campo senha:** TextFormField com `obscureText: true`, toggle pra mostrar/ocultar
- **Botão biometria:** condicional — só aparece se já tem credenciais salvas (secure storage) E dispositivo tem biometria configurada
- **Validação local:** RA não vazio, senha mínimo 6 caracteres
- **Loading state:** botão desabilitado + spinner enquanto autentica

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Campo RA | Foco abre teclado numérico |
| Campo senha | Foco abre teclado padrão |
| Botão 👁 | Toggle obscureText do campo senha |
| Link "Esqueci minha senha" | Abre modal/tela de recuperação (envia link pro email institucional) |
| Botão "ENTRAR COM BIOMETRIA" | Solicita biometria via `local_auth` → recupera credenciais → autentica no Firebase |
| Botão "ENTRAR COM SENHA" | Valida campos → autentica no Firebase com email derivado do RA + senha |

### 🧭 Navegação de saída

- **Sucesso (sem turno ativo):** → `/assumir-plantao`
- **Sucesso (com turno ativo):** → `/turno`
- **Erro de autenticação:** permanece na tela, mostra mensagem de erro discreta
- **Esqueci minha senha:** modal envia email, fecha modal, fica na tela

### 🚨 Estados especiais

- **Primeira vez no dispositivo (sem biometria salva):** botão biometria não aparece ou aparece desabilitado
- **Após login bem-sucedido:** pergunta "Salvar credenciais para usar biometria?"
- **Sem internet:** mostra banner "Sem conexão · login requer internet"
- **Conta bloqueada:** após X tentativas erradas, mostra mensagem específica
- **Conta não existe:** mostra "Matrícula não cadastrada · contate administração"

### ⚙️ Regras de negócio

- **Não tem cadastro pelo app** — usuários cadastrados via painel web pelo gestor
- **RA deve existir em `/users`** antes de aceitar login
- **Credenciais para biometria salvas em `flutter_secure_storage`** após primeiro login
- **Logout limpa tokens + secure storage** (mas mantém dados no Firestore)
- **AppCheck obrigatório** antes de qualquer operação

### 📊 Estado atual vs Novo

**Estado atual:**
- ✅ Existe `features/auth/presentation/screens/login_screen.dart` (presumido pela estrutura)
- ✅ `AuthViewModel` já gerencia estado de autenticação
- ✅ Provider `firebase_auth` já configurado
- ⚠️ Não sabemos visual atual sem screenshot

**O que muda:**
- 🔨 **Verificar se já é RA + senha ou se é email + senha** — pode ser que precise refatorar
- 🔨 **Aplicar visual do mockup** (paleta ciano, biometria como ação primária)
- 🔨 **Adicionar fluxo biométrico** com `local_auth` se não existir
- 🔨 **Adicionar secure storage** com `flutter_secure_storage` (já está no pubspec)
- 🔨 Microcopy institucional ("Cadastros são feitos pela administração do canil")

---

## TELA 1.3 — SELEÇÃO DE CÃO / ASSUMIR PLANTÃO

### 📌 Identificação
- **Mockup de referência:** `22_login_e_selecao.html` (Tela C)
- **Rota no app:** `/assumir-plantao`
- **Prioridade:** ALTA (essencial pra entrada)

### 🚪 Como se chega
- Da Splash quando user existe mas não tem turno ativo
- Do Login bem-sucedido sem turno ativo
- Do Perfil → "Encerrar Expediente" (finaliza turno atual, redireciona aqui)

### 🎯 Propósito
Permitir ao condutor selecionar o cão e abrir um turno operacional. Mostra status de cada cão para decisão informada.

### 🗄️ Dados do Firestore consumidos

| Coleção | Filtro/Doc | Campos lidos |
|---------|-----------|--------------|
| `/users` | `{currentUser.uid}` | name, ra (saudação) |
| `/dogs` | `status == 'active'` | id, name, breed, age, weight_current, photo_url, status, primary_handler_id |
| `/dogs/{id}/specialties_state` | todos | status (operational/in_formation/not_started) |
| `/dogs/{id}/health_events` | últimos por tipo | calcular pendências |
| `/dogs/{id}/last_activity` | derivado | timestamp da última atividade registrada |
| `/users/{primary_handler_id}` | dos titulares | name (pra mostrar "Titular: GCM Silva") |

### 🎨 Estrutura visual

```
[Saudação]
  BOA TARDE
  GCM Ragonha
  RA 691755 · 14/05/2026 · quarta

[Title]
  Selecione o cão              3 cães no canil

[Lista vertical de cães]
  ┌──────────────────────────────────┐
  │ [foto] BONO  [SEU CÃO]           │ ← Titular, selecionado
  │        Malinois · 6a · 28kg       │
  │        ● Operacional              │
  │        ┌──────────────────┐       │
  │        │ ✓ APTO PARA PLANTÃO     │
  │        └──────────────────┘       │
  │        Última: ontem 19:30        │
  └──────────────────────────────────┘
  ┌──────────────────────────────────┐
  │ [foto] APOLO                     │
  │        Malinois · 2a · 36kg       │
  │        ◔ Em formação              │
  │        [! APTO COM PENDÊNCIA]    │
  │        ● Antipulgas vence em 3d  │
  │        Titular: GCM Silva        │
  └──────────────────────────────────┘
  ┌──────────────────────────────────┐
  │ [foto] TOR (opacidade 85%)        │
  │        ...                        │
  │        [⊘ NÃO APTO PARA PLANTÃO] │
  │        ● Em recuperação           │
  │        ● Vacina vencida           │
  └──────────────────────────────────┘

[CTA sticky no rodapé]
  [ASSUMIR PLANTÃO COM BONO →]
```

### 🔧 Estrutura técnica

- **Saudação dinâmica:** "Bom dia" (5-12h), "Boa tarde" (12-18h), "Boa noite" (18-5h)
- **Foto do cão:** 50x50px circular, borda colorida por status
- **Border-left destaque:** 3px ciano em cães titulares
- **Card selecionado:** borda 2px ciano + fundo ciano sutil
- **Card não apto:** opacity 0.85
- **CTA sticky:** posição absolute bottom, gradient pra cima, padding seguro

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Tap em card de cão | Seleciona aquele cão · CTA atualiza texto · scroll automático até CTA |
| Tap no CTA "ASSUMIR PLANTÃO" | Cria documento em `/shifts` · atualiza `users.{uid}.active_shift_id` e `active_dog_id` · navega pra dashboard |
| Tap em cão não apto + CTA | Abre modal de confirmação "Assumir Tor com pendências críticas?" |
| Pull to refresh | Recarrega lista de cães do Firestore |

### 🧭 Navegação de saída

- **Após assumir:** → `/turno` (dashboard)
- **Não tem botão voltar** — usuário deve assumir ou fazer logout pelo menu (caso seja necessário sair)

### 🚨 Estados especiais

- **Sem cães no canil:** "Nenhum cão cadastrado no canil. Contate a administração."
- **Todos os cães em outros plantões:** "Todos os cães estão em plantão ativo. Aguarde retorno ou contate o gestor."
- **Cão sem foto:** placeholder com iniciais (ex: "BONO")
- **Loading inicial:** skeleton dos cards de cão

### ⚙️ Regras de negócio

- **Cálculo de "apto":**
  - APTO (verde): sem pendências críticas
  - APTO COM PENDÊNCIA (amarelo): tem pendência leve (vacina vencendo em 30 dias, antipulgas vencendo)
  - NÃO APTO (vermelho): vacina vencida há mais de 7 dias, em recuperação cirúrgica, ferimento ativo
- **Permite assumir cão não apto** mas registra: `shifts.assumed_with_warnings: true` + lista de pendências
- **Cães em recuperação ainda aparecem** mas com status visível (não filtra)
- **"Cobertura":** quando você assume cão que não é seu, registra `shifts.coverage_for: {titular_uid}`
- **Última atividade calculada:** maior timestamp de qualquer evento do cão (treino, ocorrência, refeição, etc)

### 📊 Estado atual vs Novo

**Estado atual:**
- ✅ Existe `features/shifts/presentation/screens/shift_assumption_screen.dart`
- ✅ `ShiftViewModel` já gerencia o assumir plantão
- ⚠️ Visual provavelmente diferente do mockup
- ⚠️ Cálculo de pendências e status "apto/não apto" pode não existir

**O que muda:**
- 🔨 **Aplicar visual do mockup** (cards verticais ricos, status badges)
- 🔨 **Calcular status de aptidão** automaticamente baseado em pendências
- 🔨 **Mostrar pendências** quando aplicável
- 🔨 **Identificar cão titular** com badge "SEU CÃO"
- 🔨 **Identificar coberturas** com "Titular: GCM Silva"
- 🔨 **Sticky CTA** com texto dinâmico
- 🔨 Modal de confirmação para assumir cão não apto
- ⚠️ Adicionar coleção `/dogs/{id}/specialties_state` se ainda não existe (NOVA)

---

## TELA 1.4 — DASHBOARD (TURNO)

### 📌 Identificação
- **Mockup de referência:** `10_dashboard.html`
- **Rota no app:** `/turno`
- **Prioridade:** ALTA (tela principal)

### 🚪 Como se chega
- Após assumir plantão
- Após login com turno já ativo
- Tap em "🏠 Turno" no bottom nav
- Após finalizar uma ocorrência

### 🎯 Propósito
Tela inicial do turno operacional. Mostra estado atual, alertas, atividades do dia e acesso rápido às ações principais.

### 🗄️ Dados do Firestore consumidos

| Coleção | Filtro | Campos |
|---------|--------|--------|
| `/users` | `{uid}` | name, ra, active_dog_id |
| `/dogs` | `{active_dog_id}` | name, breed, age, weight_current, photo_url, operational_since |
| `/shifts` | turno ativo | started_at (calcular "há X horas") |
| `/dogs/{id}/specialties_state` | todas | status (mostrar especialidades operacionais) |
| `/dogs/{id}/health_events` | recentes | calcular alertas |
| `/occurrences` | do dia, deste cão | timeline de hoje |
| `/dogs/{id}/training_sessions` | do dia | timeline de hoje |
| `/dogs/{id}/feeding_events` | do dia | timeline de hoje |
| `/dogs/{id}/health_events` | últimos | timestamp última ação por categoria |

### 🎨 Estrutura visual

```
[Header Universal]
  [foto Bono] [foto RAG]  Bono · GCM Ragonha
                          ● Turno ativo · há 5h
                          [⇄] [👤]

[Scroll area]

  [Alertas condicionais] ← só aparecem se houver
  ┌─────────────────────────────────────┐
  │ 🟡 Antipulgas vence em 15 dias      │
  │ 🔴 Vacina V10 expirada              │
  └─────────────────────────────────────┘
  
  [ATIVIDADES DE HOJE]
  ┌─────────────────────────────────────┐
  │ 07:15  🍖  Alimentação · 400g       │
  │ 09:30  🎯  Treino Obediência · 25min│
  │ 14:32  🛡  Ocorrência em andamento  │
  └─────────────────────────────────────┘
  
  [ACESSO RÁPIDO]
  ┌──────┬──────┬──────┬──────┐
  │ 🥩   │ ⚕    │ 🎯   │ 🛡   │
  │ Nutr │ Saúde│ Trein│ Ocorr│
  │ há 7h│ há 3d│ há 5h│ agora│
  └──────┴──────┴──────┴──────┘
  
  [RESUMO DO CÃO]
  ┌─────────────────────────────────────┐
  │ Bono · 28kg · 4 anos operacional    │
  │ 3 especialidades · cert. detecção   │
  └─────────────────────────────────────┘

[Bottom Nav]
  🏠 Turno  📜 Histórico  🛡 FAB  🎯 Treino  🐕 Cão
```

### 🔧 Estrutura técnica

- **Header Universal:** componente compartilhado (ver Componente 1.6)
- **Bottom Nav:** componente compartilhado (ver Componente 1.7)
- **Card de alerta:** border-left 3px na cor do nível, padding 12px
- **Cards de atividade:** lista vertical, ícone categórico + hora + título
- **Acesso rápido grid:** 4 colunas, cards com ícone + label + "última há Xh"

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Tap em alerta | Vai pra área correspondente (vacina → `/cao/vacinacao`) |
| Tap em atividade | Vai pro detalhe do item no Histórico |
| Tap card "🥩 Nutrição" | → `/cao` com scroll até seção Nutrição OU `/registrar/alimentacao` |
| Tap card "⚕ Saúde" | → `/registrar/saude` (seletor de tipo) |
| Tap card "🎯 Treino" | → `/treino` (hub) |
| Tap card "🛡 Ocorrência" | → `/ocorrencia/iniciar` (mesmo do FAB) |
| Tap no resumo do cão | → `/cao` (prontuário completo) |
| Pull to refresh | Recarrega dados do turno |

### 🧭 Navegação de saída

- Via bottom nav (Histórico, Treino, Cão)
- Via FAB → Iniciar Ocorrência
- Via header (⇄ trocar cão, 👤 perfil)
- Via cards de acesso rápido

### 🚨 Estados especiais

- **Estado vazio (dia limpo, sem atividade):**
  ```
  "Comece o dia"
  Registre a primeira atividade do plantão
  
  [4 atalhos grandes]
  🥩 Alimentação   ⚕ Saúde
  🎯 Treino        🛡 Ocorrência
  ```
- **Cão recém-trocado:** dashboard atualiza imediatamente com dados do novo cão
- **Ocorrência em andamento:** banner amarelo destacado "Você tem uma ocorrência em andamento · toque para continuar"
- **Offline:** banner "Modo offline · alguns dados podem estar desatualizados"

### ⚙️ Regras de negócio

- **Atividades de hoje** filtra por `timestamp >= startOfDay(now)` no fuso BR (-03:00)
- **Alertas calculados em runtime** a partir de health_events
- **"Última há Xh"** dos cards de acesso rápido:
  - Verde: < 6h
  - Amarelo: 6-24h
  - Vermelho: > 24h
- **Resumo do cão** com selo dinâmico "OPERACIONAL HÁ X ANOS" calculado de `operational_since`
- **Header Universal fixo** durante scroll

### 📊 Estado atual vs Novo

**Estado atual:**
- ✅ Existe `features/dashboard/presentation/screens/main_root_screen.dart`
- ✅ Dashboard funciona com dados básicos
- ⚠️ Conforme você falou, "tava feio" (foto gigante, prontidão %, etc)

**O que muda:**
- 🔨 **Refazer layout completo** seguindo mockup 10
- 🔨 **Remover** foto gigante, prontidão %, cronômetro em segundos, badge "8" sem contexto
- 🔨 **Adicionar** alertas condicionais calculados
- 🔨 **Adicionar** "última há Xh" nos cards de acesso rápido
- 🔨 **Estado vazio** com 4 atalhos grandes (caso novo)
- 🔨 **Banner de ocorrência em andamento** se aplicável
- 🔨 Header Universal e Bottom Nav devem estar integrados

---

## TELA 1.5 — PERFIL DO CONDUTOR

### 📌 Identificação
- **Mockup de referência:** `21_perfil_condutor.html`
- **Rota no app:** `/perfil`
- **Prioridade:** MÉDIA (acessada via 👤 no header)

### 🚪 Como se chega
- Tap no botão 👤 no Header Universal (em qualquer área principal)
- Abre em tela cheia, sobrepõe a área anterior

### 🎯 Propósito
Tela "sobre você" — identifica o condutor, mostra estatísticas de atuação, selos de conformidade institucional, configurações e ações administrativas.

### 🗄️ Dados do Firestore consumidos

| Coleção | Filtro | Campos |
|---------|--------|--------|
| `/users` | `{uid}` | name, ra, role, photo_url, role_since |
| `/dogs` | `primary_handler_id == uid` | name, breed, age, photo_url, specialties_state |
| `/shifts` | `handler_id == uid` | count (total de plantões) · sum(duration) (horas) |
| `/occurrences` | `primary_handler_id == uid` | count (total de ocorrências) |
| `/dogs/{id}/training_sessions` | `created_by == uid` | count (total de treinos) |
| Cálculos derivados | múltiplas coleções | selos de conformidade dinâmicos |

### 🎨 Estrutura visual

```
[Header simples]
  [✕]  Perfil  [espaço]

[Identidade]
  ┌─────────────────────────────────┐
  │      [RAG]                       │
  │   GCM Jilles Ragonha             │
  │   RA 691755 · Limeira/SP         │
  │   [● CONDUTOR TITULAR]           │
  │   [4 ANOS NO CANIL]              │
  └─────────────────────────────────┘

[Seu cão]
  ┌─────────────────────────────────┐
  │ [BONO] BINÔMIO ATIVO            │
  │        Bono · Malinois · 6a     │
  │        ● Operacional · 3 esp.   │
  │                              ›  │
  └─────────────────────────────────┘

[Sua atuação]
  ┌──────┬──────┐
  │ 847  │ 6.8k │
  │ PLANT│ HORAS│
  ├──────┼──────┤
  │ 124  │ 412  │
  │ OCOR │ TREI │
  └──────┴──────┘

[Conformidade profissional · 9 de 11]
  "Selos institucionais calculados conforme protocolo.
   Não há ranking — apenas conformidade com o padrão."
  
  OPERACIONAL
  ┌──────────────┬──────────────┐
  │ 📅 Plantões  │ 📝 Relato    │
  │ sem lacunas  │ final 100%   │
  └──────────────┴──────────────┘
  ... (mais categorias)

[Configurações]
  🔔 Notificações
  📡 Sincronização
  🔐 Segurança
  ℹ Sobre o app

[Ações]
  [⏹ ENCERRAR EXPEDIENTE]
  [→ SAIR DO APP]

[Footer]
  Canil K9 · GCM Limeira-SP · v1.3.0
```

### 🔧 Estrutura técnica

- **Tela cheia** (não modal), abre como `MaterialPageRoute` com slide-up
- **Botão ✕** fecha (pop) e volta pra área anterior
- **Identidade card:** gradient sutil ciano, padding 18px
- **Stats grid 2x2:** cards com ícone colorido + valor + label
- **Selos:** cards 2 colunas, opacidade 40% nos inativos
- **Botão Encerrar Expediente:** amarelo (atenção)
- **Botão Sair:** vermelho discreto (ação destrutiva)

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Botão ✕ | Pop · volta pra tela anterior |
| Card "Seu cão" | → `/cao` (prontuário) |
| Card stats | (sem ação por ora — futuramente abre detalhe) |
| Tap em selo ativo | Abre bottom sheet com detalhe (Tela B do mockup) |
| Tap em selo inativo | Abre bottom sheet explicando o que falta |
| Item "Notificações" | → tela de configurações de notificação |
| Item "Sincronização" | → tela de configurações de sync |
| Item "Segurança" | → tela de biometria/senha |
| Item "Sobre o app" | → tela de informações |
| "Encerrar Expediente" | Confirma · finaliza shift · vai pra `/assumir-plantao` |
| "Sair do app" | Confirma · limpa secure storage · vai pra `/login` |

### 🧭 Navegação de saída

- **✕ ou voltar:** retorna pra área anterior
- **Tap "Seu cão":** → `/cao`
- **Encerrar Expediente:** → `/assumir-plantao`
- **Sair:** → `/login`

### 🚨 Estados especiais

- **Loading inicial:** skeleton dos stats e selos
- **Sem cão titular:** card "Seu cão" mostra "Sem cão titular atribuído"
- **Selos 0 de 11:** primeira vez, mostra mensagem explicativa
- **Modal de confirmação Sair:** "Tem certeza? Você precisará fazer login novamente."
- **Modal de confirmação Encerrar:** "Encerrar expediente atual? Dados continuam acessíveis no painel."

### ⚙️ Regras de negócio

- **Selos calculados dinamicamente** em runtime (não persistidos):
  - **Plantões sem lacunas:** todos os plantões dos últimos 90 dias registrados com início e fim
  - **Relato final 100%:** últimas 30 ocorrências com `final_report` preenchido
  - **PDFs gerados 100%:** últimas 30 ocorrências com `pdf_export_url` preenchido
  - **Manutenções em dia:** especialidades operacionais com sessão nos últimos 30 dias
  - **Biblioteca atualizada:** comandos com `stage_updated_at` em até 90 dias
  - **Vacinas em dia:** todas as vacinas com `next_due_date > now`
  - **Antipulgas em dia:** próxima dose ainda não venceu
  - **Conformidade alimentar:** >= 90% nos últimos 30 dias
  - **Peso monitorado:** pesagem registrada nos últimos 30 dias
  - **Perfil completo:** photo_url, role, todos os campos preenchidos
  - **Documentos do cão:** sem documentos pendentes/expirados
- **Encerrar Expediente:**
  - Atualiza `shifts.{active_shift_id}.ended_at = now`
  - Atualiza `shifts.{active_shift_id}.status = 'finalized'`
  - Atualiza `users.{uid}.active_shift_id = null`
  - Mantém `active_dog_id` (preferência salva)
- **Sair do app:**
  - Firebase Auth signOut
  - Limpa `flutter_secure_storage`
  - **Não** encerra o turno (turno permanece ativo, condutor pode voltar)

### 📊 Estado atual vs Novo

**Estado atual:**
- ⚠️ Estrutura tem `views/profile/` antigo + provavelmente nada em `features/profile/` ainda
- ⚠️ Pasta `views/gamification/` existe (gamificação a remover)

**O que muda:**
- 🔨 **Criar feature `features/profile/`** completa (data, domain, presentation)
- 🔨 **Migrar `views/profile/` → `features/profile/presentation/screens/`**
- 🔨 **Deletar `views/gamification/`** completamente
- 🔨 **Implementar sistema de selos de conformidade** (novo)
- 🔨 **Implementar cálculos agregados** (plantões, horas, ocorrências, treinos)
- 🔨 **Bottom sheet de detalhe de selo**
- 🔨 **Encerrar Expediente** deve coexistir com `ShiftAssumptionScreen`
- 🔨 Footer institucional com versão

---

## COMPONENTE 1.6 — HEADER UNIVERSAL

### 📌 Identificação
- **Mockup de referência:** presente em todas as telas com bottom nav
- **Tipo:** Widget reutilizável
- **Localização sugerida:** `core/widgets/universal_header.dart`
- **Prioridade:** ALTA (presente em quase todas as telas)

### 🎯 Propósito
Componente persistente no topo das 4 áreas principais. Identifica o binômio ativo, mostra status do turno, oferece acesso rápido a trocar cão e perfil.

### 🗄️ Dados consumidos

Via `Consumer` ou `ref.watch` (Riverpod):
- `users.{currentUser.uid}.name` → nome do condutor
- `dogs.{active_dog_id}` → nome, photo do cão
- `shifts.{active_shift_id}.started_at` → calcular "há X horas"

### 🎨 Estrutura visual

```
┌────────────────────────────────────────────┐
│ [🐾][👤]  Bono · GCM Ragonha    [⇄] [👤]  │
│           ● Turno ativo · há 5h            │
└────────────────────────────────────────────┘
```

### 🔧 Estrutura técnica

- **Container:** padding `8px 16px 14px 16px`, background `rgba(77,208,225,0.04)`, border-bottom 1px ciano sutil
- **Avatares sobrepostos:** 2 círculos 36x36, segundo com margin-left -10px e borda mais clara
- **Texto binômio:** 13px, weight 700, branco
- **Status turno:** 10px, verde com dot pulsante, "Turno ativo · há Xh"
- **Botões:** 32x32, border-radius 8px, fundo ciano sutil

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Tap em avatares | (sem ação · podem mostrar tooltip com nome completo) |
| Tap em ⇄ | Abre Bottom Sheet de trocar cão (Componente 1.8) |
| Tap em 👤 | Navega pra `/perfil` (tela cheia) |
| Long press em avatares | (futuro: detalhe completo do binômio) |

### ⚙️ Regras de negócio

- **"Há X horas"** atualiza dinamicamente (timer no widget)
- **Dot verde pulsante** apenas se turno está ativo
- **Componente aparece em:** Turno, Histórico, Treino, Cão (4 áreas principais)
- **NÃO aparece em:** sub-telas (formulários, detalhes, modais)
- **Sub-telas têm header próprio** (back button + título contextual)

### 📊 Estado atual vs Novo

**Estado atual:**
- ⚠️ Provavelmente não existe componente unificado
- ⚠️ Cada tela atual pode ter seu próprio header

**O que muda:**
- 🔨 **Criar widget `UniversalHeader`** em `core/widgets/`
- 🔨 **Usar em Turno, Histórico, Treino, Cão**
- 🔨 **Sub-telas usam header contextual** (back + título)
- 🔨 **Timer interno** pra atualizar "há X horas"

---

## COMPONENTE 1.7 — BOTTOM NAVIGATION

### 📌 Identificação
- **Mockup de referência:** presente em todas as telas principais
- **Tipo:** Widget reutilizável
- **Localização sugerida:** `core/widgets/bottom_nav.dart`
- **Prioridade:** ALTA

### 🎯 Propósito
Navegação principal entre as 4 áreas do app, com FAB centralizado pra ação prioritária (Iniciar Ocorrência).

### 🎨 Estrutura visual

```
┌──────────────────────────────────────────────┐
│ 🏠      📜     [🛡 FAB]     🎯       🐕      │
│ Turno   Histó              Treino   Cão      │
└──────────────────────────────────────────────┘
```

### 🔧 Estrutura técnica

- **Container:** background `#050d10`, border-top 1px branco 5%, padding `8px 0 16px 0`
- **Itens normais:** Column com ícone (18px) + label (9px), padding 4px 8px, cor `#5a7280`
- **Item ativo:** cor `#4dd0e1`
- **FAB:** 54x54px circular ciano, sombra, margin-top -28px (sobe), border 4px do background
- **Layout:** 5 elementos com `MainAxisAlignment.spaceAround`

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| 🏠 Turno | Navega pra `/turno` (mesma stack, troca de tab) |
| 📜 Histórico | Navega pra `/historico` |
| 🛡 FAB | Navega DIRETO pra `/ocorrencia/iniciar` (sem menu) |
| 🎯 Treino | Navega pra `/treino` |
| 🐕 Cão | Navega pra `/cao` |

### ⚙️ Regras de negócio

- **FAB sempre dispara iniciar ocorrência** — não tem menu, não tem outras opções
- **Item ativo destacado em ciano** — corresponde à rota atual
- **NÃO aparece em:** sub-telas (formulários, detalhes, modais, ocorrência em andamento)
- **Aparece em:** Turno, Histórico, Treino, Cão
- **State preservado** entre tabs (usuário volta pra Treino e tá no mesmo lugar)

### 📊 Estado atual vs Novo

**Estado atual:**
- ⚠️ Provavelmente existe `bottomNavigationBar` mas com itens diferentes
- ⚠️ Pode ter aba "Rotina" (a ser removida)
- ⚠️ Pode ter aba "Rank" da gamificação (a ser removida)

**O que muda:**
- 🔨 **Definir 4 itens fixos** + FAB exclusivo
- 🔨 **Remover** aba Rotina (passeios vão pra Condicionamento, alimentação vai pro Cão)
- 🔨 **Remover** aba Rank
- 🔨 **FAB centralizado** com escudo 🛡 ciano fill
- 🔨 **Preservar state** entre tabs (usar `IndexedStack` ou go_router state)

---

## COMPONENTE 1.8 — BOTTOM SHEET DE TROCAR CÃO

### 📌 Identificação
- **Mockup de referência:** ainda não mockado dedicadamente · pode usar padrão dos outros bottom sheets (modais)
- **Tipo:** Modal bottom sheet
- **Localização sugerida:** `core/widgets/switch_dog_sheet.dart`
- **Prioridade:** MÉDIA (acessada pelo ⇄ do header)

### 🚪 Como se chega
- Tap no botão ⇄ no Header Universal

### 🎯 Propósito
Permite ao condutor trocar o cão ativo no plantão atual sem precisar encerrar o turno.

### 🗄️ Dados consumidos

Mesma query da Tela 1.3 (Seleção de Cão):
- `/dogs` com `status == 'active'`
- Status de aptidão de cada cão

### 🎨 Estrutura visual

```
[Backdrop escurecido com blur]

  ┌─────────────────────────────┐
  │      [handle drag]           │
  │                              │
  │ Trocar cão ativo             │
  │ Bono está em plantão · troca │
  │ não encerra o turno          │
  │                              │
  │ ┌─────────────────────────┐  │
  │ │ [foto] BONO  ATIVO     │  │
  │ │        Malinois · 6a   │  │
  │ │        [✓ ATIVO AGORA] │  │
  │ └─────────────────────────┘  │
  │ ┌─────────────────────────┐  │
  │ │ [foto] APOLO            │  │
  │ │        Malinois · 2a   │  │
  │ │        [! Pendência]   │  │
  │ │                    ⟳ ›│  │
  │ └─────────────────────────┘  │
  │                              │
  │ [Cancelar]                   │
  └─────────────────────────────┘
```

### 🔧 Estrutura técnica

- **showModalBottomSheet** com `isScrollControlled: true`, `backgroundColor: Colors.transparent`
- **Container** com `borderRadius` top 24px, max-height 70%
- **Handle drag** 36x4px no topo
- **Cards de cão** similares à Tela 1.3 mas mais compactos

### 🔗 Interações

| Elemento | Ação |
|----------|------|
| Tap no backdrop | Fecha o sheet |
| Drag down | Fecha o sheet |
| Tap no cão ativo | (sem ação, já tá ativo) |
| Tap em outro cão | Confirma · troca o cão · atualiza `users.active_dog_id` · dispara rebuild do app |
| Cancelar | Fecha o sheet |

### 🧭 Navegação de saída

- **Cancelar/Fechar:** permanece na tela atual
- **Trocar cão:** permanece na tela atual mas com novo contexto (Dashboard atualiza com dados do novo cão)

### 🚨 Estados especiais

- **Cão único disponível:** sheet diz "Você é titular apenas do Bono. Para conduzir outro cão, contate o gestor."
- **Trocar pra cão não apto:** confirmação extra com aviso

### ⚙️ Regras de negócio

- **Trocar cão NÃO encerra turno** — atualiza apenas `users.active_dog_id`
- **Histórico do turno** registra todas as trocas: `shifts.dog_changes: [{at, from, to}]`
- **Cão antigo continua disponível** pra outros condutores
- **Após troca:** todo o contexto do app reflete o novo cão (header, dashboard, treinos, etc)

### 📊 Estado atual vs Novo

**Estado atual:**
- ⚠️ Provavelmente NÃO existe troca de cão sem encerrar turno
- ⚠️ Usuário pode ter que encerrar e reabrir

**O que muda:**
- 🔨 **Criar fluxo de troca rápida** sem encerrar turno
- 🔨 **Atualizar `users.active_dog_id`** sem mexer em `shifts`
- 🔨 **Registrar `dog_changes`** no documento do turno
- 🔨 **State management** deve reagir à troca (Provider notifyListeners ou Riverpod refresh)

---

## 🎯 RESUMO DE PRIORIDADES PARTE 1

| Tela/Componente | Prioridade | Esforço estimado |
|-----------------|-----------|------------------|
| 1.1 Splash | ALTA | Baixo (1 dia) |
| 1.2 Login | ALTA | Médio (2-3 dias com biometria) |
| 1.3 Seleção de Cão | ALTA | Médio (3 dias) |
| 1.4 Dashboard | ALTA | Alto (4-5 dias) |
| 1.5 Perfil | MÉDIA | Alto (4 dias com selos) |
| 1.6 Header Universal | ALTA | Baixo (1 dia) |
| 1.7 Bottom Nav | ALTA | Baixo (1 dia) |
| 1.8 Bottom Sheet Trocar Cão | MÉDIA | Baixo (1-2 dias) |

**Total estimado da Parte 1:** ~3-4 semanas de trabalho focado.

---

## 📌 ORDEM DE IMPLEMENTAÇÃO SUGERIDA

```
SEMANA 1
  Dia 1-2: Componentes 1.6 + 1.7 (Header e Bottom Nav)
  Dia 3-4: Tela 1.1 Splash
  Dia 5: Tela 1.2 Login - estrutura visual

SEMANA 2
  Dia 1-2: Tela 1.2 Login - biometria e fluxo
  Dia 3-5: Tela 1.3 Seleção de Cão

SEMANA 3
  Dia 1-3: Tela 1.4 Dashboard - estrutura e dados
  Dia 4-5: Tela 1.4 Dashboard - alertas e estado vazio

SEMANA 4
  Dia 1-3: Tela 1.5 Perfil - estrutura e selos
  Dia 4: Componente 1.8 Bottom Sheet trocar cão
  Dia 5: Testes integrados do fluxo completo
```

---

## ⚠️ DEPENDÊNCIAS TÉCNICAS PRÉ-REQUISITO

Antes de iniciar a Parte 1, verificar:

1. **Etapa 1 do `ROADMAP_REFATORACAO.txt` concluída** (limpeza técnica)
2. **Sistema visual do `core/theme/`** atualizado com tokens dos mockups
3. **Pacotes adicionados ao pubspec:**
   - `local_auth: ^2.3.0` (já tem)
   - `flutter_secure_storage: ^10.0.0` (já tem)
   - `go_router` (recomendado, ainda não tem)
   - `intl: ^0.19.0` (já tem)

4. **Coleções Firestore validadas:**
   - `/users` (existente)
   - `/dogs` (existente)
   - `/shifts` (existente)
   - `/dogs/{id}/specialties_state` (NOVA · verificar se já existe)

---

## 📚 PARTES SEGUINTES

**PARTE 2 — Domínios Operacionais (em breve)**
- Ocorrências (iniciar, andamento, edição, finalização, PDF)
- Histórico (lista, detalhe expandido)
- Cão/Prontuário + Vacinação + Peso + Nutrição completas

**PARTE 3 — Treinos e Auxiliares (em breve)**
- Hub de Treinos
- Obediência
- Busca & Captura
- Detecção (Protocolo Ragonha)
- Guarda & Proteção
- Condicionamento
- Saúde (registro de evento)
- Modais auxiliares

---

**FIM DA PARTE 1 · 8 telas/componentes especificados**
