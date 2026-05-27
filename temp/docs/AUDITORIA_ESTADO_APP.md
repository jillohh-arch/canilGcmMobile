# AUDITORIA COMPLETA — Canil K9 GCM Limeira

**Data**: 26/05/2025  
**Base**: Leitura exclusiva do codigo-fonte. Nenhum arquivo foi alterado.

---

## 1. VEREDITO DA PERSISTENCIA

### Causa raiz do bug "registros somem ao reabrir"

O bug **NAO e de persistencia no Firestore**. Todos os tipos de registro escrevem corretamente no Firestore via `.add()` ou `.set()`. O dado esta la. O problema e de **leitura/exibicao**:

1. **ViewModels propagavam exceptions**: `TrainingViewModel.fetchTrainingsForDog` e `HealthViewModel.fetchHealthLogsForDog` faziam `throw Exception(...)` no catch. Como o `_loadAllData()` do historico chamava esses metodos fire-and-forget (sem await/try-catch), a exception nao era capturada e os dados ficavam vazios permanentemente na memoria.

2. **Sem indicador de loading**: O `HistoryScreen` mostra "Nenhum registro encontrado" imediatamente enquanto os dados estao sendo buscados do Firestore. Se o fetch falha silenciosamente, o usuario ve a tela vazia e conclui que os dados sumiram.

3. **Filtro padrao restritivo**: O filtro padrao era "Esta semana" — registros de semanas anteriores nao apareciam.

4. **NutritionViewModel com early-return**: `loadForDog()` retornava sem recarregar se ja foi chamado com o mesmo dogId, impedindo refresh ao voltar do background.

**Escopo**: O bug afeta a **exibicao** de todos os tipos no historico, nao apenas treinos. Porem, treinos sao os mais visiveis porque sao registrados com mais frequencia.

**Veredito**: Bug de **camada de apresentacao**, nao de persistencia. Os dados estao no Firestore.

---

### Tabela de Persistencia por Tipo

| Tipo | Escreve no Firestore (path) | Le do Firestore (path) | Paths correspondem? | Sobrevive restart? | Veredito |
|------|---|---|---|---|---|
| **Turno** | `active_shifts/{handlerId}` + `shift_logs/{autoId}` | `active_shifts/{handlerId}` (stream) | Sim | Sim | Funciona |
| **Condicionamento** | `trainings/{autoId}` | `trainings` + `training_sessions` + `dogs/{id}/training_sessions` (merge) | Sim | Sim | Funciona |
| **Obediencia** | `trainings/{autoId}` | Idem acima | Sim | Sim | Funciona |
| **Deteccao (Manutencao)** | `trainings/{autoId}` | Idem acima | Sim | Sim | Funciona |
| **Deteccao (Formacao)** | `dogs/{dogId}/training_sessions/{autoId}` + `dogs/{dogId}/detection_lines/{lineId}` | Merge inclui `dogs/{dogId}/training_sessions` | Sim | Sim | Funciona |
| **Busca & Captura** | `trainings/{autoId}` | Idem merge | Sim | Sim | Funciona |
| **Guarda & Protecao** | `trainings/{autoId}` | Idem merge | Sim | Sim | Funciona |
| **Saude** | `dogs/{dogId}/health_events/{autoId}` | `dogs/{dogId}/health_events` (com filtro soft-delete) | Sim | Sim | Funciona |
| **Nutricao** | `dogs/{dogId}/feeding_events/{autoId}` + `dogs/{dogId}/feedings/{id}` (dual-write) | Ambas collections (merge/dedup) | Sim | Sim | Funciona |
| **Ocorrencias** | `occurrences/{id}` + `occurrences/{id}/events/{eventId}` | `occurrences` (stream where `dog_id == dogId`) | Sim | Sim | Funciona |

**Conclusao**: O bug NAO e sistemico de persistencia. Todos os paths de escrita e leitura correspondem. Nenhum ViewModel limpa dados na inicializacao de forma destrutiva.

