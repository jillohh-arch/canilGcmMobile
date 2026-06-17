# Biblia do Projeto Canil GCM K9 - Base para o Web

Gerado em: 2026-06-04  
Projeto Firebase: `canil-gcm`  
Repo local analisado: `C:\Projetos\canil_gcm_mobile_chatgpt\canil-gcm`  
Estado Git no momento da analise: `main...origin/main`, com memorias/docs locais novas ainda nao commitadas.

> Esta biblia e uma referencia operacional para abrir o projeto web com o minimo de perda de contexto.
> Ela foi montada por leitura estatica do repo, `temp/docs`, `temp/memory`, mockups, Flutter, Firestore rules, Storage rules, Functions, tools e testes.
> Quando houver divergencia entre texto antigo e codigo/rules atuais, trate `firestore.rules`, `functions/src/index.ts`, modelos Dart e memorias recentes como fonte mais forte.

---

## 1. Essencia do produto

O Canil GCM K9 e um sistema institucional para a Guarda Civil Municipal de Limeira acompanhar binomios condutor-cao, turno, guarnicao, ocorrencias, treinos, saude, nutricao, documentos, historico e prestacao de contas.

O principio recorrente do projeto e:

> Se um gestor questionar o trabalho do condutor ou a formacao/saude do cao meses depois, o registro precisa defender a equipe.

Isso aparece em tres camadas:

- Dominio: registros ricos, autoria, timestamps, estados claros.
- Auditoria: `audit_trail`, soft delete, trilha de correcao.
- Integridade: ocorrencias finalizadas recebem hash/selo/verificador; treino e saude sao auditaveis, mas nao recebem hash probatorio de ocorrencia.

---

## 2. Regras nao negociaveis

1. Nada importante some de verdade.
   - Delete fisico e bloqueado na maioria das rules.
   - O padrao e `deleted_at`, `deleted_by`, `delete_reason`.

2. Registro institucional precisa ter autoria.
   - Criacao e edicao relevante devem carregar `audit_trail`.
   - Correcao deve preservar valor anterior ou snapshot.

3. Ocorrencia finalizada e documento selado.
   - Hash e verificador publico existem para ocorrencias.
   - Fotos podem quebrar o selo de midia sem invalidar necessariamente o documento.

4. Treino nao e documento selado.
   - Treino e registro operacional auditavel.
   - Nao introduzir hash de prova em treino.

5. Pendencia acionavel nao pode ser "limpa" e esquecida.
   - Notificacao com `action_required == true` e `resolved_at == null` fica como pendencia aberta.
   - Marcar como lida so tira realce visual.
   - Arquivar/limpar e apenas para avisos.

6. Transicoes sensiveis rodam no servidor.
   - Aprovar promocao de treino, selar ocorrencia, fechar para assinatura e assinar ocorrencia passam por Functions.

7. Web herda regra de dominio, nao layout mobile.
   - Bottom nav, FAB, telas 390px e sheets sao mobile.
   - Firestore, Functions, estados, auditoria e regras sao reutilizaveis no web.

---

## 3. Fontes de verdade do repo

### Specs e docs

Pasta: `temp/docs/`

Principais:

- `ESPEC_TECNICA_PARTE_1.md`: entrada, login, selecao de cao, turno, header, bottom nav.
- `ESPEC_TECNICA_PARTE_2.md` e `PARTE_3.md`: ocorrencias, eventos, finalizacao, historico/PDF.
- `ESPEC_TECNICA_PARTE_4_1.md`: deteccao funcional, referencia para formacao/fases.
- `ESPEC_TECNICA_PARTE_7.md`, `PARTE_9.md`: historico, integridade, PDF e endurecimento.
- `ESPEC_TECNICA_PARTE_10.md`, `PARTE_11.md`, `PARTE_12.md`: equipe, guarnicao, ciencia, participacao, assinatura, hash v4.
- `ESPEC_TECNICA_PARTE_13.md`: padrao de treino Formacao / Operacional.
- `ESPEC_TECNICA_PARTE_14.md`: notificacoes.
- `ESPEC_TECNICA_PARTE_15.md`: prontuario de saude.
- `ADENDO_VALIDACAO_E_VERIFICADOR.md`: prioridade do verificador.
- `ADENDO_DIAGNOSTICO_FRENTE_C.md`: diagnostico de equipe/assinatura.

Atencao:

- `ESPEC_TECNICA_PARTE_11.md` e `ESPEC_TECNICA_PARTE_11 (1).md` existem duplicadas.
- Nao ha `ESPEC_TECNICA_PARTE_8.md`.
- `ESPEC_TECNICA_PARTE_4.md` e `ESPEC_TECNICA_PARTE_4_1.md` coexistem; a `4_1` e a referencia mais nova para deteccao.
- Specs antigas podem contradizer Parte 12/13/14/15. Para web, preferir as partes mais novas e as rules/functions atuais.

