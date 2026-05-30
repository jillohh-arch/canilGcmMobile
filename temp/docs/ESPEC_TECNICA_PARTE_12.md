# ESPECIFICAÇÃO TÉCNICA - PARTE 12
# Ciência da guarnição, participação operacional e assinatura revisada
### REVISA o fluxo de equipe das Partes 10 e 11

> Leia depois da Parte 11. Esta parte mantém a guarnição por viatura e o cão como membro pleno, mas corrige o fluxo: a equipe não é formada dentro da ocorrência. A ocorrência apenas captura a guarnição já existente, notifica os envolvidos, registra ciência/recusa e permite colaboração enquanto estiver aberta.

---

## 12.0 - O que muda e o que se mantém

**Substitui ou corrige:**
- Tela "Gerenciar Equipe" como lugar de montar equipe dentro da ocorrência.
- Autocomplete ou adição manual de integrante no fluxo da ocorrência.
- Assinatura direta sem uma revisão completa do conteúdo final.
- Trava rígida de troca de cão durante o turno.

**Mantém:**
- Guarnição por viatura da Parte 11.
- Cão como membro pleno, com matrícula.
- Snapshot da guarnição gravado na ocorrência.
- Notificações in-app e, como evolução, push/ações nativas.
- Assinatura final com biometria e senha como fallback.
- Firestore rules como autoridade real, não só UI.
- PDF com equipe, ciência, recusas, pendências e assinaturas.

**Decisão principal:**
Equipe operacional pertence ao **turno/viatura**. A ocorrência só registra quem estava naquela guarnição naquele momento e coleta a ciência/participação de cada condutor.

---

## 12.1 - Conceitos

### Guarnição
Formada fora da ocorrência, no fluxo de turno:
```
turno ativo + K9 selecionado + viatura assumida = guarnição ativa
```

É gerenciada no módulo de turno/viatura, não no detalhe da ocorrência.

### Ciência de ocorrência
Quando uma ocorrência é aberta por uma guarnição, cada integrante recebe uma notificação dizendo que está envolvido naquela ocorrência.

O integrante pode:
- **Aceitar ciência**: confirma que participa daquele registro e passa a poder editar/adicionar informações enquanto a ocorrência estiver aberta.
- **Recusar ciência**: informa motivo obrigatório. A recusa fica registrada, aparece no detalhe/PDF e entra no hash final.

### Assinatura final
Assinatura não é o mesmo que ciência.

- Ciência acontece na abertura ou durante a ocorrência.
- Assinatura acontece no fechamento, depois de revisar o conteúdo final.

---

## 12.2 - Fluxo proposto

### 12.2.1 Formação de guarnição
1. Condutor abre turno.
2. Seleciona o K9.
3. Assume uma viatura, se estiver em operação.
4. O painel de turno mostra a guarnição atual da viatura.
5. Troca de K9 é permitida durante o turno, com auditoria.

Observação: a tela de ocorrência não adiciona nem remove equipe.

### 12.2.2 Abertura da ocorrência
Ao abrir uma ocorrência em uma viatura:
1. O app captura um snapshot da guarnição ativa.
2. O relator fica com participação `accepted` automaticamente.
3. Os demais condutores recebem participação `pending`.
4. O app cria notificações para os integrantes.
5. A ocorrência entra em `in_progress`, editável pelo relator e por quem aceitar ciência.

### 12.2.3 Ciência dos integrantes
Cada integrante recebe notificação:

> Ocorrência aberta na viatura Canil 1075. Você foi incluído como integrante da guarnição.

Ações:
- **Aceitar**: grava participação `accepted`.
- **Recusar**: abre campo de motivo e grava participação `declined`.

Regra:
- Integrante `accepted` pode editar/adicionar dados enquanto a ocorrência estiver aberta.
- Integrante `pending` pode visualizar, mas não editar.
- Integrante `declined` pode visualizar sua recusa, mas não edita nem assina.

