---

name: flutter-visual-fidelity
description: Implementa ou ajusta interfaces Flutter a partir de mockups, screenshots ou especificações visuais explicitamente definidos como referência vigente. Use quando a tarefa exigir fidelidade visual. Decisões mais recentes, código validado e design system atual sempre prevalecem sobre artefatos históricos.
disable-model-invocation: true
------------------------------

# Fidelidade Visual · K9 Ops

## Objetivo

Esta skill existe para traduzir uma referência visual aprovada para Flutter com alta fidelidade, preservando:

* identidade visual;
* hierarquia;
* composição;
* proporções;
* espaçamentos;
* tipografia;
* cores;
* estados;
* responsividade;
* comportamento real da interface.

A referência visual orienta a implementação.

Ela não substitui a arquitetura, o design system ou as decisões mais recentes do projeto.

## Quando usar

Use esta skill quando a tarefa indicar explicitamente uma referência visual vigente, como:

* mockup HTML;
* screenshot aprovado;
* imagem de referência;
* protótipo;
* especificação visual atual.

Não aplique automaticamente esta skill a qualquer tarefa de frontend.

Não presuma que todo arquivo dentro de:

```text
temp/
temp/mockups/
temp/docs/
```

continua vigente.

## Hierarquia de autoridade

Quando houver conflito visual, siga esta ordem:

1. decisão mais recente explicitamente aprovada;
2. comportamento atual validado;
3. código atual da branch;
4. design system e tokens vigentes;
5. documentação oficial atual;
6. referência visual explicitamente indicada na tarefa;
7. material histórico.

Um mockup antigo nunca deve sobrescrever silenciosamente uma decisão posterior já validada.

## Princípio fundamental

**Reproduza a intenção visual aprovada, não apenas pixels isolados.**

Fidelidade significa preservar:

```text
hierarquia
ritmo
densidade
contraste
proporção
identidade
```

sem comprometer:

```text
responsividade
acessibilidade
safe areas
conteúdo dinâmico
comportamento real
```

## Antes de implementar

### 1. Identifique a referência correta

Abra apenas os arquivos relacionados à tarefa.

Não faça auditoria geral de todos os mockups.

Confirme:

* qual tela está sendo implementada;
* qual versão da referência é vigente;
* se existem decisões posteriores à referência.

### 2. Leia a implementação atual

Antes de escrever código:

* abra a tela atual;
* identifique widgets compartilhados;
* identifique tokens;
* identifique componentes reutilizáveis;
* identifique comportamento já funcionando.

Não recrie do zero uma tela funcional apenas porque existe um mockup HTML.

### 3. Identifique o sistema visual

Extraia da referência:

* estrutura geral;
* alinhamentos;
* espaçamentos;
* larguras;
* alturas;
* radius;
* bordas;
* cores;
* tipografia;
* iconografia;
* agrupamentos;
* estados visuais;
* hierarquia de informação.

Diferencie valores realmente intencionais de medidas específicas do navegador usado para produzir o mockup.

## Identidade visual do K9 Ops

Preserve a identidade vigente do produto.

Diretrizes atuais incluem:

* base dark navy / azul petróleo;
* ciano como identidade primária;
* verde para estados positivos e operacionais;
* amarelo para atenção;
* vermelho para estados críticos ou restrições;
* profundidade visual controlada;
* glassmorphism discreto quando aprovado;
* cantos arredondados;
* contraste claro;
* aparência premium e operacional;
* elementos táticos sutis.

Não substitua essa identidade por Material Design padrão apenas por conveniência.

Não remova elementos visuais aprovados com base em heurísticas genéricas externas.

## Tokens antes de hardcode

Antes de escrever:

```dart
const Color(0xFF4DD0E1)
```

verifique se já existe algo como:

```dart
AppColors.k9Primary
```

Prefira tokens existentes quando representarem corretamente a referência.

Faça o mesmo para:

* cores;
* radius;
* espaçamentos;
* tipografia;
* sombras;
* componentes.

Hardcode apenas valores realmente específicos da tela quando não houver token equivalente.

## Tradução CSS → Flutter

## Fundo, borda e radius

HTML:

```css
background: #050d10;
border: 1px solid rgba(77, 208, 225, 0.2);
border-radius: 14px;
```

Flutter:

```dart
Container(
  decoration: BoxDecoration(
    color: AppColors.k9Background,
    border: Border.all(
      color: AppColors.k9Primary.withValues(alpha: 0.2),
    ),
    borderRadius: BorderRadius.circular(14),
  ),
  child: child,
)
```

Não use:

```dart
Container(
  color: AppColors.k9Background,
  decoration: BoxDecoration(...),
)
```

Quando houver `decoration`, coloque a cor dentro do `BoxDecoration`.

## Espaçamentos

HTML:

```css
padding: 16px 20px;
```

Flutter:

```dart
padding: const EdgeInsets.symmetric(
  vertical: 16,
  horizontal: 20,
),
```

HTML:

```css
margin: 8px 0 14px;
```

Flutter:

```dart
margin: const EdgeInsets.only(
  top: 8,
  bottom: 14,
),
```

Preserve os valores quando forem decisões visuais reais.

Adapte quando necessário para:

* safe area;
* telas menores;
* teclado;
* conteúdo variável;
* text scaling.

## Flex horizontal

HTML:

```css
display: flex;
align-items: center;
gap: 8px;
```

Flutter:

```dart
Row(
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    first,
    const SizedBox(width: 8),
    second,
  ],
)
```

## Flex vertical

HTML:

```css
display: flex;
flex-direction: column;
gap: 12px;
```

Flutter:

```dart
Column(
  children: [
    first,
    const SizedBox(height: 12),
    second,
  ],
)
```

Use APIs mais recentes de `spacing` somente se a versão Flutter do projeto suportar e o padrão atual já utilizar esse recurso.

## Distribuição horizontal

HTML:

```css
justify-content: space-between;
```

Flutter:

```dart
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    first,
    second,
  ],
)
```

## Duas colunas

Não converta automaticamente todo grid HTML em `GridView`.

Para poucos elementos:

```dart
Row(
  children: [
    Expanded(child: first),
    const SizedBox(width: 8),
    Expanded(child: second),
  ],
)
```

pode ser mais adequado.

Para coleções maiores ou conteúdo repetido, use o widget mais apropriado ao comportamento real.

## Elementos sobrepostos

HTML:

```css
position: absolute;
bottom: 0;
left: 0;
right: 0;
```

Flutter:

```dart
Stack(
  children: [
    background,
    Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: foreground,
    ),
  ],
)
```

Use `Stack` somente quando a sobreposição fizer parte real da composição.

Não use posicionamento absoluto para compensar uma estrutura de layout incorreta.

## Conteúdo fixo na parte inferior

Para CTAs persistentes, avalie o comportamento real da tela.

Possíveis padrões:

```dart
Scaffold(
  body: content,
  bottomNavigationBar: bottomAction,
)
```

ou:

```dart
Column(
  children: [
    Expanded(
      child: SingleChildScrollView(
        child: content,
      ),
    ),
    bottomAction,
  ],
)
```

Não traduza `position: sticky` do CSS literalmente sem considerar o comportamento Flutter.

## Cores e opacidade

Prefira:

```dart
AppColors.k9Primary.withValues(alpha: 0.2)
```

quando a versão Flutter do projeto utilizar essa API.

Se o projeto atual ainda usar `withOpacity`, siga o padrão existente.

Não modernize todas as chamadas fora do escopo apenas para padronizar.

## Tipografia

Preserve:

* tamanho relativo;
* peso;
* altura de linha;
* espaçamento entre letras;
* contraste;
* hierarquia.

Exemplo:

```dart
Text(
  'Título',
  style: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    height: 1.4,
    color: AppColors.k9TextPrimary,
  ),
)
```

Antes de criar um `TextStyle` completo, verifique se existe estilo equivalente no tema atual.

Não introduza uma nova fonte apenas porque o HTML de referência utilizava outra, se o aplicativo já possui sistema tipográfico definido.

## Cards

Use cards quando fizerem parte da estrutura aprovada.

Não substitua automaticamente cards existentes por estruturas mais "minimalistas".

Ao reproduzir um card, observe:

* contraste com o fundo;
* border;
* radius;
* padding;
* alinhamento interno;
* hierarquia;
* estado semântico.

Evite adicionar sombra Material padrão quando a identidade do K9 Ops utiliza profundidade diferente.

## Glassmorphism

Quando a referência vigente utilizar glassmorphism:

* preserve com moderação;
* reutilize o padrão atual;
* evite blur excessivo;
* mantenha legibilidade;
* valide performance.

Não remova glassmorphism apenas porque outra guideline genérica o desencoraja.

Também não adicione vidro decorativo onde a referência não pede.

## Gradientes

Use gradientes somente quando fizerem parte da identidade ou referência aprovada.

Exemplo:

```dart
Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        AppColors.k9Primary.withValues(alpha: 0.08),
        AppColors.k9Operational.withValues(alpha: 0.04),
      ],
    ),
  ),
)
```

Evite introduzir gradientes como decoração genérica.

## Bordas semânticas

Se a referência utilizar uma borda lateral como código visual aprovado, ela pode ser reproduzida.

Exemplo:

```dart
Container(
  decoration: const BoxDecoration(
    border: Border(
      left: BorderSide(
        color: AppColors.k9Operational,
        width: 3,
      ),
    ),
  ),
  child: child,
)
```

Não remova um padrão visual aprovado apenas porque outra skill genérica considera esse estilo um antipadrão.

## Status e cores semânticas

Use cores de acordo com o significado real.

Exemplos conceituais:

```text
verde    → operacional / positivo
amarelo  → atenção
vermelho → crítico / restrição
ciano    → ação ou identidade principal
```

Não use cor semântica apenas como decoração.

## Responsividade

O mockup representa uma referência visual, não necessariamente todos os dispositivos.

A implementação deve funcionar em diferentes condições.

Valide:

* telas estreitas;
* telas maiores;
* textos longos;
* valores grandes;
* nomes extensos;
* escalonamento de fonte;
* teclado aberto;
* safe areas;
* orientação quando aplicável.

Não preserve uma medida rígida se ela causar overflow real.

## Overflow

Nunca aceite overflow como consequência necessária da fidelidade.

Quando ocorrer:

1. determine qual elemento está excedendo;
2. preserve a hierarquia;
3. adapte o layout;
4. mantenha o resultado visual o mais próximo possível da referência.

Possíveis soluções:

* `Expanded`;
* `Flexible`;
* `Wrap`;
* limite de largura;
* ajuste responsivo;
* quebra de linha;
* scroll quando apropriado.

Não reduza arbitrariamente o tamanho de toda a tipografia para esconder overflow.

## Safe Area

Respeite:

* notch;
* status bar;
* navigation bar;
* gestos do sistema;
* teclado.

Não posicione elementos importantes sob áreas inacessíveis apenas porque o mockup foi produzido sem safe area real.

## Componentes compartilhados

Reutilize componentes existentes quando eles reproduzem corretamente o comportamento e o visual.

Antes de criar:

```text
novo header
novo card
novo badge
novo botão
```

procure equivalente no projeto.

Não force reutilização quando o componente existente possuir semântica diferente.

Não extraia componentes prematuramente apenas para reduzir duplicação mínima.

## Header e navegação

Não implemente automaticamente estruturas globais antigas vistas em mockups históricos.

Antes de reproduzir:

* header;
* bottom navigation;
* FAB;
* app bar;

verifique o padrão atual do aplicativo.

A navegação atual do produto prevalece sobre um mockup antigo.

## Ícones

Prefira:

1. ícone já utilizado pelo projeto;
2. asset oficial;
3. equivalente adequado da biblioteca atual.

Não introduza iconografia decorativa sem função.

Se a referência usar emoji apenas como placeholder visual, não assuma que o produto final também deve usar emoji.

## Imagens

Preserve:

* proporção;
* enquadramento;
* clipping;
* radius;
* posição visual.

Use:

```dart
BoxFit.cover
```

ou outro `BoxFit` apenas conforme a intenção real.

Não distorça imagem para reproduzir uma dimensão fixa do mockup.

## Estados reais

Um mockup normalmente mostra apenas um estado.

A implementação real precisa preservar estados quando aplicáveis:

```text
loading
empty
error
offline
disabled
success
```

Não remova estados já existentes porque eles não aparecem no mockup.

Quando a tela nova precisar deles, siga padrões visuais existentes do projeto.

## Conteúdo dinâmico

Teste mentalmente e, quando possível, visualmente:

* nome curto;
* nome longo;
* zero registros;
* muitos registros;
* valor ausente;
* valor desconhecido;
* texto de erro;
* dados históricos.