### Memorias

Pasta: `temp/memory/`

As memorias recentes mais uteis:

- `SESSAO_2026-05-30_FRENTE_C_GUARNICAO_V4_ENCERRAMENTO.md`
- `SESSAO_2026-05-31_ENDURECIMENTO_RULES_UI_VALIDACAO.md`
- `SESSAO_2026-06-01_INTEGRIDADE_SELO_VERIFICADOR_PUBLICO.md`
- `SESSAO_2026-06-01_TOKENS_VISUAIS_UI_PDF_VALIDACAO.md`
- `SESSAO_2026-06-03_NOTIFICACOES_E_PRONTUARIO_SAUDE.md`

### Mockups

Pasta: `temp/mockups/`

Servem como referencia visual e historica. Muitos sao mobile e alguns tem versoes antigas. Para web, usar como inspiracao de identidade visual, nao copiar layout.

Mockups recentes relevantes:

- `notificacoes_v2.html`
- `saude_hub.png`
- `saude_prontuario.png`
- `padrao_treino_formacao_operacional.html`
- `treino_v2_sessao_e_promocao.html`
- `ocorrencia_fluxo_completo_v2.html`
- `pdf_ocorrencia_v2_*.html`
- `bottom_nav_redesenho_v3.html`

---

## 4. Stack tecnica

### Mobile atual

- Flutter / Dart `^3.11.4`
- Provider para estado
- Firebase:
  - Auth
  - Firestore
  - Storage
  - Functions v2
  - Messaging / FCM
  - App Check
- UI:
  - Material 3
  - Google Fonts / Inter
  - tema escuro institucional
  - mapas com `flutter_map` / OSM
  - PDF via `pdf` e `printing`
  - imagens/PDF via Storage

### Firebase

- Projeto: `canil-gcm`
- Region Functions: `southamerica-east1`
- Hosting:
  - public: `web_verification`
  - rewrite `/v/**` para Function `verifyOccurrence`

### Observacao de README

O `README.md` menciona `go_router`, mas o app atual usa `MaterialApp` com `Navigator` e `Provider`. Tratar essa linha como desatualizada ate prova contraria.

---

## 5. Arquitetura Flutter

Estrutura real:

```text
lib/
  main.dart
  core/
    domain/
    mixins/
    services/
    theme/
    utils/
    widgets/
  features/
    app_shell/
    auth/
    conditioning/
    dogs/
    health/
    history/
    nutrition/
    occurrences/
    profiles/
    shifts/
    training/
    users/
```

Padrao predominante:

- `domain`: modelos e enums.
- `data`: services/repositories Firestore.
- `presentation`: screens, widgets, viewmodels.
- `core/services`: servicos compartilhados e infraestrutura.

Entrada do app:

- `lib/main.dart`
- Inicializa Firebase, App Check, background FCM e PushNotificationService.
- Registra providers:
  - `AuthViewModel`
  - `UserViewModel`
  - `DogViewModel`
  - `TrainingViewModel`
  - `HealthViewModel`
  - `OccurrenceViewModel`
  - `ShiftViewModel`
  - `NutritionViewModel`

Fluxo raiz:

```text
Sem auth -> LoginScreen
Auth carregando usuario/turno -> SplashScreen
Sem turno ativo -> ShiftAssumptionScreen
Turno ativo -> MainRootScreen
```

Main root mobile:

- Aba 0: Turno / dashboard
- Aba 1: Treino
- FAB central: Nova ocorrencia / continuar ocorrencia aberta
- Aba 2: Saude
- Aba 3: Historico

---

## 6. Design system

Fonte principal:

- Inter via `GoogleFonts.inter`.

Tema:

- `lib/core/theme/app_theme.dart`
- Partials:
  - `app_theme_components.dart`
  - `app_theme_status.dart`
  - `app_theme_typography.dart`

Tokens principais:

- Fundo: `#050D10`
- Primario ciano: `#4DD0E1`
- Sucesso: `#2ECC71`
- Atencao/amarelo: `#F1C40F`
- Nutricao/desenvolvimento: `#E67E22`
- Info: `#3498DB`
- Erro: `#E74C3C`
- Surface cards: `#0E1A1F`, `#06141A`, `#07141B`
- Texto principal: branco
- Texto secundario: `#B0C4CC`

Identidade visual:

- Escuro, operacional, institucional.
- Cards com borda ciano transluzida.
- Status por cor semantica.
- Titulos pequenos em caixa alta com letter spacing.
- Numeros tecnicos, hash, timestamps e contexto podem usar fonte mono quando apropriado no web.

Para web:

