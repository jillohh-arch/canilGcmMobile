# Testes automatizados de Firestore e Storage Rules

Esta pasta contém uma bateria mínima de testes server-side para provar que regras críticas do app Canil K9 GCM Limeira não dependem só do client.

## O que cobre

- Treino sem turno ativo é recusado.
- Treino com turno ativo do binômio é aceito.
- Turno ativo só pode ser gravado pelo próprio RA autenticado.
- Treino para K9 diferente do turno ativo é recusado.
- Integrante pendente não edita ocorrência.
- Integrante aceito edita ocorrência aberta.
- Ocorrência finalizada não aceita edição direta.
- Ocorrência finalizada não aceita novo evento.
- Usuário fora da equipe não assina por outro condutor.
- Condutor integrante assina a própria pendência.
- Aditamento é aceito para relator.
- Aditamento é aceito para integrante assinado.
- Aditamento é recusado para integrante não assinado.
- Documento do cão sem `audit_trail` é recusado.
- Escrita direta em `generated_pdfs` é recusada.
- `auditLogs` com ator adulterado é recusado.
- Notificação só pode ser marcada como lida pelo próprio destinatário.
- Upload válido de evidência no Storage é aceito.
- Upload de evidência com tipo inválido é recusado.
- Exclusão de evidência no Storage é recusada.
- `health_schedule` (Health v1 / 4D): ver `health_schedule_rules_tests.mjs` — leitura com `signedIn + canAccessDogRecord`; writes cliente negados; query operacional `lifecycle_status + scheduled_for + documentId`; escopo `own_records` e admin.

## Como rodar

Na raiz do projeto:

```powershell
& 'C:\npm-global\firebase.cmd' emulators:exec --project canil-gcm --only firestore,storage "node tools/rules_tests/rules_tests.mjs"
```

Alternativa, se `firebase` estiver no `PATH`:

```powershell
cd tools\rules_tests
npm test
```

### Health schedule (4D) — suite dedicada

```powershell
cd tools\rules_tests
npm run test:health-schedule
```

Ou na raiz:

```powershell
& 'C:\npm-global\firebase.cmd' emulators:exec --project canil-gcm --config firebase.json --only firestore "node tools/rules_tests/health_schedule_rules_tests.mjs"
```

## Dependências

As dependências ficam isoladas nesta pasta:

```powershell
cd tools\rules_tests
npm install
```

Pacotes usados:

- `@firebase/rules-unit-testing`
- `firebase`

## Observação

Os testes usam `withSecurityRulesDisabled()` apenas para semear estado inicial necessário, como ocorrência existente e participação. As ações testadas rodam sempre como usuários autenticados reais do cenário.
