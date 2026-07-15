---

name: ponytail
description: Modo manual para buscar a menor solução segura e suficiente dentro do escopo de uma tarefa. Use somente quando o usuário invocar explicitamente "ponytail", "modo minimalista", "solução mínima", "simplifique", "YAGNI" ou equivalente. Nunca substitui as regras de arquitetura, segurança, auditoria, compatibilidade, documentação ou validação do K9 Ops.
argument-hint: "[lite|full|ultra]"
disable-model-invocation: true
------------------------------

# Ponytail · Menor Solução Segura

## Propósito

Esta skill existe para reduzir complexidade acidental.

Quando ativada, procure a menor implementação que resolva corretamente o problema real.

O objetivo é reduzir:

* código desnecessário;
* abstrações prematuras;
* dependências;
* arquivos alterados;
* duplicação;
* boilerplate;
* complexidade sem benefício real.

Ela não é uma autorização para:

* ignorar arquitetura;
* pular investigação;
* simplificar regras de negócio;
* reduzir segurança;
* quebrar compatibilidade;
* ignorar auditoria;
* omitir testes necessários;
* entregar solução incompleta.

## Ativação

Esta skill é manual.

Só deve ser aplicada quando o usuário a invocar explicitamente.

Exemplos:

```text
/ponytail
```

```text
/ponytail lite
```

```text
/ponytail full
```

```text
/ponytail ultra
```

Também pode ser ativada quando o usuário pedir explicitamente algo como:

```text
use a solução mais simples
evite over-engineering
aplique YAGNI
faça o menor diff possível
modo minimalista
```

Não permaneça ativa automaticamente entre sessões.

Não altere o comportamento geral do projeto sem invocação explícita.

## Hierarquia de autoridade

Ponytail nunca pode sobrescrever:

1. escopo explícito da tarefa;
2. `CLAUDE.md`, `AGENTS.md` e instruções vigentes;
3. arquitetura atual do projeto;
4. contratos de dados;
5. segurança;
6. integridade de dados;
7. regras de auditoria;
8. compatibilidade mobile/web;
9. critérios de aceitação;
10. validações obrigatórias.

Se a menor solução conflitar com algum desses itens, ela não é a solução correta.

## Regra principal

A prioridade é:

```text
menor solução segura e completa
```

e não:

```text
menor quantidade de código possível
```

Código curto no lugar errado continua sendo código ruim.

## Antes de simplificar

Primeiro entenda:

* o problema real;
* o fluxo completo afetado;
* a causa raiz;
* os consumidores;
* os dados envolvidos;
* o comportamento esperado;
* as restrições existentes.

Não escolha a solução mínima antes de compreender o problema.

## A escada Ponytail

Percorra esta sequência.

Pare na primeira solução que realmente resolver o problema.

## 1. Isso precisa existir?

Questione requisitos apenas quando forem claramente:

* especulativos;
* redundantes;
* não solicitados;
* criados apenas "para o futuro".

Não questione novamente algo que já foi explicitamente decidido ou aprovado.

Não use YAGNI para remover requisito real.

## 2. Já existe algo equivalente no projeto?

Antes de criar código novo, procure:

* helper;
* utilitário;
* serviço;
* repository;
* parser;
* componente;
* model;
* padrão equivalente.

Reutilize quando a semântica for realmente a mesma.

Não force reutilização inadequada apenas para reduzir o diff.

## 3. A linguagem ou plataforma já resolve?

Prefira recursos nativos quando atendem corretamente ao requisito.

Exemplos possíveis:

```text
Dart
Flutter
Firebase
Firestore
biblioteca padrão
```

Não recrie manualmente algo que a plataforma já resolve de forma segura.

## 4. Uma dependência já instalada resolve?

Antes de adicionar pacote novo, verifique se já existe uma solução no projeto.

Use a dependência existente quando:

* ela realmente resolve o problema;
* o uso está alinhado ao projeto;
* não cria acoplamento desnecessário.

Não adicione pacote para substituir poucas linhas simples sem benefício real.

## 5. Qual é o menor ponto correto de alteração?

Corrija no ponto onde o problema realmente nasce.

Exemplo:

```text
5 consumidores falham por causa do mesmo parser
```

Prefira corrigir o parser corretamente.

Não adicione cinco guards diferentes apenas para reduzir risco aparente.

O menor diff correto pode estar em um ponto compartilhado.

## 6. Só então implemente

Faça o menor diff que resolva completamente:

* fluxo principal;
* erro relevante;
* compatibilidade necessária;
* segurança necessária;
* validação necessária.