- Manter tokens e linguagem visual.
- Nao copiar bottom nav/FAB mobile literalmente.
- Criar layout web com sidebar/topbar, paineis, tabelas e detalhes.
- Usar os mesmos estados/cores de dominio.

---

## 7. Contratos Firebase - mapa de colecoes

### Usuarios e auth

```text
users/{ra}
users/{ra}/devices/{deviceId}
```

Campos importantes em `users/{ra}`:

- `ra`
- `name`
- `callsign`
- `unit`
- `accessLevel`
- `photoUrl` / `image_url`
- `is_k9_instructor`
- `training_role`
- espelhos de claim quando aplicavel

Claims relevantes:

- Admin:
  - `admin == true`
  - `role == "admin"`
  - `roles` contem `admin`
  - ou `users/{ra}.accessLevel == "admin"` para algumas Functions.

- Instrutor K9:
  - `role == "instrutor_k9"`
  - `roles` contem `instrutor_k9`
  - `instrutor_k9 == true`
  - `training_role == "instrutor_k9"`
  - `training_instructor == true`

Ferramenta de teste:

- `tools/set_k9_instructor.js`
- Seta custom claims e espelho em `users/{ra}`.
- Claim so vale no app apos renovar token; para teste limpo, logout/login.

### Caes

```text
dogs/{dogId}
dogs/{dogId}/weight_records/{recordId}
dogs/{dogId}/weight_history/{recordId}        # legado/coexistencia
dogs/{dogId}/specialties/{specialtyId}
dogs/{dogId}/training/{modality}
dogs/{dogId}/training/{modality}/bonus_milestones/{bonusId}
dogs/{dogId}/training/{modality}/completed_module_corrections/{correctionId}
dogs/{dogId}/training_sessions/{sessionId}
dogs/{dogId}/training_attempts/{attemptId}
dogs/{dogId}/conditioning_sessions/{sessionId}
dogs/{dogId}/detection_lines/{lineId}
dogs/{dogId}/triagem_evaluations/{evaluationId}
dogs/{dogId}/guard_protection_state/{stateId}
dogs/{dogId}/commands/{commandId}
dogs/{dogId}/health_events/{eventId}
dogs/{dogId}/documents/{docId}
dogs/{dogId}/feedings/{feedingId}             # legado/coexistencia
dogs/{dogId}/feeding_events/{feedingId}
dogs/{dogId}/nutrition_prescriptions/{id}
dogs/{dogId}/nutritional_prescriptions/{id}   # legado/coexistencia
dogs/{dogId}/nutrition_supplements/{id}
```

Modelo `Dog`:

- `id`
- `name`
- `breed`
- `sex`
- `dateOfBirth`
- `status`
- `profileImageUrl`
- `conductorRa`
- `weight`
- `matricula` / `registrationNumber`
- `idealWeightMin`
- `idealWeightMax`
- `lastBathDate`
- `specialties`
- `microchip`
- `observacoes`
- `condicaoCorporal`

### Turno e guarnicao

```text
active_shifts/{ra}
shift_logs/{shiftId}
vehicles/{vehicleId}
vehicle_crews/{crewId}
vehicle_crews/{crewId}/members/{ra}
```

`active_shifts/{ra}` representa o turno ativo do condutor:

- `handlerId`
- `auth_uid`
- `handler_email`
- `dogId`
- `service_dog_id`
- `startedAt`
- `vehicle_id`
- `vehicle_label`
- `vehicle_prefix`
- `vehicle_crew_id`
- `crew_role`
- `crew_status`
- `status`

`vehicle_crews/{crewId}` representa guarnicao por viatura:

- `vehicle_id`
- `vehicle_label`
- `crew_size`
- `service_dog_id`
- `titular_handler_id`
- `active`

Membros:

- `handler_id`
- `auth_uid`
- `handler_email`
- `role`
- `status`: `titular`, `pending`, `accepted`, `declined`
- `invited_by`
- `joined_at`
- `responded_at`
- `decline_reason`

Regra atual de dominio:

- O cao de servico e um por viatura/turno.
- A guarnicao vive fora da ocorrencia.
- A ocorrencia captura snapshot/estado de participacao da equipe.

### Ocorrencias

```text
occurrences/{occurrenceId}
occurrences/{occurrenceId}/events/{eventId}
occurrences/{occurrenceId}/participations/{handlerId}
occurrences/{occurrenceId}/signatures/{handlerId}
occurrences/{occurrenceId}/amendments/{amendmentId}
occurrences/{occurrenceId}/correction_requests/{requestId}
occurrence_natures/{natureId}
```

Campos importantes de `occurrences/{id}`:

- `shift_id`
- `primary_handler_id`
- `primary_handler_ra`
- `created_by`
- `dog_id`
- `service_dog_id`
- `crew_id`
- `vehicle_id`
- `vehicle_label`
- `type_code`
- `type_name`
- `location_address`
- `gps_lat`
- `gps_lng`
- `gps_accuracy`
- `started_at`
- `finalized_at`
- `status`
- `final_report`
- `results`
- `details`
- `integrity_hash`
- `hash_version`
- `pdf_export_url`
- `duration_total`
- `finalization_draft`
- `finalization_photos`
- `finalization_photo_hashes`
- `team`
- `team_handler_ids`
- `team_emails`
- `team_auth_uids`
- `team_auth_keys`
- `signature_request_at`
- `signature_deadline`
- `signature_round`
- `participation_status`
- `accepted_handler_ids`
- `declined_handler_ids`
- `pending_handler_ids`
- `edit_authorized_handler_ids`
- `participation_revision`
- `audit_trail`
- soft delete fields

Eventos:

- `occurrence_id`
- `category`
- `timestamp`
- `title`
- `description`
- `media_items`
- `photo_urls`
- `photo_metadata`
- `gps_lat`
- `gps_lng`
- `place_label`
- `location_source`
- `dog_handler_id`
- `audit_trail`

Estados conceituais:

- Em andamento / draft operacional
- Fechada para assinaturas
- Finalizada / selada
- Finalizada com pendencia quando regra permitir
- Devolvida para retificacao quando ha correcao

Regras:

- Integrantes aceitos podem editar enquanto ocorrencia esta aberta.
- Assinatura sempre passa por tela de revisao.
- Aditamento pos-selo e trilha separada.
- Ocorrencia finalizada e protegida; alteracoes posteriores sao correcao/aditamento.

### Treinos

Colecoes raiz legadas/coexistentes:

```text
trainings/{trainingId}
training_sessions/{sessionId}
```

Colecoes canonicas por cao:

```text
dogs/{dogId}/training/{modality}
dogs/{dogId}/training_sessions/{sessionId}
dogs/{dogId}/specialties/{modality}
```

Curriculo:

```text
training_programs/{modality}
training_programs/{modality}/modules/{moduleId}
training_programs/{modality}/modules/{moduleId}/milestones/{milestoneId}
```

Promocao:

```text
promotion_requests/{requestId}
```

`dogs/{dogId}/training/{modality}` e o estado canonico de progressao:

- `modality`
- `status`: `in_formation` ou `operational`
- `current_module`
- `program_version`
- `operational_since`
- `completed_module_ids`
- `completed_modules`
- `achieved_milestones`
- `audit_trail`

`dogs/{dogId}/specialties/{modality}` fica em sincronia para coexistencia/hub.

Snapshot de modulo concluido:

- `module_id`
- `module_order`
- `module_name`
- `program_version`
- marcos com:
  - `milestone_id`
  - `label`
  - `required`
  - `achieved`
  - `achieved_at`
  - `achieved_by`

Regras de treino:

- Curriculo e dado no Firebase, nao hardcoded.
- Modulos de formacao sao sequenciais.
- Operacional destrava ao concluir ultimo modulo.
- Em Busca & Captura, recuo nao e automatico; depende de instrutor e auditoria.
- A aprovacao do ultimo modulo pelo instrutor certifica o cao como operacional.
- `completed_modules` e tratado como imutavel; correcao vai por `completed_module_corrections`.
- Marco bonus nao rebaixa operacional nem altera snapshots antigos.

Sessoes de Busca & Captura:

- `modality`
- `phase`: `formation` ou `maintenance`
- `module_id`
- `milestone_id`
- `conductor`
- `date`
- `result`
- `track`
  - `distance_m`
  - `duration_s`
  - `events[]`
  - `path`
  - `offline_synced`
- `observation`

Eventos de campo do rastreador:

- `cao_indicou`
- `checagem`
- `perdeu_rastro`
- `alvo_encontrado`

Importante:

- Sessao registra trabalho, nao marca marco automaticamente.
- Pode oferecer marcar marco, mas decisao/promo e manual/instrutor.

### Saude e prontuario

Saude esta consolidada em:

```text
dogs/{dogId}/health_events/{eventId}
dogs/{dogId}/weight_records/{recordId}
documentos/{docId}
dogs/{dogId}/nutrition_prescriptions/{id}
dogs/{dogId}/feeding_events/{id}
dogs/{dogId}/nutrition_supplements/{id}
```

Tipos de evento de saude:

- `vaccination`
- `antiparasitic`
- `exam`
- `consultation`
- `medication`
- `symptom`
- `surgery`
- `other`

Prontuario mobile atual:

- `Resumo`
- `Vacinas`
- `Peso`
- `Nutricao`
- `Docs`

Sem aba Historico. Historico e tela separada.

Peso:

- Fonte canonica: `dogs/{dogId}/weight_records`
- `weight_history` e legado/coexistencia.
- `dogs/{dogId}.weight` e atualizado para resumo.

Nutricao:

- Prescricao vigente em `nutrition_prescriptions`.
- Coexistencia com `nutritional_prescriptions`.
- Alimentacao em `feeding_events`.
- Coexistencia com `feedings`.
- Suplementos em `nutrition_supplements`.
- `hydration_notes` e campo simples da prescricao.

Docs:

- Documentos atuais ficam na raiz `documentos`.
- Nao migrar para `dogs/{dogId}/documents` sem decisao explicita.
- PDF/laudo permitido via Storage.

### Historico

Modulo:

- `lib/features/history/`

Agrega:

- Saude
- Treino
- Ocorrencia
- Nutricao

`HistoryScreenMode`:

- `full`
- `healthProntuario`

Para web:

- Historico deve ser um modulo de consulta e auditoria, com filtros, timeline, detalhes e exportacao.
- Cuidado com colecoes legadas/coexistentes para nao esconder registros.

### Notificacoes

```text
notifications/{ra}/items/{notificationId}
```

Tipos:

- `vehicle_crew_invitation`
- `vehicle_crew_invitation_accepted`
- `vehicle_crew_invitation_declined`
- `occurrence_participation_requested`
- `occurrence_participation_accepted`
- `occurrence_participation_declined`
- `signature_requested`
- `signature_completed`
- `signature_declined`
- `correction_requested`
- `deadline_warning`
- `occurrence_finalized`
- `amendment_created`
- `training_promotion_requested`
- `training_promotion_approved`
- `training_promotion_rejected`
- `training_bonus_milestone_available`

Campos:

- `type`
- `occurrence_id`
- `occurrence_title`
- `created_at`
- `read_at`
- `resolved_at`
- `archived_at`
- `action_required`
- `target_screen`
- `additional_data`
- dados de treino quando aplicavel:
  - `promotion_request_id`
  - `dog_id`
  - `dog_name`
  - `modality`
  - `module_id`
  - `module_name`
  - `milestone_id`
  - `milestone_label`
  - `decision_reason`

Badge:

```text
action_required == true
resolved_at == null
archived_at == null
```

Avisos:

- podem ser lidos;
- podem ser arquivados com `archived_at`;
- nunca apagam o registro real.

Pendencias:

- nao podem ser arquivadas enquanto abertas;
- so saem de `Requer acao` quando a acao real seta `resolved_at`.

### Auditoria

```text
auditLogs/{logId}
```

Padrao em documentos:

- `audit_trail`: lista inline de eventos.
- `created_at`
- `updated_at`
- `deleted_at`
- `deleted_by`
- `delete_reason` ou `deleted_reason`

Rules relevantes:

- `canCreateAuditedRecord`
- `canUpdateAuditedRecord`
- `canSoftDeleteAuditedRecord`
- `appendsInlineAuditOnUpdate`
- `canCreateAuditLog`

---

## 8. Firebase Functions

Arquivo: `functions/src/index.ts`

Exports atuais:

### Papeis

- `setK9InstructorRole`
  - Callable admin.
  - Seta/remove papel Instrutor K9.
  - Atualiza custom claims e espelho em `users/{ra}`.

### Treino / promocao

- `onTrainingPromotionRequestCreated`
  - Notifica instrutores.

- `onTrainingPromotionRequestUpdated`
  - Processa aprovacao/rejeicao.
  - Em aprovacao, executa a conclusao de modulo no servidor.
  - Atualiza `dogs/{dogId}/training/{modality}`.
  - Sincroniza `dogs/{dogId}/specialties/{modality}`.
  - Notifica condutor.

- `onTrainingProgramMilestoneCreated`
  - Detecta marco novo em curriculo.
  - Notifica caes ja operacionais como bonus milestone.

### Guarnicao

- `inviteVehicleCrewMember`
  - Convida membro para guarnicao de viatura.
  - Cria notificacao acionavel.

- `respondVehicleCrewInvitation`
  - Aceita/recusa convite.
  - Atualiza `vehicle_crews/{crewId}/members/{ra}`.
  - Atualiza `active_shifts/{ra}` quando aceito.
  - Marca notificacao correspondente como resolvida.

### Ocorrencia, assinatura e integridade

- `sealOccurrenceV4`
  - Sela ocorrencia com hash v4.

- `closeOccurrenceForSignatures`
  - Fecha ocorrencia para assinatura.
  - Cria assinaturas e notificacoes.

- `signOccurrence`
  - Assina ocorrencia pelo participante.
  - Atualiza status e notificacoes.

- `requestOccurrenceCorrection`
  - Abre solicitacao de correcao/devolucao.

- `acceptOccurrenceParticipation`
  - Confirma ciencia/participacao.

- `declineOccurrenceParticipation`
  - Recusa participacao.

