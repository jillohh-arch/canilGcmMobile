---

name: canil-k9-context
description: Contexto institucional estável do projeto K9 Ops. Use em decisões de produto, UX, arquitetura e regras de negócio do aplicativo mobile Flutter e em mudanças que afetem sua integração com o ecossistema K9 Ops. Não use esta skill como fonte de dados operacionais mutáveis, status atual de features ou schema técnico detalhado.
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Contexto Institucional · K9 Ops

## O produto

O K9 Ops é um sistema de gestão operacional e institucional voltado ao trabalho com cães policiais.

O ecossistema possui, entre outros componentes:

* aplicativo mobile Flutter para fluxos operacionais;
* plataforma web gerencial;
* Firebase como parte da infraestrutura compartilhada;
* módulos operacionais, administrativos e institucionais.

Mobile e web podem consumir os mesmos dados.

Nunca trate um dos sistemas como isolado sem verificar o fluxo atual.

## Objetivos permanentes

O K9 Ops existe para apoiar:

1. operação diária do Canil;
2. registro confiável das atividades realizadas;
3. gestão e acompanhamento dos cães;
4. treinamento e evolução técnica;
5. saúde e prontidão operacional;
6. prestação de contas institucional;
7. rastreabilidade de decisões e registros;
8. proteção profissional por meio de informação organizada e verificável.

## Princípio institucional central

Ao projetar um registro relevante, considere:

> Se esse fato precisar ser compreendido meses depois, o sistema preserva contexto suficiente para reconstruí-lo corretamente?

Isso não significa transformar todas as telas em ferramentas de auditoria.

A interface cotidiana deve continuar simples, clara e operacional.

A robustez deve aparecer quando necessária, sem criar burocracia desnecessária para o usuário.

## Fonte da verdade

Sempre priorize, nesta ordem:

1. escopo explícito da tarefa atual;
2. `CLAUDE.md`, `AGENTS.md` e instruções vigentes do projeto;
3. código atual da branch;
4. documentação oficial atual em `docs/`;
5. decisões recentes registradas para a feature;
6. esta skill.

Arquivos em:

```text
temp/
temp/mockups/
temp/docs/
```

são materiais auxiliares ou históricos, salvo quando a tarefa atual os declarar explicitamente como referência vigente.

Nunca faça uma releitura geral de `temp/` por padrão.

Não permita que documentação histórica sobrescreva o comportamento atual validado do sistema.

## Dados mutáveis não pertencem a esta skill

Não mantenha aqui como verdade permanente:

* idade atual de um cão;
* peso atual;
* quantidade atual de cães;
* quantidade atual de operadores;
* branch atual;
* HEAD atual;
* status de implementação de uma fase;
* lista completa de coleções;
* rotas temporárias;
* estado atual da produção;
* backlog atual.

Essas informações devem ser obtidas do código, banco, documentação atual ou contexto da tarefa.

## Identidade do produto

O K9 Ops possui identidade institucional própria.

Diretrizes atuais:

* base dark navy / azul petróleo;
* ciano como identidade primária;
* cores semânticas para estados importantes;
* profundidade visual controlada;
* glassmorphism discreto quando fizer parte do sistema visual aprovado;
* cantos arredondados;
* aparência premium, profissional e operacional;
* elementos táticos sutis;
* hierarquia visual clara.

Não confunda:

```text
visual tático institucional
```

com:

```text
gamificação militar
```

São coisas diferentes.

A identidade visual aprovada não deve ser removida apenas por uma heurística genérica de simplificação.

## Linguagem

Prefira linguagem:

* clara;
* profissional;
* operacional;
* institucional;
* natural em português do Brasil.

Evite inglês decorativo quando existe termo adequado em português.

Não transforme labels em jargão militar apenas para parecer "tático".

Datas exibidas ao usuário devem seguir o padrão brasileiro quando apropriado ao contexto.

## Gamificação

O K9 Ops não deve introduzir mecanismos competitivos ou lúdicos sem decisão explícita.

Evite por padrão:

* XP;
* ranking de operadores;
* níveis decorativos;
* conquistas competitivas;
* comparação pública de desempenho individual;
* troféus sem função operacional.

Indicadores objetivos de conformidade, progresso técnico ou status operacional podem existir quando representam informação real do domínio.

Não confunda progressão técnica com gamificação.

## Forma segue função

A interface deve ser visualmente forte, mas cada elemento precisa servir ao uso.

Evite:

* ornamento sem função;
* informação repetida;
* ações redundantes;
* densidade desnecessária;
* componentes criados apenas para preencher espaço.

Ao mesmo tempo, não remova decisões visuais aprovadas sob o argumento genérico de "simplificar".

Identidade visual e clareza operacional podem coexistir.

## Escopo das tarefas

Durante uma fase definida:

* implemente apenas o escopo da fase;
* não aproveite para modernizar áreas vizinhas;
* não faça refactors paralelos sem necessidade;
* preserve alterações preexistentes do worktree;
* não limpe arquivos que não pertencem à tarefa;
* reporte descobertas externas ao escopo sem corrigi-las automaticamente.

A menor mudança segura é preferível.

Isso não significa aplicar correção superficial quando a causa raiz estiver em um ponto compartilhado.

## Saúde e Prontidão

O módulo de Saúde deve ser tratado como parte da prontidão operacional do cão, não como um aplicativo genérico para pets.

O conceito atual é de um:

```text
Centro de Saúde e Prontidão K9
```

As decisões vigentes devem ser obtidas da documentação e implementação atuais.

Entre os conceitos já estabelecidos no projeto estão:

* status de prontidão;
* restrições operacionais;
* histórico clínico;
* agenda preventiva;
* impacto operacional das condições de saúde;
* nutrição como domínio relevante;
* registros clínicos e preventivos estruturados.

Não invente regras clínicas, diagnósticos ou critérios de prontidão sem definição de negócio.

## Nutrição

Nutrição é um domínio operacional relevante.

O projeto pode separar:

* planejamento nutricional;
* execução diária;
* acompanhamento de consumo;
* suplementos;
* histórico;
* avaliação de evolução.

Respeite a arquitetura atual.

Não recrie um modelo antigo apenas porque existe referência histórica em `temp/`.

Quando o plano alimentar for gerenciado por outro sistema ou módulo, preserve essa separação.

## Treinamento

Treinamento deve preservar:

* progressão real;
* contexto das sessões;
* avaliações;
* decisões técnicas;
* histórico;
* rastreabilidade suficiente.

Não introduza gamificação em substituição à progressão técnica.

Quando houver matriz, módulos, marcos, avaliações ou promoções, respeite o modelo atual do projeto.

## Turnos e operação

Fluxos operacionais devem representar atos reais distintos.

Não una ações diferentes apenas para reduzir telas ou código.

Exemplo de princípio já estabelecido no projeto:

```text
assumir uma função ou posto operacional
```

não é automaticamente equivalente a:

```text
associar um cão ao turno
```

Ao modificar fluxos operacionais, preserve as distinções reais do domínio.

Não assuma que um operador sempre estará com um K9 ativo.

## Ocorrências

Registros de ocorrência devem priorizar:

* reconstrução cronológica;
* autoria;
* contexto operacional;
* clareza institucional;
* integridade dos dados;
* informações necessárias para prestação de contas.

Não introduza campos ou etapas apenas para tornar o formulário mais completo.

Cada informação solicitada deve ter função operacional, administrativa ou documental clara.

## Coexistência mobile e web

Mudanças em dados compartilhados devem considerar todos os consumidores atuais.

Antes de alterar Firestore:

* consulte `firestore-coexistence`;
* verifique o código atual;
* identifique consumidores;
* preserve compatibilidade;
* não presuma que um consumidor está inativo ou irrelevante.

Mobile e web fazem parte do mesmo ecossistema.

Uma mudança local pode ter impacto global.

## Auditoria

Rastreabilidade é um requisito institucional importante.

A implementação concreta deve seguir a arquitetura atual.

Consulte:

```text
audit-trail
```

quando a tarefa envolver:

* edição de registros críticos;
* exclusão;
* restauração;
* cancelamento;
* histórico de alterações;
* integridade documental;
* autoria de ações relevantes.

Não crie um mecanismo paralelo de auditoria sem verificar o que já existe.

## Firestore e dados históricos

O K9 Ops possui dados produzidos por versões diferentes do sistema.

Ao trabalhar com leitura e parsing:

* considere campos ausentes;
* considere valores legados;
* preserve dados desconhecidos quando necessário;
* não transforme valores inválidos em valores conhecidos incorretos;
* use parsers defensivos quando o domínio exigir compatibilidade histórica.

Mudanças destrutivas de schema devem seguir `firestore-coexistence`.

## Decisões técnicas

Não introduza tecnologia, biblioteca ou padrão novo sem necessidade real.

Antes de criar algo novo:

1. verifique se já existe solução equivalente;
2. entenda o fluxo atual;
3. reutilize o padrão existente quando adequado;
4. faça a menor mudança segura.

Não preserve arquitetura ruim apenas por medo de alterar código.

Mas também não refatore uma área inteira para resolver uma tarefa localizada.

## Como decidir quando houver dúvida

Antes de perguntar ao usuário:

1. inspecione o código diretamente relacionado;
2. consulte a documentação oficial vigente;
3. procure decisões recentes do mesmo módulo;
4. verifique o comportamento já validado;
5. examine consumidores diretamente afetados.

Pergunte apenas quando persistir uma ambiguidade real de produto ou regra de negócio que não possa ser resolvida objetivamente.

Não faça auditoria geral do projeto para responder uma dúvida localizada.

## Mockups e especificações antigas

Mockups são referências de implementação quando explicitamente definidos como vigentes.

Não trate automaticamente todo arquivo em `temp/mockups/` como fonte atual.

Quando houver conflito, priorize:

```text
decisão mais recente aprovada
↓
código atual validado
↓
documentação oficial vigente
↓
mockup vigente
↓
material histórico
```

Para implementação explicitamente baseada em mockup, consulte:

```text
flutter-visual-fidelity
```

## Estado do worktree

Antes de iniciar alterações relevantes:

* identifique arquivos já modificados;
* preserve trabalho preexistente;
* não atribua alterações antigas à tarefa atual;
* não faça cleanup automático.

O projeto frequentemente possui trabalhos em paralelo.

Separação de escopo é obrigatória.

## Validação

Não declare uma tarefa concluída apenas porque o código compila mentalmente.

Execute as validações apropriadas ao escopo.

Exemplos:

```text
format
analyze
tests
build
git diff --check
validação visual
validação autenticada
```

Nem todas são necessárias em toda tarefa.

Informe claramente o que foi realmente executado.

## Regra final

O K9 Ops deve ser desenvolvido como um produto operacional real, não como um projeto demonstrativo.

Toda decisão deve equilibrar:

```text
correção
clareza
segurança
rastreabilidade
experiência operacional
compatibilidade
manutenibilidade
escopo
```

O objetivo não é construir a solução mais complexa.

Também não é construir a solução mais curta.

É construir a menor solução segura, correta e coerente com o K9 Ops atual.
