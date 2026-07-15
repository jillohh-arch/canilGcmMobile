  ---

name: audit-trail
description: Regras obrigatórias de rastreabilidade para operações críticas no K9 Ops. Use sempre que criar, editar, corrigir, cancelar, excluir logicamente ou restaurar registros operacionais, clínicos, de treinamento ou administrativos relevantes. A rastreabilidade é obrigatória, mas a implementação deve respeitar o schema e a arquitetura atuais do projeto.
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Trilha de Auditoria · K9 Ops

## Por que existe

O K9 Ops mantém registros institucionais que podem precisar ser consultados meses ou anos depois para:

* prestação de contas;
* reconstrução de fatos;
* acompanhamento operacional;
* auditoria;
* defesa profissional dos operadores;
* histórico clínico e de treinamento;
* responsabilização administrativa.

Um registro crítico deve permitir responder, quando aplicável:

* **Quem** realizou a ação;
* **Quando** a ação foi realizada;
* **O que** foi alterado;
* **Qual era o valor anterior relevante**;
* **Qual passou a ser o novo valor**;
* **Por que** uma operação sensível foi realizada.

## Regra principal

**Rastreabilidade é obrigatória. O formato técnico não deve ser inventado ou duplicado sem verificar a arquitetura atual.**

Antes de implementar ou modificar auditoria:

1. leia o código atual do fluxo;
2. identifique o schema real utilizado pela branch atual;
3. verifique se já existe serviço, evento, subcoleção, Cloud Function ou outro mecanismo de auditoria;
4. consulte a documentação oficial vigente;
5. reutilize o padrão atual quando ele continuar adequado.

Não crie automaticamente um novo campo `audit_trail`, uma nova subcoleção ou outro mecanismo paralelo apenas porque esta skill foi carregada.

## Hierarquia de autoridade

Em caso de conflito, siga esta ordem:

1. escopo explícito da tarefa atual;
2. `CLAUDE.md`, `AGENTS.md` e instruções equivalentes vigentes;
3. código atual da branch;
4. documentação oficial atual em `docs/`;
5. decisões atuais registradas para a feature;
6. esta skill;
7. documentos, mockups e especificações históricas.

Arquivos em `temp/` não são fonte de verdade por padrão.

## Quais registros exigem atenção de auditoria

Considere críticos principalmente os registros relacionados a:

* ocorrências;
* atividade operacional;
* turnos;
* saúde e prontidão;
* consultas e eventos clínicos;
* medicações e tratamentos;
* vacinação e prevenção;
* nutrição;
* pesagens;
* treinamento;
* avaliações;
* progressões;
* documentos institucionais;
* decisões administrativas relevantes.

Esta lista representa domínios, não schemas ou caminhos Firestore fixos.

Antes de alterar qualquer coleção, confirme a estrutura atual no código.

## Informações mínimas de uma ação auditável

Quando o domínio exigir rastreabilidade, preserve informações suficientes para identificar:

```text
action
actor_id
occurred_at
target
change_summary
reason, quando aplicável
```

Dependendo da arquitetura atual, também podem ser necessários:

```text
actor_name_snapshot
actor_ra_snapshot
old_value
new_value
source
request_id
```

Os nomes exatos dos campos devem seguir o contrato vigente do projeto.

Não introduza novos nomes apenas para seguir exemplos desta skill.

## Identidade histórica do responsável

Quando for importante que o registro continue legível mesmo após alterações cadastrais, pode ser apropriado preservar snapshots como:

```text
actor_id
actor_name_snapshot
actor_ra_snapshot
```

O identificador permanente continua sendo a referência principal.

Nome e RA em snapshot servem para preservar a apresentação histórica do responsável no momento da ação.

Não duplique esses dados em todo documento sem necessidade.

## Timestamps

### Regra fundamental

Não descreva horário do dispositivo como timestamp do servidor.

Valores como:

```dart
DateTime.now()
Timestamp.now()
```

representam o relógio do cliente.

Quando a autoridade temporal precisar vir do backend, utilize o mecanismo server-side definido pela arquitetura atual.

Diferencie, quando necessário:

```text
event_occurred_at
```

Quando o fato realmente aconteceu.

```text
recorded_at
```

Quando o usuário informou ou registrou o fato.

```text
created_at
```

Quando o registro foi criado no sistema.

```text
updated_at
```

