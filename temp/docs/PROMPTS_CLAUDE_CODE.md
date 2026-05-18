# 🤖 PROMPTS PARA CLAUDE CODE — APP CANIL K9 GCM LIMEIRA

> Conjunto de 3 prompts pra usar com o Claude Code durante a implementação.
> Copie e cole conforme a situação.

---

## 📁 ESTRUTURA RECOMENDADA NO PROJETO

Antes de começar, organize sua pasta `temp/` assim:

```
projeto/
├── lib/                            # código atual
├── temp/                           # documentos de referência (NÃO comitar)
│   ├── docs/
│   │   ├── ESPEC_TECNICA_PARTE_1.md
│   │   ├── ESPEC_TECNICA_PARTE_2.md
│   │   ├── ESPEC_TECNICA_PARTE_3.md
│   │   ├── ROADMAP_CANIL_K9.txt
│   │   ├── ROADMAP_REFATORACAO.txt
│   │   ├── CHECKLIST_LIMPEZA.txt
│   │   ├── GUIA_COEXISTENCIA.txt
│   │   └── MAPA_NAVEGACAO.txt
│   └── mockups/
│       ├── 01_iniciar_ocorrencia.html
│       ├── 02_ocorrencia_andamento.html
│       ├── ... (todos os 25 mockups)
│       └── 25_pdfs_auxiliares.html
└── .gitignore                      # adicione "temp/" pra não comitar
```

**Adicione no `.gitignore`:**
```
# Documentação temporária (referência local apenas)
temp/
```

---

## 🎯 PROMPT 1 — MASTER (abertura de sessão)

> **Quando usar:** No início de **toda** sessão nova com Claude Code.
> **Objetivo:** Calibrar Claude com contexto institucional e regras invioláveis.

