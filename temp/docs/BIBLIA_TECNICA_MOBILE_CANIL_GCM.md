# Bíblia Técnica Mobile - Canil GCM K9

Gerado em: 2026-06-05  
Projeto Firebase: `canil-gcm`  
App analisado: Flutter/Dart em `C:\Projetos\canil_gcm_mobile_chatgpt\canil-gcm`  
Objetivo: consolidar a fonte de verdade técnica do mobile para orientar o novo projeto web.

> Esta Bíblia descreve o app mobile como ele está organizado hoje, com foco em domínio,
> dados, regras, Firebase e pontos que o web deve herdar. Ela não é uma especificação visual
> do web. O web deve herdar contratos e decisões de domínio, não o layout mobile.

---

## 1. Essência do Produto

O Canil GCM K9 é um sistema institucional para registrar e defender tecnicamente o trabalho do canil:

- turno e binômio condutor-cão;
- guarnição/viatura;
- ocorrências e eventos;
- treinos por modalidade;
- formação e certificação operacional;
- saúde/prontuário/nutrição;
- documentos e laudos;
- notificações acionáveis;
- histórico, PDF e integridade.

Princípio recorrente do projeto:

> Se um gestor questionar o trabalho do condutor, a formação do cão ou a condição de saúde meses depois,
> o registro precisa defender a equipe.

Isso separa o sistema em três naturezas:

- **Ocorrência:** documento institucional selado, com hash/verificador.
- **Treino:** registro operacional auditável, sem hash probatório de ocorrência.
- **Saúde/prontuário:** defesa do cão, auditável, com documentos preservados.

---

## 2. Stack Mobile

| Camada | Tecnologia |
|---|---|
| App | Flutter |
| Linguagem | Dart 3.11+ |
| Estado | Provider / ChangeNotifier |
| Auth | Firebase Auth |
| Banco | Cloud Firestore |
| Storage | Firebase Storage |
| Server-side | Cloud Functions v2, região `southamerica-east1` |
| Push | Firebase Messaging + Flutter Local Notifications |
| App Check | Firebase App Check, Android debug provider no bootstrap atual |
| PDF | `pdf` + `printing` |
| GPS/mapa | `geolocator`, `flutter_map`, `latlong2` |
| Arquivos | `file_picker`, `image_picker`, Storage |
| Gráficos | `fl_chart` |
| Tema | `AppTheme`, Inter via `google_fonts`, IBM Plex Mono onde há dado técnico |

Arquivo de bootstrap principal:

- `lib/main.dart`

Providers registrados no início:

- `AuthViewModel`
- `UserViewModel`
- `DogViewModel`
- `TrainingViewModel`
- `HealthViewModel`
- `OccurrenceViewModel`
- `ShiftViewModel`
- `NutritionViewModel`

Fluxo inicial do app:

1. Inicializa Firebase.
2. Registra background handler FCM.
3. Ativa App Check sem bloquear inicialização se falhar.
4. Inicializa Push/FCM sem bloquear inicialização se falhar.
5. Se não autenticado: `LoginScreen`.
6. Se autenticado mas dados/turno ainda carregando: `SplashScreen`.
7. Se não há turno ativo: `ShiftAssumptionScreen`.
8. Se há turno ativo: `MainRootScreen`.

---

## 3. Arquitetura do Código

O app usa uma organização por feature:

```txt
lib/
  core/
    domain/
    services/
    theme/
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

Padrão recorrente:

- `domain/`: modelos de domínio e normalização de dados.
- `data/`: serviços/repositórios Firestore/Storage/Functions.
- `presentation/screens/`: telas.
- `presentation/widgets/`: componentes específicos.
- `presentation/viewmodels/`: estado local com `ChangeNotifier`.

Camadas críticas:

- **Services/Repositories:** encapsulam Firestore, Functions, Storage e regras de persistência.
- **ViewModels:** orquestram tela/estado e chamam serviços.
- **Functions:** fazem transições sensíveis e notificações.
- **Rules:** bloqueiam deletes, exigem auditoria e limitam updates.

Para o web, a leitura correta é:

- copiar o **contrato de domínio**;
- não copiar a estrutura de telas mobile;
- preferir Functions para ações sensíveis;
- manter compatibilidade com coleções legadas quando o mobile ainda faz dual-read.

---

## 4. Navegação Mobile Atual

Raiz com turno ativo:

- `MainRootScreen`

Bottom nav atual:

| Índice | Aba | Tela |
|---:|---|---|
| 0 | Turno | `ActiveShiftDashboardScreen` |
| 1 | Treino | `TrainingHubScreen` |
| centro | Nova | FAB de nova ocorrência |
| 2 | Saúde | `DogHealthProntuarioScreen` |
| 3 | Histórico | `HistoryScreen` |

O FAB central não é uma aba; ele abre ou continua ocorrência.

Regras da raiz:

- se há ocorrência aberta do cão ativo, mostra banner flutuante;
- ao tocar em FAB, se já existe ocorrência aberta, pergunta se deseja continuar;
- se não há ocorrência aberta, abre `StartOccurrenceScreen`;
- a aba Saúde sempre usa o cão ativo do turno.

Isto é mobile-only para layout. Para o web, a ideia vira:

- dashboard com cards e atalhos;
- ocorrência aberta como estado global;
- saúde/treino/histórico como rotas completas, não tabs estreitas.

---

## 5. Identidade, Usuários e Papéis

Usuário é identificado principalmente por RA.

Coleções relevantes:

- `users/{ra}`
- `users/{ra}/devices/{deviceId}`

Serviços:

- `AuthService`
- `UserService`
- `HandlerIdentityService`
- `PushNotificationService`

Papéis atuais importantes:

- usuário comum/condutor;
- `Instrutor K9`, via custom claim e espelho em `users/{ra}`;
- Admin é necessário para gestão, mas a UI Admin mobile ainda não é o centro do projeto.

Campos/claims usados para Instrutor K9:

- custom claim `role: "instrutor_k9"`;
- custom claim `roles: ["instrutor_k9"]`;
- custom claim `instrutor_k9: true`;
- custom claim `training_role: "instrutor_k9"`;
- custom claim `training_instructor: true`;
- espelho em Firestore: `users/{ra}.is_k9_instructor == true`;
- espelho em Firestore: `users/{ra}.training_role == "instrutor_k9"`.

Function relacionada:

- `setK9InstructorRole`

Regra importante:

- claim novo só passa a valer no app depois de refresh do ID token;
- para teste limpo, logout/login no aparelho resolve.

Para o web:

- a tela Admin de usuários deve chamar Function, não editar claim diretamente;
- a UI pode ler o espelho em `users`, mas autorização real deve depender de claims/rules/Functions.

---

## 6. Turno, Viatura e Guarnição

Coleções:

- `active_shifts/{ra}`
- `shift_logs/{shiftId}`
- `vehicles/{vehicleId}`
- `vehicle_crews/{crewId}`
- `vehicle_crews/{crewId}/members/{ra}`

Serviços principais:

- `ShiftService`
- `ShiftViewModel`
- `VehicleService`
- `VehicleCrewService`
- `VehicleCrewTransitionService`
- `ActiveShiftIdentityService`

Regras atuais de domínio:

- o turno ativo vincula RA, cão, viatura e contexto operacional;
- a guarnição é por viatura/turno;
- convite de guarnição é acionável;
- aceitar/recusar convite passa por callable Function;
- active shift é usado pelas rules para validar gravação de treino e atividades;
- um cão de serviço por viatura/turno é a regra consolidada.

Functions:

- `inviteVehicleCrewMember`
- `respondVehicleCrewInvitation`

Notificações:

- `vehicle_crew_invitation`
- `vehicle_crew_invitation_accepted`
- `vehicle_crew_invitation_declined`

Para o web:

- dashboard de turnos ativos deve ler `active_shifts`;
- gestão de viaturas deve tratar `vehicles` como dado administrativo;
- convites e aceite devem continuar passando por Function;
- tela de guarnição web deve mostrar estado por viatura, membros e cão de serviço.

---

## 7. Cães, Perfil e Especialidades

Coleção principal:

- `dogs/{dogId}`

Subcoleções importantes:

- `dogs/{dogId}/specialties/{specialtyId}`
- `dogs/{dogId}/commands/{commandId}`
- `dogs/{dogId}/external_certifications/{certId}`

Serviços:

- `DogService`
- `DogSpecialtyService`
- `DogCommandService`
- `DogProfileService`
- `DogFitnessService`

Regras:

- cão tem status operacional geral (`Ativo`, licença, aposentado etc.);
- especialidades operacionais saíram da tela de Saúde;
- especialidades vivem no hub de Treinos;
- `specialties` hoje funciona como coexistência/compatibilidade para o hub;
- para modalidades novas, a progressão canônica é `dogs/{dogId}/training/{modality}`.

Para o web:

- perfil do cão deve reunir visão geral, saúde, treinos, documentos, ocorrências e histórico;
- especialidades devem aparecer como estado operacional/formação por modalidade;
- alterações críticas em cadastro devem ter auditoria/soft delete.

---

## 8. Ocorrências

Coleção:

- `occurrences/{occurrenceId}`

Subcoleções:

- `occurrences/{occurrenceId}/events/{eventId}`
- `occurrences/{occurrenceId}/signatures/{signatureId}`
- `occurrences/{occurrenceId}/participations/{handlerId}`
- `occurrences/{occurrenceId}/amendments/{amendmentId}`
- `occurrences/{occurrenceId}/correction_requests/{requestId}`

Serviços/repositórios:

- `OccurrenceRepository`
- `OccurrenceEventRepository`
- `SignatureRepository`
- `AmendmentRepository`
- `OccurrenceTransitionService`
- `OccurrenceFinalizationService`
- `IntegrityVerificationService`
- `OccurrenceLocationService`

Telas principais:

- `StartOccurrenceScreen`
- `ActiveOccurrenceScreen`
- `FinalizeOccurrenceScreen`
- `OccurrenceReviewScreen`
- `OccurrenceConfirmationScreen`
- `OccurrenceTeamScreen`
- `CreateAmendmentScreen`

Estados relevantes:

- aberta / em andamento;
- finalizing;
- awaiting_signatures;
- finalized;
- finalized_with_pending.

Regras consolidadas:

- uma ocorrência aberta por cão ativo é tratada como fluxo principal;
- eventos são registros de atividade dentro da ocorrência;
- finalização gera payload determinístico;
- fechamento para assinaturas cria pendências para participantes;
- assinatura passa por Function;
- recusa/devolução preserva histórico e reabre como nova rodada;
- ocorrência finalizada bloqueia edição comum;
- após finalização, apenas metadados de PDF/auditoria podem mudar;
- delete físico é bloqueado.

Functions críticas:

- `sealOccurrenceV4`
- `closeOccurrenceForSignatures`
- `signOccurrence`
- `requestOccurrenceCorrection`
- `acceptOccurrenceParticipation`
- `declineOccurrenceParticipation`
- `verifyOccurrence`

Para o web:

- web deve ter consulta/revisão forte de ocorrência;
- ações de assinatura/correção devem reutilizar Functions;
- verificador público já existe via Hosting rewrite `/v/**` para `verifyOccurrence`;
- dashboard gestor deve destacar ocorrências aguardando assinatura/correção.

---

## 9. Integridade, Hash e PDF

Integridade com hash é de ocorrência, não de treino.

Componentes:

- `OccurrenceFinalizationService`
- `IntegrityVerificationService`
- `StorageService`
- `occurrence_pdf_generator`
- Function `verifyOccurrence`

Campos relevantes em ocorrência:

- `integrity_hash`
- `hash_version`
- `finalized_at`
- `finalization_photo_hashes`
- `pdf_export_url`
- `pdf_generated_at`
- `finalization_draft`
- `signature_round`

Versões de hash:

- v1: legado básico;
- v2: inclui hashes de mídia;
- v3: inclui assinaturas;
- v4: inclui participações e pedidos de correção, além de eventos/mídias/assinaturas.

Regras:

- hash armazenado deve ser imutável após selo;
- fotos/mídias podem quebrar selo de mídia;
- verificador recalcula no servidor;
- PDF é consequência do registro, não fonte primária;
- treino e saúde não recebem selo de prova.

Para o web:

- implementar tela de verificação/consulta pode reaproveitar Function;
- relatórios devem exibir status de integridade;
- não recalcular hash no cliente web como fonte de verdade.

---

## 10. Treinos - Visão Geral

Coleções legadas e atuais:

- `trainings/{trainingId}` legado raiz;
- `training_sessions/{sessionId}` legado raiz;
- `dogs/{dogId}/training_sessions/{sessionId}` canônico para sessões por cão;
- `dogs/{dogId}/training/{modality}` canônico para progressão;
- `dogs/{dogId}/specialties/{specialtyId}` coexistência para hub;
- `training_programs/{modality}`;
- `training_programs/{modality}/modules/{moduleId}`;
- `training_programs/{modality}/modules/{moduleId}/milestones/{milestoneId}`;
- `promotion_requests/{requestId}`.

Serviços:

- `TrainingService`
- `TrainingRepository`
- `TrainingProgramService`
- `TrainingPromotionService`
- `DetectionService`
- `ConditioningService`

Telas:

- `TrainingHubScreen`
- `TrainingLogScreen`
- `BuscaCapturaFormacaoScreen`
- `BuscaCapturaManutencaoScreen`
- `DetectionEntryScreen`
- `DetectionFormationScreen`
- `DetectionMaintenanceScreen`
- `DetectionTriagemScreen`
- `GuardProtectionCurriculumScreen`
- `ConditioningScreen`
- `ObedienceTrainingScreen`
- `TrainingPromotionRequestScreen`

Regra superior:

- treino é registro operacional auditável;
- não carimbar hash probatório de ocorrência;
- soft delete em sessão quando aplicável;
- histórico deve buscar caminhos legados e canônicos enquanto coexistirem.

---

## 11. Padrão Formação / Operacional

Fonte canônica:

- `dogs/{dogId}/training/{modality}`

Campos esperados:

- `modality`
- `status`: `in_formation` ou `operational`
- `current_module`
- `current_module_id`
- `program_version`
- `completed_module_ids`
- `completed_modules`
- `achieved_milestones`
- `operational_since`
- `audit_trail`

Currículo:

- `training_programs/{modality}`
- subcoleção `modules`;
- subcoleção `milestones`.

Fluxo:

1. App lê currículo do Firebase.
2. App inicializa progressão se não existir.
3. Formação mostra módulos sequenciais.
4. Apenas módulo atual recebe marcos.
5. Condutor solicita evolução.
6. Instrutor K9 aprova/rejeita.
7. Cloud Function aplica progressão.
8. Último módulo aprovado torna o cão operacional.
9. `specialties.status` é mantido em sincronia para coexistência.

Regra de integridade:

- `completed_modules` é imutável pelo client;
- correções devem ir por `completed_module_corrections`;
- aprovação real é servidor/Function.

Functions:

- `onTrainingPromotionRequestCreated`
- `onTrainingPromotionRequestUpdated`
- lógica interna de progressão em `applyApprovedTrainingPromotion`
- `onTrainingProgramMilestoneCreated`

Notificações:

- `training_promotion_requested`
- `training_promotion_approved`
- `training_promotion_rejected`
- `training_bonus_milestone_available`

Para o web:

- painel deve administrar currículos;
- painel deve aprovar/rejeitar promoções;
- painel deve mostrar snapshots de módulos concluídos;
- edição de currículo deve ser auditada e não quebrar snapshots históricos.

---

## 12. Modalidades de Treino

### Busca & Captura

Modalidade:

- `busca_captura`

Currículo:

- `training_programs/busca_captura`

Estado:

- `dogs/{dogId}/training/busca_captura`

Características:

- Formação/Operacional implementado;
- sessão de trilha com GPS;
- eventos de campo: cão indicou, checagem, perdeu rastro, alvo encontrado;
- offline durável para trilha/eventos;
- sessão não marca marco automaticamente;
- marco/promoção é decisão manual.

### Detecção

Características:

- fluxo de triagem/linhas/fases próprio;
- referência histórica de progressão/fases;
- não deve ser reimplementada no web sem mapear o contrato atual;
- segue Protocolo Ragonha, com regras específicas de acertos/falhas nas linhas.

Coleções:

- `dogs/{dogId}/detection_lines`
- `dogs/{dogId}/triagem_evaluations`
- `dogs/{dogId}/training_sessions`
- `dogs/{dogId}/training_attempts`

### Guarda & Proteção

Modalidade:

- `guarda_protecao`

Currículo v1:

1. Caça e mordida técnica.
2. Defesa controlada.
3. Comandos especializados.
4. Cenários operacionais simulados.
5. Certificação.

Regras de domínio:

- caça entra primeiro por ser prazerosa e construir impulso;
- mordida técnica nasce sobre caça;
- defesa entra gradualmente conforme maturidade;
- defesa deve ser equilibrada com retorno à caça;
- comandos/obediência especializada entram em estágio mais avançado;
- sem GPS;
- sessão registra figurante, equipamento, impulso, comandos, capacidades e cenário.

### Obediência

Treino geral, tela própria:

- `ObedienceTrainingScreen`

### Condicionamento Físico

Treino geral, tela própria:

- `ConditioningScreen`
- `dogs/{dogId}/conditioning_sessions`

Regra recente:

- `Condicionamento` e `Condicionamento Físico` devem ser tratados como a mesma família no hub.

---

## 13. Saúde, Prontuário e Nutrição

Tela principal atual:

- `DogHealthProntuarioScreen`

Abas:

- Resumo
- Vacinas
- Peso
- Alimentação/Nutrição
- Docs

Não existe aba Histórico no prontuário; o histórico é acessado por tela focada ou embutido por tema.

Coleções:

- `dogs/{dogId}/health_events`
- `dogs/{dogId}/weight_records`
- `dogs/{dogId}/weight_history` legado/coexistência
- `dogs/{dogId}/feeding_events`
- `dogs/{dogId}/feedings` legado/coexistência
- `dogs/{dogId}/nutritional_prescriptions`
- `dogs/{dogId}/nutrition_prescriptions` legado/coexistência
- `dogs/{dogId}/nutrition_supplements`
- `dogs/{dogId}/documents`
- `documentos/{docId}` legado/raiz para documentos

Serviços:

- `HealthService`
- `DogProfileService`
- `WeightHistoryService`
- `NutritionService`
- `PdfAttachmentService`

Regras:

- peso canônico: `weight_records`;
- saúde usa `health_events`;
- documentos continuam funcionando no caminho raiz/documentos enquanto não houver migração;
- PDF/laudo deve ser anexável e preservado;
- documentos são arquiváveis, não deletáveis;
- suplementos têm histórico próprio;
- hidratação é campo simples na prescrição;
- saúde não deve exibir especialidades operacionais.

Para o web:

- prontuário deve ser muito mais confortável que o mobile: tabelas, filtros, timeline, anexos;
- permitir upload PDF;
- registrar vacina/peso/nutrição com autoria;
- preservar dual-read enquanto dados legados existirem.

---

## 14. Notificações

Coleção:

- `notifications/{ra}/items/{notificationId}`

Modelo:

- `NotificationItem`

Campos importantes:

- `type`
- `created_at`
- `read_at`
- `action_required`
- `resolved_at`
- `archived_at`
- `target_screen`
- `additional_data`
- `occurrence_id`
- `promotion_request_id`
- `dog_id`
- `modality`
- `module_id`
- `decision_reason`

Regra consolidada:

- badge conta `action_required == true && resolved_at == null`;
- `read_at` não resolve pendência;
- pendência aberta não é arquivável;
- aviso pode ser soft-archived com `archived_at`;
- delete físico bloqueado;
- assinatura/evolução sempre abrem tela de revisão, não resolvem em um clique;
- convite de guarnição pode ter ação inline.

Tipos principais:

- `vehicle_crew_invitation`
- `signature_requested`
- `training_promotion_requested`
- avisos derivados: aprovado/rejeitado/finalizado/bônus.

Para o web:

- central de pendências deve ser uma primeira-classe;
- separar "Requer ação" de "Avisos";
- ações críticas via Function;
- backfill/resolution logic deve continuar alinhado ao backend.

---

## 15. Histórico

Tela:

- `HistoryScreen`

Carregador:

- `history_data_loader.dart`

Escopo:

- ocorrências;
- treinos;
- saúde;
- nutrição;
- peso;
- documentos/eventos conforme fontes disponíveis.

Regras:

- deve ler caminhos legados e novos;
- filtrar sem ocultar dados importantes por padrão estreito;
- timeline deve respeitar autoria/timestamp;
- detalhes de ocorrência finalizada devem refletir hash/PDF/auditoria.

Para o web:

- histórico deve virar timeline/tabela robusta;
- filtros por cão, condutor, período, tipo, modalidade, status;
- exportação administrativa é uma necessidade nova do web.

---

## 16. Storage e Anexos

Storage rules relevantes:

- `profile_photos/{fileName}`
- `users/{fileName}`
- `trainings/{fileName}`
- `health/{fileName}`
- `health/exams/{fileName}`
- `health_attachments/{dogId}/{fileName}`
- `occurrences/{occurrenceId}/events/{fileName}`
- `occurrences/{occurrenceId}/finalization/{fileName}`
- `dogs/{dogId}/feeding_photos/{fileName}`
- `dogs/{dogId}/training_sessions/{sessionId}/media/{fileName}`
- `documentos/{dogId}/{fileName}`
- `occurrences/{occurrenceId}/{fileName}` para PDF

Serviços:

- `StorageService`
- `MediaAttachmentUploadService`
- `MediaProcessingService`
- `PdfAttachmentService`

Regras:

- imagens têm limite de tamanho por path;
- PDFs de saúde/documentos têm limite próprio;
- update/delete no Storage costuma ser bloqueado;
- hash SHA-256 de mídia é usado para integridade de ocorrência.

Para o web:

- uploads devem respeitar os mesmos paths e limits;
- PDFs e imagens devem ser tratados como anexos imutáveis/arquiváveis;
- verificação de mídia deve continuar server-side quando ligada a ocorrência.

---

## 17. Firestore Rules - Contratos Críticos

Regras recorrentes:

- delete físico bloqueado em quase todos os domínios;
- create/update relevante exige `audit_trail`;
- soft delete usa `deleted_at`, `deleted_by`, `delete_reason`;
- ocorrências finalizadas bloqueiam edição comum;
- progressão de treino tem update limitado;
- `completed_modules` não é campo livre para client;
- notificações não são deletadas.

Matches principais:

- `active_shifts/{ra}`
- `shift_logs/{shiftId}`
- `vehicles/{vehicleId}`
- `vehicle_crews/{crewId}`
- `vehicle_crews/{crewId}/members/{ra}`
- `users/{ra}`
- `users/{ra}/devices/{deviceId}`
- `dogs/{dogId}`
- `dogs/{dogId}/training/{modality}`
- `dogs/{dogId}/training_sessions/{sessionId}`
- `dogs/{dogId}/health_events/{eventId}`
- `dogs/{dogId}/weight_records/{recordId}`
- `dogs/{dogId}/feeding_events/{feedingId}`
- `occurrences/{occurrenceId}`
- `occurrences/{occurrenceId}/events/{eventId}`
- `occurrences/{occurrenceId}/signatures/{signatureId}`
- `training_programs/{programId}`
- `promotion_requests/{requestId}`
- `notifications/{userId}/items/{notificationId}`

Para o web:

- não confiar apenas em UI para esconder ações;
- se uma ação não passa pela rule ou Function, está errada;
- Admin web deve usar Functions para claims e transições sensíveis.

---

## 18. Cloud Functions

Arquivo:

- `functions/src/index.ts`

Região:

- `southamerica-east1`

Functions/callables importantes:

- `setK9InstructorRole`
- `inviteVehicleCrewMember`
- `respondVehicleCrewInvitation`
- `sealOccurrenceV4`
- `closeOccurrenceForSignatures`
- `signOccurrence`
- `requestOccurrenceCorrection`
- `acceptOccurrenceParticipation`
- `declineOccurrenceParticipation`
- `verifyOccurrence`

Triggers:

- `onTrainingPromotionRequestCreated`
- `onTrainingPromotionRequestUpdated`
- `onTrainingProgramMilestoneCreated`
- `onNotificationCreated`

Responsabilidades:

- aplicar progressão de treino aprovada;
- notificar Instrutores K9;
- resolver notificações após ação;
- atribuir/remover role Instrutor K9;
- selar ocorrência;
- fechar ocorrência para assinaturas;
- assinar ocorrência;
- reabrir por correção;
- aceitar/recusar participação;
- enviar FCM quando notificação é criada;
- expor verificador público.

Para o web:

- criar camada `functions`/`actions` explícita;
- operações de Admin e aprovação devem chamar callables;
- nunca duplicar lógica de transição crítica em React/Next client.

---

## 19. Design System Mobile

Fonte visual principal:

- `AppTheme`
- `BinomioHeader`
- componentes `hud_*`
- componentes `tactical_*`

Tokens recorrentes:

- fundo escuro tático;
- ciano como ação/ênfase;
- amarelo como atenção/formação;
- verde como operacional/sucesso;
- vermelho como erro/crítico;
- Inter para texto;
- IBM Plex Mono para dado técnico/hash/timestamp/contexto.

Componentes globais:

- `BinomioHeader`
- `MainRoot` bottom nav;
- FAB de ocorrência;
- cards táticos;
- painéis HUD;
- central de notificações/bell no header.

Para o web:

- preservar identidade visual;
- não copiar bottom nav, FAB e layout 390px;
- usar tokens equivalentes em Tailwind/shadcn;
- dados técnicos continuam bons em fonte mono.

---

## 20. Coexistência e Legado

O mobile ainda lê/grava alguns caminhos legados por compatibilidade.

Exemplos:

- treinos: `trainings`, `training_sessions`, `dogs/{dogId}/training_sessions`;
- peso: `weight_history` e `weight_records`;
- nutrição: `feedings` e `feeding_events`;
- prescrição: `nutrition_prescriptions` e `nutritional_prescriptions`;
- documentos: `documentos` raiz e documentos por cão;
- especialidades: `specialties` como espelho/coexistência da progressão.

Regra para o web:

- começar lendo o canônico;
- quando necessário, dual-read para não perder histórico;
- novas escritas devem ir para o canônico;
- não fazer migração destrutiva sem plano, backfill e validação.

---

## 21. O Que É Domínio Reutilizável no Web

Reutilizar diretamente:

- Auth por RA/email;
- claims e papéis;
- modelo de cão;
- turno ativo;
- guarnição/viatura;
- ocorrências e estados;
- eventos de ocorrência;
- assinatura/correção;
- hash/verificador;
- notificações acionáveis;
- treinamento Formação/Operacional;
- currículo em Firestore;
- promoção co-validada;
- saúde/prontuário;
- peso/nutrição/documentos;
- audit trail;
- soft delete;
- Storage paths.

Repensar para web:

- bottom nav;
- FAB;
- sheets mobile;
- dashboards 390px;
- fluxo de formulário em tela cheia;
- navegação por tabs estreitas;
- ações rápidas do cockpit mobile.

Adicionar no web aos poucos:

- CRUD administrativo de currículo;
- gestão completa de usuários/claims;
- relatórios gerenciais;
- tabelas e filtros avançados;
- auditoria consultável por gestor;
- dashboards por período;
- exportações;
- gestão de viaturas/cães/condutores em escala.

---

## 22. Lacunas e Pontos de Atenção

1. **Web terá escopo novo.**  
   Nem tudo existe no mobile. Admin, relatórios e gestão de currículo são naturalmente web-first.

2. **Mobile tem coexistência real.**  
   O web não deve assumir que só existe o caminho canônico.

3. **Rules são a verdade de segurança.**  
   Antes de criar tela web de escrita, conferir se a rule ou Function suporta a operação.

4. **Detecção tem lógica própria.**  
   Não unificar às pressas com B&C/G&P sem diagnóstico específico.

5. **Guarda & Proteção é recém-implantado.**  
   Currículo v1 já existe, mas validação real de campo ainda é dependente de uso.

6. **Documentos de saúde ainda têm coexistência.**  
   Não migrar paths sem plano.

7. **Release mobile recente ainda tem worktree mista.**  
   Há alterações locais não commitadas no momento desta Bíblia; conferir antes de usar como baseline de release.

---

## 23. Comandos Úteis

Instalar deps:

```powershell
flutter pub get
```

Análise focada:

```powershell
C:\flutter\bin\cache\dart-sdk\bin\dart.exe analyze <arquivos>
```

Build release:

```powershell
$env:PATH='C:\Windows\system32;C:\Windows;C:\Windows\System32\WindowsPowerShell\v1.0;C:\Program Files\Git\cmd;C:\flutter\bin;' + $env:PATH
& 'C:\flutter\bin\flutter.bat' build apk --release
```

Seed de currículo B&C:

```powershell
node tools\upload_training_programs.js tools\training_programs_busca_captura_seed.json
```

Seed de currículo G&P:

```powershell
node tools\upload_training_programs.js tools\training_programs_guarda_protecao_seed.json
```

Atribuir Instrutor K9 para teste:

```powershell
node tools\set_k9_instructor.js --ra <RA> --service-account "<caminho-json>"
```

Deploy rules:

```powershell
firebase deploy --only firestore:rules --project canil-gcm
```

Deploy Functions:

```powershell
firebase deploy --only functions --project canil-gcm
```

---

## 24. Mapa Rápido Para o Web

Primeiros módulos recomendados no web:

1. **Auth + Layout Admin**
   - login;
   - leitura do usuário atual;
   - permissões/claims;
   - shell administrativo.

2. **Dashboard Canil**
   - cães ativos;
   - turnos ativos;
   - ocorrências abertas;
   - pendências;
   - promoções aguardando;
   - alertas de saúde.

3. **Cães**
   - perfil;
   - saúde;
   - treinos;
   - ocorrências;
   - documentos.

4. **Treinos**
   - leitura de progressão;
   - solicitações de promoção;
   - aprovação/rejeição;
   - currículo em modo leitura;
   - depois CRUD admin de currículo.

5. **Ocorrências**
   - consulta;
   - revisão;
   - assinaturas;
   - PDF;
   - integridade/verificador.

6. **Admin**
   - usuários;
   - Instrutor K9;
   - viaturas;
   - cães;
   - cadastros auxiliares.

7. **Relatórios**
   - por período;
   - por cão;
   - por condutor;
   - por modalidade;
   - exportação.

---

## 25. Decisões Canônicas Para Não Reabrir Sem Motivo

- Web novo deve começar do zero.
- Stack recomendada do web: Next.js + TypeScript + Firebase + Tailwind + shadcn/ui.
- Web herda domínio, não layout mobile.
- Treino não tem hash de prova.
- Ocorrência finalizada tem hash/verificador.
- Progressão canônica de modalidade é `dogs/{dogId}/training/{modality}`.
- `specialties` continua como coexistência para o hub.
- Currículo é dado em Firestore, não hardcode.
- Promoção é co-validada por Instrutor K9 e aplicada no servidor.
- Pendência acionável só sai quando resolvida, não quando lida.
- Soft delete é padrão; hard delete é exceção bloqueada.

---

## 26. Arquivos-Chave

Bootstrap:

- `lib/main.dart`
- `lib/features/app_shell/presentation/screens/main_root_screen.dart`

Tema/UI:

- `lib/core/theme/app_theme.dart`
- `lib/core/widgets/binomio_header.dart`

Firebase/security:

- `firestore.rules`
- `storage.rules`
- `functions/src/index.ts`
- `firebase.json`

Ocorrências:

- `lib/features/occurrences/data/occurrence_repository.dart`
- `lib/features/occurrences/data/occurrence_event_repository.dart`
- `lib/features/occurrences/data/signature_repository.dart`
- `lib/core/services/occurrence_transition_service.dart`
- `lib/core/services/occurrence_finalization_service.dart`
- `lib/core/services/integrity_verification_service.dart`

Treinos:

- `lib/features/training/data/training_service.dart`
- `lib/features/training/data/training_program_service.dart`
- `lib/features/training/data/training_promotion_service.dart`
- `lib/features/training/data/detection_service.dart`
- `lib/features/training/presentation/screens/training_hub_screen.dart`
- `lib/features/training/presentation/screens/busca_captura_formacao_screen.dart`
- `lib/features/training/presentation/screens/guard_protection_curriculum_screen.dart`

Saúde/nutrição:

- `lib/features/health/data/health_service.dart`
- `lib/features/health/presentation/screens/dog_health_prontuario_screen.dart`
- `lib/features/nutrition/data/nutrition_service.dart`
- `lib/features/dogs/data/weight_history_service.dart`
- `lib/features/dogs/data/dog_profile_service.dart`

Turno/guarnição:

- `lib/features/shifts/data/shift_service.dart`
- `lib/features/shifts/data/vehicle_crew_service.dart`
- `lib/features/shifts/data/vehicle_crew_transition_service.dart`
- `lib/features/shifts/presentation/screens/active_shift_dashboard_screen.dart`
- `lib/features/shifts/presentation/screens/vehicle_crew_profile_screen.dart`

Notificações:

- `lib/core/domain/notification_item.dart`
- `lib/core/services/notification_service.dart`
- `lib/core/services/push_notification_service.dart`
- `lib/features/occurrences/presentation/screens/pending_screen.dart`

Histórico:

- `lib/features/history/presentation/screens/history_screen.dart`
- `lib/features/history/presentation/screens/history_data_loader.dart`
- `lib/features/history/presentation/screens/history_detail_screen.dart`

Tools:

- `tools/set_k9_instructor.js`
- `tools/upload_training_programs.js`
- `tools/training_programs_busca_captura_seed.json`
- `tools/training_programs_guarda_protecao_seed.json`
- `tools/backfill_notification_resolution.js`

