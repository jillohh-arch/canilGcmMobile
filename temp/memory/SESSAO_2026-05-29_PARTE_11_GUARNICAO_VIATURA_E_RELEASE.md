# Sessao 2026-05-29 - Frente C, Parte 11, guarnicao por viatura e release

Data/hora de fechamento deste registro: 29/05/2026 18:19 BRT.

Projeto: Canil K9 GCM Limeira
Workspace: `C:\Projetos\canil_gcm_mobile_chatgpt\canil-gcm`
Branch atual no fechamento: `feature/frente-c-guarnicao-viatura`

## Contexto geral da sessao

Esta sessao continuou a Frente C de equipe e co-assinatura. A primeira parte do dia tratou a Frente C conforme a Parte 10: equipe manual, assinaturas, notificacoes, hash v3, PDF e Firestore rules. Depois, com a chegada da `ESPEC_TECNICA_PARTE_11.md` e dos mockups novos, o modelo foi revisado: a equipe deixa de ser montada manualmente por autocomplete e passa a nascer da guarnicao ativa da viatura.

O usuario tambem validou no celular e reportou problemas reais:

- Erro de `permission-denied` ao gerar PDF e ao adicionar nomes da equipe.
- Selecao de GCMs no autocomplete sem botao claro para confirmar.
- PDF de uma ocorrencia grande gerando `out of memory`.
- Necessidade de cadastrar a viatura no Firestore para testar o novo fluxo.

## Entregas ja consolidadas antes da Parte 11

### Frente C - Parte 10

Foram implementados e estabilizados os blocos principais da co-assinatura:

- Modelo de equipe na ocorrencia.
- Status `awaiting_signatures` e `finalized_with_pending`.
- Subcolecao `occurrences/{id}/signatures`.
- Subcolecao `notifications/{userId}/items`.
- Tela de pendencias.
- Badge/lista de notificacoes in-app.
- Fechamento da ocorrencia para assinaturas.
- Trava de edicao quando a ocorrencia esta aguardando assinaturas.
- Assinatura por biometria com fallback de senha.
- Finalizacao automatica quando todas as assinaturas sao coletadas.
- Finalizacao com pendencia apos prazo vencido.
- Hash v3 incluindo equipe e assinaturas.
- PDF com secao de equipe e assinaturas.
- Aditamento por relator original e por integrante que assinou.
- Firestore rules versionadas para assinaturas, notificacoes, aditamentos e travas de status.

### Correcoes apos teste no aparelho

Depois da validacao no celular, foram corrigidos pontos praticos:

- Firestore rules e Storage rules foram ajustadas/publicadas para liberar os fluxos esperados sem abrir escrita indevida.
- O seletor de equipe ganhou acao visivel de adicionar, com botao `+` por integrante e toque na linha funcionando.
- O gerador de PDF deixou de carregar fotos grandes em paralelo e passou a otimizar imagens:
  - download sequencial;
  - timeout por foto;
  - redimensionamento maximo para 960 px;
  - JPEG quality 72;
  - dependencia `image` adicionada ao `pubspec.yaml`.

Commits ja existentes no historico antes desta etapa:

- `69f77ec merge: Frente C equipe e coassinatura`
- `bac087e feat: entrega Frente C equipe e coassinatura`
- `3974415 fix: libera equipe em ocorrencias legadas`
- `94c8ce0 fix: ajusta selecao de equipe e fotos no PDF`

## Entrada nova da Parte 11

O usuario adicionou dois mockups em `temp/mockups`:

- `turno_selecionar_viatura.html`
- `ocorrencia_equipe_guarnicao.html`

Eles definiram o novo contrato visual e funcional:

- A viatura vem do Firestore, colecao `vehicles`.
- Abrir turno passa a permitir selecionar viatura.
- A viatura e opcional: pode iniciar turno so com o K9 para treino.
- A viatura pode ser assumida depois durante o turno.
- Capacidade vem do cadastro da viatura.
- Guarnicao ativa = condutores com turno ativo na mesma `vehicle_id`.
- Ocorrencia captura snapshot da guarnicao ao ser criada.
- Equipe da ocorrencia e indivisivel.
- Cao entra como membro K9, mas nao assina.
- Condutores assinam pela guarnicao/binomio.
- Acoes de trabalho do cao podem registrar quem conduziu o K9 naquele momento.

Contrato da colecao `vehicles/{vehicleId}` adotado:

```js
{
  name: "Canil",
  prefix: "1075",
  model: "Chevrolet Trailblazer",
  crew_size: 2,
  unit: "Limeira/SP",
  active: true
}
```

O usuario criou manualmente a colecao/documento no Firebase Console, porque a colecao so passa a existir quando o primeiro documento e gravado.

## Implementacao da Parte 11 nesta sessao

### 1. Modelo e servico de viaturas

Criados:

- `lib/features/shifts/domain/vehicle.dart`
- `lib/features/shifts/data/vehicle_service.dart`

O modelo `Vehicle` suporta:

- `id`
- `name`
- `prefix`
- `modelName`
- `crewSize`
- `unit`
- `active`
- `label` calculado como `name + prefix`, por exemplo `Canil 1075`.

O `VehicleService` faz:

- leitura de viaturas ativas em `vehicles`;
- leitura de ocupacao por `active_shifts`;
- busca direta por ID.

### 2. Turno com viatura opcional

Arquivos alterados:

- `lib/features/shifts/domain/active_shift_session.dart`
- `lib/features/shifts/data/shift_service.dart`
- `lib/features/shifts/presentation/viewmodels/shift_viewmodel.dart`
- `lib/features/shifts/presentation/screens/shift_assumption_screen.dart`
- `lib/features/shifts/presentation/screens/shift_assumption_dog_card_widgets.dart`
- `lib/features/shifts/presentation/screens/active_shift_dashboard_screen.dart`
- `lib/features/shifts/presentation/screens/active_shift_cockpit.dart`
- `lib/features/shifts/presentation/screens/active_shift_header.dart`

Campos novos no turno ativo:

- `vehicle_id`
- `vehicle_label`
- `vehicle_prefix`
- `vehicle_model`
- `vehicle_unit`
- `vehicle_joined_at`

Comportamentos implementados:

- Abrir turno com K9 e viatura.
- Abrir turno so com K9.
- Assumir viatura depois, no dashboard.
- Header do turno mostra a viatura ativa quando houver.
- Capacidade da viatura e exibida como `N + K9`.
- Ocupacao da viatura e calculada por turnos ativos com o mesmo `vehicle_id`.
- `ShiftService` valida capacidade e impede misturar outro K9 de servico na mesma viatura.

### 3. Ocorrencia captura guarnicao da viatura

Arquivos alterados:

- `lib/features/occurrences/domain/occurrence.dart`
- `lib/features/occurrences/presentation/view_models/occurrence_view_model.dart`
- `lib/features/occurrences/presentation/screens/start_occurrence_screen.dart`
- `lib/features/occurrences/data/occurrence_repository.dart`

Campos novos na ocorrencia:

- `vehicle_id`
- `vehicle_label`
- `vehicle_prefix`
- `vehicle_model`
- `vehicle_unit`

Ao criar uma ocorrencia:

- o app le o turno ativo;
- se houver `vehicle_id`, busca todos os turnos ativos da mesma viatura;
- monta o snapshot da guarnicao;
- grava a equipe no campo `team`;
- grava `team_handler_ids`, `team_emails` e metadados ja usados pelas rules;
- mantem fallback para ocorrencias sem viatura ou legadas.

### 4. Team com K9 como membro operacional

Arquivo principal:

- `lib/core/domain/occurrence_team_member.dart`

Campos adicionados ao membro da equipe:

- `dog_id`
- `dog_name`
- `dog_matricula`
- `dog_breed`

O parse aceita formatos legados e tambem o formato proposto no mockup:

