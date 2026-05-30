# ESPECIFICAÇÃO TÉCNICA — PARTE 10
# Equipe e assinaturas (Frente C)

> A maior das três frentes. Transforma a ocorrência de um registro individual em **co-assinado por quem estava lá** — o que torna o documento muito mais difícil de questionar 6 meses depois. Spec + prompt no mesmo arquivo.

---

## 10.0 — Escopo
Permitir que uma ocorrência tenha **equipe de até 3 condutores** (titular + 2 integrantes), com **co-assinatura formal** dos integrantes antes do selo definitivo. O registro só vira "resultado final" quando todos assinam, e o PDF nasce co-assinado. Esta parte se apoia nas Partes 7 e 9 (Frente A + integridade) e expande a regra de aditamento pós-selo.

## 10.1 — Decisões confirmadas
1. **Assinar = biometria com senha como fallback** (reusa Firebase Auth).
2. **Notificação:** in-app primeiro (badge + lista de pendências), push como evolução se FCM existir.
3. **Trava de edição enquanto aguarda assinaturas** — quem assinou, assinou aquela versão.
4. **Aditamento pós-selo:** apenas handler original + **integrantes que assinaram aquela ocorrência específica**.
5. **Adicionar equipe a qualquer momento** — abertura, durante, ou logo antes do fechamento. Trava ao pedir assinaturas.
6. **Prazo de 48h** (configurável) — passou, titular pode finalizar com `finalized_with_pending` registrando a ausência.

## 10.2 — Modelo de dados

### Ocorrência (campos novos em `occurrences/{id}`)
| Campo | Tipo | Descrição |
|:---|:---|:---|
| `team` | array<map> | `{handlerId, role: 'titular'\|'integrante', addedAt, addedBy}` |
| `team_size_max` | int | 3 (titular + 2 integrantes) |
| `signature_request_at` | timestamp | quando o titular fechou pra pedir assinaturas |
| `signature_deadline` | timestamp | `signature_request_at + 48h` (configurável) |
| `status` | string | adiciona `'awaiting_signatures'`, `'finalized_with_pending'` aos estados existentes |

### Subcoleção `occurrences/{id}/signatures/{handlerId}`
| Campo | Tipo | Descrição |
|:---|:---|:---|
| `handlerId` | string | identifica o integrante |
| `status` | string | `'pending'`, `'signed'`, `'expired'` |
| `signed_at` | timestamp | quando assinou |
| `signature_method` | string | `'biometric'` ou `'password'` |
| `signature_hash` | string | SHA-256 de `(occurrence_hash_preview + handlerId + signed_at + method)` |

### Subcoleção `notifications/{userId}/items/{notificationId}`
| Campo | Tipo | Descrição |
|:---|:---|:---|
| `type` | string | `'signature_requested'`, `'signature_completed'`, `'deadline_warning'`, etc. |
| `occurrence_id` | string | referência |
| `created_at` | timestamp | |
| `read_at` | timestamp? | `null` enquanto não lido |

## 10.3 — Estados e transições
```
draft                                      (em andamento, equipe pode atuar)
   │
   │ titular toca em "Fechar para assinaturas"
   ▼
awaiting_signatures                        (EDIÇÃO TRAVADA pra todos; integrantes notificados)
   │
   ├─ todos assinaram ──────────►   finalized (hash sela; PDF co-assinado)
   │                                    │
   │                                    └─ aditamentos via Parte 9 (handler + integrantes assinados)
   │
   ├─ prazo venceu (48h) ──┐
   │                       │
   │  titular escolhe ─────┼─► aguardar mais (renova prazo)
   │                       ├─► finalized_with_pending (hash sela, registra ausências)
   │                       └─► voltar a draft (cancela pedido de assinatura)
   ▼
   (loops)
```

## 10.4 — Fluxos principais

