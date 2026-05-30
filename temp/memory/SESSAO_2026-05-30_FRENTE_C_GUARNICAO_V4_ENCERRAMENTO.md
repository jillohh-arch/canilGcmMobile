# Sessão 2026-05-30 - Frente C, guarnição por viatura, hash v4 e estabilização

## Contexto

Esta sessão continuou a Frente C do app Canil K9 GCM Limeira, partindo do modelo de equipe e coassinatura já iniciado na Parte 10 e revisado pela Parte 11/12. O foco deixou de ser equipe montada manualmente dentro da ocorrência e passou para guarnição operacional por viatura, com convite, aceite/recusa, participação na ocorrência, assinatura posterior e integridade probatória.

O trabalho foi feito na branch `feature/frente-c-guarnicao-viatura`, com o objetivo de manter a `main` buildável e entregar APKs testáveis no celular durante a validação.

## Especificações e decisões aplicadas

- `ESPEC_TECNICA_PARTE_10.md`: base de equipe, assinaturas, subcoleções, notificações, PDF e rules.
- `ESPEC_TECNICA_PARTE_11.md`: revisão do modelo para guarnição por viatura e cão como membro pleno.
- `ESPEC_TECNICA_PARTE_12.md`: evolução do fluxo para equipe formada fora da ocorrência, participação com aceite/recusa, correções, notificações e transições sensíveis no servidor.
- Prompt detalhado da Frente C por viatura: adotado o modelo com `vehicle_crews`, `members`, `participations`, `signature_round`, `correction_requests`, Functions para FCM/transições e compatibilidade legada com `dogId`.

Decisão central: a ocorrência não monta equipe por autocomplete no momento do registro. A equipe nasce antes, na guarnição da viatura, e a ocorrência captura um snapshot operacional dessa composição.

## Modelo de guarnição e viatura

- Criada a coleção lógica `vehicle_crews`.
- O turno passou a guardar dados de viatura e guarnição:
  - `vehicle_id`
  - `vehicle_label`
  - `vehicle_prefix`
  - `vehicle_model`
  - `vehicle_unit`
  - `vehicle_crew_id`
  - `crew_role`
  - `crew_status`
- Criado modelo de domínio para `VehicleCrew` e `VehicleCrewMember`.
- Criado serviço `VehicleCrewService` para acompanhar guarnição e membros.
- Criado serviço `VehicleCrewTransitionService` para chamar Functions de convite e resposta.
- Ajustado `ShiftService` para assumir viatura, criar/atualizar guarnição, manter titular e sincronizar active shift.
- Ajustado `ShiftViewModel` para seleção de cão/viatura e troca de cão sem encerrar expediente.
- Mantido fallback legado `dogId` junto de `service_dog_id`.

## Cão como membro pleno

- O modelo de ocorrência passou a carregar dados de viatura e equipe binômio.
- O cão continua sem assinar, mas aparece como membro operacional do binômio.
- O PDF e telas de detalhe foram preparados para exibir condutor + K9, incluindo matrícula quando disponível.
- A captura de equipe preserva o vínculo do condutor, cão e viatura no momento da ocorrência.

## Equipe fora da ocorrência

- Criada tela de perfil/gestão de guarnição por viatura.
- Criado header de equipe/guarnição no dashboard de turno.
- A antiga lógica de adicionar integrante direto na ocorrência foi substituída pelo fluxo de convite na guarnição.
- A lista de candidatos para convite passou a ler `/users`, não apenas `active_shifts`.
- Foi corrigido o fallback para usuários cadastrados como `/users/{RA}` sem campo `ra` no corpo do documento.
- O convite mantém o status `pending` até o condutor aceitar.
- O integrante só entra efetivamente na guarnição após aceite.
- A recusa exige motivo e fica registrada.

## Participação na ocorrência