Não implemente infraestrutura "para depois".

## Bugfix

Para bugs, siga:

```text
sintoma
↓
fluxo real
↓
causa raiz
↓
menor correção no ponto correto
```

Não confunda:

```text
menor diff
```

com:

```text
patch superficial
```

Se a correção apenas esconder o sintoma, ela não é Ponytail.

Ela é dívida técnica.

## Escopo mínimo não significa arquitetura mínima

No K9 Ops, frequentemente buscamos:

```text
menor escopo possível
```

Isso significa:

* não alterar áreas paralelas;
* não fazer refactors desnecessários;
* não incluir melhorias não solicitadas.

Isso não significa eliminar a arquitetura necessária.

Áreas como:

* Firestore;
* Saúde;
* Turnos;
* Ocorrências;
* Treinamento;
* Auditoria;
* Permissões;

podem exigir soluções mais estruturadas por natureza.

## Abstrações

Evite criar sem necessidade atual:

* interface com uma única implementação;
* factory para um único produto;
* configuração para valor fixo;
* camada intermediária sem responsabilidade;
* wrapper que apenas repassa chamadas;
* arquitetura preparada para casos inexistentes.

Mas preserve abstrações que já fazem parte da arquitetura do projeto.

Não destrua uma estrutura existente apenas porque código inline seria menor.

## Services e repositories

Não crie um service ou repository novo apenas por formalidade.

Crie quando houver responsabilidade real, como:

* acesso a dados;
* isolamento de infraestrutura;
* regra compartilhada;
* coordenação;
* transformação significativa.

Ao mesmo tempo, não mova lógica de domínio para widget apenas para evitar criar um arquivo necessário.

## Arquivos

Prefira menos arquivos alterados quando isso não prejudicar:

* separação de responsabilidades;
* arquitetura;
* testabilidade;
* manutenção.

Não coloque código no arquivo errado apenas para evitar tocar em outro arquivo.

O menor número de arquivos não é objetivo absoluto.

## Dependências

Nova dependência precisa justificar:

* benefício;
* manutenção;
* tamanho;
* risco;
* necessidade real.

Antes de adicionar:

```text
já existe no projeto?
stdlib resolve?
Flutter resolve?
Firebase resolve?
```

Se sim, prefira a opção existente.

## Código legado

Não refatore legado automaticamente.

Se o legado:

* não causa o problema;
* não está no escopo;
* funciona atualmente;

deixe como está.

Se ele for a causa raiz da tarefa atual, corrija apenas o necessário.

Não transforme bugfix em modernização completa.

## Firestore

Ponytail não pode simplificar mudanças de Firestore ignorando compatibilidade.

Antes de alterar:

```text
campo
tipo
coleção
subcoleção
semântica
rules
índice
```

consulte:

```text
firestore-coexistence
```

Não escolha uma mudança destrutiva apenas porque exige menos código.

## Auditoria

Quando a tarefa envolver registros críticos, consulte:

```text
audit-trail
```

Não remova rastreabilidade para simplificar implementação.

Também não crie auditoria adicional sem necessidade.

## Segurança

Nunca simplifique removendo:

* autenticação;
* autorização;
* validação de entrada em fronteiras de confiança;
* proteção contra perda de dados;
* consistência necessária;
* controles de acesso;
* tratamento de concorrência necessário.

Ocultar uma ação na interface não substitui segurança real.

## Integridade de dados

Não reduza validações quando a ausência delas puder produzir:

* corrupção;
* perda de dados;
* estado impossível;
* inconsistência entre consumidores;
* histórico incorreto.

Lazy significa evitar trabalho desnecessário.

Não significa aceitar risco desnecessário.

## Concorrência

Não adicione transaction, lock ou mecanismo complexo sem risco real.

Mas quando houver risco concreto de concorrência, não escolha uma implementação insegura apenas porque é menor.

Use o mecanismo mais simples que realmente garanta a consistência necessária.

## Estado e UI

Não crie:

* estado global para problema local;
* ViewModel para valor trivial;
* nova arquitetura de navegação para uma tela;
* componente compartilhado sem reutilização real.

Ao mesmo tempo, não coloque toda lógica diretamente em um widget se a feature já possui estrutura clara para essa responsabilidade.

## Testes

Use a menor validação que realmente prove a mudança.

Pode ser:

* teste existente relevante;
* pequeno teste unitário;
* teste de parser;
* teste de widget;
* `flutter analyze`;
* validação manual reproduzível;
* validação autenticada;
* combinação adequada.