### 12.2.4 Ocorrência em andamento
Enquanto `status == in_progress` ou `finalizing`:
- Relator pode editar.
- Integrantes com participação `accepted` podem editar.
- Todas as alterações precisam gerar trilha de auditoria.
- A UI deve indicar claramente quem aceitou, quem está pendente e quem recusou.

### 12.2.5 Finalização
O relator finaliza a ocorrência pelo fluxo já conhecido:
1. Preenche resultados, relato final e fotos.
2. O app salva o conteúdo final.
3. Se houver integrantes aceitos, a ocorrência passa para `awaiting_signatures`.
4. O app envia notificação de assinatura para cada integrante `accepted`.
5. Se não houver integrantes aceitos, pode finalizar direto, registrando recusas/pendências no PDF.

### 12.2.6 Revisão antes de assinar
Ao tocar na notificação de assinatura, o integrante não cai direto no modal.

Ele deve abrir uma tela de revisão:
- resumo da ocorrência;
- timeline completa;
- locais;
- fotos;
- resultados;
- relato final;
- equipe/ciência/recusas;
- alterações/auditoria relevante;
- PDF prévio ou espelho do PDF.

Ações:
- **Assinar**: biometria ou senha.
- **Solicitar correção**: informa motivo e notifica o relator.
- **Recusar assinatura**: motivo obrigatório, registrado de forma transparente.

Se uma correção for aceita pelo relator, a ocorrência volta para edição e assinaturas anteriores daquela rodada ficam obsoletas.

---

## 12.3 - Modelo de dados

### Ocorrência - `occurrences/{occurrenceId}`

Campos novos ou revisados:

| Campo | Tipo | Descrição |
|:---|:---|:---|
| `team` | array<map> | Snapshot da guarnição no momento da abertura. Não é editado manualmente na ocorrência. |
| `vehicle_id` | string? | Viatura da ocorrência. |
| `vehicle_label` | string? | Rótulo da viatura para leitura/PDF. |
| `participation_status` | string | Resumo: `pending`, `partial`, `accepted`, `declined_present`. |
| `accepted_handler_ids` | array<string> | RAs com ciência aceita. |
| `declined_handler_ids` | array<string> | RAs que recusaram ciência. |
| `pending_handler_ids` | array<string> | RAs ainda sem resposta. |
| `edit_authorized_handler_ids` | array<string> | Relator + integrantes com ciência aceita. Ajuda queries/rules. |
| `participation_revision` | int | Incrementa quando ciência/recusa muda. |

### Participações - `occurrences/{occurrenceId}/participations/{handlerId}`

| Campo | Tipo | Descrição |
|:---|:---|:---|
| `handler_id` | string | RA do condutor. |
| `auth_uid` | string? | UID do Firebase Auth, quando conhecido. |
| `role` | string | `relator` ou `integrante`. |
| `status` | string | `pending`, `accepted`, `declined`, `correction_requested`. |
| `created_at` | timestamp | Quando a participação foi criada. |
| `responded_at` | timestamp? | Quando aceitou/recusou. |
| `response_method` | string? | `in_app`, `push_action`, `system`. |
| `decline_reason` | string? | Obrigatório quando `status == declined`. |
| `correction_reason` | string? | Obrigatório quando `status == correction_requested`. |
| `device_info` | map? | Metadados técnicos mínimos, quando disponíveis. |

### Assinaturas - `occurrences/{occurrenceId}/signatures/{handlerId}`

Mantém a estrutura da Parte 10, mas com duas decisões novas:
- só integrantes com participação `accepted` recebem pedido de assinatura;
- recusa de assinatura tem motivo obrigatório e aparece no PDF.

Campos adicionais recomendados:

| Campo | Tipo | Descrição |
|:---|:---|:---|
| `status` | string | `pending`, `signed`, `declined`, `expired`, `obsolete`. |
| `decline_reason` | string? | Obrigatório se `status == declined`. |
| `signature_round` | int | Rodada de assinatura. Incrementa se voltar para edição. |

### Notificações - `notifications/{userId}/items/{notificationId}`