### 10.4.1 Adicionar integrante
- **Quando:** a qualquer momento enquanto `status == 'draft'`.
- **Onde:** no detalhe da ocorrência, uma seção "Equipe" com botão "+ Adicionar integrante".
- **Quem pode adicionar:** titular ou integrantes já adicionados.
- **Como:** autocomplete sobre `users` (lista de condutores cadastrados). Limite total 3.
- **Auditável:** entrada na trilha (quem adicionou quem, quando).
- **Integrante adicionado** passa a ver a ocorrência na sua lista (compartilhada via consulta `where('team', arrayContains: handlerId)` ou estrutura similar).

### 10.4.2 Visualização da equipe
- **Header da ocorrência:** stack de avatares (titular + integrantes), titular marcado (coroa pequena ou label "titular").
- **Seção "Equipe"** no detalhe: lista com cada membro, papel, data de inclusão, status de assinatura (pendente/assinado/ausente).

### 10.4.3 Fechamento para assinaturas (pelo titular)
- Botão renomeado de "Finalizar" para **"Fechar para assinaturas"** (quando há equipe além do titular).
- Ao tocar: status vira `awaiting_signatures`, `signature_request_at = now`, `signature_deadline = now + 48h`.
- **Edição direta trava** pra todos (titular incluído).
- **Notificação in-app** disparada pra cada integrante: "X te pediu assinatura na ocorrência Y".

### 10.4.4 Assinatura por integrante
- Integrante vê na **lista "Pendências"** (acessível pelo menu/badge).
- Abre a ocorrência → revisa o conteúdo (mesma tela de detalhe; tudo somente leitura).
- Botão **"Assinar"** abre modal:
  - Tela de revisão final com checklist do que está sendo assinado ("Você está assinando uma ocorrência com X ações, em Y locais, com Z fotos. Concorda com o registro?")
  - Botão **"Confirmar com biometria"** → dispara biometria do dispositivo. Fallback automático pra senha se biometria indisponível ou recusada.
  - Confirmação positiva: cria `signatures/{handlerId}` com `status: 'signed'`, `signed_at`, `signature_method`, `signature_hash`.
- **Notificação in-app** pro titular: "X assinou".
- Integrante pode **recusar** explicitamente (botão "Não posso assinar") — cria signature com `status: 'expired'` antecipadamente, com motivo opcional.

### 10.4.5 Todas as assinaturas coletadas → finalized
- Trigger automático quando o número de signatures `'signed'` iguala o tamanho da equipe (minus o titular, que não assina a si mesmo — ou assina, decisão de implementação).
- Status muda pra `finalized`.
- **Hash da ocorrência é gerado** (versão final), incluindo as assinaturas na serialização (ver 10.7).
- PDF nasce co-assinado.
- Notificação in-app pra todos os membros: "Ocorrência Y selada".

### 10.4.6 Prazo vencido — finalização com pendência
- Job periódico (ou verificação ao abrir o app) detecta `signature_deadline < now` em ocorrências `awaiting_signatures`.
- Notificação in-app pro titular: "O prazo de assinatura da ocorrência Y venceu. O que fazer?"
- Opções pro titular:
  - **Aguardar mais 48h** — renova `signature_deadline`.
  - **Finalizar com pendência** — status vira `finalized_with_pending`. Hash sela com o que tem; integrantes pendentes marcados como `'expired'` com nota "convidado em [data], não assinou no prazo de [data]".
  - **Voltar para draft** — cancela o pedido, volta a permitir edição. Assinaturas já feitas são limpas (ou marcadas como obsoletas — decisão de implementação; recomendo limpar e re-pedir, pra evitar confusão).
- Mesmo após prazo vencido, integrante pendente ainda pode assinar enquanto o titular não decide — o sistema favorece o registro completo.

## 10.5 — Aditamento pós-selo (extensão da Parte 9)
A regra atual da Parte 9 é "apenas handler original cria aditamento". Com a Frente C, expande:
- **`amendment.created_by` deve ser:** `occurrence.team[].handlerId` **E** `signatures/{handlerId}.status == 'signed'` na ocorrência.
- Ou seja: o handler original (sempre presente como titular) **e** os integrantes que efetivamente assinaram. Integrantes pendentes/expirados em `finalized_with_pending` **não** podem aditar (não assinaram).
- Cada aditamento já traz `created_by`; o filtro é só na validação client + server.

