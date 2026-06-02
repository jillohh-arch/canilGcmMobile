# Ferramental de teste: Instrutor K9

Este ferramental existe para validar a Etapa 4 em dois aparelhos enquanto a tela Admin ainda nao existe.
Ele nao altera a logica de producao do app, rules ou Functions. Ao ser executado, ele altera dados reais de teste no Firebase:

- custom claims do Firebase Auth;
- espelho em `users/{ra}` para a UI e roteamento de notificacoes.

## Requisitos

Use uma credencial com permissao de Firebase Admin/Auth.

Opcoes:

1. Variavel de ambiente `GOOGLE_APPLICATION_CREDENTIALS` apontando para um JSON de service account.
2. Argumento `--service-account <caminho-do-json>`.
3. Application Default Credentials ja configurada no ambiente.

Nunca committe JSON de service account.

## Comandos

Conceder papel de Instrutor K9:

```powershell
node tools/k9_instructor_role_test_tool.js grant --ra 691640
```

Consultar status:

```powershell
node tools/k9_instructor_role_test_tool.js status --ra 691640
```

Remover papel:

```powershell
node tools/k9_instructor_role_test_tool.js revoke --ra 691640
```

Se o e-mail do Firebase Auth nao seguir o padrao `<ra>@gcm.com.br`, informe explicitamente:

```powershell
node tools/k9_instructor_role_test_tool.js grant --ra 691640 --email pessoa@dominio.com
```

## O que o grant grava

Custom claims relevantes:

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

## Renovacao de token

Depois de rodar `grant` ou `revoke`, faca logout/login no celular afetado.
O custom claim novo so entra no ID token renovado. Para teste em campo, logout/login e o caminho mais previsivel.

## Roteiro Etapa 4 em dois aparelhos

1. Celular A: entre com um condutor comum, sem claim de Instrutor K9.
2. Celular B: entre com o usuario que recebera o papel de Instrutor K9.
3. No computador, rode `grant` para o RA do celular B.
4. Celular B: faca logout/login para renovar o token.
5. Celular A: em Busca & Captura, marque os marcos obrigatorios do modulo atual e toque em `Solicitar evolucao`.
6. Celular B: confirme recebimento da notificacao `training_promotion_requested` ou abra a lista/tela de solicitacoes.
7. Celular B: rejeite uma solicitacao com motivo obrigatorio e confirme que o condutor recebe a orientacao.
8. Celular A: solicite novamente quando estiver pronto.
9. Celular B: aprove.
10. Confira que a conclusao roda pela Function: `completed_modules` e gravado, `current_module` avanca, e no ultimo modulo o cao vira `operational`.

## Limpeza

Se o papel foi concedido apenas para teste, remova depois:

```powershell
node tools/k9_instructor_role_test_tool.js revoke --ra 691640
```