- Ao abrir ocorrência, os membros aceitos da guarnição são capturados como equipe/participações.
- Foram adicionadas estruturas para `participations`, com aceite automático ou registro de recusa justificada conforme o fluxo.
- Condutores aceitos podem colaborar na ocorrência enquanto ela estiver aberta.
- As notificações de ocorrência aberta e assinatura pendente foram integradas ao fluxo de pendências.
- Criada tela de revisão da ocorrência para permitir que o condutor veja o conteúdo antes de concordar/assinar.

## Hash e integridade

- Criado `hash_version: 4`.
- O v4 inclui equipe, participações, rodada de assinatura e dados necessários para coautoria probatória.
- O verificador foi conectado antes de liberar o v4:
  - v1: legado.
  - v2: inclui fotos.
  - v3: inclui equipe/assinaturas do modelo anterior.
  - v4: inclui guarnição/participações/rodada.
- Criado/expandido `IntegrityVerificationService`.
- Ajustado `OccurrenceFinalizationService` para serialização determinística compatível com v1, v2, v3 e v4.
- Adicionados testes para verificação de hash v1-v4 e preservação de v3 legado.
- O fechamento v4 passou a delegar transição sensível para Function.

## Assinaturas e devolução para draft

- Ajustado fluxo de assinatura para preservar histórico probatório.
- A devolução para draft não apaga assinaturas anteriores.
- Assinaturas da rodada são invalidadas pela `signature_round`, preservando o registro original.
- Corrigido ponto de permissão no client: a assinatura grava primeiro a subcoleção crítica e trata atualização auxiliar da ocorrência como best effort quando rules bloqueiam side effects.
- Mantido fallback de senha e biometria para assinatura.

## Firebase Functions

Foi criada a pasta `functions/` com TypeScript e Firebase Functions 2nd gen.

Functions relevantes:

- `inviteVehicleCrewMember`
  - Envia convite para integrante da guarnição.
  - Agora valida o convidado em `/users/{ra}`.
  - Não exige que o convidado tenha turno ativo para receber convite.

- `respondVehicleCrewInvitation`
  - Aceita ou recusa convite.
  - Aceite não exige turno ativo.
  - Se houver turno ativo, sincroniza viatura/guarnição no turno.
  - Registra `auth_uid` e e-mail do condutor no membro aceito.

- `sealOccurrenceV4`
  - Responsável por selar ocorrência v4 no servidor.
  - Calcula hash e atualiza status de forma centralizada.

- `requestOccurrenceCorrection`
  - Registra solicitação de correção/devolução sem apagar histórico.

- `declineOccurrenceParticipation`
  - Registra recusa de participação com justificativa.

- `onNotificationCreated`
  - Preparada para push via FCM.
  - Deploy geral encontrou pendência de permissão/Eventarc para este gatilho.
  - As Functions de convite/resposta foram deployadas separadamente com sucesso.

## Firestore rules

- `firestore.rules` foi versionado e ampliado.
- Foram adicionadas regras para:
  - `vehicle_crews`
  - `vehicle_crews/{crewId}/members`
  - `notifications`
  - `occurrences`
  - `participations`
  - `signatures`
  - restrições por status da ocorrência
  - restrições de edição em estados sensíveis
- Corrigida regra de retomada de guarnição/viatura para permitir assumir guarnição inativa sem abrir escrita ampla em guarnição ativa.
- Rules foram deployadas durante a sessão.

## Notificações e push

- Criado/expandido `NotificationItem`.
- Criado `PushNotificationService`.
- O app registra token de dispositivo em `/users/{ra}/devices`.
- Notificações de convite de guarnição foram integradas com ações de aceitar/recusar.
- A tela de pendências foi ampliada para abrir guarnição, ocorrência e assinatura conforme o tipo.
- Pendência restante: o gatilho `onNotificationCreated` depende de permissão/propagação Eventarc no Firebase. Convite e aceite via app estão funcionando no servidor, mas push automático ainda deve ser revalidado após resolver Eventarc.

## UI e fluxo ajustados durante teste no celular

Problemas reportados e tratados:

- Splash screen travada:
  - `main.dart` deixou de bloquear o app aguardando push/App Check.
  - Inicialização de push ficou defensiva e não bloqueante.