## 10.6 — Notificações
- **In-app (v1):** coleção `notifications/{userId}/items/{...}`, badge no app com contador de não-lidos, tela "Pendências" lista as ações esperadas.
- Tipos: `signature_requested`, `signature_completed`, `deadline_warning`, `occurrence_finalized`, `amendment_created`.
- **Push (v2, se FCM existir):** enviar junto da gravação na coleção. Não bloquear v1 por causa do push.

## 10.7 — Hashing (assinaturas no payload)
**Crítico:** as assinaturas entram na serialização do hash da ocorrência. Sem isso, alguém poderia trocar quem assinou sem quebrar o selo.

- Quando o status transita para `finalized` (ou `finalized_with_pending`), a serialização determinística (já existente, ordena chaves recursivamente) passa a incluir:
  - `team` (array ordenado por `handlerId`)
  - `signatures` (array ordenado por `handlerId`, cada item com `handlerId`, `status`, `signed_at` em UTC, `signature_method`)
- **Não incluir `signature_hash`** no payload do hash da ocorrência (seria circular).
- **`hash_version` sobe para 3** quando há equipe com assinaturas. Ocorrências v1 e v2 (sem equipe) continuam intactas, sem migração.
- **Backward compat:** ocorrências sem `team` (ou `team` com apenas o titular) continuam v2 — sem mudança.

## 10.8 — Segurança (Firestore rules)
A auditoria forense indicou que `firestore.rules` precisa ser versionado. Esta parte exige rules específicas:
- **Adicionar integrante a `team`:** permitido se `request.auth.uid in resource.data.team[].handlerId` (qualquer membro pode adicionar até o limite) e `status == 'draft'`.
- **Escrever em `signatures/{handlerId}`:** permitido se `request.auth.uid == handlerId` e o handlerId está em `team`.
- **Mudar status para `awaiting_signatures`:** apenas o titular (`team[].role == 'titular'`).
- **Criar amendment:** `request.auth.uid in occurrence.team[].handlerId` E existe `signatures/{request.auth.uid}` com `status == 'signed'`.
- **Editar diretamente ocorrência com status `awaiting_signatures` ou posterior:** negado.

## 10.9 — PDF (seção equipe e assinaturas)
- **Cabeçalho de equipe:** logo após o cabeçalho institucional, antes do conteúdo, uma faixa "Equipe responsável": nome de cada membro + função + RA (ou identificador).
- **Seção "Assinaturas":** após a validação do original (selo SHA-256), antes da seção de aditamentos (se houver). Cada assinatura: nome, RA, data/hora UTC, método (biometria/senha), hash da assinatura.
- **Ocorrências `finalized_with_pending`:** seção destaca em âmbar quem ficou pendente, com a frase padronizada: "Convidado em [data]; não assinou no prazo de [data]."
- Frase de abertura do bloco de assinaturas: "Este registro foi co-assinado pelos integrantes abaixo, atestando presença no fato narrado."

## 10.10 — Critério de pronto
1. Adicionar integrantes (até 2) em qualquer momento até fechar pra assinaturas; auditável.
2. Header da ocorrência mostra a equipe (avatares + papéis).
3. Botão "Fechar para assinaturas" trava edição e dispara notificações in-app.
4. Integrante recebe notificação, abre, revisa, assina via biometria (senha fallback); signature gravada.
5. Todos assinarem → status `finalized` automático; hash sela incluindo equipe e assinaturas.
6. Prazo vencido → titular pode renovar, finalizar com pendência, ou voltar a draft.
7. `finalized_with_pending` documenta a ausência transparentemente, no detalhe e no PDF.
8. Aditamento pós-selo: apenas membros que **assinaram** podem criar.
9. Firestore rules impõem todas as restrições no servidor (não só client).
10. PDF nasce co-assinado, com seção dedicada e hash que inclui as assinaturas.
11. `hash_version: 3` para ocorrências com equipe assinada. v1/v2 intactas.

