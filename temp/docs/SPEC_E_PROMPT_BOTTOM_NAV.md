# Bottom Navigation — Redesenho (especificação + prompt)

## Decisão
**Tratamento 2** — barra ancorada (irmã do Header Universal) + **expanding pill** na aba ativa + **FAB central sólido** para a ação "Nova Ocorrência".
Mockup de referência: `temp/mockups/bottom_nav_redesenho_v3.html` (lado direito, "Tratamento 2").

## Princípio
O nav é **espelho do Header Universal**: mesma faixa ancorada de ponta a ponta, mesmo véu ciano de fundo, e a **borda superior do nav é idêntica à borda inferior do header**. Ciano **sólido**, sem vidro (glass) nem gradiente. A barra atual (caixa quadrada no centro, dois itens parecendo ativos) é substituída.

## Tokens (os mesmos do header — não criar cores soltas)
- Fundo da barra: `rgba(77,208,225,0.04)`
- Borda superior: `1px solid rgba(77,208,225,0.12)`
- Padding: ~9px lateral, ~10px topo, **+ safe area inferior** (SafeArea)
- Ícones traço fino (~22px): inativo `#5a7280`; ativo `#4dd0e1`
- **Pill ativo (expanding):** fundo `rgba(77,208,225,0.10)`, borda `1px rgba(77,208,225,0.22)`, radius full, padding `0 15px`, ícone + label (12–13px, peso 700), cor `#4dd0e1` — é o **mesmo tratamento dos botões ⇄ / perfil do header**.
- **FAB central (Nova Ocorrência):** círculo 54px, fundo `#4dd0e1` **sólido**, ícone `#04181c`, **ring** `border: 4px solid #050d10`, sombra `0 4px 16px rgba(77,208,225,0.32)`, elevado ~`-30px`, label "Nova" 8.5px ciano abaixo.

## Estrutura (5 slots)
`[ Turno ] [ Histórico ] [ ● Nova — FAB ] [ Treino ] [ Cão ]`
- **4 destinos** de navegação: Turno, Histórico, Treino, Cão.
- **1 ação central**: Nova Ocorrência (FAB).

## Comportamento
- Aba ativa = expanding pill: **só a ativa mostra o nome**; inativas só ícone. Ao trocar de aba, o pill desliza/expande para a nova.
- O **FAB é AÇÃO, não destino**: nunca fica "selecionado"; toca → abre o fluxo de Nova Ocorrência → volta para a aba anterior.
- Resolve o problema atual: acaba a caixa quadrada e os "dois selecionados".

## Regras do projeto
- Reaproveitar o widget do **Header Universal** como referência de tokens.
- `main` buildável; trabalhar em branch.
- **Validar com evidência:** print da barra nas 4 abas + acionando a Nova Ocorrência.
