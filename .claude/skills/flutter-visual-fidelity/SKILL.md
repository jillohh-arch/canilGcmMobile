---
name: flutter-visual-fidelity
description: Converte mockups HTML em widgets Flutter com fidelidade visual precisa. Use quando implementar telas a partir de arquivos HTML em temp/mockups/, traduzir CSS em Theme/widgets Flutter, garantir que paleta de cores, espaçamentos, bordas, tipografia e hierarquia visual do mockup sejam reproduzidos no código Dart. Inclui padrões de tradução CSS-Flutter, decisões de quando usar Container vs DecoratedBox, e princípios de qualidade visual.
---

# Fidelidade Visual · Mockup HTML → Flutter

## Princípio fundamental

Os mockups em `temp/mockups/*.html` definem **exatamente** como cada tela deve ficar. 
Sua tarefa é **reproduzir essa visualização em Flutter** com fidelidade.

Não improvise. Não simplifique. Não "modernize". O mockup já foi pensado.

## Workflow correto

Quando for implementar uma tela:

1. **Abra o mockup HTML** correspondente (ex: `temp/mockups/10_dashboard.html`)
2. **Identifique a estrutura** (header, body, sections, cards)
3. **Extraia os valores** (cores, espaçamentos, tamanhos, bordas)
4. **Traduza pra Flutter** mantendo proporções
5. **Valide visualmente** comparando lado a lado

## Tradução CSS → Flutter (cheat sheet)

### Cores

```css
/* HTML/CSS */
background: #050d10;
color: #4dd0e1;
border-color: rgba(77, 208, 225, 0.2);
```

```dart
// Flutter
Container(
  color: AppColors.k9Background,  // #050d10
  child: Text(
    '...',
    style: TextStyle(color: AppColors.k9Primary),  // #4dd0e1
  ),
  decoration: BoxDecoration(
    border: Border.all(
      color: AppColors.k9Primary.withOpacity(0.2),
    ),
  ),
)
```

### Espaçamentos

```css
padding: 16px 20px;       /* vertical horizontal */
margin: 8px 0 14px 0;     /* top right bottom left */
```

```dart
padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),

margin: const EdgeInsets.only(top: 8, bottom: 14),
```

### Bordas

```css
border: 1px solid rgba(77, 208, 225, 0.3);
border-radius: 14px;
```

```dart
decoration: BoxDecoration(
  border: Border.all(
    color: AppColors.k9Primary.withOpacity(0.3),
    width: 1,
  ),
  borderRadius: BorderRadius.circular(14),
)
```

### Border-radius assimétrico

```css
border-radius: 14px 14px 0 0;
```

```dart
borderRadius: const BorderRadius.only(
  topLeft: Radius.circular(14),
  topRight: Radius.circular(14),
),
```

### Border-left destaque

```css
border-left: 3px solid #2ecc71;
padding-left: 12px;
```

```dart
Container(
  decoration: const BoxDecoration(
    border: Border(
      left: BorderSide(color: AppColors.k9Operational, width: 3),
    ),
  ),
  padding: const EdgeInsets.only(left: 12),
  child: ...,
)
```

### Tipografia

```css
font-size: 14px;
font-weight: 700;
letter-spacing: 0.5px;
line-height: 1.4;
color: #fff;
```

```dart
Text(
  '...',
  style: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    height: 1.4,
    color: AppColors.k9TextPrimary,
  ),
)
```

**Mapping de font-weight:**
- `400` → `FontWeight.w400` (normal)
- `500` → `FontWeight.w500`
- `600` → `FontWeight.w600` (semi-bold)
- `700` → `FontWeight.w700` (bold)
- `800` → `FontWeight.w800` (extra-bold)

### Display flex

```css
display: flex;
align-items: center;
gap: 8px;
```

```dart
Row(
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    Widget1(),
    const SizedBox(width: 8),
    Widget2(),
    const SizedBox(width: 8),
    Widget3(),
  ],
)
```

### Display flex column

```css
display: flex;
flex-direction: column;
gap: 12px;
```

```dart
Column(
  children: [
    Widget1(),
    const SizedBox(height: 12),
    Widget2(),
  ],
)

// Ou em Flutter moderno (3.7+):
Column(
  spacing: 12,
  children: [Widget1(), Widget2()],
)
```