Tipos novos:

| Tipo | Uso |
|:---|:---|
| `occurrence_participation_requested` | Ocorrência aberta, integrante precisa aceitar/recusar ciência. |
| `occurrence_participation_accepted` | Integrante aceitou ciência. |
| `occurrence_participation_declined` | Integrante recusou ciência. |
| `signature_requested` | Ocorrência fechada, assinatura necessária. |
| `signature_declined` | Integrante recusou assinar. |
| `correction_requested` | Integrante pediu correção antes de assinar. |

Campos recomendados:

| Campo | Tipo | Descrição |
|:---|:---|:---|
| `type` | string | Tipo da notificação. |
| `occurrence_id` | string | Ocorrência alvo. |
| `target_screen` | string | `participation`, `occurrence_review`, `signature_review`. |
| `action_required` | bool | Se exige ação do usuário. |
| `created_at` | timestamp | Criação. |
| `read_at` | timestamp? | Leitura. |
| `resolved_at` | timestamp? | Quando a ação foi concluída. |
| `additional_data` | map? | Payload de navegação/deep link. |

---

## 12.4 - Hash e integridade

Esta parte altera o conteúdo probatório final. Recomenda-se subir para **`hash_version: 4`** quando houver participações.

Motivo: `hash_version: 3` já significa "team + signatures". A Parte 12 adiciona ciência/recusa operacional, então mudar o payload mantendo v3 criaria ambiguidade.

### Hash v4 inclui
- Dados da ocorrência já cobertos pelo v3.
- `team` ordenado por `handler_id`.
- `participations` ordenadas por `handler_id`.
- `signatures` ordenadas por `handler_id`.
- `accepted_handler_ids`, `declined_handler_ids`, `pending_handler_ids`.
- `vehicle_id` e dados essenciais da viatura.
- Créditos do K9 nas ações.

### Hash v4 não inclui
- `signature_hash`, para evitar circularidade.
- IDs de notificação.
- Campos voláteis de UI.
- Tokens FCM.

### Compatibilidade
- v1/v2 continuam legados.
- v3 continua válido para co-assinatura da Parte 10/11.
- v4 é usado para ocorrências com ciência de guarnição.

---

## 12.5 - Firestore rules

As rules precisam impor no servidor:

1. Criar participação:
   - permitido ao relator no momento da abertura;
   - um doc por integrante do `team`.

2. Aceitar ciência:
   - permitido somente ao próprio `handlerId`;
   - `request.auth.uid` precisa bater com `auth_uid` ou chave de equipe equivalente;
   - transição permitida: `pending -> accepted`.

3. Recusar ciência:
   - permitido somente ao próprio `handlerId`;
   - `decline_reason` obrigatório e não vazio;
   - transição permitida: `pending -> declined`.

4. Editar ocorrência aberta:
   - permitido ao relator;
   - permitido a integrante em `accepted_handler_ids`;
   - negado a `pending` e `declined`.

5. Fechar para assinaturas:
   - permitido ao relator;
   - cria assinaturas apenas para integrantes com participação `accepted`;
   - trava edição direta.

6. Assinar:
   - permitido somente ao próprio integrante;
   - exige participação `accepted`;
   - exige ocorrência em `awaiting_signatures`.

7. Recusar assinatura:
   - permitido somente ao próprio integrante;
   - motivo obrigatório;
   - entra no PDF/hash.

8. Aditamento:
   - relator original;
   - ou integrante com participação `accepted` e assinatura `signed`.

---

## 12.6 - Push e ações na notificação

### Fase 1 - In-app
Implementar primeiro:
- badge;
- lista de pendências;
- tela de ciência;
- tela de revisão de assinatura;
- deep link interno ao tocar na notificação.

### Fase 2 - Push nativo
Depois:
- FCM para envio remoto;
- ação "Aceitar" direto na notificação;
- ação "Recusar" abrindo app em uma tela curta de motivo;
- ação "Assinar" abrindo app direto na revisão de assinatura.

