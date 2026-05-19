# Sessão — Telas 2.3 e 2.4 (Edição de Evento + Wizard de Finalização)

**Data:** 2025-01-27  
**Branch:** `claude/vigilant-mayer-abfe1f` → merged to `main`  
**Commit:** `44da808`

---

## O que foi feito

### Correções na Tela 2.2

- **SnackBar cinza removida** — não aparece mais "Registrando: ..." ao adicionar evento rápido. Feedback agora é badge "Salvo agora" inline.
- **Timeline invertida** — query no Firestore usa `descending: true`, eventos mais recentes no topo.
- **Índice Firestore criado** — índice composto `deleted_at ASC + timestamp DESC` na coleção `events` (necessário após mudança de ordenação).

### Tela 2.3 — Edição de Evento (nova)

**Arquivo:** `lib/features/occurrences/presentation/screens/edit_event_screen.dart`

Tela fullscreen de criação/edição de evento da timeline:
- Chips de horário (Agora / Há 5min / Editar manual com TimePicker)
- Radio list vertical de categorias (`OccurrenceEventCategory` — 8 valores)
- Campos título (obrigatório) + descrição (opcional, multiline)
- Galeria horizontal de fotos com upload ao Firebase Storage (`MediaProcessingService` + `StorageService`)
- Trilha de auditoria expansível (modo edição)
- Soft delete com dialog de motivo obrigatório
- PopScope com confirmação de descarte se houver mudanças
- CTA sticky "SALVAR EVENTO"

**Navegação conectada:**
- Tap em evento da timeline → `EditEventScreen` em modo edição
- "+ Outro evento / Central" → `EditEventScreen` em modo criação
- Bottom sheet antigo removido

### Tela 2.4 — Wizard de Finalização (nova)

**Arquivo:** `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart`

Wizard linear de 3 passos com PageView controlado (sem swipe):

**Passo 1 — Relato Final:**
- Campo multiline obrigatório
- Botão "GRAVAR RELATO" com transcrição em tempo real via `SpeechDictationService`
- Indicador visual "Ouvindo..." com dot pulsante
- Contador de caracteres

**Passo 2 — Resultado (Multi-Select):**
- Grid 2x3 com os 6 `OccurrenceResult` (Droga, Arma, Pessoa detida, BO, Sem constatação, Apoio prestado)
- "Sem constatação" é mutuamente exclusivo com os demais
- Mínimo 1 resultado obrigatório para avançar

**Passo 3 — Detalhes por Resultado:**
- Campos condicionais baseados nos resultados selecionados:
  - Droga: tipo, quantidade, unidade
  - Arma: tipo, quantidade
  - Pessoa detida: quantidade, encaminhamento
  - BO: número, tipo
- Se só "Sem constatação" ou "Apoio prestado": mensagem "Nenhum detalhe necessário"

**Infraestrutura do wizard:**
- Progress bar 3 segmentos (verde = completo, ciano = atual, cinza = futuro)
- Card de contexto fixo (tipo + duração + eventos)
- Footer com Voltar / Próximo / Concluir
- SHA-256 `integrityHash` gerado na conclusão
- Botão ✕ → dialog "Salvar como rascunho?" (status: `finalizing`)
- Após concluir → pop até tela anterior

---

## Arquivos criados

| Arquivo | Linhas |
|---------|--------|
| `edit_event_screen.dart` | ~924 |
| `finalize_occurrence_screen.dart` | ~915 |

## Arquivos modificados

| Arquivo | Mudança |
|---------|---------|
| `active_occurrence_screen.dart` | Navegação real para 2.3 e 2.4, removido bottom sheet e stubs |
| `occurrence_event_repository.dart` | Query `descending: true` |
| `occurrence_view_model.dart` | +6 linhas (updateOccurrence) |
| `active_occurrence_event_card.dart` | Thumbnails, botão editar, badge editado |
| `active_occurrence_timeline.dart` | Linha vertical conectora |
| `start_occurrence_screen.dart` | Refactor widgets extraídos |
| `start_occurrence_cta.dart` | Ajuste menor |
| `start_occurrence_info_grid.dart` | Refactor |
| `start_occurrence_observation.dart` | Widget extraído (novo) |
| `start_occurrence_time_chips.dart` | Widget extraído (novo) |

## Serviços reutilizados

- `MediaProcessingService` — pick + compress imagens
- `StorageService` — upload ao Firebase Storage
- `SpeechDictationService` — transcrição de áudio pt_BR
- `AuditService` — trilha de auditoria inline
- `crypto` package — SHA-256 para integrity hash

## Verificação

- `dart analyze lib/features/occurrences/` → zero issues
- Build release APK gerado e copiado para Google Drive

## Próximos passos sugeridos

- Tela 2.5 — Confirmação Final (tela de sucesso pós-finalização)
- Documento 2.6 — PDF da Ocorrência
- Tela 2.7 — Histórico (Lista Filtrada)
- Testar fluxo completo no device (criar → eventos → finalizar)
