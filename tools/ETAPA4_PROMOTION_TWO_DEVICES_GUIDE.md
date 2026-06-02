# Etapa 4 - validacao em dois aparelhos

Este guia prepara a validacao da promocao co-validada de Busca & Captura.
O ferramental daqui nao altera a logica de producao. Ele serve para:

- atribuir/remover o papel `Instrutor K9` para teste;
- conferir se a Cloud Function processou a aprovacao;
- validar o fluxo em dois celulares.

## 1. Deploy necessario

A aprovacao nao e concluida pelas rules. As rules apenas permitem que um
Instrutor K9 decida a `promotion_requests/{id}`.

A conclusao real roda na Function:

- `onTrainingPromotionRequestUpdated`;
- ela grava `completed_modules`;
- avanca `current_module`;
- no ultimo modulo, seta `status=operational`;
- sincroniza `dogs/{dogId}/specialties`.

Comando usado para deploy:

```powershell
& 'C:\npm-global\firebase.cmd' deploy --only functions,firestore:rules --project canil-gcm --non-interactive
```

## 2. Service account para o utilitario local

O utilitario usa Admin SDK, entao precisa de credencial com permissao de
Firebase Auth e Firestore.

Crie/baixe a chave no Console Firebase:

1. Project settings.
2. Service accounts.
3. Generate new private key.
4. Salve fora do repositorio, por exemplo:

```text
C:\tmp\canil-gcm-service-account.json
```

Nao committe esse JSON.

Voce pode passar a credencial por variavel:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS='C:\tmp\canil-gcm-service-account.json'
node tools/set_k9_instructor.js --ra 691640
```

Ou direto no comando:

```powershell
node tools/set_k9_instructor.js --ra 691640 --service-account 'C:\tmp\canil-gcm-service-account.json'
```

Tambem aceita e-mail ou UID, desde que exista um `users/{ra}` correspondente:

```powershell
node tools/set_k9_instructor.js --email 691640@gcm.com.br
node tools/set_k9_instructor.js --uid abcFirebaseUid123
```

Para remover o papel depois:

```powershell
node tools/set_k9_instructor.js --ra 691640 --remove
```

## 3. O que o utilitario grava

Custom claims no Firebase Auth:

```json
{
  "role": "instrutor_k9",
  "roles": ["instrutor_k9"],
  "instrutor_k9": true,
  "training_role": "instrutor_k9",
  "training_instructor": true
}
```

Espelho em `users/{ra}`:

```json
{
  "auth_uid": "<uid>",
  "email": "<email>",
  "is_k9_instructor": true,
  "training_role": "instrutor_k9",
  "claim_role": "instrutor_k9",
  "claim_refresh_required": true
}
```

O script e idempotente: se o Auth e o espelho ja estiverem corretos, ele apenas
imprime o estado e nao regrava.

## 4. Como o claim passa a valer no app

Custom claim entra no app pelo ID token do Firebase Auth.

As telas de promocao ja chamam refresh forcado do token ao checar o papel:

- `currentUserIsInstructorK9(forceRefresh: true)`;
- `currentUserHasInstructorClaim(forceRefresh: true)`.

Mesmo assim, para teste limpo em dois aparelhos, faca logout/login no aparelho
do Instrutor K9 depois de rodar o utilitario. Isso elimina token antigo em cache.

## 5. Roteiro com dois aparelhos

### Preparacao

1. Celular A: entrar com o condutor comum, sem claim Instrutor K9.
2. Celular B: entrar com o usuario que sera Instrutor K9.
3. No computador, conceder o papel ao usuario do Celular B:

```powershell
node tools/set_k9_instructor.js --ra <RA_DO_INSTRUTOR>
```

4. Celular B: fazer logout/login.
5. No Console Firestore, conferir `users/<RA_DO_INSTRUTOR>`:

```text
is_k9_instructor = true
training_role = instrutor_k9
claim_role = instrutor_k9
auth_uid = <uid do usuario>
```

### Cenario A - condutor solicita e instrutor aprova

1. Celular A: abrir Busca & Captura do cao em formacao.
2. Marcar todos os marcos obrigatorios do modulo atual.
3. Tocar em `Solicitar evolucao`.
4. Console Firestore: abrir a collection `promotion_requests`.
5. Localizar a solicitacao nova e conferir:

```text
status = pending
requester_ra = <RA_DO_CONDUTOR>
dog_id = <dogId>
modality = busca_captura
module_id = <modulo atual>
marks_snapshot = lista dos marcos
```

6. Celular B: abrir a notificacao ou tela de validacao da solicitacao.
7. Aprovar.
8. Console Firestore: conferir em `promotion_requests/{id}`:

```text
status = approved
decision = approved
decision_by = <RA_DO_INSTRUTOR>
processing_status = completed
processed_at = timestamp
next_module = <proximo modulo ou null>
operational = true/false
```

9. Console Firestore: conferir em `dogs/{dogId}/training/busca_captura`:

```text
completed_modules = array com snapshot do modulo aprovado
completed_module_ids = inclui o modulo aprovado
current_module = proximo modulo, ou null no ultimo
status = in_formation, ou operational no ultimo
operational_since = timestamp no ultimo modulo
```

10. Console Firestore: conferir `dogs/{dogId}/specialties`:

```text
type = busca_captura
status = igual ao progresso canonico
current_module = igual ao progresso canonico
progress_percentage = atualizado
```

Opcional: acompanhar pelo smoke check read-only:

```powershell
node tools/training_promotion_smoke_check.js --request <PROMOTION_REQUEST_ID> --watch --timeout 120
```

### Cenario B - instrutor rejeita com motivo

1. Celular A: criar nova solicitacao de evolucao.
2. Celular B: abrir a solicitacao.
3. Tocar em `Apontar falta`.
4. Informar motivo, por exemplo: `Refazer indicacao passiva com distracao`.
5. Console Firestore: conferir `promotion_requests/{id}`:

```text
status = rejected
decision = rejected
decision_reason = Refazer indicacao passiva com distracao
decision_by = <RA_DO_INSTRUTOR>
processing_status = completed
```

6. Conferir que `dogs/{dogId}/training/busca_captura` nao avancou modulo.
7. Conferir notificacao ao condutor:

```text
notifications/{RA_DO_CONDUTOR}/items
type = training_promotion_rejected
```

### Cenario C - Instrutor K9 conduz e conclui direto

1. Celular B: usar o mesmo usuario Instrutor K9 como condutor do cao.
2. Abrir Busca & Captura.
3. Marcar os marcos obrigatorios do modulo atual.
4. Tocar em `Solicitar evolucao`.
5. O app cria `promotion_requests` com `direct_instructor=true` e decide em seguida.
6. Console Firestore: conferir:

```text
promotion_requests/{id}.status = approved
promotion_requests/{id}.direct_instructor = true
promotion_requests/{id}.processing_status = completed
dogs/{dogId}/training/busca_captura.completed_modules atualizado
```

## 6. Sinais de problema

Se a solicitacao fica `approved` mas sem `processing_status`, a Function ainda
nao processou ou nao foi disparada.

Se vira `processing_status=error`, leia `processing_error` no proprio doc
`promotion_requests/{id}`.

Se o Instrutor K9 nao consegue aprovar:

1. Rodar `node tools/set_k9_instructor.js --ra <RA>`.
2. Conferir `changed_auth_claims` e `custom_claims_after`.
3. Fazer logout/login no celular do instrutor.
4. Tentar novamente.