### Observação técnica
Botão de recusa direto na notificação com texto pode depender de suporte específico por plataforma. Em Android pode existir input em ação de notificação; em iOS o fluxo costuma ser mais restrito. Por isso o caminho seguro é: "Recusar" abre o app já no formulário de motivo.

---

## 12.7 - Troca de cão durante o turno

A troca de K9 durante o turno é permitida.

### Regras
- Não encerra o turno.
- Registra auditoria.
- Atualiza o K9 ativo do turno.
- Novas ocorrências usam o novo K9.
- Ocorrências já abertas mantêm o snapshot original, a menos que seja registrada uma troca operacional dentro daquela ocorrência.

### Registro recomendado no turno

Subcoleção ou array:
`active_shifts/{handlerId}/dog_switches/{switchId}` ou campo `dog_switches`.

| Campo | Tipo | Descrição |
|:---|:---|:---|
| `from_dog_id` | string | K9 anterior. |
| `from_dog_name` | string | Nome do K9 anterior. |
| `to_dog_id` | string | Novo K9. |
| `to_dog_name` | string | Nome do novo K9. |
| `switched_at` | timestamp | Horário da troca. |
| `reason` | string? | Motivo opcional, recomendado. |
| `performed_by` | string | RA do condutor. |

### Se houver ocorrência aberta
Não alterar silenciosamente o `team` da ocorrência. Exibir opção:
- "Trocar K9 apenas para próximos registros";
- "Registrar troca nesta ocorrência".

Se registrar na ocorrência, criar evento auditável na timeline:
`dog_switched`, com K9 anterior, novo K9, motivo e horário.

---

## 12.8 - UI esperada

### Módulo Turno / Guarnição
Deve existir uma área própria para:
- viatura atual;
- condutores ativos;
- K9 de serviço;
- troca de K9;
- assumir/sair da viatura;
- ocupação da viatura;
- alerta de turno longo.

### Ocorrência - detalhe
Não deve parecer uma tela de montagem de equipe.

Mostrar apenas:
- guarnição capturada;
- status de ciência de cada condutor;
- status de assinatura quando aplicável;
- ações disponíveis conforme papel/status.

### Tela de Ciência
Tela simples:
- resumo da ocorrência;
- relator;
- viatura;
- K9;
- local/data;
- botões "Aceitar ciência" e "Recusar com motivo".

### Tela de Revisão de Assinatura
Tela completa:
- todo conteúdo da ocorrência;
- timeline;
- fotos;
- resultados;
- relato final;
- ciência/recusas;
- botão "Assinar";
- botão "Solicitar correção";
- botão "Recusar assinatura".

---

## 12.9 - PDF

Adicionar seções:

### Guarnição e ciência
Lista:
- relator;
- integrantes;
- K9;
- status de ciência;
- data/hora da resposta;
- motivo de recusa, se houver.

### Assinaturas
Lista:
- quem assinou;
- método;
- data/hora;
- quem recusou assinatura;
- quem ficou pendente/expirado.

### Troca de K9
Se houver troca durante a ocorrência:
- K9 anterior;
- K9 novo;
- horário;
- motivo;
- responsável.

---

## 12.10 - Critério de pronto

1. A equipe não é montada dentro da ocorrência.
2. Guarnição é gerenciada no turno/viatura.
3. Abrir ocorrência captura snapshot da guarnição.
4. Integrantes recebem notificação de ciência.
5. Integrante aceita ou recusa com motivo.
6. Apenas relator e integrantes que aceitaram podem editar ocorrência aberta.
7. Finalização segue fluxo conhecido e depois pede assinatura aos integrantes aceitos.
8. Integrante revisa a ocorrência inteira antes de assinar.
9. Integrante pode solicitar correção ou recusar assinatura com motivo.
10. Push/deep link leva para a tela correta.
11. Troca de K9 durante turno é permitida e auditável.
12. Ocorrência já aberta não muda equipe/K9 silenciosamente.
13. Firestore rules bloqueiam edição por quem não aceitou.
14. PDF mostra guarnição, ciência, recusas, pendências e assinaturas.
15. Hash v4 inclui participações e assinaturas.