Quando ocorreu a última alteração.

Não crie todos esses campos automaticamente.

Use somente os conceitos necessários ao domínio atual.

## `created_at`

Quando existir:

* deve representar a criação do registro;
* não deve ser alterado em edições posteriores.

## `updated_at`

Quando existir:

* deve ser atualizado somente quando houver alteração real do registro;
* não substitui o histórico detalhado de mudanças quando esse histórico for necessário.

## Criação de registros

Ao criar um registro crítico, preserve conforme o padrão vigente:

* autoria;
* horário confiável;
* identificador;
* contexto necessário para compreender o registro posteriormente.

Se já existir um serviço centralizado para criação auditada, reutilize-o.

Não implemente um segundo mecanismo paralelo.

## Edição de registros

Antes de implementar edição de um registro crítico, determine:

1. o registro pode realmente ser editado?
2. a mudança pode sobrescrever o valor original?
3. seria mais correto registrar uma retificação?
4. o valor anterior precisa permanecer consultável?
5. existe impacto em outros sistemas ou relatórios?

Para dados de maior relevância institucional, pode ser preferível manter:

```text
registro original
+
retificação
```

em vez de sobrescrever silenciosamente a informação anterior.

Isso deve ser decidido conforme o domínio.

## Registro de `old_value` e `new_value`

Quando a auditoria exigir explicitamente:

```text
old_value → new_value
```

não presuma que o seguinte fluxo seja seguro em todos os casos:

```text
get()
↓
tempo passa
↓
update()
```

Outro usuário ou processo pode modificar o documento entre a leitura e a escrita.

Quando consistência concorrente for necessária, avalie o uso do mecanismo já adotado pelo projeto, como:

* transaction;
* operação server-side;
* Cloud Function;
* escrita atômica;
* evento append-only.

Não introduza complexidade adicional quando não houver risco real de concorrência.

## Alterações de múltiplos campos

Quando uma única ação modificar vários campos relacionados, não gere obrigatoriamente uma entrada artificial para cada campo.

Prefira o formato atual do projeto.

Uma alteração pode ser representada como:

```text
uma ação
+
conjunto de mudanças
```

quando isso produzir histórico mais claro.

Exemplo conceitual:

```text
action: updated
changes:
  weight_kg:
    old: 29.4
    new: 29.8
  body_condition:
    old: ideal
    new: attention
```

Não adote esse formato sem verificar o schema vigente.

## Exclusão

### Regra de segurança

Não faça exclusão física de registros críticos automaticamente.

Antes de implementar exclusão, determine qual conceito o domínio utiliza:

* soft delete;
* cancelamento;
* arquivamento;
* invalidação;
* retificação;
* exclusão física excepcional.

Para registros históricos e operacionais relevantes, normalmente deve existir preservação do histórico.

Não transforme isso em regra universal para caches, dados temporários ou estruturas técnicas.

## Motivo da exclusão ou cancelamento

Quando a ação remover um registro da visualização operacional ou alterar sua validade histórica, o motivo pode ser obrigatório.

O motivo deve ser:

* solicitado antes da operação;
* validado;
* preservado na auditoria;
* apresentado novamente quando necessário.

Não registre apenas:

```text
deleted: true
```

quando o contexto da exclusão for institucionalmente importante.

## Restauração

Quando o domínio permitir restauração:

* a restauração deve ser uma nova ação auditável;
* o histórico da exclusão não deve desaparecer;
* autoria e horário devem ser preservados;
* o documento deve voltar ao estado válido seguindo o mecanismo atual.

Nunca "limpe" o histórico para fazer parecer que a exclusão nunca aconteceu.

## Integridade da própria auditoria

Uma trilha de auditoria só deve ser descrita como imutável ou confiável quando existirem controles compatíveis.

Verifique, conforme o caso:

* Firestore Rules;
* permissões dos usuários;
* operações server-side;
* possibilidade de alterar entradas antigas;
* possibilidade de sobrescrever toda a estrutura;
* validações de backend.

Não afirme que um histórico é imutável apenas porque a interface não possui botão de edição.

## Arrays de auditoria

Se o projeto atual utilizar um array no próprio documento, preserve o padrão somente enquanto ele continuar adequado.

Considere:

* crescimento do documento;
* limite de tamanho do Firestore;
* concorrência;
* custo de leitura;
* necessidade de paginação;
* necessidade de consultas específicas.

