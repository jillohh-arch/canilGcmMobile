# 🛠 SETUP CLAUDE CODE — APP CANIL K9 GCM LIMEIRA

> Guia completo de configuração do Claude Code com skills,
> MCP servers e hooks otimizados pro projeto.

---

## 📦 ESTRUTURA RECOMENDADA

```
~/.claude/                              # configurações globais do Claude Code
├── skills/                             # skills compartilhadas entre projetos
│   └── (vazio inicialmente)
├── settings.json                       # configurações globais
└── mcp.json                            # MCP servers globais

projeto-canil-k9/                       # raiz do seu projeto
├── .claude/
│   ├── skills/                         # skills específicas do projeto
│   │   ├── canil-k9-context/
│   │   │   └── SKILL.md
│   │   ├── flutter-canil-conventions/
│   │   │   └── SKILL.md
│   │   ├── firestore-coexistence/
│   │   │   └── SKILL.md
│   │   ├── audit-trail/
│   │   │   └── SKILL.md
│   │   └── pdf-generation/
│   │       └── SKILL.md
│   ├── settings.json                   # config local
│   ├── mcp.json                        # MCP servers locais
│   └── hooks/                          # scripts de hooks
│       ├── post-edit-dart.sh
│       ├── pre-commit.sh
│       └── session-start.sh
├── CLAUDE.md                           # contexto do projeto (Claude lê automaticamente)
├── lib/                                # código Flutter
├── temp/                               # documentação (não comitar)
│   ├── docs/
│   └── mockups/
└── .gitignore                          # ignorar temp/ e .claude/settings.local
```

---

## 🎯 PASSO 1 — Criar o CLAUDE.md (contexto raiz do projeto)

Esse arquivo é **lido automaticamente** pelo Claude Code toda vez que você abre o projeto. É o "contexto sempre presente".

Crie na raiz do projeto:

```markdown
# Projeto: App Canil K9 GCM Limeira

## Visão geral

App Flutter + Firebase em produção, usado por 6 guardas civis municipais de Limeira-SP. 
Gerencia binômios condutor-cão (K9) com foco em prestação de contas institucional 
e defesa profissional dos condutores.

## Stack

- Flutter 3.x
- Firebase: Auth, Firestore, Storage, App Check
- State management: Provider
- Navegação: Navigator manual (em transição pra go_router)
- Versão atual em produção: v1.0.0+2

## Estrutura

```
lib/
├── core/              # widgets compartilhados, theme, utils
├── features/          # módulos por domínio (auth, dogs, shifts, etc)
├── services/          # serviços Firebase
└── main.dart
```

## Documentação de referência

Pasta `temp/` (não comitada) contém:
- `docs/ESPEC_TECNICA_PARTE_1.md` (Fundação)
- `docs/ESPEC_TECNICA_PARTE_2.md` (Operacional)
- `docs/ESPEC_TECNICA_PARTE_3.md` (Treinos e Saúde)
- `docs/ROADMAP_REFATORACAO.txt`
- `docs/MAPA_NAVEGACAO.txt`
- `mockups/*.html` (25 mockups visuais)

**Sempre consulte esses documentos antes de implementar features novas.**

## Princípios invioláveis

1. **Coexistência com painel React** — outro app web acessa o mesmo Firestore. 
   Mudanças destrutivas em coleções seguem protocolo de 4 fases.

2. **Sem gamificação** — sem XP, ranking, troféus. Apenas selos de conformidade binários.

3. **Trilha de auditoria obrigatória** em todas as escritas Firestore.

4. **Soft delete** sempre (nunca hard delete).

5. **Tom institucional** sério (sem RPG, sem militar gamer, sem inglês decorativo).

6. **Defesa profissional proporcional** — não chamativa, mas completa quando questionada.

## Filtro central de design

"Se um gestor questionar o trabalho do condutor 6 meses depois, esse registro defende ele?"

## Sistema visual

- Paleta dark: bg #050d10, ciano primário #4dd0e1
- Verde #2ecc71 (operacional), amarelo #f1c40f (formação), 
  laranja #e67e22 (nutrição), vermelho #e74c3c (crítico)
- Tipografia: Inter

## Como trabalhar

- Commits pequenos e frequentes
- Sempre rodar `flutter analyze` antes de commitar
- Antes de mudar Firestore, consultar `docs/GUIA_COEXISTENCIA.txt`
- Quando em dúvida, perguntar ao Jilles (usuário)
```

---

## 🎯 PASSO 2 — Criar Skill 1: canil-k9-context

Esta é a skill **mais importante** — carrega contexto institucional sempre.

Crie a pasta:
```bash
mkdir -p .claude/skills/canil-k9-context
```

Crie o arquivo `.claude/skills/canil-k9-context/SKILL.md`:

```markdown
---
name: canil-k9-context
description: Contexto institucional do app Canil K9 GCM Limeira. Carrega automaticamente quando trabalhando em features do app, especialmente decisões de design, UX, ou regras de negócio relacionadas a defesa profissional de condutores K9, prestação de contas institucional, ou casos de auditoria.
---

# Contexto institucional · App Canil K9 GCM Limeira

## Quem é o usuário

Jilles Ragonha, GCM RA 691755, instrutor K9 nacional. Conduz Bono (Malinois 
6 anos, operacional em 3 especialidades) e Apolo (Malinois 2 anos, em formação).

## Por que o app existe

Há discussão institucional de que o canil não trabalha. O app existe pra:
- Prestação de contas
- Proteção do condutor  
- Prontuário institucional
- Evidência defensiva

## Caso real fundador

Jilles deu 800g/dia ao Bono baseado em conhecimento técnico. Veterinário 
institucional dizia 300g. Teve que pagar laudo nutricional do próprio bolso 
pra provar que estava certo. O app transforma isso em registro institucional 
sólido.

## Filtro central

"Se um gestor questionar o trabalho do condutor 6 meses depois, esse 
registro defende ele?"

Aplique esse filtro em todas as decisões de design e UX.

## Princípios norteadores

1. Forma segue função - corta decoração
2. Defesa profissional proporcional (não chamativa)
3. Tom institucional sério (sem RPG/militar gamer/inglês decorativo)
4. Subtração no MVP
5. Auditor é usuário invisível

## Regras invioláveis

- NUNCA reintroduzir gamificação (XP, ranking, troféus)
- NUNCA quebrar coexistência com painel React (consulte GUIA_COEXISTENCIA.txt)
- SEMPRE implementar trilha de auditoria
- SEMPRE usar soft delete
- SEMPRE preservar EXIF em fotos
- Tom institucional: "senha" não "Chave de Acesso", "Sem guia" não "off-leash"

## Aba "Rotina" foi removida

- Alimentação → Cão/Nutrição
- Passeios → Condicionamento
- Escovação/banho/limpeza → cortados

## Bottom Navigation fixo

Turno · Histórico · FAB(🛡 Ocorrência) · Treino · Cão

## Quando você (Claude) precisar tomar decisão de produto

Pause e pergunte ao Jilles. Não invente comportamento.
```

---

## 🎯 PASSO 3 — Skill 2: flutter-canil-conventions

Crie `.claude/skills/flutter-canil-conventions/SKILL.md`:

```markdown
---
name: flutter-canil-conventions
description: Convenções de código Flutter específicas do projeto Canil K9. Use quando criar novas features, screens, widgets, ou refatorar código existente. Define padrões de pastas, nomenclatura, estado, navegação e estilo.
---

# Convenções Flutter · App Canil K9

## Estrutura de pastas

```
lib/
├── core/
│   ├── theme/                  # cores, tipografia, espaçamentos
│   ├── widgets/                # widgets compartilhados (UniversalHeader, etc)
│   ├── services/               # serviços compartilhados (PdfGenerator, etc)
│   └── utils/                  # helpers
├── features/
│   └── [domain]/
│       ├── data/
│       │   ├── models/
│       │   └── repositories/
│       ├── domain/
│       │   └── use_cases/
│       └── presentation/
│           ├── screens/
│           ├── widgets/
│           └── view_models/    # ou providers/
└── services/                   # serviços globais (Firebase)
```

## Nomenclatura

- Arquivos: `snake_case.dart`
- Classes: `PascalCase`
- Variáveis/funções: `camelCase`
- Constantes: `kCamelCase`
- Cores no theme: `Colors.k9Primary`, `Colors.k9Operational`, etc

## Domínios

- `auth` - autenticação
- `dogs` - cães e prontuário
- `shifts` - turnos
- `occurrences` - ocorrências
- `training` - treinos
- `health` - eventos de saúde
- `nutrition` - alimentação
- `profile` - perfil do condutor

## State management

- **Provider** atualmente (em produção)
- Migração futura pra Riverpod considerada
- Cada feature tem seu `ViewModel` (ChangeNotifier)

## Navegação

- **Atual:** Navigator manual
- **Migração planejada:** go_router
- Por enquanto, manter Navigator manual mas estruturar pra facilitar migração

## Padrão de tela nova

```dart
// features/dogs/presentation/screens/dog_profile_screen.dart

class DogProfileScreen extends StatelessWidget {
  const DogProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.k9Background,
      body: SafeArea(
        child: Consumer<DogProfileViewModel>(
          builder: (context, vm, _) {
            if (vm.isLoading) return const LoadingState();
            if (vm.error != null) return ErrorState(error: vm.error!);
            if (vm.dog == null) return const EmptyState();
            
            return Column(
              children: [
                const UniversalHeader(),
                Expanded(child: _buildContent(vm)),
                if (showBottomNav) const BottomNav(active: NavTab.dog),
              ],
            );
          },
        ),
      ),
    );
  }
}
```

## Cores do tema

```dart
class AppColors {
  static const k9Background = Color(0xFF050D10);
  static const k9BackgroundSecondary = Color(0xFF0A1418);
  static const k9Primary = Color(0xFF4DD0E1);
  static const k9Operational = Color(0xFF2ECC71);
  static const k9Formation = Color(0xFFF1C40F);
  static const k9Nutrition = Color(0xFFE67E22);
  static const k9Critical = Color(0xFFE74C3C);
  static const k9Weight = Color(0xFF2C6E91);
  static const k9History = Color(0xFF5A4080);
}
```

## Sempre fazer

- `flutter analyze` antes de commitar
- Imports organizados (dart > flutter > packages > project)
- `const` constructors quando possível
- Null safety estrito
- Tratamento de erro em chamadas Firestore

## Nunca fazer

- Hard delete (sempre soft delete com `deleted_at`)
- Strings hardcoded de UI (usar `core/strings/` se internacionalizar)
- Lógica de negócio em screens (sempre no ViewModel)
- Misturar Provider e setState na mesma feature
```

---

## 🎯 PASSO 4 — Skill 3: firestore-coexistence

Crie `.claude/skills/firestore-coexistence/SKILL.md`:

```markdown
---
name: firestore-coexistence
description: Regras críticas de coexistência com o painel React que acessa o mesmo Firestore. Use sempre antes de criar, modificar ou deletar campos de coleções Firestore. Define protocolo de 4 fases para mudanças destrutivas.
---

# Coexistência Firestore · Canil K9

## Contexto

Existe um painel web React separado que acessa o MESMO Firestore que este app Flutter.
Ambos são controlados pelo Jilles, mas o painel está em produção e não pode quebrar.

## Mudanças aditivas (SEGURAS)

Mudanças que apenas ADICIONAM são seguras:
- Novos campos em documentos existentes
- Novas coleções
- Novos índices

Pode fazer sem cerimônia, apenas avise o Jilles antes.

## Mudanças destrutivas (CUIDADO)

Mudanças que PODEM QUEBRAR o painel React:
- Remover campos
- Renomear campos
- Mudar tipo de campo (string → number)
- Mudar estrutura de subcoleção
- Migrar dados entre coleções

**NUNCA faça diretamente. Use o protocolo de 4 fases:**

## Protocolo de 4 Fases

### Fase 1 — ADITIVA (sem quebrar)
- Adiciona campo NOVO ao lado do antigo
- Ambos coexistem
- App Flutter já usa o novo
- Painel React continua usando o antigo

### Fase 2 — BACKFILL
- Script (Cloud Function ou manual) preenche campo novo
  com dados derivados do antigo
- Validação: campos antigo e novo refletem mesma informação

### Fase 3 — MIGRAÇÃO DO PAINEL
- Jilles atualiza painel React pra usar campo novo
- Período de validação (~1 semana)
- Monitorar erros no Sentry/console

### Fase 4 — CLEANUP
- Após validação, remover campo antigo
- Limpar código de migração
- Atualizar documentação

## Antes de qualquer mudança Firestore, perguntar

1. Essa mudança é aditiva ou destrutiva?
2. Se destrutiva, posso fazer aditiva primeiro?
3. O painel React lê esse campo? (consultar Jilles)
4. Vale a pena ou posso adaptar o código sem mudar o Firestore?

## Coleções e seus consumidores

| Coleção | Flutter app | Painel React |
|---------|-------------|--------------|
| /users | leitura/escrita | leitura/escrita |
| /dogs | leitura/escrita | leitura/escrita |
| /shifts | leitura/escrita | leitura |
| /occurrences | leitura/escrita | leitura |
| /occurrences/{id}/events | leitura/escrita | leitura |

Coleções marcadas NOVA nos documentos de especificação:
- Aditivas, então seguras pra criar

## Regras de segurança

Sempre atualizar `firestore.rules` quando criar coleção nova.
Mostrar diff pro Jilles antes de fazer deploy.

## Quando em dúvida

PAUSA E PERGUNTA. Quebrar painel em produção é inaceitável.
```

---

## 🎯 PASSO 5 — Skill 4: audit-trail

Crie `.claude/skills/audit-trail/SKILL.md`:

```markdown
---
name: audit-trail
description: Padrão obrigatório de trilha de auditoria para todas as escritas Firestore. Use sempre que criar, editar ou deletar documentos. Garante defesa profissional dos condutores K9 com rastreabilidade completa.
---

# Trilha de Auditoria · Padrão Obrigatório

## Por que existe

O app é arquivo de defesa profissional. Toda edição precisa ser rastreável.
Se um gestor questionar um registro 6 meses depois, precisamos provar:
- Quem fez
- Quando fez
- O que mudou (valor antes e depois)

## Estrutura padrão

Todo documento crítico tem campo `audit_trail` (array):

```dart
{
  // ... outros campos
  audit_trail: [
    {
      action: 'created',         // created | updated | deleted | restored
      at: Timestamp,
      by: 'uid_do_user',
      by_name: 'GCM Ragonha',    // snapshot do nome no momento
      by_ra: '691755',           // snapshot do RA
      field: null,               // só preenchido em 'updated'
      old_value: null,
      new_value: null,
      reason: null,              // só preenchido em 'deleted'
    }
  ]
}
```

## Documentos com audit_trail obrigatório

- `/occurrences/{id}` e subcoleção `events`
- `/dogs/{id}/health_events/{id}`
- `/dogs/{id}/feeding_events/{id}`
- `/dogs/{id}/weight_records/{id}`
- `/dogs/{id}/training_sessions/{id}`
- `/dogs/{id}/commands/{id}` (e estágios)
- `/shifts/{id}`
- `/dogs/{id}/nutritional_prescriptions/{id}`

## Como implementar

### Ao criar

```dart
await collection.add({
  // ... dados do documento
  created_at: FieldValue.serverTimestamp(),
  updated_at: FieldValue.serverTimestamp(),
  audit_trail: [
    {
      'action': 'created',
      'at': FieldValue.serverTimestamp(),
      'by': currentUser.uid,
      'by_name': currentUser.name,
      'by_ra': currentUser.ra,
    }
  ],
});
```

### Ao editar

```dart
await doc.update({
  fieldName: newValue,
  updated_at: FieldValue.serverTimestamp(),
  audit_trail: FieldValue.arrayUnion([
    {
      'action': 'updated',
      'at': Timestamp.now(),
      'by': currentUser.uid,
      'by_name': currentUser.name,
      'by_ra': currentUser.ra,
      'field': 'fieldName',
      'old_value': oldValue,
      'new_value': newValue,
    }
  ]),
});
```

### Soft delete

NUNCA fazer `doc.delete()`. Sempre soft delete:

```dart
await doc.update({
  deleted_at: FieldValue.serverTimestamp(),
  deleted_by: currentUser.uid,
  deleted_reason: motivo,  // OBRIGATÓRIO
  audit_trail: FieldValue.arrayUnion([
    {
      'action': 'deleted',
      'at': Timestamp.now(),
      'by': currentUser.uid,
      'by_name': currentUser.name,
      'reason': motivo,
    }
  ]),
});
```

## Fotos: preservar EXIF

Ao salvar fotos no Storage:
- NÃO comprimir/reprocessar a foto original
- Salvar metadata EXIF (data, hora, GPS, dispositivo)
- Em Storage: `/incidents/{id}/photos/{photoId}_original.jpg` (com EXIF)
- Se precisar thumbnail, gerar separadamente: `_thumb.jpg`

## Timestamps imutáveis

- `created_at` NUNCA muda (usa `FieldValue.serverTimestamp()` na criação)
- `updated_at` atualiza a cada edição
- Eventos dentro de subcoleções têm `timestamp` próprio (do evento, não do registro)

## Listagem da trilha

Ao mostrar audit_trail na UI:
- Ordenar por `at` ASC (mais antigo primeiro)
- Mostrar de forma legível: "GCM Silva editou descrição em 12/05 às 14:32"
- No PDF, incluir trilha completa
- Permitir filtrar por tipo de ação (criação, edição, exclusão)
```

---

## 🎯 PASSO 6 — Skill 5: pdf-generation

Crie `.claude/skills/pdf-generation/SKILL.md`:

```markdown
---
name: pdf-generation
description: Padrão de geração de PDFs institucionais (Ocorrência, Carteira Vacinação, Peso, Nutrição, Histórico Mensal). Use quando implementar qualquer geração de PDF do app. Define estrutura visual formal, hash de integridade, QR code e identidade institucional.
---

# Geração de PDFs · Padrão Institucional

## Filosofia

PDFs são o **produto institucional final** do app. Vão pra auditor, comandante, 
promotor, defesa. Saem do tema dark do app e entram em **light mode formal**.

## Pacotes Flutter

```yaml
dependencies:
  pdf: ^3.x.x
  printing: ^5.x.x      # preview e share
  qr_flutter: ^4.x.x    # QR codes
  crypto: ^3.x.x         # SHA-256
```

## Cores por tipo de PDF

| PDF | Cor identidade | Hex |
|-----|----------------|-----|
| Ocorrência | Ciano escurecido | #0A8E9D |
| Carteira de Vacinação | Ciano escurecido | #0A8E9D |
| Histórico de Peso | Azul | #2C6E91 |
| Relatório Nutricional | Laranja | #C25E1F |
| Histórico Mensal | Roxo | #5A4080 |

## Estrutura padrão

### Capa

- Brasão GCM (placeholder até ter o real)
- "GUARDA CIVIL MUNICIPAL DE LIMEIRA"
- "CANIL K9 · [unidade ou subtítulo]"
- Tipo de documento (em destaque)
- Título principal (nome do cão ou ocorrência)
- Card de metadata (datas, contadores)
- ID único: TIPO: YYYY/MM/XXXX-K9
- Footer com identificação do binômio

### Páginas internas

Header padrão:
```
[brasão mini] GCM LIMEIRA · [TIPO DO DOC]    ID:XXXX
─────────────────────────────────────────  (linha colorida)
```

Footer padrão:
```
─────────────────────────────────────────
GCM Limeira · Canil K9 · [Tipo]   Página X de Y
```

### Última página

- Trilha de auditoria
- Card de integridade com hash SHA-256
- QR Code com link de verificação
- Caixa de assinatura tradicional

## Tipografia

- **Inter** (sans-serif) — corpo do texto
- **SF Mono** ou monospace — IDs, hashes, timestamps
- Tamanhos:
  - Título principal: 24pt
  - Seções: 13pt
  - Corpo: 11pt
  - Auxiliar: 9pt
  - Micro (IDs): 7-8pt

## Hash SHA-256

```dart
import 'package:crypto/crypto.dart';
import 'dart:convert';

String calculateDocumentHash(Map<String, dynamic> docData) {
  final jsonString = jsonEncode(docData);
  final bytes = utf8.encode(jsonString);
  final hash = sha256.convert(bytes);
  return hash.toString();
}
```

Hash calculado UMA VEZ ao finalizar documento. Armazenado em 
`occurrences.{id}.integrity_hash`. Re-gerações usam mesmo hash se nada mudou.

## QR Code

Link aponta pra Firebase Hosting com URL pública do documento:

```
https://canilk9.limeira.sp.gov.br/v/{occurrence_id}
```

Autenticação não obrigatória (acesso público pra verificação), 
mas só mostra metadados básicos e hash. Conteúdo completo precisa login.

## Cabeçalho institucional

```dart
pw.Container(
  decoration: pw.BoxDecoration(
    border: pw.Border(
      bottom: pw.BorderSide(color: PdfColor.fromHex('0A8E9D'), width: 2),
    ),
  ),
  child: pw.Row(
    children: [
      pw.Container(
        width: 22, height: 22,
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('0A8E9D'),
          shape: pw.BoxShape.circle,
        ),
        child: pw.Center(child: pw.Text('🛡', style: pw.TextStyle(color: PdfColors.white))),
      ),
      pw.SizedBox(width: 8),
      pw.Text('GCM LIMEIRA · CANIL K9', style: pw.TextStyle(
        color: PdfColor.fromHex('0A8E9D'),
        fontWeight: pw.FontWeight.bold,
        fontSize: 10,
      )),
      pw.Spacer(),
      pw.Text('REG XXXX', style: pw.TextStyle(
        color: PdfColors.grey700,
        fontSize: 9,
      )),
    ],
  ),
)
```

## Princípios

- Light mode SEMPRE (branco/preto/cor de detalhe)
- Linguagem formal institucional ("substância análoga à maconha", não "maconha")
- Sem emojis decorativos no corpo (apenas em ícones específicos)
- Tabelas com zebra striping
- Hierarquia visual clara (títulos > subtítulos > corpo)
- Margens generosas (impressão A4)
- Identificação completa em todas as páginas
```

---

## 🎯 PASSO 7 — Configurar MCP Servers

Crie `.claude/mcp.json`:

```json
{
  "mcpServers": {
    "firebase": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-firebase"],
      "env": {
        "FIREBASE_PROJECT_ID": "seu-project-id"
      }
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "seu-token-aqui"
      }
    },
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/caminho/absoluto/do/projeto"
      ]
    }
  }
}
```

**IMPORTANTE:**
- Tokens e API keys: nunca comitar! Use variáveis de ambiente.
- O arquivo `.claude/settings.local.json` (que tem suas keys) deve estar no `.gitignore`.

---

## 🎯 PASSO 8 — Configurar Hooks

Crie a pasta `.claude/hooks/` e os scripts:

### Hook 1 — `.claude/hooks/post-edit-dart.sh`

```bash
#!/bin/bash
# Roda após edição de arquivo .dart

FILE="$1"

if [[ "$FILE" == *.dart ]]; then
  echo "🔍 Rodando flutter analyze em $FILE..."
  flutter analyze "$FILE"
fi
```

### Hook 2 — `.claude/hooks/pre-commit.sh`

```bash
#!/bin/bash
# Roda antes de commit

echo "🧪 Rodando testes antes do commit..."
flutter test
if [ $? -ne 0 ]; then
  echo "❌ Testes falharam · commit abortado"
  exit 1
fi

echo "🔍 Rodando analyze..."
flutter analyze
if [ $? -ne 0 ]; then
  echo "❌ Analyze encontrou problemas · commit abortado"
  exit 1
fi

echo "✓ Tudo certo, prossegue commit"
```

### Hook 3 — `.claude/hooks/session-start.sh`

```bash
#!/bin/bash
# Roda no início de cada sessão Claude Code

echo "🐕 Bem-vindo ao projeto Canil K9 GCM Limeira"
echo "📂 Documentação em temp/docs/"
echo "🎨 Mockups em temp/mockups/"
echo ""
echo "Status atual:"
git status --short
echo ""
echo "Última versão: $(grep 'version:' pubspec.yaml | head -1)"
```

Dar permissão de execução:

```bash
chmod +x .claude/hooks/*.sh
```

E referenciar em `.claude/settings.json`:

```json
{
  "hooks": {
    "post-edit": ".claude/hooks/post-edit-dart.sh",
    "pre-commit": ".claude/hooks/pre-commit.sh",
    "session-start": ".claude/hooks/session-start.sh"
  }
}
```

---

## 🎯 PASSO 9 — Adicionar ao .gitignore

```
# Documentação temporária (referência local)
temp/

# Configurações locais do Claude Code
.claude/settings.local.json
.claude/cache/
```

**O que comitar:**
- `.claude/skills/*` ✓ (compartilha com time futuro)
- `.claude/settings.json` ✓ (config compartilhada)
- `.claude/mcp.json` ✓ (mas sem tokens)
- `.claude/hooks/*.sh` ✓
- `CLAUDE.md` ✓

**O que NÃO comitar:**
- `.claude/settings.local.json` ✗ (tokens locais)
- `.claude/cache/` ✗
- `temp/` ✗

---

## 🎯 PASSO 10 — Testar setup

Abra novo terminal na raiz do projeto:

```bash
# Inicia Claude Code
claude

# Ele deve carregar:
# - CLAUDE.md automaticamente
# - Skills do projeto
# - MCP servers configurados
```

Teste com prompt simples:

```
Liste as skills carregadas neste projeto
```

Deve listar as 5 skills do Canil K9.

---

## 🎯 USO NO DIA A DIA

### Início de sessão

Claude Code já carrega contexto automaticamente. Não precisa colar Prompt 1.

### Pra cada tarefa nova

Use Prompt 2 do documento `PROMPTS_CLAUDE_CODE.md`, adaptado:

```
Implementar Tela 1.4 Dashboard.

Especificação: temp/docs/ESPEC_TECNICA_PARTE_1.md seção Tela 1.4
Mockup: temp/mockups/10_dashboard.html

[resto do prompt]
```

Claude vai automaticamente:
- Carregar context da skill `canil-k9-context`
- Aplicar convenções da skill `flutter-canil-conventions`
- Consultar `firestore-coexistence` quando mexer no Firestore
- Aplicar `audit-trail` em escritas
- Usar `pdf-generation` quando gerar PDFs

---

## 📊 CUSTO ESTIMADO

Claude Code via API (Anthropic):

- **Modelo Sonnet 4** (recomendado pra esse projeto): ~$3/M tokens input, $15/M output
- **Sessão típica de 30min**: ~$0.50-$2.00
- **Dia de desenvolvimento (8h)**: ~$10-$30
- **Mês inteiro** (~22 dias): ~$220-$660

Pra projeto de 7 meses: ~$1.500-$4.500 total em API.

**Compare com:**
- Contratar dev Flutter pleno por 7 meses: ~R$60-80mil
- Você sozinho: tempo seu

API é investimento alto mas escala com produtividade.

---

## 🎯 ALTERNATIVA HÍBRIDA (recomendada)

Pra economizar custos, use estratégia mista:

1. **Claude Code (API)** pra:
   - Tarefas complexas (implementar tela nova)
   - Refatoração (decisões arquiteturais)
   - Debug difícil
   - Revisões

2. **Cursor ou Copilot** pra:
   - Autocomplete de código
   - Pequenas edições
   - Boilerplate

3. **Anthropic claude.ai** pra:
   - Decisões de produto (nosso uso atual)
   - Documentação
   - Brainstorming

Combinando, fica mais barato e cada ferramenta no seu forte.

---

## ✅ CHECKLIST DE SETUP

- [ ] Pasta `.claude/skills/` criada com 5 skills
- [ ] `CLAUDE.md` na raiz do projeto
- [ ] `.claude/mcp.json` configurado (sem tokens commitados)
- [ ] Hooks criados e com permissão de execução
- [ ] `.gitignore` atualizado
- [ ] `temp/` populada com 3 documentos + 25 mockups
- [ ] `claude` rodando e carregando contexto
- [ ] Teste de skill: "liste as skills carregadas"
- [ ] Teste de hook: editar um .dart e ver `flutter analyze` rodando

---

**Quando estiver tudo configurado, você está pronto pra começar a implementação.**

🛡 Boa execução, Ragonha.
