# Sessao 2026-05-26 — Auditoria Completa + Fix Finalizacao de Ocorrencia

## Contexto
Sessao focada em duas frentes: auditoria completa do estado real do app e resolucao de bug critico de loading infinito na finalizacao de ocorrencias.

---

## 1. Auditoria Completa do App

### Objetivo
Produzir retrato fiel do estado do codigo, confirmando ou refutando hipoteses do panorama anterior.

### Resultado Principal — Persistencia
**O bug "registros somem ao reabrir" NAO e de persistencia.** Todos os tipos de registro escrevem corretamente no Firestore. O problema era de leitura/exibicao:
- ViewModels propagavam exceptions (`throw Exception`) no catch do fetch
- Sem indicador de loading — mostrava "vazio" durante o fetch
- Filtro padrao restritivo ("Esta semana")
- NutritionViewModel com early-return impedindo reload

### Correcoes de Historico
- Filtro padrao mudado para "Hoje"
- `TrainingViewModel.fetchTrainingsForDog` — nao propaga mais exception
- `HealthViewModel.fetchHealthLogsForDog` — idem
- `TrainingService.getTrainingsForDog` — busca cada collection independentemente com try/catch
- Aceita `training.dogId.isEmpty` no filtro (subcollections sem dogId explicito)
- `NutritionViewModel.loadForDog` — adicionado parametro `forceReload`
- Debug prints adicionados no `_loadAllData`

### Relatorio Gerado
Arquivo: `temp/docs/AUDITORIA_ESTADO_APP.md`
- Tabela de persistencia por tipo (todos OK)
- Relatorio por dominio (14 dominios)
- Top 10 riscos
- Inventario de dados hardcoded
- Resolucao de cada hipotese do panorama original

---

## 2. Fix Finalizacao de Ocorrencia — Loading Infinito

### Sintoma
Ocorrencia com 8 acoes, fotos e atualizacoes de GPS. Ao clicar finalizar, loading infinito sem sair da tela.

### Causa Raiz
1. **Draft save inflava o audit_trail**: Cada auto-save (700ms debounce) adicionava ao `audit_trail` uma entrada com `finalization_draft` inteiro como oldValue/newValue
2. **`docRef.get()` no finalize**: Precisava baixar documento inteiro (potencialmente proximo de 1MB) antes de atualizar
3. **Firestore SDK nao respeita `Future.timeout`**: O await ficava pendente indefinidamente

### Solucao Aplicada

#### occurrence_repository.dart
- **Novo metodo `saveDraft()`**: Update direto sem `docRef.get()`, sem audit trail
- **`finalize()` refatorado**: 
  - Removido `docRef.get()` (nao precisa ler documento antes)
  - Usa `docRef.update()` com `FieldValue.arrayUnion` (preserva audit_trail anterior)
  - Timeout de 15s — se nao confirmar, write fica na fila local do SDK
  - Removido `Occurrence.fromMap()` (evita parsear documento pesado)
- **`update()` otimizado**: `_noAuditFields` exclui `finalization_draft` e `status` do audit trail

#### occurrence_view_model.dart
- **Novo metodo `saveDraft()`**: Usa o repository.saveDraft leve
- **Protecao contra dupla finalizacao**: Check `_isLoading` e `status.isClosed`
- **Cancela stream `watchOpen`** apos finalize (evita re-emissao de valor stale)
- **Novo getter `isWatchingOpen`**: Permite MainRootScreen detectar stream inativo

#### finalize_occurrence_screen.dart
- **`_saveDraft()` usa `vm.saveDraft()`** (nao mais `vm.updateOccurrence`)
- **Timeout de 30s** com mensagem ao usuario
- **Debug prints** para diagnostico

#### main_root_screen.dart
- **Reinicia `watchOpen`** quando detecta stream inativo (`!isWatchingOpen`)
- Banner de ocorrencia aberta desaparece imediatamente apos finalize

---

## 3. Conformidade com Specs Validada

- Hash SHA-256 com serializacao deterministica
- Audit trail preservado com arrayUnion
- Soft delete (nunca hard delete em ocorrencias)
- Draft auto-save com debounce 700ms
- Status finalizing -> finalized correto
- finalization_draft deletado ao finalizar
- Imutabilidade pos-finalizacao (apenas PDF metadata permitido)
- Timeout para conexao instavel (write enfileirado localmente)

---

## 4. Arquivos Modificados

### Ocorrencias
- `lib/features/occurrences/data/occurrence_repository.dart`
- `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart`
- `lib/features/occurrences/presentation/view_models/occurrence_view_model.dart`

### Historico
- `lib/features/history/presentation/screens/history_data_loader.dart`
- `lib/features/history/presentation/screens/history_screen.dart`

### ViewModels
- `lib/features/training/presentation/viewmodels/training_viewmodel.dart`
- `lib/features/health/presentation/viewmodels/health_viewmodel.dart`
- `lib/features/nutrition/presentation/viewmodels/nutrition_viewmodel.dart`

### Services
- `lib/features/training/data/training_service.dart`

### Navegacao
- `lib/features/app_shell/presentation/screens/main_root_screen.dart`

### Docs
- `temp/docs/AUDITORIA_ESTADO_APP.md` (relatorio completo)

---

## 5. Proximos Passos Sugeridos (do Top 10 Riscos)

1. Substituir hard deletes por soft delete em `training_service`, `dog_service`, `user_service`
2. Implementar cache offline real (hive/sqflite) para sessoes de deteccao em campo
3. Adicionar indicador de loading no historico
4. Implementar confirmacao veterinaria em Saude
5. Criar endpoint de verificacao `/v/{id}` para QR code do PDF
6. Diferenciar materiais de odor por linha de deteccao
7. Tornar comandos de obediencia e exercicios de condicionamento configuraveis via Firestore
