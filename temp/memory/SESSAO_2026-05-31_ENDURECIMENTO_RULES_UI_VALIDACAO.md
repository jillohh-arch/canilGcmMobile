# Sessão 2026-05-31 - Endurecimento de rules, integridade, UI e validação no aparelho

## Contexto

Esta sessão continuou a estabilização da Frente C e atacou os pontos críticos apontados pela auditoria forense: permissões frouxas no Firestore/Storage, rastreabilidade por `audit_trail`, validação real do selo, fluxo de guarnição/participação, telas principais e correções de permissão vistas no celular.

O trabalho foi feito sobre a branch `main`, que já carregava a Frente C de guarnição por viatura, hash v4 e assinatura. Ao final, o APK release foi gerado, copiado para o Google Drive e validado no aparelho pelo usuário.

## Resultado final validado

- App abriu corretamente após instalação do APK release.
- Seleção de cão e viatura deixou de entrar em loop.
- Header/menu passou a funcionar de forma consistente nas telas principais.
- Registro de treinos voltou a funcionar com rules endurecidas.
- Fluxo de ocorrência, participação, devolução, finalização e assinatura foi validado no aparelho.
- Firestore rules e Storage rules foram publicadas no Firebase.
- APK release atualizado foi copiado para `G:\Meu Drive\app k9\claude\app-release.apk`.
- Usuário confirmou: "tudo testado e tudo ok".

## Firestore rules

As regras foram endurecidas para reduzir escrita ampla e tornar as permissões compatíveis com prova operacional.

### Mudanças principais

- `rules_version = '2'` mantido e regras versionadas no repositório.
- Criadas funções auxiliares para validar trilha inline:
  - `hasInlineAuditOnCreate()`
  - `appendsInlineAuditOnUpdate()`
  - `canCreateAuditedRecord()`
  - `canUpdateAuditedRecord()`
  - `canUpdateAuditedOrSoftDelete()`
- `dogs`, `users`, `health_logs`, `trainings`, `training_sessions`, `incidents`, `routines`, `gps_tracks`, comandos, especialidades, documentos e estados operacionais passaram a exigir auditoria inline.
- `active_shifts` continuou restrito ao RA do usuário autenticado.
- `shift_logs` exige validação do payload e vínculo com o condutor.
- `vehicle_crews` ficou restrito ao titular/condutor correto e com campos permitidos controlados.
- `occurrences` passou a validar estado editável, participação, editor autorizado, assinatura, aditamento e transições.
- `participations` deixou de permitir update direto pelo client.
- `correction_requests` ficou bloqueado para escrita direta do client.
- `auditLogs` deixou de aceitar qualquer log genérico de usuário logado. Agora exige:
  - `actor.uid` igual ao `request.auth.uid`;
  - `actor.email` igual ao e-mail autenticado;
  - `source == 'mobile'`;
  - campos controlados.
- `badges_state` ficou restrito ao próprio usuário.
- `generated_pdfs` foi fechado para escrita direta do client.
- `documentos` passou a exigir `audit_trail` e payload validado.
- Deletes físicos foram mantidos bloqueados nas entidades críticas.

### Pontos verificados após endurecimento

A busca por padrões de risco ainda encontra ocorrências de `signedIn()`, mas elas aparecem dentro de regras com condições adicionais, como titular, RA, editor autorizado, status editável ou validação de payload. Não ficou escrita ampla direta do tipo `allow create, update: if signedIn()` em coleções críticas sem complemento.

## Storage rules

As regras de Storage foram endurecidas para impedir apagamento de evidências e mídias por qualquer usuário logado.

### Mudanças principais

- Uploads continuam permitidos por tipo e tamanho, mas `update` e `delete` foram bloqueados.
- Pastas como `profile_photos`, `users`, `routines`, `trainings`, `incidents`, `health`, fotos de ocorrência, fotos de finalização e mídias de treino agora usam:
  - `allow create` validado por tipo/tamanho;
  - `allow update, delete: if false`.