- `verifyOccurrence`
  - HTTP publico `/v/{id}`.
  - Verifica hash documental.
  - Com `?media=1`, tenta verificacao profunda de midias no Storage.

### Push

- `onNotificationCreated`
  - Envia FCM para dispositivos em `users/{ra}/devices`.

---

## 9. Storage rules

Principio:

- Leitura autenticada.
- Criacao controlada por tipo/tamanho.
- Update/delete bloqueados.

Caminhos:

```text
profile_photos/{fileName}
users/{fileName}
routines/{fileName}
trainings/{fileName}
incidents/{fileName}
health/{fileName}
health/exams/{fileName}
health_attachments/{dogId}/{fileName}
occurrences/{occurrenceId}/events/{fileName}
occurrences/{occurrenceId}/finalization/{fileName}
dogs/{dogId}/feeding_photos/{fileName}
dogs/{dogId}/training_sessions/{sessionId}/media/{fileName}
documentos/{dogId}/{fileName}
occurrences/{occurrenceId}/{fileName}
```

Limites:

- Imagens em geral: 10 MB.
- Training session media: 20 MB.
- PDFs/health attachments/documentos: 20 MB.

---

## 10. Integridade, hash e verificador

Servicos:

- `HashService`
- `IntegrityVerificationService`
- `OccurrenceFinalizationService`
- `occurrence_pdf_generator.dart`

Functions:

- `sealOccurrenceV4`
- `verifyOccurrence`

Regra de dominio:

- Hash de prova e para ocorrencia finalizada.
- Versoes v1-v4 existem por compatibilidade.
- v4 inclui equipe, participacoes, assinaturas e eventos canonicos.
- Midias/fotos tem hash proprio.
- Verificador pode retornar:
  - documento integro;
  - documento quebrado;
  - midia quebrada;
  - legado;
  - sem selo.

Para web:

- Criar uma tela de verificacao/consulta de ocorrencia pode reaproveitar endpoint `/v/{id}`.
- Painel interno pode listar ocorrencias finalizadas com status de integridade.
- Nao recalcular hash no client web como fonte oficial; usar Function ou algoritmo espelhado apenas para UI diagnostica.

---

## 11. Ferramentas locais

Pasta: `tools/`

Principais:

- `set_k9_instructor.js`
  - Atribui papel Instrutor K9 por service account.

- `k9_instructor_role_test_tool.js` e `.md`
  - Apoio de teste para papel K9.

- `training_programs_busca_captura_seed.json`
  - Curriculo seed de Busca & Captura.

- `upload_training_programs.js`
  - Upload de curriculos de treino.

- `training_promotion_smoke_check.js`
  - Smoke test de promocao.

- `ETAPA4_PROMOTION_TWO_DEVICES_GUIDE.md`
  - Guia de teste com dois aparelhos.

- `backfill_notification_resolution.js`
  - Backfill de notificacoes resolvidas.

- `upload_occurrence_natures.js`
  - Seed de naturezas.

- `rules_tests/`
  - Testes de Firestore rules via emulator.

---

## 12. Testes existentes

Pasta: `test/`

Categorias:

- Core:
  - `audit_service_test.dart`
  - `hash_service_test.dart`
  - `integrity_verification_service_test.dart`
  - `occurrence_finalization_service_test.dart`
  - `notification_item_test.dart`

- Dogs:
  - `dog_command_service_test.dart`

- Occurrences:
  - repositories
  - domain models
  - view model initial event

- Training:
  - detection service
  - training program service
  - training service
  - detection phase config
  - detection formation screen

- Integration:
  - `fronte_c_integration_test.dart`

- Rules:
  - `tools/rules_tests/rules_tests.mjs`

Comandos usuais:

```powershell
C:\flutter\bin\cache\dart-sdk\bin\dart.exe analyze
flutter test
npm --prefix functions run build
npm --prefix tools/rules_tests test
flutter build apk --release
```

Em Windows, quando o Flutter reclamar de Git no PATH, usar sessao com:

```powershell
$env:PATH='C:\Windows\system32;C:\Windows;C:\Windows\System32\WindowsPowerShell\v1.0;C:\Program Files\Git\cmd;C:\flutter\bin;' + $env:PATH
```

---

## 13. O que o web deve herdar

Herdar diretamente:

- Firestore schema.
- Functions.
- Rules.
- Storage contracts.
- Estados de ocorrencia.
- Estados de guarnicao.
- Estados de participacao/assinatura.
- Curriculo e progressao de treino.
- Promocao co-validada.
- Notificacoes e semantica de pendencia.
- Auditoria/soft delete.
- Integridade/verificador.
- Design tokens.

Nao herdar literalmente:

- Bottom nav mobile.
- FAB central de ocorrencia como padrao web.
- Sheets mobile.
- Grid e cards pensados para 390px.
- Layout de mockups HTML antigos quando contradizem specs novas.