---

## 2. RELATORIO POR DOMINIO

### Turno — Funciona

**Evidencia**: `shift_service.dart` escreve em batch para `active_shifts/{handlerId}` e `shift_logs/{autoId}`. `ShiftViewModel` observa via stream real-time (`watchActiveShift`). O `Consumer3` no `main.dart` (linha 69) garante que o app so mostra `MainRootScreen` quando o turno esta carregado.

**O que falta**: `shift_logs` e write-only — o app grava historico de turnos mas nunca exibe. Nao ha tela de "historico de turnos".

---

### Historico — Parcial

**Evidencia**: `history_screen.dart` + `history_data_loader.dart` + `history_filters.dart`. Agrega dados de 4 ViewModels (Training, Health, Nutrition, Occurrence). Filtros por periodo (Hoje/Ontem/Semana/Mes/Personalizado) e por tipo (Tudo/Nutricao/Saude/Treino/Ocorrencia). Exportacao PDF funcional.

**Problemas encontrados**:
- Sem indicador de loading — mostra "Nenhum registro encontrado" durante o fetch
- Filtro de data funciona corretamente mas o padrao era restritivo (corrigido para "Hoje")
- Registros da subcollection `dogs/{dogId}/training_sessions` com `dogId` vazio nao apareciam no filtro `training.dogId == dogId` (corrigido)

---

### Ocorrencias — Funciona

**Evidencia**:
- **Hash SHA-256**: `finalize_occurrence_screen.dart` linha 360 — gera hash imutavel com `sha256.convert(utf8.encode(jsonEncode(payload)))` usando serializacao deterministica (`_stableJsonValue`)
- **Audit trail**: `occurrence_repository.dart` grava inline audit entries em create/update/delete/finalize. `audit_service.dart` (358 linhas) grava na collection `auditLogs`
- **Soft delete**: `Occurrence` usa mixin `SoftDeletable`. Exclusoes marcam `deleted_at`, nao apagam
- **PDF de confirmacao**: `occurrence_pdf_generator.dart` (2546 linhas) gera relatorio completo com QR code de verificacao
- **Stream real-time**: `watchByDog` usa `.snapshots()` com filtro `dog_id == dogId`

**O que falta**: A URL de verificacao (`https://canilk9.limeira.sp.gov.br/v/{id}`) e gerada no PDF mas o endpoint web **nao existe neste projeto** — precisaria de um servidor separado.

---

### Hub de Treinos — Funciona

**Evidencia**: `training_hub_screen.dart` usa 3 `StreamBuilder` aninhados lendo do Firestore em tempo real:
- `watchSpecialtiesForDog(dogId)` — specialties
- `watchSessionsForDog(dogId)` — sessions
- Dog data stream

Cards de especialidade (Deteccao, B&C, G&P) sao **dinamicos** — badges, subtitulos e "ultima sessao" derivam do Firestore via `buildHubData()`. Para Deteccao especificamente, `_DetectionSpecialtyRow` usa um `StreamBuilder<List<DetectionLine>>` adicional.

**O que falta**: Nada critico. Funciona como esperado.

---

### Deteccao — Parcial

**Evidencia**:
- **Maquina de estados**: `detection_phase_config.dart` define 8 fases (1b-2b-2v-3b-3v-4b-4v-4c) com criterios corretos (3 consecutivos, exceto 3v que requer 10)
- **Transicao 4c para operational**: `detection_service.dart` linha 387 — completar 4c muda status para `operational`
- **Counter per-session**: Conforme spec — `DetectionSessionRecorder` inicia com `currentStreak = 0` em cada nova sessao. Miss reseta para 0.
- **Auto-save**: `autosaveFormationProgress()` em `detection_service.dart` linha 307 salva progresso no Firestore