```js
team: {
  conductors: [...],
  service_dog: {...}
}
```

Internamente, para coexistencia com a Frente C ja entregue, a ocorrencia continua usando lista de `OccurrenceTeamMember`, agora enriquecida com os dados do K9. Isso preserva assinaturas, notificacoes, aditamentos e hash v3.

### 5. Matricula do cao

Arquivo alterado:

- `lib/features/dogs/domain/dog.dart`

O campo existente `registrationNumber` passou a coexistir com `matricula`:

- leitura aceita `matricula` ou `registrationNumber`;
- escrita grava os dois quando houver valor.

Isso permite usar a nomenclatura da Parte 11 sem quebrar dados antigos.

### 6. Interface de turno e guarnicao

Tela de abrir turno:

- mostra o binomio selecionado;
- lista viaturas ativas do Firestore;
- mostra modelo, unidade, capacidade e ocupacao;
- permite iniciar apenas com o K9;
- usa cards no estilo dos mockups novos.

Dashboard do turno:

- se o turno estiver sem viatura, mostra card para assumir viatura;
- se a viatura estiver assumida, o header mostra a viatura junto do turno.

Tela de equipe da ocorrencia:

- troca o texto de `Equipe` para `Guarnicao` quando houver K9;
- mostra condutores e K9 associado;
- remove o caminho de adicao/remocao manual quando a ocorrencia veio de viatura.

### 7. Assinaturas mantidas

O fluxo de assinatura da Parte 10 foi preservado:

- somente condutores assinam;
- titular fecha para assinaturas;
- integrantes assinam;
- K9 aparece como membro/presenca atestada, mas nao assina;
- notificacoes seguem por `handlerId`/RA.

Arquivos tocados no entorno:

- `lib/features/occurrences/presentation/widgets/signature_confirmation_dialog.dart`
- `lib/features/occurrences/presentation/view_models/occurrence_team_view_model.dart`
- `lib/features/occurrences/presentation/widgets/team_header_widget.dart`
- `lib/features/occurrences/presentation/widgets/team_management_widget.dart`

### 8. Hash e integridade

Arquivos alterados:

- `lib/core/services/occurrence_finalization_service.dart`
- `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart`
- `lib/core/domain/occurrence_team_member.dart`
- `lib/features/occurrences/domain/occurrence_event.dart`

O hash v3 agora acomoda:

- `team` com dados do K9;
- `vehicle_id`;
- `vehicle_label`;
- `vehicle_model`;
- `vehicle_prefix`;
- `vehicle_unit`;
- `signatures`;
- `dog_handler_id` em eventos de emprego do cao.

Para ocorrencias diretas com guarnicao mas sem co-assinantes, a regra passou a aceitar `hash_version` 3. Isso evita que uma ocorrencia de viatura com apenas um condutor e K9 seja reduzida a v2 e perca a propriedade probatoria da equipe/viatura.

### 9. Credito do trabalho do K9 por acao

Arquivos alterados:

- `lib/features/occurrences/domain/occurrence_event.dart`
- `lib/features/occurrences/presentation/screens/active_occurrence_screen.dart`
- `lib/features/occurrences/presentation/screens/edit_event_screen.dart`
- `lib/features/occurrences/presentation/widgets/active_occurrence_event_card.dart`
- `lib/core/services/pdf_generator/occurrence_pdf_generator.dart`

Foi adicionado o campo:

- `dog_handler_id`

Quando o evento e de categoria `dogWork`, o app registra o RA do condutor autenticado. A timeline e o PDF passam a exibir esse credito operacional.

### 10. PDF

Arquivos alterados:

- `lib/core/services/pdf_generator/occurrence_pdf_generator.dart`
- `lib/core/pdf/team_and_signatures_section.dart`

O PDF agora:

- exibe a viatura quando houver;
- exibe a guarnicao;
- mostra K9 com matricula;
- informa que o K9 tem presenca atestada pela guarnicao;
- mostra assinatura apenas dos condutores;
- mostra quem conduziu o K9 em acoes de trabalho do cao.