- Criada regra para `documentos/{dogId}/{fileName}` permitindo imagem, PDF, DOC e DOCX até 20 MB.
- `health_attachments/{dogId}/{fileName}` mantido para anexos de saúde.

## Identidade ativa e treinos

O erro de permissão ao registrar treinos foi rastreado para divergência entre usuário autenticado, RA/handler usado no payload e o turno ativo.

### O que foi implementado

- Criado `ActiveShiftIdentityService`.
- Serviços de treino passaram a resolver identidade canônica do turno ativo antes de gravar.
- `TrainingService` passou a enviar `handlerId`, `handler_id`, `performed_by`, `dogId` e `dog_id` compatíveis com o turno ativo.
- `TrainingViewModel` foi ajustado para usar a identidade ativa.
- `detection_triagem_screen.dart` passou a gravar avaliação com auditoria e identidade compatível.
- Compatibilidade com `dogId` legado foi preservada.

### Validação

- Registro de treino de detecção voltou a funcionar.
- Triagem de detecção voltou a funcionar.
- Fluxos de guarda e proteção e demais treinos foram testados no aparelho após novo APK e rules publicadas.

## Protocolo Ragonha e detecção

A auditoria apontava que linhas de detecção ainda tinham permissões muito abertas e pouca proteção server-side.

### O que foi ajustado

- `detection_lines` passou a exigir `audit_trail` em criação e atualização.
- Updates em linhas de detecção passaram por `_saveLineWithAudit`.
- Operações como adicionar linha, atualizar linha, registrar acerto e registrar falha passaram a gerar trilha inline.
- Rules agora impedem update direto sem auditoria.
- Testes de `DetectionService` foram atualizados.

## Integridade e verificador de selo

O verificador deixou de ser apenas uma peça isolada e passou a cobrir o fluxo produtivo.

### O que foi entregue

- `IntegrityVerificationService` expandido.
- Verificação de hash para versões:
  - v1: legado;
  - v2: fotos;
  - v3: equipe/assinaturas;
  - v4: guarnição/participações/rodada.
- `OccurrenceFinalizationService` e lógica de hash foram mantidos compatíveis com serialização determinística.
- Verificação passou a recalcular e comparar o hash armazenado.
- PDF passou a apontar para endpoint público de verificação.
- Criado `web_verification/index.html`.
- `firebase.json` recebeu rewrite para `/v/**`.
- `functions/src/index.ts` recebeu endpoint `verifyOccurrence`.
- Functions/Hosting foram publicados durante a sessão.

## Frente C - guarnição, participação e assinatura

Foram corrigidos problemas observados nos testes com dois usuários.

### Pontos tratados

- Loop ao aceitar convite/participação e voltar para seleção de cão/viatura.
- Falha de permissão ao assinar ocorrência.
- Condutor pendente precisa aceitar participação antes de editar.
- Condutor recusado não vira editor.
- Relator entra como aceito automaticamente.
- Participações de integrantes entram como pendentes.
- A tela de pendências abre a revisão da ocorrência.
- A revisão permite aceitar ou recusar participação.
- Devolução para correção preserva histórico e não apaga o registro probatório.
- Assinatura mantém fluxo com verificação e tela de revisão.

## UI e navegação

Foram aplicados ajustes de usabilidade e consistência visual.

### Header e menu

- Header consolidado com menu hambúrguer.
- Menu contém:
  - Meu perfil
  - Minha Equipe
  - Meu K9
  - Trocar K9
  - Notificações
  - Encerrar Turno
  - Sair
- Ajustes para evitar duplicidade de ícone de notificação e sumiço do perfil.
- Dashboard, histórico e treinos foram alinhados ao header mais consistente.

### Dashboard

- Tela de turno reformulada para destacar:
  - binômio em serviço;
  - viatura/equipe;
  - ações rápidas;
  - últimos registros.
- Cards de cão, perfil e equipe deixaram de duplicar navegação que já existe no menu.

### Histórico