```
Estou refatorando o app Canil K9 GCM Limeira (Flutter + Firebase) que já está em produção sendo usado por 6 guardas municipais.

# CONTEXTO INSTITUCIONAL

Sou Jilles Ragonha, GCM RA 691755, instrutor K9 nacional. Conduzo o Bono (Malinois 6 anos, operacional em 3 especialidades) e o Apolo (Malinois 2 anos, em formação).

Esse app existe por uma razão específica: "há discussão de que canil não trabalha". Cada feature precisa ajudar a defender o trabalho dos condutores. O filtro central que aplico em tudo é: "Se um gestor questionar o trabalho do condutor 6 meses depois, esse registro defende ele?"

Caso real que motivou o app: eu dei 800g de ração diária ao Bono baseado em conhecimento técnico, enquanto o veterinário institucional dizia 300g. Tive que pagar laudo nutricional do próprio bolso pra provar que estava certo. O app precisa transformar isso em registros institucionais sólidos.

# DOCUMENTOS DE REFERÊNCIA

Na pasta `temp/docs/` estão os documentos oficiais do projeto:

- ESPEC_TECNICA_PARTE_1.md → Fundação (Splash, Login, Seleção de Cão, Dashboard, Perfil, Header Universal, Bottom Nav, Bottom Sheet)
- ESPEC_TECNICA_PARTE_2.md → Operacional (Ocorrências completas, Histórico, Prontuário e sub-telas)
- ESPEC_TECNICA_PARTE_3.md → Treinos e Saúde (Hub, Obediência, B&C, Detecção · Protocolo Ragonha, G&P, Saúde, Modais, PDFs)
- ROADMAP_REFATORACAO.txt → Plano em 6 etapas
- CHECKLIST_LIMPEZA.txt → Etapa 1 detalhada com comandos
- GUIA_COEXISTENCIA.txt → Coordenação com painel React
- MAPA_NAVEGACAO.txt → Navegação consolidada

Em `temp/mockups/` estão os 25 mockups HTML com referência visual exata de cada tela.

LEIA esses arquivos quando precisar de contexto. Não invente comportamento - se algo não estiver nos documentos, me pergunte.

# REGRAS INVIOLÁVEIS

1. **NUNCA quebrar o painel React** que opera no mesmo Firestore. Antes de mudar qualquer estrutura de coleção/documento, consulte `GUIA_COEXISTENCIA.txt`. Mudanças destrutivas seguem o protocolo de 4 fases (aditiva → backfill → migração → cleanup).

2. **NUNCA reintroduzir gamificação**: XP, ranking, troféus, comparação entre condutores. Substituí por selos de conformidade institucional binários (tem ou não tem) sem competição. Se ver algo parecido com gamificação no código existente, marque pra remoção.

3. **TRILHA DE AUDITORIA é obrigatória** em toda edição: quem, quando, campo alterado, valor antigo, valor novo. Soft delete sempre com motivo. Timestamps imutáveis. EXIF preservado em fotos.

4. **Defesa profissional proporcional**: não chamativa, não defensiva por padrão, mas completa quando questionada. PDFs gerados sempre com hash SHA-256.

5. **Tom institucional sério**: sem RPG, sem militar gamer, sem inglês decorativo. "Senha" não "Chave de Acesso". "Sem guia" não "off-leash". Datas formato BR.

6. **Aba "Rotina" foi removida**: alimentação está em Cão/Nutrição, passeios em Condicionamento, escovação/banho/limpeza foram cortados. Se ver código antigo dessas, marque pra remoção.

7. **Header Universal e Bottom Navigation** seguem padrão fixo definido na Parte 1. Bottom nav: Turno · Histórico · FAB(🛡 Ocorrência) · Treino · Cão.

8. **Protocolo Ragonha (Detecção)** tem regras DURAS: F3 (Ponto de Virada) exige 10 acertos consecutivos. 1 erro zera contador. Não simplifique essa lógica.

# SISTEMA VISUAL

Paleta: bg #050d10/#0a1418, primário ciano #4dd0e1, verde #2ecc71 (operacional), amarelo #f1c40f (formação), laranja #e67e22 (nutrição), vermelho #e74c3c (crítico/saúde), azul #2c6e91 (peso), roxo #5a4080 (histórico).

Bordas 10-14px, sem retículas HUD, sem ilustrações IA, sem emojis decorativos em excesso. Botão primário SEMPRE ciano fill. Destrutivo SEMPRE vermelho outline. Tipografia Inter.

Frame phone: 390x844 com border-radius 40px (referência mockups).

# ESTADO ATUAL DO PROJETO

- Versão em produção: v1.0.0+2
- Stack: Flutter + Firebase (Auth/Firestore/Storage/AppCheck) + Provider + Navigator manual
- 6 condutores GCM Limeira testando
- Painel web React separado acessa o mesmo Firestore (eu controlo os dois)
- Estrutura tem duplicação `views/` vs `features/` (refatoração inacabada)
- DECISÃO: refatoração gradual, não recomeçar do zero

# COMO TRABALHAR COMIGO

- Faça perguntas quando algo não estiver claro nos documentos
- Antes de implementar feature grande, mostre seu plano resumido pra eu validar
- Commit pequeno e frequente · um commit por passo do checklist
- Se notar inconsistência entre documentos e código atual, me alerte
- Não otimize coisas que parecem ineficientes mas são intencionais (paleta sem brilho, ausência de gamificação, simplicidade visual)
- Se for tomar decisão arquitetural importante, pause e me consulte

Quando eu disser "vamos começar", aguarde minha próxima mensagem com a tarefa específica.
```

---

## 🎯 PROMPT 2 — POR TAREFA (use a cada implementação)

> **Quando usar:** Pra cada feature/tela específica que você for implementar.
> **Adapte** os campos entre colchetes com a informação real.

### Versão 2A — Implementar tela nova

```
TAREFA: Implementar [NOME DA TELA] do app.

REFERÊNCIAS:
- Especificação técnica: temp/docs/ESPEC_TECNICA_PARTE_[X].md, seção [Tela X.Y]
- Mockup visual: temp/mockups/[NN_nome_arquivo.html]
- Mapa de navegação: temp/docs/MAPA_NAVEGACAO.txt

ESCOPO DESTA SESSÃO:
- Implementar APENAS essa tela
- Reutilizar componentes existentes onde fizer sentido
- Criar componentes novos apenas se necessário
- Seguir estrutura de pastas: features/[domain]/

PEDIDOS:
1. Antes de codar, leia a especificação técnica completa da tela
2. Abra o mockup HTML pra ver a referência visual
3. Verifique o que já existe no código atual em features/[domain]/ e em views/[domain]/
4. Apresente um plano resumido em 5-10 bullets do que vai fazer
5. Aguarde minha aprovação antes de começar a codar
6. Implemente com commits pequenos (1 commit por subtask)
7. Ao terminar, rode `flutter analyze` e `flutter test` pra garantir que não quebrou nada

ATENÇÃO ESPECIAL:
- Aplicar Header Universal (se for tela de área principal)
- Bottom Navigation (se for tela de área principal)
- Trilha de auditoria nas escritas Firestore
- Estados especiais (vazio, loading, offline, erro) conforme documentado
- Validações antes de habilitar CTAs
- Acessibilidade básica (labels, contraste)

NÃO FAÇA:
- Não refatore código não relacionado a essa tela
- Não introduza pacotes novos sem me consultar
- Não modifique estrutura de coleções Firestore (consulte GUIA_COEXISTENCIA.txt se precisar)
- Não adicione gamificação
- Não substitua paleta institucional por algo "mais vibrante"

Pode começar pelo plano.
```