### Justify-content

```css
justify-content: space-between;
```

```dart
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [...],
)
```

### Grid 2 colunas

```css
display: grid;
grid-template-columns: 1fr 1fr;
gap: 8px;
```

```dart
GridView.count(
  crossAxisCount: 2,
  mainAxisSpacing: 8,
  crossAxisSpacing: 8,
  shrinkWrap: true,
  physics: const NeverScrollableScrollPhysics(),
  children: [...],
)

// OU mais comum (mais flexível):
Row(
  children: [
    Expanded(child: Widget1()),
    const SizedBox(width: 8),
    Expanded(child: Widget2()),
  ],
)
```

### Position absolute

```css
position: absolute;
bottom: 0;
left: 0;
right: 0;
```

```dart
Positioned(
  bottom: 0,
  left: 0,
  right: 0,
  child: ...,
)

// Dentro de Stack
Stack(
  children: [
    backgroundWidget,
    Positioned(
      bottom: 0, left: 0, right: 0,
      child: foregroundWidget,
    ),
  ],
)
```

### Sticky bottom (CTA fixo)

```css
.cta-sticky {
  position: sticky;
  bottom: 0;
  background: linear-gradient(to top, #050d10 80%, transparent);
  padding: 16px;
}
```

```dart
// Padrão recomendado: Scaffold + bottomNavigationBar OU Column + Expanded
Scaffold(
  body: Column(
    children: [
      Expanded(child: SingleChildScrollView(child: content)),
      _buildStickyBottomCta(),
    ],
  ),
)

Widget _buildStickyBottomCta() {
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          AppColors.k9Background,
        ],
        stops: const [0.0, 0.2],
      ),
    ),
    padding: const EdgeInsets.all(16),
    child: ElevatedButton(...),
  );
}
```

### Border-bottom em divisores

```css
border-bottom: 1px solid rgba(255, 255, 255, 0.06);
```

```dart
Container(
  decoration: const BoxDecoration(
    border: Border(
      bottom: BorderSide(
        color: Color(0x0FFFFFFF), // branco com 6% opacidade
        width: 1,
      ),
    ),
  ),
  child: ...,
)
```

## Cores de opacidade

Sempre que vir `rgba(R, G, B, 0.X)`:

```dart
Color(0xFFRRGGBB).withOpacity(0.X)

// Ou diretamente em hexadecimal:
// rgba(77, 208, 225, 0.2) = 4DD0E1 com 20% opacity = 33 no alpha
Color(0x334DD0E1)
```

Tabela de conversão de opacidade pra hex:
- 0.05 → `0D`
- 0.1 → `1A`
- 0.15 → `26`
- 0.2 → `33`
- 0.3 → `4D`
- 0.4 → `66`
- 0.5 → `80`
- 0.6 → `99`
- 0.7 → `B3`
- 0.8 → `CC`
- 0.9 → `E6`

## Componentes comuns dos mockups

### Status badge (verde/amarelo/vermelho)

```html
<span class="status-badge apt">✓ APTO PARA PLANTÃO</span>

<style>
.status-badge.apt {
  background: rgba(46, 204, 113, 0.1);
  color: #2ecc71;
  border: 1px solid rgba(46, 204, 113, 0.3);
  padding: 6px 10px;
  border-radius: 8px;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.3px;
}
</style>
```

```dart
class StatusBadge extends StatelessWidget {
  final String text;
  final BadgeType type;

  const StatusBadge({super.key, required this.text, required this.type});

  Color get _color {
    switch (type) {
      case BadgeType.apt: return AppColors.k9Operational;
      case BadgeType.warning: return AppColors.k9Formation;
      case BadgeType.critical: return AppColors.k9Critical;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        border: Border.all(color: _color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: _color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

enum BadgeType { apt, warning, critical }
```

### Card com gradient sutil

```html
<div class="dog-card">
  ...
</div>

<style>
.dog-card {
  background: linear-gradient(135deg, rgba(77, 208, 225, 0.08), rgba(46, 204, 113, 0.04));
  border: 1px solid rgba(77, 208, 225, 0.2);
  border-radius: 16px;
  padding: 16px;
}
</style>
```