Traducao recomendada para web:

- Sidebar ou top navigation por modulo.
- Tabelas densas para administracao.
- Detail drawer ou painel lateral para contexto.
- Timeline vertical/horizontal para historico.
- Dashboards com cards resumidos.
- Forms de edicao com auditoria visivel.
- Dialogs confirmatorios apenas em transicoes sensiveis.

---

## 14. Primeiro recorte sugerido para o web

### Fase 1 - Admin operacional

Objetivo: dar poder administrativo sem quebrar mobile.

Telas:

- Login web.
- Dashboard admin.
- Usuarios/condutores.
- Atribuir/remover Instrutor K9.
- Caes.
- Viaturas.
- Naturezas de ocorrencia.
- Curriculos de treino.

Contratos:

- Usar Auth Firebase.
- Respeitar claims.
- Mutacoes sensiveis por Functions quando existirem.
- Para CRUD ainda sem Function, criar com `audit_trail` e respeitar rules.

### Fase 2 - Curriculo e treino

Telas:

- `training_programs`
- modulos
- milestones
- versoes/ativo/inativo
- progresso por cao
- promotion_requests

Ponto critico:

- Editar curriculo nao pode reescrever snapshots ja concluidos.
- Novo marco em curriculo deve virar bonus para cao operacional.

### Fase 3 - Auditoria e ocorrencias

Telas:

- Lista de ocorrencias.
- Detalhe com eventos, fotos, equipe, participacoes, assinaturas.
- Status de hash.
- Verificador.
- Aditamentos/correcoes.

Ponto critico:

- Nao permitir edicao direta em ocorrencia selada.

### Fase 4 - Saude e prontuario

Telas:

- Prontuario web do cao.
- Vacinas.
- Peso.
- Nutricao.
- Docs/laudos.
- Historico unificado.

Ponto critico:

- Documentos sao imutaveis no sentido institucional: arquivar/corrigir com trilha, nao apagar.

---

## 15. Como conversar com este projeto

Quando pedir trabalho neste repo, use este estilo:

1. Comece dizendo se e diagnostico ou implementacao.
   - "Nao edite nada, so leia e reporte" quando for auditoria.
   - "Pode implementar" quando a decisao estiver fechada.

2. Cite fontes.
   - `temp/docs/...`
   - `temp/mockups/...`
   - `temp/memory/...`
   - arquivos reais de `lib/`, `functions/`, `firestore.rules`.

3. Separe:
   - regra de dominio;
   - UI mobile;
   - contrato Firestore;
   - Function/server;
   - rules;
   - validacao.

4. Em caso de duvida, marque "a decidir".
   - Nao inventar a verdade canonica.

5. Para web, sempre perguntar:
   - "Esta tela altera dominio ou so administra dados existentes?"
   - "Existe Function para esta transicao?"
   - "As rules permitem?"
   - "Precisa audit_trail?"
   - "E soft delete ou arquivamento?"

6. Para commit/release:
   - conferir `git status`;
   - nao incluir lixo de build;
   - se o usuario disser "commitar tudo", o escopo esta aberto;
   - caso contrario, stage seletivo.

7. Para validacao:
   - "build passou" nao significa "validado".
   - Quando mobile, validar no celular.
   - Quando web, validar fluxo real no navegador e, se envolver rules/Functions, validar backend.

Prompt curto recomendado para iniciar o web:

```text
Leia temp/docs/BIBLIA_PROJETO_CANIL_GCM_WEB.md, temp/docs/ESPEC_TECNICA_PARTE_13.md, temp/docs/ESPEC_TECNICA_PARTE_14.md, temp/docs/ESPEC_TECNICA_PARTE_15.md e as memorias recentes em temp/memory.
Quero iniciar o painel web sem mudar contratos mobile. Primeiro diagnostique:
1. quais colecoes e Functions o web deve consumir;
2. quais telas admin sao seguras para Fase 1;
3. quais mutacoes precisam de Function;
4. quais gaps de rules impedem o web.
Nao implemente ate eu aprovar.
```

Prompt de implementacao web conservador:

```text
Implementar Fase 1 do painel web de forma aditiva e conservadora.
Nao alterar schema mobile sem decisao explicita.
Usar Firebase Auth/Firestore/Functions existentes.
Toda escrita deve respeitar audit_trail e soft delete.
Transicoes sensiveis devem chamar Functions.
Reporte arquivos alterados, colecoes tocadas e validacao executada.
```

---

## 16. Lacunas e riscos para decidir antes/de durante web

1. Admin web ainda nao existe neste repo mobile.
   - O README menciona painel React separado, mas neste workspace o foco e mobile.
   - Se o web for repo novo, documentar schema compartilhado desde o inicio.