---

## 12.11 - Etapas de implementação sugeridas

### Etapa 1 - Guarnição fora da ocorrência
- Criar/ajustar painel de guarnição no turno.
- Remover UX de montagem de equipe da ocorrência.
- Permitir troca de K9 durante turno com auditoria.

### Etapa 2 - Participações
- Criar subcoleção `participations`.
- Ao abrir ocorrência, criar participações para a guarnição.
- Relator auto-aceito; demais pendentes.

### Etapa 3 - Notificação de ciência
- Notificação in-app para aceitar/recusar.
- Tela de ciência.
- Motivo obrigatório para recusa.

### Etapa 4 - Permissão de edição colaborativa
- Liberar edição para integrantes `accepted`.
- Bloquear `pending` e `declined`.
- Regras no Firestore.

### Etapa 5 - Finalização e revisão de assinatura
- Finalização gera pedido de assinatura apenas para aceitos.
- Tela de revisão completa.
- Assinar, solicitar correção ou recusar assinatura.

### Etapa 6 - Push/deep links
- FCM ou mecanismo equivalente.
- Ações nativas quando possível.
- Deep links para ciência e revisão de assinatura.

### Etapa 7 - Hash v4 e PDF
- Hash v4 com participações.
- PDF com guarnição, ciência, recusas e assinaturas.
- Testes de integridade.

---

## 12.12 - Prompt para implementação futura

Vamos implementar a Parte 12: ciência da guarnição e participação operacional. Leia `temp/docs/ESPEC_TECNICA_PARTE_12.md`, junto com as Partes 10, 11, 9 e 7. Não comece por UI: primeiro diagnostique o estado real do turno, guarnição, notificações, rules, assinatura e hash.

Diagnóstico obrigatório:
1. Onde a guarnição está sendo formada hoje?
2. A ocorrência ainda tem algum caminho de adicionar/remover equipe manualmente?
3. Como as notificações in-app estão modeladas?
4. Existe FCM ou só `flutter_local_notifications`?
5. As rules conseguem identificar o integrante por RA + `auth_uid`?
6. O fluxo de finalização está separando ciência, edição e assinatura?
7. A troca de K9 durante turno já é permitida? Se sim, está auditável?

Implementar em etapas, validando cada uma no celular e no servidor.

---

## 12.13 - Brief para mockups HTML

Gerar mockups mobile em HTML/CSS, largura base 390px, tema escuro operacional, usando os tokens visuais do app:
- fundo: `#050d10`;
- primário sólido: `#4dd0e1`;
- cards escuros, borda fina, raio pequeno;
- sem landing page;
- sem textos explicando o app;
- simular telas reais de uso.

Mockups necessários:
1. **Turno - Guarnição da viatura**
   - header com condutor, K9 e viatura;
   - cards dos integrantes ativos;
   - K9 de serviço;
   - botão trocar K9;
   - botão assumir/sair da viatura;
   - aviso de turno longo.

2. **Notificação/Ciência de ocorrência aberta**
   - estado de notificação;
   - tela aberta por deep link;
   - resumo da ocorrência;
   - botões aceitar e recusar;
   - modal/campo de motivo para recusa.

3. **Detalhe da ocorrência colaborativa**
   - guarnição capturada;
   - status de ciência: aceitou, pendente, recusou;
   - indicação de quem pode editar;
   - timeline da ocorrência.

4. **Tela de revisão para assinatura**
   - ocorrência completa em modo revisão;
   - fotos, resultados, relato e timeline;
   - ações: assinar, solicitar correção, recusar assinatura.

5. **Pendências**
   - lista separada entre "ciência pendente" e "assinatura pendente";
   - badges claros;
   - toque abrindo a tela correta.

6. **PDF - seção de guarnição e ciência**
   - bloco de equipe;
   - K9 com matrícula;
   - ciência/recusas;
   - assinaturas.