Não use conteúdo fake permanente para manter o layout bonito.

## Animações

Implemente apenas animações:

* já existentes no produto;
* explicitamente aprovadas;
* presentes na referência quando ela representar movimento;
* necessárias para clareza de interação.

Não adicione animação decorativa apenas para "dar vida".

Também não remova transições já aprovadas porque um mockup estático não consegue representá-las.

Sempre respeite redução de movimento quando a implementação atual oferecer esse suporte.

## Material Design

Use Flutter e Material como infraestrutura.

Não permita que estilos padrão do Material substituam a identidade visual do K9 Ops.

Evite deixar componentes com aparência padrão quando o design system atual define:

* cor;
* shape;
* padding;
* tipografia;
* estados.

## Acessibilidade

Fidelidade visual não pode eliminar requisitos básicos.

Verifique quando aplicável:

* contraste;
* tamanho de áreas tocáveis;
* labels semânticos;
* text scaling;
* feedback de estado;
* uso de cor como único indicador.

Não faça redesign completo em nome de acessibilidade fora do escopo.

Corrija conflitos objetivos quando encontrados na própria implementação.

## Performance

Evite soluções visuais claramente caras sem necessidade.

Observe especialmente:

* blur excessivo;
* múltiplos `BackdropFilter`;
* listas pesadas;
* imagens grandes sem controle;
* rebuilds desnecessários.

Não remova um efeito aprovado apenas por suspeita de performance.

Meça ou identifique problema concreto quando possível.

## Comparação visual

Depois da implementação, compare a referência com o app real.

Idealmente utilize:

```text
mesma largura aproximada
mesmo estado de dados
mesmo conteúdo
```

Observe:

* posição dos blocos;
* proporção;
* densidade;
* contraste;
* spacing;
* tipografia;
* bordas;
* alinhamentos.

Não declare fidelidade visual apenas porque os mesmos componentes existem.

## Validação recomendada

Quando as ferramentas permitirem:

1. abra a referência;
2. execute o aplicativo;
3. navegue até a tela;
4. use dimensões comparáveis;
5. capture screenshots;
6. compare lado a lado;
7. ajuste diferenças relevantes.

Pixel-perfect absoluto não é obrigatório quando diferenças de plataforma justificarem adaptação.

O resultado final deve manter a mesma intenção e hierarquia visual.

## Quando a referência parecer errada

Não altere silenciosamente.

Primeiro determine se:

```text
a referência está desatualizada
```

ou:

```text
a implementação atual divergiu indevidamente
```

Consulte:

* decisões recentes;
* código validado;
* documentação oficial vigente.

Quando existir uma divergência real de produto que não possa ser resolvida objetivamente, reporte a diferença.

## O que não fazer

Não:

* ler todos os mockups do projeto sem necessidade;
* recriar componente compartilhado sem procurar equivalente;
* substituir navegação atual por estrutura histórica;
* copiar CSS literalmente quando a plataforma exige adaptação;
* hardcodar todas as cores ignorando tokens;
* introduzir animações decorativas;
* simplificar a referência sem motivo;
* "modernizar" uma tela aprovada durante implementação;
* remover identidade visual em nome de guidelines genéricas;
* aceitar overflow para manter medidas rígidas.

## Checklist final

Antes de concluir:

* [ ] A referência correta foi utilizada.
* [ ] Nenhuma decisão recente foi substituída por material antigo.
* [ ] A implementação atual foi lida antes das alterações.
* [ ] Componentes existentes foram considerados.
* [ ] Tokens atuais foram reutilizados quando aplicável.
* [ ] Hierarquia visual foi preservada.
* [ ] Espaçamentos estão coerentes.
* [ ] Tipografia está coerente.
* [ ] Cores semânticas mantêm seu significado.
* [ ] Não existem overflows evidentes.
* [ ] Safe areas foram respeitadas.
* [ ] Estados funcionais foram preservados.
* [ ] Responsividade foi considerada.
* [ ] A comparação visual foi realizada quando possível.
* [ ] Nenhuma alteração fora do escopo foi introduzida.

## Regra final

**Reproduza a intenção visual aprovada sem transformar um mockup histórico em autoridade absoluta.**

A melhor implementação é aquela que parece pertencer ao mesmo produto da referência, mas continua funcionando corretamente no K9 Ops real.