### 11. Firestore rules

Arquivo alterado e publicado:

- `firestore.rules`

Mudancas:

- `vehicles/{vehicleId}` liberado para leitura autenticada.
- Escrita em `vehicles` permanece bloqueada pelo app.
- `active_shifts` e `shift_logs` aceitam os campos de viatura.
- `canFinalizeDirectly` aceita `hash_version` 2 ou 3.
- Edicao manual de `team` fica bloqueada quando a ocorrencia veio de viatura (`vehicle_id` presente).
- Campos de viatura da ocorrencia ficam protegidos contra alteracao em updates normais.

Comando executado:

```powershell
& 'C:\npm-global\firebase.cmd' deploy --only firestore:rules --project canil-gcm
```

Resultado: deploy concluido com sucesso e rules publicadas.

## Validacoes tecnicas executadas

### Dart format

Executado `dart format` nos arquivos alterados da Parte 11.

### Dart analyze

Executado `dart analyze` nos arquivos tocados. Resultado:

```text
No issues found!
```

### Firestore rules dry-run

Executado antes do deploy real:

```powershell
& 'C:\npm-global\firebase.cmd' deploy --only firestore:rules --project canil-gcm --dry-run
```

Resultado: rules compilaram com sucesso.

### Build debug

Executado:

```powershell
C:\flutter\bin\flutter.bat build apk --debug
```

Resultado: build debug gerado com sucesso.

### Build release

Executado:

```powershell
C:\flutter\bin\flutter.bat build apk --release
```

Resultado:

```text
Built build\app\outputs\flutter-apk\app-release.apk (146.3MB)
```

Arquivo local:

```text
C:\Projetos\canil_gcm_mobile_chatgpt\canil-gcm\build\app\outputs\flutter-apk\app-release.apk
```

Arquivo copiado para o Google Drive:

```text
G:\Meu Drive\app k9\claude\app-release.apk
```

Tamanho copiado:

```text
153447043 bytes
```

Data/hora do arquivo no Drive:

```text
29/05/2026 18:19:31
```

## Estado Git no fechamento

Branch:

```text
feature/frente-c-guarnicao-viatura
```

Importante: as alteracoes da Parte 11 ainda nao foram commitadas nesta branch no momento deste registro. Arquivos de `temp/docs`, `temp/mockups` e `.claude/settings.local.json` continuam como nao rastreados, e foram preservados sem commit automatico.

## Como testar no celular

No Firestore, confirmar que existe:

```text
vehicles/1075
```

Com os campos:

```text
name       string   Canil
prefix     string   1075
model      string   Chevrolet Trailblazer
crew_size  number   2
unit       string   Limeira/SP
active     boolean  true
```

Roteiro minimo:

1. Instalar o APK release copiado para o Drive.
2. Fazer login.
3. Selecionar o K9.
4. Conferir se a tela lista `Canil 1075`.
5. Iniciar turno com a viatura.
6. Conferir se o header do turno mostra a viatura.
7. Criar ocorrencia.
8. Conferir se a equipe/guarnicao aparece com condutor + K9.
9. Fechar para assinaturas se houver mais de um condutor na mesma viatura.
10. Gerar PDF e conferir secao de viatura, guarnicao e K9.

## Observacoes e riscos ainda abertos

- Teste real de dois condutores na mesma viatura ainda depende de dois logins/turnos ativos no aparelho ou em aparelhos separados.
- A rule de capacidade da viatura esta validada no client; a protecao final contra lotacao por escrita direta ainda pode ser endurecida no servidor em uma etapa dedicada, porque Firestore rules nao contam facilmente ocupacao agregada de outros documentos.
- `vehicles` esta somente leitura para o app. Cadastro/alteracao de viatura hoje deve ser feito pelo Console ou por Admin SDK/script de seed.
- A Parte 11 foi implementada preservando coexistencia com dados legados da Parte 10.