- Loop após selecionar cão/viatura:
  - Corrigido uso de timeout contínuo nos viewmodels.
  - `UserViewModel` e `ShiftViewModel` passaram a usar timer apenas para carga inicial.

- Foto do condutor sumindo:
  - Corrigido fallback de usuários e leitura de campos alternativos (`photoUrl`, `image_url`).

- Perfil do usuário e botão de encerrar expediente:
  - Ajustado fluxo de navegação/estado para não retornar indevidamente à seleção de cão.

- Erro ao assinar ocorrência:
  - Ajustado fluxo para não falhar toda a assinatura quando atualização auxiliar no documento principal encontra restrição de rule.

- Lista de integrantes mostrando poucos condutores:
  - Corrigida fonte da lista para `/users`.
  - Removida dependência de `active_shifts` para convidar.
  - Adicionado fallback pelo ID do documento quando o campo `ra` está ausente.

## PDF e ocorrência

- A finalização passou a delegar hash/selagem ao serviço central.
- O PDF foi ajustado para lidar com equipe/assinaturas no novo modelo.
- Houve relato de out of memory em um PDF específico grande; foram feitos ajustes de fluxo, mas esse caso ainda merece validação focada se voltar a ocorrer.

## Dependências e configuração

- Adicionadas dependências necessárias para Functions, Cloud Functions e push.
- `firebase.json` passou a configurar Functions com predeploy `npm run build`.
- `AndroidManifest.xml` recebeu ajustes necessários ao fluxo de notificações.
- `.gitignore` foi atualizado para evitar versionar artefatos locais/gerados de Functions e configuração local da Claude.

## Validações executadas

Durante a sessão foram executados:

- `dart format` nos arquivos alterados pontualmente.
- `dart analyze` em arquivos críticos alterados.
- `npm run build` em `functions/`.
- Deploy de Firestore rules.
- Deploy das Functions `inviteVehicleCrewMember` e `respondVehicleCrewInvitation`.
- `flutter build apk --release`.
- Cópia do APK release para `G:\Meu Drive\app k9\claude\app-release.apk`.

Resultado confirmado no fechamento:

- APK release gerado com sucesso.
- APK copiado para o Drive.
- Functions de convite e resposta atualizadas com sucesso em produção.
- Pendência externa: `onNotificationCreated` requer resolver/aguardar permissão Eventarc.

## Arquivos principais alterados/criados

- `firestore.rules`
- `firebase.json`
- `functions/src/index.ts`
- `functions/package.json`
- `functions/package-lock.json`
- `functions/tsconfig.json`
- `lib/main.dart`
- `lib/core/domain/notification_item.dart`
- `lib/core/domain/occurrence_participation.dart`
- `lib/core/domain/occurrence_signature.dart`
- `lib/core/services/integrity_verification_service.dart`
- `lib/core/services/notification_service.dart`
- `lib/core/services/occurrence_finalization_service.dart`
- `lib/core/services/occurrence_transition_service.dart`
- `lib/core/services/push_notification_service.dart`
- `lib/features/occurrences/data/occurrence_repository.dart`
- `lib/features/occurrences/data/signature_repository.dart`
- `lib/features/occurrences/domain/occurrence.dart`
- `lib/features/occurrences/presentation/screens/active_occurrence_screen.dart`
- `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart`
- `lib/features/occurrences/presentation/screens/occurrence_review_screen.dart`
- `lib/features/occurrences/presentation/screens/occurrence_team_screen.dart`
- `lib/features/occurrences/presentation/screens/pending_screen.dart`
- `lib/features/occurrences/presentation/screens/start_occurrence_screen.dart`
- `lib/features/shifts/data/shift_service.dart`
- `lib/features/shifts/data/vehicle_crew_service.dart`
- `lib/features/shifts/data/vehicle_crew_transition_service.dart`
- `lib/features/shifts/domain/active_shift_session.dart`
- `lib/features/shifts/domain/vehicle.dart`
- `lib/features/shifts/domain/vehicle_crew.dart`
- `lib/features/shifts/presentation/screens/active_shift_cockpit.dart`
- `lib/features/shifts/presentation/screens/active_shift_dashboard_screen.dart`
- `lib/features/shifts/presentation/screens/active_shift_profile_cards.dart`
- `lib/features/shifts/presentation/screens/vehicle_crew_profile_screen.dart`
- `lib/features/shifts/presentation/viewmodels/shift_viewmodel.dart`
- `lib/features/users/data/user_service.dart`
- `lib/features/users/domain/user.dart`
- `lib/features/users/presentation/viewmodels/user_viewmodel.dart`
- `test/core/services/integrity_verification_service_test.dart`
- `test/core/services/occurrence_finalization_service_test.dart`