2. Algumas specs antigas estao duplicadas ou superadas.
   - Parte 10/11 foram revisadas pela Parte 12.
   - Parte 4 foi revisada por 4_1.
   - Parte 8 ausente.

3. Coexistencia de colecoes e real.
   - `weight_records` vs `weight_history`.
   - `feeding_events` vs `feedings`.
   - `nutrition_prescriptions` vs `nutritional_prescriptions`.
   - root `trainings`/`training_sessions` vs subcolecoes por cao.

4. Alguns textos no terminal aparecem com mojibake.
   - Nem sempre significa arquivo quebrado; pode ser encoding do PowerShell.
   - Antes de corrigir acento em massa, detectar bytes reais.

5. Docs/laudos usam colecao raiz `documentos`.
   - Nao migrar para `dogs/{dogId}/documents` sem planejamento.

6. Web de curriculo precisa tratar versoes.
   - Edicao de curriculo novo nao pode invalidar snapshot antigo de formacao.

7. Claims exigem refresh de token.
   - UI web deve explicar relogin ou forcar refresh apos admin alterar papel.

8. Rules sao rigorosas.
   - Um CRUD web aparentemente simples pode falhar se nao montar `audit_trail`.

9. Notificacoes abertas dependem de `resolved_at`.
   - Se criar novos tipos no web, tambem precisa resolver no fluxo real.

---

## 17. Checklist para abrir o projeto web

- [ ] Decidir se o web sera repo separado ou pasta neste workspace.
- [ ] Definir stack web.
- [ ] Configurar Firebase Auth.
- [ ] Ler `.firebaserc` e usar projeto `canil-gcm`.
- [ ] Reusar rules/functions atuais.
- [ ] Implementar login e guard de admin.
- [ ] Criar camada de acesso Firestore tipada.
- [ ] Criar mapa de colecoes compartilhado.
- [ ] Criar helper de `audit_trail`.
- [ ] Criar helper de soft delete.
- [ ] Criar helper de timestamp/RA/auth.
- [ ] Primeira tela: Dashboard admin somente leitura.
- [ ] Segunda tela: Usuarios e papel Instrutor K9 via Function.
- [ ] Terceira tela: Curriculos de treino somente leitura.
- [ ] Depois liberar CRUD de curriculo com auditoria.

---

## 18. Arquivos mais importantes para manter abertos ao construir o web

```text
firebase.json
.firebaserc
firestore.rules
storage.rules
functions/src/index.ts
lib/main.dart
lib/core/domain/notification_item.dart
lib/core/services/audit_service.dart
lib/core/services/hash_service.dart
lib/core/services/integrity_verification_service.dart
lib/core/theme/app_theme.dart
lib/features/occurrences/domain/occurrence.dart
lib/features/occurrences/domain/occurrence_event.dart
lib/features/training/domain/training_program.dart
lib/features/training/domain/training_promotion_request.dart
lib/features/training/domain/training_session_model.dart
lib/features/dogs/domain/dog.dart
lib/features/health/domain/health_log_model.dart
lib/features/nutrition/domain/feeding.dart
lib/features/nutrition/domain/nutrition_prescription.dart
lib/features/nutrition/domain/nutrition_supplement.dart
lib/features/shifts/domain/active_shift_session.dart
lib/features/shifts/domain/vehicle_crew.dart
temp/memory/SESSAO_2026-06-03_NOTIFICACOES_E_PRONTUARIO_SAUDE.md
temp/memory/SESSAO_2026-06-01_INTEGRIDADE_SELO_VERIFICADOR_PUBLICO.md
temp/docs/ESPEC_TECNICA_PARTE_12.md
temp/docs/ESPEC_TECNICA_PARTE_13.md
temp/docs/ESPEC_TECNICA_PARTE_14.md
temp/docs/ESPEC_TECNICA_PARTE_15.md
```

---

## 19. Resumo executivo para o web

O web deve nascer como painel administrativo e auditorial do mesmo dominio mobile.

O mobile ja resolve:

- turno ativo;
- guarnicao por viatura;
- ocorrencias com equipe/ciencia/assinatura/hash;
- treinos com curriculo e promocao;
- prontuario de saude;
- nutricao;
- notificacoes;
- historico;
- PDF/verificador.

O web deve resolver primeiro:

- administracao de usuarios/papeis;
- administracao de curriculos de treino;
- consulta e auditoria de ocorrencias;
- prontuario/relatorios em tela grande;
- backoffice de dados mestres.

O web nao deve:

- criar schema paralelo;
- burlar Functions;
- editar ocorrencia selada direto;
- limpar pendencias abertas;
- apagar registros reais;
- transformar treino em documento selado com hash.

Frase guia:

> O web e a mesa de controle institucional. O mobile e a ferramenta de campo. Ambos falam o mesmo Firestore, respeitam as mesmas Functions e defendem o mesmo registro.
