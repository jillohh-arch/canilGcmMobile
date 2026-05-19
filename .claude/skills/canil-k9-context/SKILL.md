---
name: canil-k9-context
description: Contexto institucional permanente do app Canil K9 GCM Limeira. Carrega quando trabalhando em features, decisões de design ou UX, regras de negócio relacionadas a defesa profissional de condutores K9, prestação de contas institucional, casos de auditoria, gamificação, trilha de auditoria, prontuário do cão, ocorrências, ou qualquer aspecto relacionado ao app Flutter de gestão do canil da GCM Limeira.
---

# Contexto Institucional · App Canil K9 GCM Limeira

## Quem usa o app

Guarda Civil Municipal de Limeira-SP. Especificamente o canil K9 com 6 condutores ativos. 
Usuário principal e proprietário do projeto: **Jilles Ragonha (GCM RA 691755)**, 
instrutor K9 nacional.

Cães principais:
- **Bono**: Malinois, 6 anos, 28kg. Operacional em 3 especialidades 
  (Detecção de Drogas, Busca & Captura, Guarda & Proteção em formação)
- **Apolo**: Malinois, 2 anos, 36kg. Em formação básica

## Por que o app existe

Há discussão institucional na GCM Limeira de que "canil não trabalha". O app existe para:

1. **Prestação de contas institucional** — provar trabalho ao gestor
2. **Proteção do condutor** — quando questionado, ter registros sólidos
3. **Prontuário institucional** — histórico médico, treinos, nutrição
4. **Evidência defensiva** — arquivo profissional pra defesa em auditoria

## Caso fundador (precedente real)

Jilles dava 800g/dia de ração ao Bono baseado em conhecimento técnico próprio. 
Veterinário institucional questionou, dizia 300g/dia. Jilles pagou laudo nutricional 
particular do próprio bolso para provar que estava correto. O app transforma esse tipo 
de situação em registro institucional rastreável.

## Filtro central de design

**Aplique em toda decisão:** "Se um gestor questionar o trabalho do condutor 6 meses 
depois, esse registro defende ele?"

Se a resposta for não, repensar a feature.

## Princípios norteadores invioláveis

### 1. Forma segue função
- Corta decoração
- Sem elementos visuais que não servem ao propósito institucional
- Beleza vem da clareza, não de ornamentos

### 2. Defesa profissional proporcional
- Não chamativa (lição aprendida do caso do laudo)
- Não defensiva por padrão
- Mas completa e robusta quando questionada

### 3. Tom institucional sério
- **SEM** RPG ou militar gamer ("Prontuário de Combate", "K9 Duty Selection")
- **SEM** inglês decorativo ("off-leash" → "sem guia")
- **SEM** terminologia jovem ou casual
- "Senha" não "Chave de Acesso"
- Datas formato BR (DD/MM/AAAA)

### 4. Subtração no MVP
- Quando em dúvida, corta
- Features podem ser adicionadas depois
- Bug não introduzido > feature inacabada

### 5. Auditor é usuário invisível
- Toda escrita pensada como se um auditor fosse ler em 6 meses
- Linguagem formal nos registros
- Dados completos com proveniência

## Princípio especial: SEM gamificação

**REMOVIDO completamente do projeto:**
- XP, pontos, níveis
- Ranking entre condutores
- Troféus e badges decorativos
- "Conquistas" gameficadas
- Comparações competitivas

**SUBSTITUÍDO por** selos de conformidade institucional:
- Binários (tem ou não tem)
- Sem comparação entre condutores
- Critério objetivo (ex: "Plantões sem lacunas há 142 dias")
- Sem ranking nem competição

Se ver código antigo com gamificação (pasta `views/gamification/`, classes com 
XP/Level/Rank), marca pra remoção.

## Decisões transversais já tomadas

### Aba "Rotina" foi removida
- Alimentação → seção Nutrição dentro do Cão/Prontuário
- Passeios → Condicionamento Físico (cardiovascular)
- Escovação, banho, limpeza, brincadeira casual → cortados (não defendem profissionalmente)

### Bottom Navigation fixo
```
Turno · Histórico · FAB(🛡 Ocorrência) · Treino · Cão
```

### Header Universal (em todas áreas principais)
```
[avatares] Bono · GCM Ragonha    [⇄] [👤]
           ● Turno ativo · há 5h
```

- ⇄ abre bottom sheet de trocar cão
- 👤 abre perfil em tela cheia
- Header NÃO aparece em sub-telas (formulários, detalhes)

### Trilha de auditoria obrigatória
Toda escrita em coleções operacionais registra:
- Quem fez (uid + name snapshot + RA snapshot)
- Quando (timestamp servidor)
- O que mudou (campo, valor antes, valor depois)
- Motivo (em deletes)

### Soft delete sempre
Nunca `doc.delete()`. Sempre marca `deleted_at + deleted_by + deleted_reason`.

### EXIF preservado
Fotos enviadas mantêm metadata (data, GPS, dispositivo). NÃO comprimir/reprocessar 
o original. Thumbnails são separados.

### Cores semânticas
- **Ciano #4dd0e1**: primário, geral
- **Verde #2ecc71**: operacional, conformidade
- **Amarelo #f1c40f**: formação, atenção
- **Laranja #e67e22**: nutrição
- **Vermelho #e74c3c**: saúde/crítico
- **Azul #2c6e91**: peso
- **Roxo #5a4080**: histórico, relatórios

### Tipografia
Inter (sans-serif). Sem serifa (institucional moderno, não tradicional).

## Coexistência com painel React

**CRÍTICO:** Existe painel web React em produção que acessa o MESMO Firestore. 
Jilles controla ambos.

Mudanças no Firestore exigem cuidado:
- Aditivas (novos campos/coleções) = seguras
- Destrutivas (renomear/remover campos) = protocolo de 4 fases

Consulte skill `firestore-coexistence` antes de mexer em Firestore.

## Quando você (Claude) precisa decidir

Em dúvida sobre design ou produto:
1. Releia os mockups em `temp/mockups/`
2. Consulte ESPEC_TECNICA_PARTE_*.md em `temp/docs/`
3. **Se ainda incerto, PERGUNTE ao Jilles**
4. Nunca invente comportamento

Não tente "otimizar" coisas que parecem ineficientes mas são intencionais:
- Paleta sem brilho
- Ausência de gamificação
- Simplicidade visual
- Linguagem formal