Não migre automaticamente para subcoleção apenas porque o array cresceu.

Também não mantenha indefinidamente um array inadequado apenas por compatibilidade histórica.

Qualquer mudança de estrutura deve seguir `firestore-coexistence`.

## Concorrência

Não presuma que `arrayUnion` resolve toda a concorrência.

Ele pode ajudar a evitar perda de entradas adicionadas simultaneamente, mas não garante sozinho:

* correção do `old_value`;
* ordem lógica dos eventos;
* atomicidade de mudanças relacionadas;
* proteção contra sobrescrita de outros campos;
* integridade da própria auditoria.

Avalie o fluxo real antes de escolher a solução.

## Firestore compartilhado

Antes de qualquer mudança em:

* campos;
* tipos;
* coleções;
* subcoleções;
* estrutura de auditoria;
* Rules;
* Functions;

consulte:

```text
firestore-coexistence
```

A necessidade de auditoria não autoriza quebrar consumidores atuais.

## Web e mobile

O K9 Ops possui múltiplos consumidores dos mesmos dados.

Quando uma estrutura auditável for utilizada por mais de um sistema:

* confirme como cada consumidor lê;
* confirme como cada consumidor escreve;
* evite que uma aplicação sobrescreva o histórico produzido pela outra;
* preserve compatibilidade durante migrações.

Não presuma que o painel web é apenas leitura.

Verifique o código e o contrato atuais.

## Fotos e evidências

Preservação de arquivo original e metadados deve seguir a decisão atual da feature.

Quando uma imagem for tratada como evidência e houver requisito de preservação:

* mantenha o original sem alteração destrutiva;
* gere derivados separadamente;
* não substitua o arquivo original por thumbnail;
* avalie privacidade antes de expor EXIF ou GPS.

Não aplique preservação e exposição de EXIF universalmente a todas as imagens do aplicativo.

## Exibição na interface

Quando o histórico de alterações fizer parte da experiência da feature:

* ordene os eventos de forma compreensível;
* identifique ação, responsável e horário;
* apresente mudanças relevantes;
* evite mostrar estrutura técnica bruta do Firestore.

Exemplo de linguagem:

```text
GCM Ragonha atualizou o peso de 29,4 kg para 29,8 kg.
```

```text
GCM Silva cancelou o registro.
Motivo: duplicidade de lançamento.
```

A interface não precisa mostrar todos os detalhes técnicos usados internamente.

## PDFs e relatórios

Não inclua automaticamente a trilha completa em todo PDF.

Quando o objetivo do documento exigir histórico de alterações:

* utilize o mecanismo de auditoria vigente;
* apresente somente informações apropriadas ao destinatário;
* não exponha dados internos ou sensíveis sem necessidade.

Consulte:

```text
pdf-generation
```

quando a tarefa envolver documentos institucionais.

## Mudanças de schema de auditoria

Alterar o formato de auditoria pode ser uma mudança incompatível.

Antes de:

* renomear campos;
* converter array em subcoleção;
* mudar estrutura de uma entrada;
* alterar tipos;
* remover dados antigos;

consulte:

```text
firestore-coexistence
```

Planeje compatibilidade e migração quando necessário.

## Checklist obrigatório

Antes de concluir uma alteração envolvendo auditoria, confirme:

* [ ] O schema atual foi verificado.
* [ ] Não foi criado um mecanismo paralelo desnecessário.
* [ ] A autoria é identificável.
* [ ] O horário usado corresponde ao tipo de timestamp declarado.
* [ ] Alterações relevantes permanecem reconstruíveis.
* [ ] Exclusões ou cancelamentos preservam contexto quando necessário.
* [ ] A concorrência foi considerada quando realmente aplicável.
* [ ] A própria trilha possui proteção compatível com a integridade alegada.
* [ ] Web e mobile continuam compatíveis.
* [ ] Nenhuma mudança de schema foi feita sem consultar `firestore-coexistence`.
* [ ] A solução permaneceu dentro do escopo da tarefa atual.

## Regra final

**Preserve rastreabilidade sem inventar arquitetura.**

O objetivo da auditoria no K9 Ops é permitir que uma ação relevante continue compreensível, atribuível e tecnicamente defensável no futuro.

A implementação deve sempre seguir a arquitetura real e vigente do projeto.
