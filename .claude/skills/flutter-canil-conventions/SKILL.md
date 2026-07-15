---

name: flutter-canil-conventions
description: Convenções estáveis de desenvolvimento Flutter do projeto K9 Ops. Define disciplina de escopo, organização, nomenclatura, integração com o código existente e validações mínimas. Não substitui a leitura da implementação atual da feature.
alwaysApply: true
-----------------

# Convenções Flutter · K9 Ops

## Princípio principal

**Siga o padrão real já existente no projeto antes de criar um padrão novo.**

Esta skill contém convenções transversais do K9 Ops.

Ela não deve ser usada para impor uma arquitetura imaginada sobre código que já possui um padrão válido e estabelecido.

Quando houver diferença entre esta skill e a implementação atual, investigue antes de alterar.

## Hierarquia de autoridade

Em caso de conflito, siga esta ordem:

1. escopo explícito da tarefa atual;
2. `CLAUDE.md`, `AGENTS.md` e demais instruções vigentes;
3. código atual da branch;
4. documentação oficial atual em `docs/`;
5. decisões recentes registradas para a feature;
6. esta skill;
7. documentos e especificações históricas.

Não use arquivos de `temp/` como fonte de verdade por padrão.

## Antes de editar

Faça um preflight proporcional à tarefa.

No mínimo, quando trabalhando em Git:

```bash
git branch --show-current
git status --short
```

Quando relevante, confirme também:

```bash
git rev-parse HEAD
git diff --stat
git diff --check
```

Antes de alterar arquivos:

* identifique modificações preexistentes;
* preserve trabalho que já estava no worktree;
* não atribua alterações antigas à tarefa atual;
* não limpe arquivos fora do escopo;
* não faça reset, checkout destrutivo ou restore sem autorização.

## Disciplina de escopo

Durante uma tarefa:

1. entenda o fluxo real afetado;
2. localize os arquivos responsáveis;
3. trace a causa raiz quando houver bug;
4. faça a menor mudança segura que resolva o problema completo;
5. não refatore áreas vizinhas apenas porque poderiam ficar melhores;
6. reporte descobertas externas ao escopo sem corrigi-las automaticamente.

"Menor mudança" não significa corrigir apenas o sintoma.

Quando a causa raiz estiver em um ponto compartilhado, prefira corrigir o ponto correto em vez de espalhar tratamentos pelos consumidores.

## Organização do projeto

O projeto é organizado principalmente por domínio e feature.

Estrutura geral comum:

```text
lib/
├── core/
└── features/
    └── <feature>/
        ├── data/
        ├── domain/
        └── presentation/
```

Subestruturas podem variar conforme a feature.

Antes de criar novas pastas:

1. observe a organização da feature atual;
2. procure uma feature equivalente;
3. siga o padrão real do projeto.

Não crie camadas vazias apenas para cumprir um diagrama arquitetural.

## `core/`

Use `core/` para recursos realmente compartilhados.

Exemplos possíveis:

```text
core/services/
core/theme/
core/utils/
core/widgets/
```

Não mova código para `core/` apenas porque ele poderia ser reutilizado no futuro.

Extraia quando:

* a reutilização for real;
* o componente representar uma responsabilidade transversal;
* o projeto já possuir um padrão compartilhado equivalente.

## Nomenclatura Dart

Siga as convenções do projeto e do Dart:

```text
arquivos       → snake_case.dart
classes        → PascalCase
variáveis      → camelCase
métodos        → camelCase
constantes     → camelCase
```

Não renomeie arquivos, classes ou símbolos fora do escopo apenas para padronizar.

## Vocabulário de domínio

Use os nomes já estabelecidos pelo projeto.

Não crie domínios paralelos por variação terminológica.

Antes de introduzir nomes como:

```text
incident
incidents
occurrence
occurrences
```

verifique qual vocabulário o código atual utiliza.

A mesma regra vale para:

* health;
* training;
* shifts;
* nutrition;
* dogs;
* readiness;
* demais módulos.

Vocabulário inconsistente pode gerar:

* rotas paralelas;
* coleções duplicadas;
* services redundantes;
* models incompatíveis.

## Gerenciamento de estado

Use o padrão já adotado pela feature.

Quando a área existente utilizar Provider/ChangeNotifier, preserve o padrão salvo decisão explícita em contrário.

Não introduza outro gerenciador de estado para resolver uma alteração localizada.

Não crie ViewModel apenas porque a estrutura da pasta possui `viewmodels/`.

Crie-o quando existir responsabilidade real de:

* estado;
* coordenação;
* carregamento;
* transformação;
* interação com serviços.

## Widgets

Não imponha `StatelessWidget` ou `StatefulWidget` universalmente.

Escolha conforme a necessidade real e o padrão existente.

Use:

* `StatelessWidget` quando não houver estado local mutável;
* `StatefulWidget` quando houver ciclo de vida ou estado local apropriado;
* widgets consumidores conforme o padrão atual da biblioteca de estado utilizada.

Não converta widgets sem necessidade apenas por preferência arquitetural.

## Models

Ao trabalhar com models:

* preserve compatibilidade com dados históricos;
* siga a nomenclatura vigente;
* mantenha parsing defensivo quando necessário;
* preserve valores desconhecidos quando o domínio exigir;
* não transforme valor inválido em valor conhecido incorreto.

Não imponha universalmente:

```text
fromMap()
toMap()
```

se a implementação atual utilizar outro padrão válido.

Quando existirem esses métodos, mantenha a conversão coerente com o contrato atual.

## Firestore ↔ Dart

Quando o projeto utilizar:

```text
snake_case no Firestore
camelCase no Dart
```

preserve a conversão.

Exemplo conceitual:

```dart
class ExampleModel {
  final String activeDogId;

  const ExampleModel({
    required this.activeDogId,
  });

  factory ExampleModel.fromMap(Map<String, dynamic> map) {
    return ExampleModel(
      activeDogId: map['active_dog_id'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'active_dog_id': activeDogId,
    };
  }
}
```

Esse é um exemplo de convenção, não uma obrigação de estrutura para todos os models.

## Parsing defensivo

Dados históricos podem conter:

* campos ausentes;
* `null`;
* tipos legados;
* enums desconhecidos;
* timestamps em representações diferentes.

Quando necessário, diferencie corretamente:

```text
known
unknown
absent
```

Não faça fallback para um valor conhecido apenas para evitar erro de parsing.

Um valor desconhecido continua sendo desconhecido.

## IDs

Use a estratégia de identificação já definida pelo domínio.

Não imponha UUID universalmente.

IDs podem ser:

* gerados pelo Firestore;
* determinísticos;
* baseados na entidade;
* UUID;
* provenientes de outro sistema.

Não altere a estratégia de IDs sem necessidade explícita.

## Firestore

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

Quando a operação envolver rastreabilidade crítica, consulte também:

```text
audit-trail
```

Não crie schema novo baseado apenas em exemplos antigos.

## Repositories e services

Antes de criar um novo repository ou service:

1. procure implementação equivalente;
2. determine a responsabilidade real;
3. evite duplicar acesso ao mesmo domínio;
4. preserve a fonte canônica atual.

Não crie uma camada que apenas repasse uma chamada sem agregar responsabilidade real.

Ao mesmo tempo, não coloque acesso Firestore diretamente em widgets quando a feature já possui camada própria para isso.

## Navegação

Use o mecanismo já adotado pela área atual.

Não crie nova solução de roteamento para uma alteração localizada.

Antes de adicionar ou modificar navegação:

* encontre telas equivalentes;
* siga o padrão atual;
* preserve back navigation;
* preserve parâmetros;
* preserve valores de retorno quando existirem.

Não altere a navegação global fora do escopo da tarefa.

## Widgets compartilhados

Antes de criar um novo componente:

1. procure componente equivalente;
2. reutilize quando semanticamente adequado;
3. estenda apenas quando isso não prejudicar consumidores existentes.

Extraia um widget compartilhado quando houver reutilização real ou quando ele representar elemento consistente do design system.

Não utilize uma regra rígida como:

```text
apareceu 3 vezes → extrair obrigatoriamente
```

A decisão depende da responsabilidade do componente.

## UI e tema

Utilize os tokens e componentes atuais do projeto.

Prefira:

```text
AppColors
AppTheme
componentes compartilhados
estilos existentes
```

a valores hardcoded quando existir token correspondente.

Não altere identidade visual global durante implementação localizada.

Não substitua componentes aprovados por Material Design padrão apenas por conveniência.

## Mockups

Para implementação explicitamente baseada em uma referência visual vigente, consulte:

```text
flutter-visual-fidelity
```

Não presuma que todo mockup em `temp/` continua atual.

Decisões recentes e comportamento validado prevalecem sobre material histórico.

## Dependências

Antes de adicionar um pacote:

1. verifique se o projeto já possui solução equivalente;
2. confirme se Dart, Flutter ou Firebase já oferecem o recurso;
3. avalie impacto de manutenção;
4. adicione somente quando houver benefício real.