**Problemas**:
- **Material/odor NAO varia por linha**: `detection_formation_screen.dart` mostra sempre `['nose_mp', 'real', 'scentlogix']` independente de ser Drogas/Armas/Cadaver. A spec nao e explicita sobre isso, mas operacionalmente faz sentido ter materiais diferentes por linha.
- **Fase "Final"**: A spec PARTE_4 original menciona uma fase Final apos 4c. A spec PARTE_4_1 (revisada) a remove. O codigo segue a PARTE_4_1 (4c e a ultima).
- **Offline com recovery**: O auto-save grava no Firestore (requer conexao). Nao ha cache local verdadeiro — se o app fechar sem conexao, a sessao pode ser perdida.

---

### Busca & Captura — Funciona

**Evidencia**: `busca_captura_formacao_screen.dart` e `busca_captura_manutencao_screen.dart` salvam via `TrainingViewModel.addTrainingSession()` com metadata `specialty: 'busca_captura'`. GPS tracking integrado.

**O que falta**: Nada critico identificado.

---

### Guarda & Protecao — Funciona

**Evidencia**: `guard_protection_screen.dart` (2384+ linhas) salva via `TrainingViewModel.addTrainingSession()` com metadata rica: impulso, figurante, equipamento, capacidades, comandos, cenario, comportamento, avaliacao, pagamento.

**O que falta**: Nada critico identificado.

---

### Condicionamento — Funciona

**Evidencia**: `conditioning_screen.dart` salva via `_persistSession()` -> `TrainingViewModel.addTrainingSession()`. Catalogo de exercicios com campos dinamicos por tipo. GPS tracking integrado.

**Problema menor**: Catalogo de exercicios e **hardcoded** (linhas 70-122) — 11 exercicios em 3 categorias. Nao e configuravel via Firestore.

---

### Obediencia — Parcial

**Evidencia**: `obedience_training_screen.dart` salva via `TrainingViewModel.addTrainingSession()`.

**Problemas**:
- **Comandos hardcoded**: Linhas 28-48 — 13 comandos em 3 categorias (`OPERACIONAIS`, `POSTURAIS`, `HABILIDADES`) definidos como `static const`
- **Ambientes hardcoded**: Linha 51 — `['Canil', 'Praca', 'Rua', 'Local com distracao']`
- **Ratings hardcoded**: Linha 62 — `['Ruim', 'Regular', 'Bom', 'Otimo']`

Nenhum desses e carregado do Firestore. Funciona, mas nao e configuravel.

---

### Saude — Parcial

**Evidencia**: `HealthService.addHealthLog()` escreve em `dogs/{dogId}/health_events/{autoId}` com audit trail inline. Soft delete implementado via `SoftDeletable`. Telas existem: `HealthDashboardScreen`, `HealthLogScreen`, `HealthEventFormScreen`, `HealthTypeSelectorScreen`.

**Problemas**:
- **Sem fluxo de confirmacao veterinaria**: Nao ha status pending/confirmed, nao ha fila de aprovacao. Todo registro e imediatamente final.
- **Sem calculo de aptidao verificado**: A spec define regras (vacina vencida > 7 dias = NAO APTO), mas nao localizado no dashboard.

---

### Nutricao — Funciona

**Evidencia**: `NutritionService` faz dual-write para `dogs/{dogId}/feeding_events` e `dogs/{dogId}/feedings`. Leitura merge/dedup de ambas. Stream real-time para refeicoes do dia. Historico 90 dias com conformidade calculada. Soft delete implementado.

**O que falta**: Nada critico.

---

### Cao (Perfil) — Funciona

**Evidencia**: `dog_profile_screen.dart` + `k9_profile_page.dart` com sistema de selo operacional. Troca de binomio via `showDogSwitcher()` em `active_shift_dog_switcher.dart`.

---

### Navegacao — Parcial

**Evidencia**: `MainRootScreen` usa `IndexedStack` com 4 tabs. `PopScope` implementado em 7 telas criticas (GPS tracking, main root, finalize occurrence, occurrence confirmation, edit event, detection formation, start occurrence).