## Atualizacao complementar da sessao - 30/05/2026

Depois dos testes no celular, foram feitos ajustes adicionais importantes na Frente C e em telas transversais do app.

### Headers padronizados fora de ocorrencias

- O header que estava visualmente melhor na aba Treinos foi usado como referencia.
- O componente `BinomioHeader` passou a concentrar os atalhos padronizados: trocar K9, notificacoes/pendencias com badge e perfil do condutor.
- Foram alinhados os headers de Turno/Dashboard, Treinos, Historico e Prontuario K9.
- O header das telas de ocorrencia foi mantido fora dessa padronizacao, conforme solicitado.
- A navegacao para perfil voltou a abrir a tela completa do condutor, preservando o botao de encerrar expediente.

### Devolucao para retificacao

Problema observado no celular:

- O GCM Silva abriu a notificacao de assinatura.
- Ao revisar, devolveu a ocorrencia para retificacao.
- Na conta do relator, a ocorrencia voltou para `in_progress`, mas a tela de finalizacao nao vinha com todos os dados preenchidos.
- Ao tentar finalizar novamente, houve erro de permissao do Firestore.

Correcoes aplicadas:

- A Function `requestOccurrenceCorrection` passou a restaurar `finalization_draft` a partir dos campos finais ja gravados na ocorrencia.
- As assinaturas da rodada continuam sendo invalidadas como `obsolete`, sem apagar o historico probatorio.
- A tela `FinalizeOccurrenceScreen` passou a reconstruir o rascunho com uma estrategia mais segura:
  - usa o draft salvo quando ele tem conteudo;
  - se o draft estiver vazio ou parcial, recupera `final_report`, `results` e `details` da ocorrencia;
  - mescla draft parcial com dados finais preservados, evitando perder edicoes feitas apos a devolucao.

### Fechamento para assinaturas no servidor

Problema identificado:

- O fechamento para nova rodada de assinaturas ainda dependia de escrita direta do client no documento da ocorrencia e nas subcolecoes.
- Isso deixava a transicao sensivel vulneravel a `permission-denied` e contrariava a decisao da Frente C de mover transicoes criticas para Firebase Functions.

Correcoes aplicadas:

- Criada a Cloud Function `closeOccurrenceForSignatures`.
- O app passou a chamar essa Function via `OccurrenceTransitionService`.
- A Function valida no servidor: ocorrencia aberta, relator autenticado, integrantes aptos e rodada atual de assinatura.
- A Function grava `awaiting_signatures`, prazo, dados de finalizacao, assinaturas pendentes, notificacoes e trilha de auditoria.
- Foram removidas notificacoes duplicadas criadas pelo client nesse fechamento.

### Assinatura no servidor

Problema observado:

- Mesmo apos ajustes de rules, a assinatura do GCM Silva ainda retornava `cloud_firestore/permission-denied`.
- A causa provavel era a assinatura ainda tentar gravar direto em `occurrences/{id}/signatures/{ra}` pelo app, dependendo de indices como `team_auth_keys`/`team_auth_uids` estarem completos e perfeitamente sincronizados.

Correcoes aplicadas:

- Criada a Cloud Function `signOccurrence`.
- O app deixou de fazer escrita direta em `signatures` ao assinar.
- `OccurrenceRepository.addSignature` agora chama `OccurrenceTransitionService.signOccurrence`.
- A Function valida no servidor: ocorrencia em `awaiting_signatures`, condutor na equipe, condutor coassinante, rodada atual e usuario autenticado compativel com o RA/UID.
- A Function grava assinatura, `signed_handler_ids`, `signed_emails`, `signed_auth_uids`, auditoria inline, `auditLogs` e notificacao ao relator.
- A validacao de coassinantes no servidor foi flexibilizada com seguranca para aceitar participantes `accepted` ou `pending` que nao tenham recusado, mantendo bloqueio para `declined`.

### Firestore rules e permissao

- As rules continuam fechando escrita direta sensivel para finalizacao, reabertura e assinatura.
- A correcao principal nao foi abrir permissao ampla no Firestore, e sim mover a assinatura para Function administrativa com validacao explicita.
- O arquivo `firestore.rules` permaneceu versionado e com restricoes para ocorrencias, assinaturas, participacoes, notificacoes e aditamentos.

### UI de assinatura

- O modal de assinatura foi ajustado para caber melhor no celular.
- Foram adicionados botoes claros para assinar com biometria, assinar com senha/fallback e cancelar.
- O erro de permissao deixou de depender da escrita direta do modal, porque a conclusao de assinatura agora passa pela Function `signOccurrence`.

### Validacoes executadas nesta complementacao

- `npm run build` em `functions/`.
- Deploy das Functions para o projeto `canil-gcm`.
- Criacao/atualizacao em producao das Functions `closeOccurrenceForSignatures`, `signOccurrence`, `requestOccurrenceCorrection`, `sealOccurrenceV4`, `declineOccurrenceParticipation`, `inviteVehicleCrewMember`, `respondVehicleCrewInvitation` e `onNotificationCreated`.
- `dart format` nos arquivos alterados.
- `dart analyze` na area de ocorrencias e servicos afetados.
- `flutter build apk --release`.
- APK copiado para `G:\Meu Drive\app k9\claude\app-release.apk`.

Ultimo APK gerado nesta complementacao:

- Caminho: `G:\Meu Drive\app k9\claude\app-release.apk`
- Tamanho: `154496838 bytes`
- Data/hora: `30/05/2026 16:45:39`

### Observacao de Git

- No momento desta complementacao, o trabalho ja estava diretamente na branch `main`.
- Portanto, nao houve merge tecnico de uma feature branch para `main`; o encerramento correto e commit direto na `main`.

## Pendencias recomendadas apos a complementacao

1. Reinstalar o APK atualizado no celular.
2. Testar novamente o fluxo completo: relator fecha para assinatura, GCM Silva abre a pendencia, revisa, assina e o relator visualiza assinatura concluida.
3. Testar devolucao para retificacao novamente: integrante devolve, relator reabre, campos finais aparecem preenchidos, relator finaliza de novo e nova rodada de assinatura e criada.
4. Confirmar que o hash v4 final continua incluindo equipe, participacoes, assinaturas e correction_requests.
5. Revalidar push real com app em segundo plano/fechado.

## Pendências recomendadas para a próxima sessão

1. Resolver permissão/propagação Eventarc para `onNotificationCreated`.
2. Validar push real no aparelho com app fechado, incluindo ações aceitar/recusar.
3. Revalidar assinatura de ocorrência com rules em produção.
4. Testar ocorrência grande que causou out of memory no PDF.
5. Validar guarnição com mais de dois condutores cadastrados em `/users`.
6. Confirmar se o fluxo de troca de cão durante turno atende ao uso operacional real.
7. Revalidar PDF com equipe, K9, matrículas, assinaturas e status de pendência.

## Observação de encerramento

Esta sessão consolidou uma mudança de arquitetura: a Frente C deixou de ser apenas "assinatura de equipe na ocorrência" e passou a representar a guarnição operacional da viatura, com participação auditável, aceite/recusa, transições sensíveis no servidor e hash v4 cobrindo a nova estrutura.