Não crie suíte inteira para uma mudança trivial.

Não remova ou ignore teste importante para reduzir o trabalho.

## Regra para lógica nova

Quando adicionar lógica não trivial, deixe uma forma objetiva de verificar seu comportamento.

Exemplos:

```text
branch importante
parser
transformação de dados
regra de negócio
fluxo crítico
```

Use o padrão de testes já existente no projeto.

Não crie mecanismos improvisados de teste dentro de código de produção.

## Comentários

Não adicione comentários como:

```dart
// ponytail: ...
```

ao código do projeto.

Esta skill é uma estratégia de trabalho.

Ela não deve deixar sua própria marca no código.

Adicione comentário somente quando o código realmente precisar explicar:

* decisão não óbvia;
* workaround;
* limitação conhecida;
* motivo técnico relevante.

## Intensidade

## `lite`

Implemente normalmente o que foi pedido.

Quando existir uma alternativa claramente mais simples, mencione-a sem substituir automaticamente o requisito.

Ideal para:

* tarefas já bem especificadas;
* comparação de soluções;
* revisão de complexidade.

## `full`

Modo padrão.

Escolha a menor solução segura que satisfaça integralmente:

* requisito;
* arquitetura;
* compatibilidade;
* validação.

Evite trabalho especulativo.

## `ultra`

Questione agressivamente:

* abstrações;
* infraestrutura futura;
* novas dependências;
* duplicação;
* features especulativas.

Mesmo em `ultra`, nunca simplifique:

* segurança;
* integridade;
* auditoria necessária;
* compatibilidade;
* critérios de aceitação;
* regras já aprovadas.

`Ultra` questiona complexidade não necessária.

Não questiona requisitos confirmados.

## Quando parar

Pare quando o problema estiver corretamente resolvido.

Não continue para:

* refatorar arquivos vizinhos;
* limpar warnings antigos;
* trocar biblioteca;
* padronizar nomes fora do escopo;
* criar infraestrutura futura;
* melhorar telas não relacionadas.

Reporte essas oportunidades separadamente quando forem relevantes.

## Mudanças compartilhadas

Antes de alterar um elemento compartilhado, identifique os consumidores relevantes.

Exemplos:

```text
parser
service
repository
widget compartilhado
model
campo Firestore
```

Uma alteração central pode ser o menor diff correto.

Mas precisa preservar os outros consumidores.

## Trabalho preexistente

Nunca simplifique o worktree apagando alterações que não pertencem à tarefa.

Antes de trabalhar:

* identifique estado atual;
* preserve arquivos preexistentes;
* não faça cleanup destrutivo;
* não inclua mudanças alheias no commit.

## Commits

Ponytail não autoriza commit automático.

Siga o workflow atual.

Quando o commit fizer parte da tarefa:

* revise o diff;
* inclua somente o escopo;
* não misture alterações preexistentes.

## Output

Não imponha limite artificial de três linhas.

Siga o formato solicitado pela tarefa ou pelo projeto.

Quando não houver formato específico, reporte:

```text
O que foi feito

Por que esta é a menor solução segura

O que deliberadamente não foi adicionado

Validações executadas
```

Se nada relevante foi evitado, não invente uma justificativa.

## O que Ponytail nunca deve fazer

Não:

* interromper uma tarefa aprovada para questionar sua existência;
* reduzir requisito já confirmado;
* remover arquitetura necessária;
* ignorar documentação vigente;
* alterar schema destrutivamente para economizar código;
* esconder erro em vez de corrigir causa raiz;
* trocar solução existente só porque outra seria menor;
* produzir comentário `ponytail` no código;
* permanecer ativo sem invocação explícita.

## Checklist

Antes de concluir em modo Ponytail:

* [ ] O problema real foi entendido.
* [ ] A causa raiz foi identificada quando aplicável.
* [ ] Soluções existentes foram procuradas.
* [ ] Nenhuma abstração especulativa foi criada.
* [ ] Nenhuma dependência desnecessária foi adicionada.
* [ ] O menor ponto correto de alteração foi escolhido.
* [ ] Segurança não foi reduzida.
* [ ] Compatibilidade não foi ignorada.
* [ ] Auditoria necessária foi preservada.
* [ ] A validação é proporcional ao risco.
* [ ] Nenhuma área fora do escopo foi alterada.

## Regra final

**Escreva menos código, não menos solução.**

O melhor diff é o menor diff que continua:

```text
correto
seguro
compatível
compreensível
manutenível
```

seis meses depois.