### Versão 2B — Executar passo do roadmap de refatoração

```
TAREFA: Executar Etapa [X], Passo [Y] do ROADMAP_REFATORACAO.txt

REFERÊNCIAS:
- Plano completo: temp/docs/ROADMAP_REFATORACAO.txt
- Checklist se for Etapa 1: temp/docs/CHECKLIST_LIMPEZA.txt
- Coexistência: temp/docs/GUIA_COEXISTENCIA.txt

PEDIDOS:
1. Leia o passo específico no documento
2. Faça um diagnóstico do estado atual do código relacionado
3. Liste o que vai mudar e o impacto previsto
4. Confirme se é mudança aditiva (segura) ou destrutiva (precisa cuidado com painel React)
5. Aguarde minha aprovação
6. Execute em commits pequenos
7. Ao final, rode os testes e confirme que app ainda compila

Comece pelo diagnóstico.
```

### Versão 2C — Criar componente compartilhado

```
TAREFA: Criar componente [NOME] em core/widgets/

REFERÊNCIAS:
- Especificação: temp/docs/ESPEC_TECNICA_PARTE_[X].md, seção [Componente X.Y]
- Mockup: temp/mockups/[arquivo.html]

PEDIDOS:
1. Verificar se já existe algo similar em lib/
2. Propor API do componente (parâmetros, callbacks)
3. Implementar com testes unitários básicos
4. Documentar uso com exemplo de código no topo do arquivo
5. Verificar se outras telas existentes podem usar imediatamente

Comece propondo a API.
```

### Versão 2D — Implementar funcionalidade Firestore

```
TAREFA: Implementar fluxo [NOME] que escreve em [/coleção]

REFERÊNCIAS:
- Especificação: temp/docs/ESPEC_TECNICA_PARTE_[X].md, seção [Tela X.Y]
- Coexistência: temp/docs/GUIA_COEXISTENCIA.txt

PEDIDOS:
1. Mostrar a estrutura atual da coleção (campo a campo)
2. Mostrar a estrutura nova proposta
3. Marcar quais mudanças são aditivas (seguras) e quais destrutivas
4. Se houver mudanças destrutivas:
   a. Propor estratégia em 4 fases (aditivo → backfill → migração → cleanup)
   b. Listar impacto no painel React
   c. Aguardar aprovação ANTES de mexer
5. Implementar a leitura/escrita com error handling
6. Atualizar regras de segurança Firestore se necessário (mostrar diff)

Comece pelo diagnóstico de estrutura.
```

---

## 🎯 PROMPT 3 — REVISÃO E AUDITORIA

> **Quando usar:** Depois de implementar algo significativo, antes do commit final.
> **Objetivo:** Claude audita o próprio trabalho com olhos críticos.

```
REVISÃO DA IMPLEMENTAÇÃO: [NOME DO QUE FOI IMPLEMENTADO]

Faça uma auditoria honesta do código que você implementou nesta sessão. Não seja generoso consigo mesmo - quero crítica útil.

CHECKLIST DE REVISÃO:

# Conformidade com a especificação
- [ ] Todos os campos da spec foram implementados?
- [ ] Estados especiais (vazio, loading, erro, offline) tratados?
- [ ] Navegação de saída corresponde ao MAPA_NAVEGACAO.txt?
- [ ] Header Universal aplicado onde devia?

# Visual
- [ ] Paleta institucional respeitada?
- [ ] Sem emojis decorativos em excesso?
- [ ] Bordas, espaçamentos, tipografia seguem o padrão?
- [ ] Botões primário/secundário/destrutivo na cor correta?

# Dados e Firestore
- [ ] Trilha de auditoria implementada em escritas?
- [ ] Soft delete (não hard delete)?
- [ ] Timestamps imutáveis?
- [ ] EXIF preservado em fotos?
- [ ] Regras de segurança atualizadas?

# Coexistência com painel React
- [ ] Mudanças destrutivas em coleções? Se sim, foi seguido o protocolo de 4 fases?
- [ ] Painel React continua funcionando? (consultar GUIA_COEXISTENCIA.txt)

# Filosofia institucional
- [ ] Sem gamificação?
- [ ] Sem terminologia militar gamer/RPG?
- [ ] Tom institucional sério mantido?
- [ ] Filtro "isso defende o condutor 6 meses depois?" passa?

# Técnico
- [ ] `flutter analyze` limpo?
- [ ] `flutter test` passa?
- [ ] Sem dependências novas não autorizadas?
- [ ] Sem código morto deixado pra trás?
- [ ] Commits pequenos e bem nomeados?

# Documentação
- [ ] Funções/classes complexas têm comentários?
- [ ] README ou docs atualizados se necessário?

Para cada item NÃO conforme, descreva:
1. O que está faltando/errado
2. Por que é importante
3. Como corrigir

Liste também:
- 3 pontos fortes da implementação
- 3 oportunidades de melhoria futura (não obrigatórias agora)
- Qualquer débito técnico criado intencionalmente
```