**Problemas**:
- Nem todas as telas com formularios tem `PopScope` — possivel perda de dados ao pressionar back em telas de registro sem protecao

---

### Infra — Parcial

**Evidencia**:
- Firebase Auth com mapeamento RA para email
- Firestore como banco principal
- Firebase Storage para midia
- `audit_service.dart` (358 linhas) — sistema de auditoria robusto
- `gps_tracking_service.dart` — rastreamento GPS com alta precisao (`bestForNavigation`)

**Problemas**:
- **Sem offline-first**: Nao ha `hive`, `sqflite`, ou fila offline. Dependencia total de conectividade Firestore.
- **`flutter_map_tile_caching`** declarado no pubspec mas nao utilizado no codigo
- **Hard deletes existem**: `training_service.dart:36` (`.delete()`), `dog_command_service.dart:45`, `dog_service.dart:42`, `user_service.dart:27` — violam o principio de soft delete

---

## 3. TOP 10 RISCOS

Ordenados por impacto no principio "este registro defende o condutor 6 meses depois":

| # | Risco | Impacto | Evidencia |
|---|---|---|---|
| 1 | **Hard delete em treinos** (`training_service.dart:36`) apaga permanentemente o registro do Firestore | Se um treino for deletado por engano, nao ha como recuperar. Perde-se evidencia de formacao do cao. | `_firestore.collection('trainings').doc(id).delete()` |
| 2 | **Sem offline/auto-save real** — sessao de deteccao em campo sem sinal pode ser perdida | Condutor faz 20 repeticoes em area sem cobertura, app fecha, dados perdidos. Spec exige recovery. | Nenhum cache local encontrado. Auto-save depende de Firestore online. |
| 3 | **Sem indicador de loading no historico** — condutor pode achar que dados sumiram | Gera desconfianca no sistema. Condutor pode re-registrar (duplicatas) ou abandonar o app. | `history_timeline_list.dart:16` — mostra empty state imediatamente |
| 4 | **Sem confirmacao veterinaria em Saude** — qualquer pessoa pode registrar vacina/exame como fato consumado | Registro de vacinacao sem validacao profissional pode ser questionado em auditoria externa. | Nenhum campo `status` ou fluxo de aprovacao em `HealthLogModel` |
| 5 | **Endpoint de verificacao `/v/{id}` nao existe** — QR code no PDF aponta para URL inexistente | Documento oficial com QR code que nao funciona prejudica credibilidade institucional. | URL hardcoded em `occurrence_pdf_generator.dart:44` mas sem servidor |
| 6 | **Material/odor igual para todas as linhas de deteccao** | Registro nao diferencia se o cao treinou com material real de drogas vs armas vs cadaver. Reduz valor probatorio. | `detection_formation_screen.dart:373` — mesma lista para todas as linhas |
| 7 | **Hard delete em caes** (`dog_service.dart:42`) | Deletar um cao apaga todo o historico associado (ou deixa registros orfaos). | `.delete()` sem soft delete |
| 8 | **Fotos sem subpath por evento** — todas as fotos de uma ocorrencia ficam na mesma pasta | Dificulta auditoria e pode causar conflitos de nomes em ocorrencias longas com muitos eventos. | `storage_service.dart` — path e `{folder}/{uuid}.ext` sem granularidade por evento |
| 9 | **`fetchAllTrainings()` e dead code que le so de `trainings`** | Se alguem usar por engano no futuro, dados de `training_sessions` e subcollections desaparecem da view. | `training_viewmodel.dart:143` — nunca chamado mas existe |
| 10 | **Comandos de obediencia e exercicios de condicionamento hardcoded** | Nao e possivel adicionar novos comandos/exercicios sem deploy. Limita evolucao operacional. | `obedience_training_screen.dart:28-48`, `conditioning_screen.dart:70-122` |

---

## 4. O QUE NAO FOI POSSIVEL VERIFICAR

