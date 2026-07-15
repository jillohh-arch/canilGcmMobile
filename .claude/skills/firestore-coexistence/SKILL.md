---

name: firestore-coexistence
description: Regras obrigatórias de compatibilidade para alterações no Firestore compartilhado pelo ecossistema K9 Ops. Use antes de criar, modificar, renomear, remover ou reinterpretar campos, coleções, subcoleções, tipos, regras de segurança, índices ou operações que possam afetar dados compartilhados entre mobile, web e backend.
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Coexistência Firestore · K9 Ops

## Por que existe

O K9 Ops possui múltiplos consumidores que podem acessar os mesmos dados.

Entre eles podem existir:

* aplicativo mobile Flutter;
* plataforma web;
* Cloud Functions;
* relatórios;
* rotinas administrativas;
* integrações futuras;
* dados históricos produzidos por versões anteriores.

Uma alteração aparentemente local pode quebrar outro fluxo do sistema.

Por isso, qualquer mudança no contrato de dados deve considerar o ecossistema inteiro.

## Regra principal

**Nunca altere o contrato do Firestore olhando apenas para o arquivo que está sendo modificado.**

Antes de mudar dados compartilhados:

1. identifique o schema atual;
2. descubra quem lê;
3. descubra quem escreve;
4. verifique dados históricos;
5. determine se a mudança é compatível;
6. planeje migração somente quando necessária.

## Fonte da verdade

Para entender o estado atual do Firestore, priorize:

1. escopo explícito da tarefa atual;
2. código atual da branch;
3. código atual dos demais consumidores disponíveis;
4. `CLAUDE.md`, `AGENTS.md` e instruções vigentes;
5. documentação oficial atual em `docs/`;
6. configuração Firebase atual;
7. esta skill;
8. documentos e especificações históricas.

Não use listas antigas de coleções ou consumidores como fonte definitiva.

Não presuma que uma aplicação está inativa, somente leitura ou irrelevante.

Verifique o estado atual.

## Antes de qualquer mudança

Responda mentalmente:

```text
O que está mudando?

Quem lê esse dado?

Quem escreve esse dado?

Existem documentos antigos sem esse campo?

Existem valores legados?

O tipo atual é consistente?

A semântica está mudando?

Rules ou índices serão afetados?

Outro consumidor pode quebrar?

A mudança precisa realmente acontecer no Firestore?
```

A análise deve ser proporcional ao risco.

Uma adição simples não precisa virar uma migração complexa.

Uma quebra de contrato precisa de planejamento.

# Classificação das mudanças

## 1. Mudança aditiva e compatível

Exemplos:

* adicionar campo opcional;
* adicionar nova coleção;
* adicionar nova subcoleção;
* adicionar índice;
* adicionar metadado que consumidores antigos ignoram;
* adicionar novo recurso sem alterar o significado dos dados existentes.

Normalmente é a forma preferida de evolução.

Mesmo assim, verifique:

* conflito de nomes;
* Firestore Rules;
* necessidade de índice;
* comportamento com documentos antigos;
* serialização e parsing.

### Exemplo

Documento antigo:

```text
{
  weight_kg: 29.8
}
```

Documento novo:

```text
{
  weight_kg: 29.8,
  body_condition_score: 5
}
```

Se leitores antigos ignoram `body_condition_score`, a mudança tende a ser compatível.

Isso não elimina a necessidade de verificar Rules e parsers.

---

## 2. Mudança comportamental

A estrutura pode continuar igual, mas o significado ou comportamento muda.

Exemplos:

* um status passa a representar outra coisa;
* um campo antes opcional passa a ser tratado como obrigatório;
* determinada query deixa de considerar certos documentos;
* um valor passa a bloquear uma operação;
* uma regra de segurança passa a impedir uma escrita anteriormente válida;
* a origem canônica de um dado muda.

Essas mudanças podem quebrar consumidores sem alterar nenhum nome de campo.

Trate mudança de semântica como mudança de contrato.

---

## 3. Mudança incompatível ou destrutiva

Exemplos:

* remover campo;
* renomear campo;
* alterar tipo;
* alterar estrutura de objeto;
* transformar string em lista;
* transformar enum em objeto;
* mover dados para outra coleção;
* alterar estratégia de IDs;
* excluir documentos;
* alterar caminho canônico;
* restringir acesso de forma incompatível;
* substituir uma coleção por outra.

Não faça diretamente sem avaliar um rollout compatível.

# Estratégia para mudanças incompatíveis

Quando possível, utilize evolução em fases.

## Fase 1 — Compatibilidade aditiva

Introduza a nova estrutura sem remover imediatamente a antiga.

Exemplo conceitual:

```text
campo_antigo
+
campo_novo
```

Durante a transição, leitores novos podem precisar tolerar ambos.

Exemplo:

```dart
final value =
    map['new_field'] ??
    map['legacy_field'];
```