Não:

* adicione dependência especulativa;
* troque biblioteca existente fora do escopo;
* remova dependência como limpeza paralela.

## Assincronismo

Ao trabalhar com código assíncrono:

* trate erros relevantes;
* evite estados inconsistentes;
* respeite o ciclo de vida dos widgets;
* verifique uso de `BuildContext` após `await`;
* utilize `mounted` quando necessário;
* evite notificações após descarte;
* evite subscriptions duplicadas.

## Controllers e listeners

Quando criar:

```text
TextEditingController
AnimationController
ScrollController
StreamSubscription
listener
```

garanta descarte quando necessário.

Não crie listeners duplicados para o mesmo estado sem motivo.

## Firestore listeners

Antes de adicionar um novo listener em tempo real:

* verifique se já existe stream equivalente;
* determine quem controla o ciclo de vida;
* evite múltiplas assinaturas desnecessárias;
* preserve cancelamento correto.

Não substitua leitura pontual por stream sem requisito real de atualização em tempo real.

## Tratamento de erros

Não silencie exceções críticas.

Quando aplicável, diferencie:

```text
loading
empty
error
success
```

Mensagens ao usuário devem ser compreensíveis.

Logs devem ajudar o diagnóstico sem expor:

* tokens;
* dados sensíveis;
* credenciais;
* informações pessoais desnecessárias.

## Segurança

Não mova validações críticas apenas para a interface.

Quando uma regra precisar ser garantida independentemente do cliente, verifique a camada adequada:

* Firestore Rules;
* Cloud Functions;
* backend;
* transação.

Não presuma que ocultar um botão impede uma operação.

## Performance

Otimize com evidência.

Use `const` quando natural e seguro.

Evite problemas claros como:

* rebuilds desnecessários;
* listeners duplicados;
* queries repetidas sem motivo;
* processamento pesado dentro de `build`;
* carregamento repetitivo do mesmo recurso.

Não faça micro-otimizações fora do escopo.

## Código legado

Não modernize código legado automaticamente.

Se ele estiver funcionando e não fizer parte da tarefa:

* preserve;
* reporte problema relevante;
* não refatore apenas por preferência.

Se o legado for a causa raiz do problema atual, corrija somente o necessário.

## Compatibilidade

Não altere API interna utilizada por múltiplas features sem identificar consumidores.

Antes de mudar:

```text
assinatura de método
model
service
repository
widget compartilhado
campo Firestore
```

procure usos relevantes.

Mudanças compartilhadas exigem validação proporcional ao alcance.

## Formatação

Formate apenas os arquivos relevantes sempre que possível.

Exemplo:

```bash
dart format lib/features/health/...
```

Evite formatar o projeto inteiro durante uma alteração localizada se isso gerar diffs desnecessários.

## Validação

Após alterações, execute a matriz apropriada ao escopo.

Exemplos:

```bash
dart format <arquivos alterados>
flutter analyze
flutter test
git diff --check
```

Dependendo da tarefa também podem ser necessárias:

* validação visual;
* teste manual;
* teste autenticado;
* build;
* teste específico da feature.

Não afirme que uma validação passou sem executá-la.

Se uma validação não puder ser feita, informe claramente.

## Warnings preexistentes

Não atribua warnings antigos à alteração atual.

Quando houver falha de validação:

1. determine se foi causada pela mudança;
2. identifique se é preexistente;
3. reporte separadamente.

Não corrija todo warning antigo apenas para deixar a saída limpa, salvo se isso fizer parte do escopo.

## Commits

Não faça commit automaticamente salvo quando:

* a tarefa pedir explicitamente;
* o workflow atual autorizar claramente essa etapa.

Antes de commit:

* confira `git status`;
* confira o diff;
* confirme que apenas arquivos do escopo serão incluídos.

Não inclua arquivos preexistentes por acidente.

## Finalização da tarefa

Reporte objetivamente:

```text
Branch / estado relevante

Arquivos alterados

O que mudou

Decisões relevantes

Validações executadas

Pendências ou riscos
```

Não apresente como trabalho da sessão arquivos que já estavam modificados antes.

Não declare produção atualizada quando somente código local foi alterado.

## Regra final

**Consistência com o K9 Ops atual vence preferência pessoal.**

Leia o fluxo real.

Preserve o escopo.

Respeite o código existente.

Corrija a causa raiz.

Faça apenas a menor mudança segura necessária para entregar uma solução completa.