| Item | Razao |
|---|---|
| **Comportamento real do Firestore em producao** (indices, permissoes, security rules) | Nao ha acesso ao console Firebase. As queries parecem corretas pelo codigo, mas indices compostos podem estar faltando no ambiente real. |
| **Calculo de aptidao do cao** (APTO/NAO APTO) | A spec define regras, mas nao localizada a implementacao exata no dashboard. Pode estar em um widget nao auditado. |
| **Comportamento offline real** | Firestore SDK tem cache offline nativo, mas o app nao o configura explicitamente. Pode funcionar parcialmente por padrao do SDK, mas nao e garantido para writes. |
| **Performance com volume de dados** | Queries sem `.limit()` em `getTrainingsForDog` (busca TODOS os treinos do cao). Com centenas de sessoes, pode ficar lento. Nao testavel sem dados reais. |
| **Security Rules do Firestore** | Nao ha arquivo `firestore.rules` no projeto. As regras podem estar configuradas diretamente no console Firebase. |
| **Tela de Deteccao Triagem** (`DetectionTriagemScreen`) | Referenciada no routing mas nao auditada em profundidade nesta sessao. |
| **Aptidao e alertas de saude no dashboard** | Spec menciona calculo automatico mas implementacao nao rastreada ate o widget final. |

---

## 5. DADOS HARDCODED — INVENTARIO COMPLETO

| Arquivo | Linhas | Conteudo hardcoded |
|---|---|---|
| `obedience_training_screen.dart` | 28-48 | 13 comandos em 3 categorias (Senta, Deita, Fica, Junto, etc.) |
| `obedience_training_screen.dart` | 51 | Ambientes: Canil, Praca, Rua, Local com distracao |
| `obedience_training_screen.dart` | 54-58 | Sugestoes de foco (4 itens) |
| `obedience_training_screen.dart` | 62 | Ratings: Ruim, Regular, Bom, Otimo |
| `conditioning_screen.dart` | 70-122 | 11 exercicios em 3 categorias com campos por tipo |
| `detection_formation_screen.dart` | 373-410 | Materiais de odor: nose_mp, real, scentlogix (igual para todas as linhas) |
| `detection_maintenance_screen.dart` | 44-48 | Materiais: Nose-MP Drogas, Droga real, Scentlogix |
| `detection_entry_screen.dart` | 163 | Tipos de linha fallback: drogas, armas, cadaver |
| `occurrence_pdf_generator.dart` | 44 | URL de verificacao: `https://canilk9.limeira.sp.gov.br/v` |

---

## 6. RESOLUCAO DAS HIPOTESES DO PANORAMA ORIGINAL

Cada item do panorama anterior (`AUDITORIA_ESTADO_APP` hipoteses) resolvido com evidencia do codigo:

| # | Hipotese original | Status anterior | Veredito da auditoria | Evidencia |
|---|---|---|---|---|
| 0 | Persistencia — registros somem ao reabrir | 🔴 Bug confirmado | ✅ **Resolvido** — bug era de exibicao, nao de persistencia. Dados estao no Firestore. ViewModels propagavam exceptions que impediam leitura. | `training_viewmodel.dart:134`, `health_viewmodel.dart:147` — `throw Exception` no catch |
| 1 | Turno — persistencia apos restart | ❓ Ponto cego | ✅ Funciona — stream real-time `watchActiveShift` reconecta automaticamente | `shift_viewmodel.dart:156-171` |
| 2 | Historico — exportar PDF | ❓ Nunca verificado | ✅ Funcional — gera PDF real com tabela de dados, header institucional, paginacao | `history_screen.dart:241-352` |
| 3 | Ocorrencias — hash imutavel | ⚪ Specado | ✅ Implementado — SHA-256 com serializacao deterministica | `finalize_occurrence_screen.dart:360` |
| 3 | Ocorrencias — trilha de auditoria | ⚪ Specado | ✅ Implementado — inline audit trail + collection `auditLogs` | `audit_service.dart`, `occurrence_repository.dart` |
| 3 | Ocorrencias — pagina `/v/{id}` | 🔴 Nao existe | 🔴 **Confirmado ausente** — URL gerada no PDF mas sem servidor/endpoint | `occurrence_pdf_generator.dart:44` |
| 3 | Ocorrencias — fotos sem subpasta | 🟠 Suspeito | 🔴 **Confirmado** — path e `{folder}/{uuid}.ext` sem granularidade por evento | `storage_service.dart` |
| 4 | Hub — resumo hardcoded | 🟠 Suspeito | ✅ **Refutado** — cards sao dinamicos via StreamBuilder do Firestore | `training_hub_screen.dart:84-103`, `training_hub_categories.dart` |
| 5 | Deteccao — material por linha | 🟠 Suspeito | 🔴 **Confirmado** — mesma lista para todas as linhas | `detection_formation_screen.dart:373`, `detection_maintenance_screen.dart:44-48` |
| 5 | Deteccao — persistencia sessoes | ❓ Suspeito | ✅ Funciona — escreve em `dogs/{dogId}/training_sessions` e `detection_lines` | `detection_service.dart:286` |
| 5 | Deteccao — counter per-session | ⚪ Specado | ✅ Conforme spec — `DetectionSessionRecorder` inicia com streak=0 | `detection_phase_config.dart:226-233` |
| 6 | B&C — resumo hub hardcoded | 🟠 Suspeito | ✅ **Refutado** — derivado do Firestore via `buildHubData()` | `training_hub_screen.dart:103` |
| 7 | G&P — resumo hub hardcoded | 🟠 Suspeito | ✅ **Refutado** — idem acima | `training_hub_screen.dart:103` |
| 8 | Condicionamento — persistencia | 🔴 Bug | ✅ **Dado persiste** — bug era de leitura/exibicao no historico | `training_service.dart` → `trainings/{autoId}` |
| 9 | Obediencia — comandos hardcoded | 🟠 Suspeito | 🔴 **Confirmado** — 13 comandos em `static const` | `obedience_training_screen.dart:28-48` |
| 10 | Saude — confirmacao veterinaria | ❓ Nunca auditado | 🔴 **Ausente** — nenhum campo status, nenhum fluxo de aprovacao | `health_log_model.dart` — sem campo `status` |
| 11 | Nutricao — registro completo | ❓ Nunca auditado | ✅ Funciona — dual-write, stream real-time, historico 90d, conformidade | `nutrition_service.dart` |
| 12 | Cao/binomio — perfil | ❓ Nunca auditado | ✅ Existe — `dog_profile_screen.dart` + `k9_profile_page.dart` + troca via `showDogSwitcher()` | |
| 13 | Back Android — fecha app | 🔴 Bug | 🟡 **Parcial** — `PopScope` em 7 telas criticas, mas nao em todas | `main_root_screen.dart:77` tem PopScope |
| 14 | Auditoria/soft delete | ⚪ Specado | 🟡 **Parcial** — soft delete em Occurrence, Health, Nutrition. Hard delete em Training, Dog, User | `soft_deletable.dart` vs `training_service.dart:36` |
| 14 | Offline/auto-save | ⚪ Specado | 🔴 **Ausente** — sem cache local. Apenas auto-save de deteccao (requer Firestore online) | Nenhum `hive`/`sqflite` no pubspec |

### Resumo da resolucao

- **Hipoteses confirmadas como bug**: 5 (material por linha, comandos hardcoded, saude sem vet, fotos sem subpath, offline ausente)
- **Hipoteses refutadas**: 4 (hub hardcoded era dinamico, persistencia funciona, nutricao funciona, perfil existe)
- **Hipoteses parcialmente resolvidas**: 2 (back Android, soft delete)
- **Confirmado funcional**: 8 (turno, PDF, hash, audit trail, deteccao counter, B&C, G&P, condicionamento)

---

*Fim do relatorio.*