Esse fallback deve ser temporário quando fizer parte de uma migração.

Não mantenha compatibilidade legada indefinidamente sem necessidade.

## Dual-write

Em alguns casos pode ser necessário escrever temporariamente em:

```text
campo antigo
+
campo novo
```

Só faça dual-write quando realmente necessário.

Ele aumenta o risco de divergência.

Se utilizado:

* defina qual campo é canônico;
* defina quem mantém a sincronização;
* determine quando o dual-write será removido.

Nunca transforme uma solução de migração em arquitetura permanente por acidente.

---

## Fase 2 — Backfill

Quando documentos antigos precisarem receber a nova estrutura, execute uma migração controlada.

Antes de qualquer backfill:

* estime quantidade de documentos;
* identifique casos inconsistentes;
* torne o processo idempotente;
* teste em ambiente seguro ou amostra controlada;
* defina comportamento em caso de falha;
* considere backup quando houver risco relevante;
* registre progresso quando necessário.

Um backfill idempotente deve poder ser executado novamente sem corromper dados.

Exemplo conceitual:

```text
se novo campo não existe
e dado legado válido existe
→ preencher campo novo
```

Não sobrescreva dados novos já existentes sem uma regra explícita.

### Produção

Nunca execute automaticamente:

```text
backfill massivo
migração destrutiva
cleanup irreversível
```

em produção apenas porque o código foi preparado.

A execução precisa fazer parte explicitamente do escopo autorizado.

---

## Fase 3 — Migração dos consumidores

Atualize todos os consumidores relevantes.

Isso pode incluir:

* mobile;
* web;
* Cloud Functions;
* relatórios;
* parsers;
* testes;
* scripts administrativos.

Durante a transição, pode ser necessário ler:

```text
novo
↓ fallback
antigo
```

Depois que a migração estiver validada, remova fallbacks desnecessários.

---

## Fase 4 — Cleanup

Somente remova a estrutura antiga após confirmar:

* consumidores migrados;
* documentos históricos tratados;
* produção observada sem regressões relevantes;
* código legado sem uso;
* documentação atualizada.

Então podem ser removidos:

* campo antigo;
* dual-write;
* fallback;
* migration flags;
* scripts temporários;
* código de compatibilidade.

Não faça cleanup apenas porque a nova implementação já funciona localmente.

# Quando não usar quatro fases

Não force esse processo para mudanças genuinamente aditivas.

Exemplo:

```text
nova subcoleção que nenhum consumidor antigo conhece
```

pode simplesmente ser criada, desde que:

* Rules estejam corretas;
* o contrato esteja definido;
* não exista conflito com estrutura atual.

O objetivo é reduzir risco, não criar burocracia.

# Dados históricos

O K9 Ops possui dados criados por versões diferentes do sistema.

Ao implementar parsers, considere:

* campo ausente;
* valor `null`;
* tipo legado;
* enum desconhecido;
* Timestamp Firestore;
* representação serializada;
* estrutura parcialmente migrada.

Não presuma que todos os documentos possuem o schema mais recente.

## Parsing defensivo

Quando o domínio exigir compatibilidade histórica, prefira distinguir corretamente situações como:

```text
known
unknown
absent
```

em vez de transformar tudo em um valor padrão conhecido.

Exemplo conceitual:

```text
"active" → conhecido

"legacy_custom_value" → desconhecido, raw preservado

campo inexistente → ausente
```

Não invente valores para esconder inconsistências históricas.

# Mudança de tipo

Alterar tipo é uma mudança incompatível mesmo quando o nome do campo permanece igual.

Exemplo:

```text
ANTES
status: "active"
```

```text
DEPOIS
status: {
  code: "active",
  reason: null
}
```

Consumidores antigos continuarão procurando uma string.

Se a mudança for necessária, trate como migração de contrato.

# Campos obrigatórios

Firestore não possui schema rígido por padrão.

Portanto, tornar um campo obrigatório exige atenção.

Antes de assumir que:

```text
campo sempre existe
```

verifique:

* documentos históricos;
* documentos criados por outros consumidores;
* dados parcialmente migrados;
* fixtures e ambientes de teste.

Durante uma transição, o parser pode precisar tolerar ausência.

# Coleções e subcoleções

Não mantenha nesta skill uma lista definitiva de coleções do projeto.

O K9 Ops evolui continuamente.

Antes de criar nova estrutura:

1. procure estrutura equivalente;
2. verifique convenções atuais;
3. identifique consumidores;
4. confirme se o dado pertence realmente àquele domínio.

Não crie duas fontes da verdade para a mesma informação.

# Fonte canônica

Quando mais de uma estrutura representar informação semelhante, determine explicitamente qual é a fonte canônica.

Exemplo conceitual:

```text
active_shifts
```

pode representar estado operacional atual enquanto outra coleção representa histórico.

Não sincronize duas estruturas sem compreender a responsabilidade de cada uma.