---

## 🎯 PROMPTS COMPLEMENTARES (situacionais)

### Pra quando ele simplificar algo que era intencional

```
Pausa. Você simplificou [X] mas isso era intencional. Releia [documento específico] na seção [Y] e me explique por que é intencional. Depois reverta e faça da forma documentada.
```

### Pra quando ele introduzir gamificação por hábito

```
Detectei elementos de gamificação no que você fez: [descreve o que viu]. Isso foi removido por decisão de design (ver Prompt Master). Substitua por selos de conformidade binários SEM comparação entre condutores. Sem XP, sem ranking, sem troféus.
```

### Pra quando você quiser ele explicar antes de codar

```
Antes de implementar, me explique em 5 bullets:
1. O que você entendeu da tarefa
2. Os arquivos que vai mexer
3. As decisões de design que vai tomar
4. Os riscos potenciais
5. O que vai testar pra validar

Aguarde minha aprovação.
```

### Pra quando algo quebrou em produção

```
Algo quebrou em produção: [descrição do problema].

Antes de propor fix:
1. Reproduza o problema localmente
2. Identifique a causa raiz (não o sintoma)
3. Verifique se afeta o painel React também
4. Proponha 2 soluções: emergencial (rápida) e definitiva (correta)
5. Aguarde minha decisão sobre qual aplicar
```

### Pra quando ele oferecer features extras que você não pediu

```
Você sugeriu adicionar [feature extra]. Não está no escopo desta sessão e nem nos documentos. Foque no que pedi. Adicione "[feature extra]" numa lista de "Backlog de melhorias" no final, sem implementar.
```

---

## 🎯 EXEMPLO DE FLUXO IDEAL DE UMA SESSÃO

```
[ABRE NOVA SESSÃO CLAUDE CODE]

VOCÊ: [Cola Prompt 1 - Master]

CLAUDE: Entendido. Aguardo a tarefa específica.

VOCÊ: vamos começar. Quero implementar a Tela 1.4 Dashboard (Turno). 
[cola Versão 2A do Prompt 2 com os campos preenchidos]

CLAUDE: Lendo a especificação... Lendo o mockup... 
Aqui está meu plano:
1. ...
2. ...
[apresenta plano]

VOCÊ: Aprovado. Pode prosseguir. Vai commitando passo a passo.

CLAUDE: [implementa em commits]

VOCÊ: [Cola Prompt 3 - Revisão]

CLAUDE: [audita o próprio trabalho]

VOCÊ: Beleza. Vamos pra próxima.
```

---

## 📋 DICAS FINAIS PRO CLAUDE CODE

1. **Sempre comece com o Prompt 1** em sessão nova. Não confie que ele "lembra" da sessão anterior — não lembra.

2. **Mantenha sessões focadas**. 1 tela ou 1 passo de roadmap por sessão. Quando terminar, abra nova.

3. **Use commits pequenos**. Se algo quebrar, é fácil reverter.

4. **Salve os prompts num arquivo de texto** no seu computador. Adapta os campos `[X]` conforme usa.

5. **Quando ele errar feio**, não suaviza. Diga "isso está errado por X razão, refaça assim Y."

6. **Confie mas verifique**. Sempre rode `flutter analyze` e teste manualmente antes de commitar.

7. **Use o git como rede de segurança**. Antes de qualquer sessão importante, faça commit do estado atual.

8. **Sessões em projetos grandes consomem muito contexto**. Quando começar a notar respostas erráticas, abra sessão nova.

9. **Não tenta fazer tudo de uma vez**. Refatoração de 7 meses é tanga em pedaços pequenos.

10. **Quando travar, volte aqui**. Me consulta sobre decisões de produto. Claude Code é bom em código, eu sou bom em decisões de design e produto.

---

**Bons códigos, Ragonha. 🛡**
