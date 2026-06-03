# ESPEC TÉCNICA — PARTE 14
## Notificações: header global + tela + comportamentos

> Filtro de sempre: *"se um gestor questionar o trabalho do condutor 6 meses depois, esse registro o defende?"* — aplicado às notificações no ponto crítico: **uma pendência acionável não pode ser apagada e esquecida.**

---

## 0. Contexto e objetivo

Hoje as notificações vivem **dentro do menu hamburguer**, com um badge amarelo no ☰. As três notificações do sistema são todas **acionáveis e time-sensitive**, então escondê-las atrás do menu prejudica a descoberta — o condutor não vê a pendência sem abrir o menu.

As três notificações atuais:
1. **Convite para a viatura / guarnição** (Frente C)
2. **Solicitação de assinatura** em ocorrência (co-assinatura — trava o fechamento)
3. **Evolução no treinamento** (promoção co-validada — Etapa 4)

Objetivo desta parte: dar às notificações **acesso de um toque** (sino no header com badge), uma **tela própria organizada por urgência**, e os **comportamentos** que faltam (marcar lida, limpar avisos, ações), respeitando as regras de auditoria.

**Fora de escopo:** gerar notificações novas (a geração já existe, FCM no ar) e criar tipos novos. Esta parte é sobre **acesso, apresentação e ações** sobre o que já é gerado.

---

## 1. Header global (ajuste transversal)

- **Hamburguer à esquerda** — abre o drawer (convenção: menu lateral mora à esquerda). **Sem badge.**
- **Sino à direita** — com **badge de contador**, abre a tela de Notificações em um toque.
- O **badge conta apenas pendências não resolvidas** ("requer ação"). Avisos **não** entram na conta — o número reflete só o que de fato cobra o usuário.
- **Remover** o item "Notificações" de dentro do hamburguer e o badge do ☰ (migra para o sino).
- É o **header global**: aplica a todas as telas com cabeçalho.

> **Atenção (Claude Code):** diagnostique o header atual antes de mexer — onde o hamburguer é renderizado, como o badge é montado hoje, quais telas compartilham o cabeçalho. Não quebre telas existentes ao centralizar o padrão.

---

## 2. Tela de Notificações

**Cabeçalho da tela:** voltar (‹) · título "Notificações" · subtítulo "X requerem ação · Y avisos" · ação "Marcar lidas".

**Duas seções, propósitos diferentes:**

### Requer ação (topo)
Pendências que cobram uma decisão. É o que alimenta o badge. Ordenação por urgência:
`assinatura > convite > evolução` (ou por prazo/tempo quando houver).

### Avisos (embaixo)
Informativo, para consulta. Tem a ação **Limpar** (ver §4).

**Card de notificação:** ícone por tipo · título · contexto (dados técnicos — nº da ocorrência, módulo, VTR — em **mono**) · timestamp (**mono**) · ações. Não-lida = fundo levemente realçado + ponto colorido (vermelho/âmbar/ciano por urgência).

---

## 3. Mapa de tipos → seção / ação / destinatário

| Notificação | Seção | Ação | Para quem |
|---|---|---|---|
| Convite de guarnição recebido | Requer ação | **Aceitar / Recusar** (inline) | quem é convidado |
| Convite aceito/recusado | Aviso | abre a equipe da VTR | quem convidou |
| Assinatura necessária | Requer ação | **Revisar e assinar** (abre tela) | co-signatário |
| Ocorrência selada | Aviso | abre a ocorrência | participantes |
| Evolução solicitada (`*_requested`) | Requer ação | **Avaliar** (abre tela) | Instrutor K9 |
| Evolução aprovada/recusada (`*_approved` / `*_rejected`) | Aviso | abre o histórico do cão | condutor |

---

## 4. Comportamentos

- **Ações inline só quando é seguro decidir na hora:** aceitar/recusar convite resolve no próprio card.
- **Ações que abrem tela:** "Revisar e assinar" e "Avaliar evolução" **sempre** abrem a tela de revisão — nunca resolvem em um clique no card. Reaproveitar os **deep links já existentes** (Etapa 4 e ocorrência); não recriar navegação.
- **Marcar lidas:** seta `read=true`, tira o realce de não-lida. **Não remove** nada. Vale para pendências e avisos.
- **Limpar:** só na seção **Avisos**. Arquiva/soft-delete os avisos. **Pendência não tem "limpar".**
- **Pendência só sai de "requer ação" quando a ação subjacente é resolvida** (assinou / aceitou / avaliou) — é derivada do estado da entidade, não removível à mão.
- **Voltar (‹):** retorna à tela de origem.

---

## 5. Regras de auditoria (não-negociáveis)

1. **Pendência acionável não é limpável.** Só sai da lista quando **resolvida**. Se o usuário pudesse apagar uma assinatura pendente, ele apagaria, esqueceria, e a ocorrência ficaria sem fechar — o buraco que o app existe para tapar.
2. **Assinar e avaliar evolução sempre abrem a tela de revisão.** Não se assina uma ocorrência nem se aprova uma evolução sem ver o conteúdo. Botão de um clique no card seria perigoso.
3. **Limpar avisos não apaga registro real.** O dado (a ocorrência, o treino, a guarnição) permanece intacto; some apenas o aviso.

---

## 6. Fonte de dados

- **Consumir as notificações já existentes** (confirmar o caminho real no código — `notifications/{ra}/items` ou equivalente). **Não recriar a geração** nem a entrega (FCM já no ar).
- Mapear cada tipo existente (convite, assinatura, `*_requested/approved/rejected`) para seção/ação conforme §3.
- O **badge** consome a contagem de pendências não resolvidas (requer ação) do usuário logado, em tempo real.

---

## 7. Implementação — passos sugeridos

1. **Diagnosticar:** header atual; estrutura/caminho das notificações existentes; deep links da Etapa 4 e da ocorrência.
2. **Header global:** hamburguer esquerda + sino direita com badge (pendências). Remover badge/item do hamburguer.
3. **Tela de notificações:** duas seções, cards por tipo, ações inline × deep link conforme §3/§4.
4. **Comportamentos:** marcar lidas; limpar avisos (com a regra "só avisos"); voltar.
5. **Travar as regras de auditoria** (§5) no código, não só na UI.
6. **Validar no aparelho** (não só build): badge atualiza ao chegar/resolver pendência; ações inline funcionam; deep links abrem a tela certa; "limpar" não some com pendência; "marcar lidas" não remove.

---

## 8. Critério de pronto

- Sino no header com badge correto (só pendências), em todas as telas com cabeçalho; hamburguer limpo à esquerda.
- Tela com as duas seções, as três notificações mapeadas, ações funcionando.
- Pendência não some por "limpar"; só por resolução. Assinar/avaliar abrem tela.
- Validado em aparelho real, com pendência chegando e sendo resolvida.