Evite soluções em que dois documentos diferentes possam discordar sem regra clara de autoridade.

# Firestore Rules

Mudanças em `firestore.rules` fazem parte do contrato do sistema.

Uma alteração de permissão pode quebrar um fluxo mesmo quando o schema permanece igual.

Antes de modificar Rules:

* identifique quem precisa ler;
* identifique quem precisa escrever;
* valide papéis e permissões;
* verifique operações do mobile;
* verifique operações da web;
* verifique Cloud Functions quando aplicável;
* teste cenários permitidos e negados.

Não assuma:

```text
usuário autenticado = usuário autorizado
```

## Deploy

Alterar o arquivo de Rules não significa que o deploy está autorizado.

Nunca execute deploy automaticamente fora do escopo explícito da tarefa.

Sempre diferencie:

```text
código preparado
```

de:

```text
mudança aplicada em produção
```

# Índices

Novas queries podem exigir índices compostos.

Quando criar ou alterar uma consulta:

* valide a query real;
* identifique necessidade de índice;
* atualize configuração somente quando necessário;
* não crie índices especulativos;
* preserve índices existentes fora do escopo.

Uma query funcionar em poucos dados não garante que o contrato esteja completo.

# Cloud Functions

Considere lógica server-side quando houver necessidade real de:

* autoridade;
* segredo;
* atomicidade entre múltiplos recursos;
* validação que não pode depender do cliente;
* processamento confiável fora do ciclo de vida do aplicativo;
* operação administrativa privilegiada.

Não mova lógica para Cloud Functions automaticamente sob o argumento genérico de segurança.

Primeiro determine o requisito real.

# Operações em múltiplos documentos

Quando uma ação precisar manter consistência entre vários documentos, avalie o mecanismo adequado:

* transaction;
* batch;
* Cloud Function;
* operação idempotente;
* reconciliação posterior.

A escolha depende do domínio.

Não use batch apenas porque existem múltiplas escritas.

Não use transaction quando não houver dependência de leitura consistente.

# Auditoria

Quando uma mudança afetar registros institucionais relevantes, consulte:

```text
audit-trail
```

Não crie um segundo sistema de auditoria durante uma migração.

Mudanças de schema da própria auditoria também devem seguir estas regras de coexistência.

# Mobile e web

Mobile e web fazem parte do mesmo ecossistema.

Antes de concluir que uma mudança é segura:

* procure leituras do campo;
* procure escritas do campo;
* procure queries baseadas nele;
* procure parsers;
* procure Functions;
* procure relatórios relevantes.

Não presuma que um consumidor não utiliza um campo apenas porque ele não apareceu no primeiro arquivo consultado.

Também não faça auditoria geral de todo o repositório sem necessidade.

Pesquise proporcionalmente ao impacto da mudança.

# Mudanças de estado operacional

Alguns dados representam estado atual e possuem alto acoplamento entre fluxos.

Exemplos podem incluir:

* turno ativo;
* equipe;
* viatura;
* associação de K9;
* progressão de treinamento;
* prontidão.

Antes de mudar esses contratos, trace o fluxo real de leitura e escrita.

Não una conceitos distintos apenas para simplificar schema.

# Operações perigosas

Nunca execute automaticamente sem autorização explícita:

```text
delete massivo
backfill em produção
remoção de campo em massa
migração irreversível
deploy de Rules
deploy de Functions
alteração destrutiva de dados reais
```

Preparar:

```text
script
migration
rules
function
```

não autoriza executar.

# Checklist antes de alterar Firestore

Confirme:

* [ ] O schema atual foi verificado.
* [ ] A mudança foi classificada.
* [ ] Consumidores relevantes foram identificados.
* [ ] Leituras e escritas foram consideradas.
* [ ] Dados históricos foram considerados.
* [ ] Tipos legados foram considerados.
* [ ] A fonte canônica continua clara.
* [ ] Rules foram avaliadas.
* [ ] Índices foram avaliados.
* [ ] Migração foi criada apenas se necessária.
* [ ] Nenhum dual-write permanente foi introduzido por acidente.
* [ ] Nenhuma operação de produção foi executada sem autorização.
* [ ] A mudança permaneceu dentro do escopo da fase atual.

# Formato de reporte

Quando uma tarefa alterar o contrato de dados, reporte objetivamente:

```text
Tipo da mudança:
Consumidores afetados:
Compatibilidade:
Dados históricos:
Migração necessária:
Rules:
Índices:
Deploy realizado:
Risco residual:
```

Não afirme que houve deploy quando apenas arquivos locais foram alterados.

# Regra final

**Compatibilidade é uma propriedade do ecossistema inteiro, não apenas do schema.**

Faça a menor mudança segura que preserve:

```text
dados atuais
dados históricos
mobile
web
backend
regras de segurança
comportamento já validado
```

Nunca quebre um consumidor silenciosamente para simplificar outro.
