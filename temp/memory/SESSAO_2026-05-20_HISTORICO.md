# Sessão 2026-05-20 — Tela 2.7 Histórico

## Resumo

Reescrita completa da tela de Histórico (Tela 2.7) conforme mockup `13_historico (1).html`.
Commit: `8542a3d` | Branch: `claude/condescending-payne-20b7aa` → merged to `main`

## O que foi feito

### 1. Integração de Ocorrências no Histórico
- `history_data_loader.dart`: adicionado `OccurrenceViewModel.watchByDog(dogId)` no `_loadAllData()`
- Novo método `_buildOccurrenceEntry(Occurrence)` que mapeia ocorrências do novo fluxo para `HistoryEntry`
- Ocorrências criadas via `StartOccurrenceScreen` agora aparecem na timeline

### 2. Header replicado do padrão Turno
- Removido `BinomioHeader` genérico
- Criado `_HistoryShiftHeader` inline replicando o visual do `_ShiftHeader` da aba turno:
  - Avatares sobrepostos 44px (cão + condutor)
  - "Bono · GCM Ragonha" + dot verde "Turno ativo" + elapsed
  - Botões ⇄ e 👤

### 3. Timeline compacta
- `history_timeline_item.dart`: layout com hora (36px) + ícone circular emoji + título + meta row
- Badges: `_AuthorBadge` (VOCÊ ciano / outros cinza), `_InProgressBadge` pulsante
- Navegação: in-progress → `ActiveOccurrenceScreen`, outros → `RegistroDetalhePage`

### 4. Filtros inline
- `history_filters.dart`: chips horizontais de período e categoria com emojis
- Bottom sheet "Mais filtros" com `_FilterSheetGroup`

### 5. Tela de Detalhe (Tela B)
- `history_detail_screen.dart` reescrito conforme mockup:
  - Header: ‹ voltar + "DETALHE DO REGISTRO" + título + ⋯
  - Card resumo: emoji contextual (🛡/⚕/🎯/🍖) + título + data/local
  - RESULTADO: parseia `_outcomes` → cards com labels reais (DROGA APREENDIDA, ARMA APREENDIDA, etc.)
  - INFORMAÇÕES: Duração · Condutor · Cão · Equipe · Veículo · Local (com emojis)
  - LINHA DO TEMPO: ícones coloridos contextuais (▶ início, 📍 chegada, 🐾 cão, 📷 foto, 🛡 verificação, ✓ finalizado)
  - TRILHA DE AUDITORIA: rows com ícone + ação + user + timestamp
  - CTA bar: "Gerar PDF" (outline + ícone) + "Compartilhar" (fill + ícone)

## Pendências identificadas

- **Header redundante**: os dois cabeçalhos (título + card resumo) mostram info repetida. Usuário vai preparar mockup atualizado para ajustar.
- **Exportar PDF do histórico**: botão existe mas mostra snackbar placeholder

## Arquivos modificados

```
lib/features/history/presentation/screens/
├── history_data_loader.dart    (integração OccurrenceViewModel)
├── history_detail_screen.dart  (reescrita completa)
├── history_filters.dart        (chips + bottom sheet)
├── history_screen.dart         (header + estrutura)
├── history_timeline_item.dart  (item compacto + badges)
└── history_timeline_list.dart  (agrupamento por dia)
```

## Decisões técnicas

- `HistoryEntry.originalModel` guarda referência ao `Occurrence`/`Incident` original para navegação
- `RecordDetail.fromEntry()` faz parsing inteligente dos details map para popular campos
- Emojis usados em vez de Material Icons nos cards para consistência com mockup
- `_OutcomeDisplay` mapeia strings do Firestore (`drug_seized`, etc.) para labels PT-BR