---

## Prompt (colar no Claude Code)

Vamos implementar a **Frente C** — equipe e co-assinatura. Leia `temp/docs/ESPEC_TECNICA_PARTE_10.md` (esta) junto com as PARTE_7 (ocorrências) e PARTE_9 (integridade). Skills: `canil-k9-context`, `firestore-coexistence`, `audit-trail`.

**Diagnóstico primeiro:**
1. Como está modelado o `created_by` da ocorrência hoje? Onde está a `users` collection?
2. O `firestore.rules` está versionado no repo? (auditoria forense indicou que não.) Se não, vai precisar criar/versionar antes ou junto.
3. Existe alguma estrutura de notificação no projeto, ainda que parcial?
4. O Firebase Auth já tem biometria configurada (`local_auth` ou similar no `pubspec`)?
5. Como o `hash_version: 2` decide entre v1 e v2 hoje — o caminho está pronto pra acomodar v3?

**Não comece a implementar antes de me devolver o diagnóstico.** A Parte 10 mexe em segurança e integridade — qualquer atalho aqui compromete a co-assinatura como prova.

## Implementação em etapas (uma por vez, mostrando cada)

**Etapa 1 — Modelo + estado**
- Campos novos da ocorrência (`team`, `signature_request_at`, `signature_deadline`, novos status).
- Subcoleção `signatures`.
- Subcoleção `notifications`.
- Transições de estado documentadas no código.
- **Validar:** criar ocorrência manualmente, adicionar membro, verificar campos no Firestore.

**Etapa 2 — Adicionar integrantes + visualização**
- Seção "Equipe" no detalhe com autocomplete de condutores.
- Header com avatares.
- Limite total 3.
- Auditável.
- **Validar no celular:** adicionar integrante, ver no header, ver na trilha de auditoria.

**Etapa 3 — Fechamento + assinatura + notificação**
- Botão "Fechar para assinaturas" com transição de estado.
- Trava de edição em `awaiting_signatures`.
- Tela de modal de assinatura com biometria (Firebase Auth + `local_auth`) e fallback senha.
- Tela "Pendências" do usuário logado.
- Notificações in-app (badge + lista).
- **Validar no celular:** titular fecha pra assinatura, integrante recebe notificação, assina via biometria, titular vê a assinatura.

**Etapa 4 — Selo + prazo + finalização com pendência**
- Transição automática para `finalized` quando todas as assinaturas.
- Hash com equipe e assinaturas no payload (`hash_version: 3`).
- Detecção de prazo vencido + opções pro titular.
- Status `finalized_with_pending` com registro transparente.
- **Validar no celular:** assinar tudo → selo automático com hash v3; em outra ocorrência, deixar prazo vencer e usar a opção de finalizar com pendência.

**Etapa 5 — Aditamento estendido + PDF + Firestore rules**
- Expansão da regra de aditamento (Parte 9): handler original + integrantes assinados.
- Seção "Equipe e assinaturas" no PDF; bloco de pendência em âmbar.
- `firestore.rules` versionado com todas as restrições da seção 10.8.
- **Validar no celular:** integrante assinado cria aditamento (permitido); outro usuário tenta (recusado pelo servidor); PDF mostra equipe e assinaturas; PDF de `finalized_with_pending` mostra o bloco de pendência.

## Regras do projeto
Branch; `main` buildável; merge `--no-ff` só após cada etapa validada. Nada hardcoded. `firestore.rules` versionado.

**Atenção especial:** as assinaturas entram no hash do selo final. Quando o status transita pra `finalized`, a serialização determinística passa a incluir `team` e `signatures` (sem `signature_hash` — seria circular). Esse é o ponto que torna a co-assinatura uma propriedade probatória real.