```dart
Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        AppColors.k9Primary.withOpacity(0.08),
        AppColors.k9Operational.withOpacity(0.04),
      ],
    ),
    border: Border.all(
      color: AppColors.k9Primary.withOpacity(0.2),
    ),
    borderRadius: BorderRadius.circular(16),
  ),
  child: ...,
)
```

### Avatar circular com borda

```html
<div class="avatar">BONO</div>

<style>
.avatar {
  width: 50px;
  height: 50px;
  border-radius: 50%;
  background: #1a2a30;
  border: 2px solid #2ecc71;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #2ecc71;
  font-size: 11px;
  font-weight: 800;
}
</style>
```

```dart
Container(
  width: 50,
  height: 50,
  decoration: BoxDecoration(
    color: AppColors.k9Surface,
    shape: BoxShape.circle,
    border: Border.all(
      color: AppColors.k9Operational,
      width: 2,
    ),
  ),
  child: Center(
    child: Text(
      'BONO',
      style: TextStyle(
        color: AppColors.k9Operational,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  ),
)
```

### Botão primário (ciano fill)

```dart
Widget primaryButton({required String label, required VoidCallback onPressed}) {
  return SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.k9Primary,
        foregroundColor: AppColors.k9Background,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    ),
  );
}
```

### Botão destrutivo (vermelho outline)

```dart
Widget destructiveButton({required String label, required VoidCallback onPressed}) {
  return SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.k9Critical.withOpacity(0.06),
        foregroundColor: AppColors.k9Critical,
        side: BorderSide(color: AppColors.k9Critical.withOpacity(0.3)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
```

## Validação visual

Depois de implementar uma tela, **valide visualmente** comparando com o mockup:

### Checklist de validação

- [ ] Paleta de cores correta (mesmos hexadecimais)
- [ ] Espaçamentos corretos (margens, paddings)
- [ ] Bordas e radius corretos
- [ ] Tipografia certa (Inter, tamanhos, weights)
- [ ] Hierarquia visual respeitada
- [ ] Estados especiais implementados (loading, vazio, erro)
- [ ] Componentes condicionais (badges, alertas) aparecem certo

### Como comparar lado a lado

1. Abre o mockup HTML no navegador (ex: 390x844 mobile view)
2. Roda o app no emulador no mesmo tamanho
3. Tira screenshot do mockup e do app
4. Compara visualmente

Se possível, use Puppeteer pra automatizar screenshots dos mockups.

## Quando o mockup parece "errado" pra você

**NÃO modifique sem consultar o Jilles.** O mockup foi pensado pra defender 
profissionalmente os condutores. Decisões aparentemente estranhas geralmente têm 
razão institucional.

Exemplos de "parecem errados mas são intencionais":
- Paleta sem brilho/saturação → defesa proporcional, não chamativa
- Ausência de animações elaboradas → seriedade institucional
- Botões sem efeitos fancy → forma segue função
- Linguagem formal → auditor invisível como usuário

Se realmente acha que algo está errado:
1. Releia o mockup com cuidado
2. Consulte ESPEC_TECNICA correspondente
3. Em última instância, **pergunte ao Jilles** explicando seu raciocínio

## Antipadrões a evitar

❌ **Não use** Material Design padrão sem customização — o app tem identidade própria
❌ **Não use** widgets visualmente "ricos" do Material 3 (ex: Card com sombra padrão)
❌ **Não use** cores fora da paleta institucional
❌ **Não adicione** animações elaboradas (fade simples, sim; spring complex, não)
❌ **Não use** ícones decorativos que não estão no mockup

## Padrões a seguir

✅ **Use** Container + BoxDecoration pra customização precisa
✅ **Use** const onde possível pra performance
✅ **Use** AppColors constantes (não hexa hardcoded)
✅ **Use** padding/margin exatos do mockup
✅ **Use** mesma hierarquia visual do mockup

## Quando criar widget reutilizável

Se mesmo componente aparece em 3+ telas (header, badge, card de cão), **extraia pra 
widget reutilizável** em `core/widgets/`.

Se aparece em 1-2 telas apenas, mantenha local na feature.