- Tela de histórico simplificada conforme mockup.
- Filtros superiores foram reduzidos.
- Chips redundantes foram removidos.
- Lista ficou mais legível, com menos ruído visual.
- Corrigida exibição de identificador estranho após endereço. A lista passou a evitar mostrar hash/ID técnico como se fosse protocolo operacional.

## Soft delete e auditoria em serviços

Foram removidos riscos críticos de hard delete em serviços sensíveis.

### Serviços endurecidos

- `DogService`
- `UserService`
- `DogCommandService`
- `DogSpecialtyService`
- `WeightHistoryService`
- `TrainingService`
- `ConditioningService`
- `NutritionService`
- `DetectionService`

### Padrão aplicado

- Exclusões físicas substituídas por soft delete quando aplicável.
- Soft delete exige motivo e trilha.
- Atualizações críticas adicionam `audit_trail`.
- Criações críticas adicionam `audit_trail`.

## Documentos do cão

O upload de documentos do cão foi ajustado para coexistir com as novas rules.

### O que mudou

- `DogProfileService.uploadDocument()` agora grava `audit_trail` no documento Firestore.
- Firestore exige campos controlados e auditoria.
- Storage permite o arquivo em `documentos/{dogId}/{fileName}` com tipo/tamanho controlado.

## PDF e endpoint público

O fluxo de PDF foi ajustado em duas frentes:

- Correções de memória/out of memory foram tratadas no fluxo de geração.
- O PDF passou a expor verificação real, não apenas mostrar hash armazenado.

O endpoint `/v/{id}` foi criado para consulta pública de integridade, via Firebase Hosting + Function.

## Testes e validações técnicas

Durante a sessão foram executados, em diferentes momentos:

- `dart analyze` em arquivos alterados.
- Testes de serviços de treino.
- Testes do serviço de detecção.
- Testes de verificação de integridade.
- Dry-run de Firestore rules.
- Dry-run de Storage rules.
- Deploy real de Firestore rules.
- Deploy real de Storage rules.
- Deploy de Functions/Hosting para verificação pública.
- Build APK release.

## Deploys feitos

### Firebase

- Firestore rules publicadas.
- Storage rules publicadas.
- Functions/Hosting publicados para o endpoint de verificação.

### APK

APK release gerado em:

```text
build/app/outputs/flutter-apk/app-release.apk
```

APK copiado para:

```text
G:\Meu Drive\app k9\claude\app-release.apk
```

Última cópia confirmada durante a sessão:

```text
31/05/2026 20:47:30
```

## Validação no aparelho

Após a última geração do APK e publicação das rules, o usuário testou o app no celular e confirmou que estava tudo ok.

Validação funcional coberta pelo usuário:

- Login e seleção de cão/viatura.
- Navegação sem loop para seleção inicial.
- Header/menu funcionando.
- Registros de treino sem erro de Firestore.
- Fluxo de ocorrência e assinatura sem erro de permissão.
- Operações principais publicadas no Firebase funcionando com o APK release.

## Observações de engenharia

- A branch local está em `main`.
- A `main` local estava `ahead 1` de `origin/main` antes do fechamento final.
- O working tree continha mudanças amplas da sessão e de sessões anteriores da Frente C.
- Arquivos gerados locais como `.firebase/` e `estrutura.txt` não devem ser tratados como parte funcional do app.
- O próximo ciclo ideal é criar testes automatizados de Firestore Rules com Emulator para provar recusas server-side.

## Próximos passos recomendados

1. Criar suíte de testes de Firestore Rules com Emulator.
2. Testar explicitamente recusas proibidas:
   - treino sem turno ativo;
   - assinatura por não integrante;
   - edição por integrante pendente ou recusado;
   - documento sem `audit_trail`;
   - adulteração de `auditLogs`;
   - exclusão de foto/evidência no Storage;
   - finalização ou devolução forçada diretamente pelo client.
3. Revisar mocks e tokens visuais restantes para reduzir cores hardcoded.
4. Fazer nova auditoria curta pós-merge para confirmar que `main` continua buildável e sem permissões amplas críticas.
