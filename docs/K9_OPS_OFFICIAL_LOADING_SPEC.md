# K9 Ops — Loading Oficial
## Motion Spec + Plano de Implementação

**Status:** Direção visual aprovada
**Escopo:** Web + Mobile
**Estratégia técnica recomendada:** Lottie para animação do K9/HUD + interface nativa controlada pelo aplicativo
**Objetivo:** substituir o loading provisório da Web e criar o loading oficial do Mobile com uma identidade visual única, leve e coerente com o K9 Ops.

---

# 1. Direção visual oficial

## 1.1 Identidade

O loading oficial do K9 Ops deve seguir a identidade institucional já adotada pelo produto:

- fundo dark navy / quase preto;
- cyan / teal como cor de destaque;
- glow controlado;
- HUD discreto;
- linguagem tática e tecnológica;
- aparência premium;
- alta legibilidade;
- ausência de elementos caricatos ou excessivamente “gamificados”.

O elemento visual principal será um **Pastor Belga Malinois holográfico**, representado em perfil lateral e correndo no lugar.

O K9 deve transmitir:

- prontidão;
- energia;
- foco;
- operação;
- inteligência;
- movimento.

---

# 2. Variação Web

## 2.1 Formato

- layout horizontal;
- composição mais rica;
- foco em sensação de “painel operacional sendo preparado”;
- suporte a múltiplas etapas de inicialização.

## 2.2 Texto principal

**PREPARANDO PAINEL OPERACIONAL...**

## 2.3 Etapas visuais

1. **Validando acesso**
   Conexão segura estabelecida

2. **Carregando permissões**
   Verificando níveis de autorização

3. **Sincronizando módulos**
   Inicializando componentes

## 2.4 Elementos visuais

- marca `K9 OPS SYSTEMS`;
- versão/build no topo;
- indicador de status;
- Malinois holográfico;
- HUD circular de fundo;
- barra de progresso;
- percentual quando fizer sentido;
- checklist de etapas;
- footer institucional:
  `K9 OPS • INTELLIGENCE IN MOTION`.

---

# 3. Variação Mobile

## 3.1 Formato

- layout vertical;
- composição mais limpa;
- prioridade para performance e leitura rápida;
- menos informação simultânea que na Web.

## 3.2 Texto principal

**INICIALIZANDO SISTEMA...**

## 3.3 Etapas visuais

1. **Validando acesso**
2. **Sincronizando módulos**

A implementação pode manter outras etapas internamente, mas o Mobile não precisa exibir toda a granularidade da Web.

## 3.4 Elementos visuais

- marca `K9 OPS SYSTEMS`;
- versão/build;
- Malinois holográfico;
- HUD circular discreto;
- barra de progresso;
- status atual;
- footer institucional:
  `K9 OPS • INTELLIGENCE IN MOTION`.

---

# 4. Motion Spec

## 4.1 Malinois

O Malinois é o elemento principal da animação.

### Movimento

- corrida em perfil lateral;
- o cão permanece aproximadamente na mesma posição horizontal;
- o ciclo deve transmitir deslocamento sem que o asset atravesse a tela;
- movimento fluido e contínuo;
- anatomia realista;
- postura operacional.

### Partes animadas

Prioridade:

1. pernas dianteiras;
2. pernas traseiras;
3. tronco;
4. cabeça;
5. cauda;
6. glow e rastros.

### Intensidade

- pernas: movimento principal;
- tronco: oscilação vertical sutil;
- cabeça: muito estável;
- cauda: movimento discreto;
- glow: moderado;
- rastros: moderados;
- nenhuma deformação exagerada.

---

# 5. Ciclo de animação

## 5.1 Loop principal

Recomendação inicial:

- duração: **1,4 s**;
- faixa aceitável: **1,2 s a 1,6 s**;
- loop contínuo;
- reinício imperceptível.

O ponto exato deve ser validado visualmente após a primeira animação funcional.

## 5.2 HUD

- rotação lenta;
- ciclo sugerido: **10 s a 18 s**;
- não competir visualmente com o cão.

## 5.3 Glow

- pulsação sutil;
- ciclo sugerido: **0,8 s a 1,2 s**;
- evitar aparência de “pisca-pisca”.

## 5.4 Rastros

- podem acompanhar o ciclo de corrida;
- devem reforçar a sensação de movimento;
- não podem reduzir a leitura da silhueta do K9.

---

# 6. Estratégia de animação

## 6.1 Estratégia recomendada

**Lottie para o K9/HUD + UI nativa para progresso, estados e textos.**

A animação não deve conter a lógica do loading.

### Lottie

Responsável por:

- ciclo de corrida do Malinois;
- glow;
- rastros;
- HUD;
- microefeitos visuais.

### UI nativa

Responsável por:

- título;
- status;
- percentual;
- barra de progresso;
- etapas;
- textos;
- comportamento de erro;
- acessibilidade;
- adaptação responsiva.

## 6.2 Motivo da decisão

Essa separação:

- reduz acoplamento;
- facilita manutenção;
- permite progresso real;
- permite Web e Mobile compartilharem o mesmo conceito sem depender da mesma composição;
- evita transformar toda a tela em um vídeo ou animação monolítica;
- facilita fallback e acessibilidade.

---

# 7. Estrutura dos assets

## 7.1 Camadas sugeridas para produção da animação

### Malinois

- cabeça;
- tronco;
- perna dianteira A;
- perna dianteira B;
- perna traseira A;
- perna traseira B;
- cauda;
- harness/peitoral;
- glow;
- rastros.

### Ambiente visual

- HUD externo;
- HUD interno;
- plataforma/scan inferior;
- partículas;
- linhas de movimento.

### Interface

Os seguintes elementos **não devem ser incorporados obrigatoriamente no Lottie**:

- textos;
- percentual;
- barra de progresso;
- checklist;
- versão/build;
- mensagens de estado.

Esses elementos devem permanecer nativos sempre que possível.

---

# 8. Estados do loading

## 8.1 Estados conceituais

O loading deve refletir o bootstrap real do sistema sempre que houver sinais técnicos disponíveis.

### Estado 1 — Inicialização

Faixa visual sugerida:

- `5%–15%`

Mensagem:

- Web: `Validando acesso`
- Mobile: `Validando acesso`

### Estado 2 — Autenticação validada

Faixa visual sugerida:

- `15%–35%`

Web:

- `Carregando permissões`

Mobile:

- pode continuar com mensagem simplificada ou avançar para sincronização.

### Estado 3 — Bootstrap de módulos

Faixa visual sugerida:

- `35%–70%`

Mensagem:

- `Sincronizando módulos`

### Estado 4 — Finalização

Faixa visual sugerida:

- `70%–95%`

Mensagem alternativa:

- `Finalizando inicialização...`

### Estado 5 — Pronto

- `100%`;
- concluir estados;
- executar transição suave;
- navegar para a tela de destino.

---

# 9. Progresso real vs. progresso visual

## 9.1 Regra

Não inventar percentual “preciso” quando o sistema não tiver medição real.

Existem duas estratégias válidas:

### Estratégia A — progresso real

Quando o bootstrap expõe etapas concretas:

- cada etapa concluída atualiza o progresso;
- o percentual é derivado de pesos definidos;
- `100%` somente após o sistema estar pronto.

### Estratégia B — progresso semideterminado

Quando não existe granularidade suficiente:

- usar progresso por etapas;
- avançar suavemente até um teto seguro;
- nunca mostrar `100%` antes da conclusão real;
- finalizar somente quando o bootstrap confirmar prontidão.

O percentual pode ser omitido no Mobile se não houver valor tecnicamente defensável.

---

# 10. Regras de UX

## 10.1 Tempo mínimo

Evitar flash visual quando o carregamento for muito rápido.

Sugestão inicial:

- mínimo entre **1,2 s e 1,8 s**.

O valor final deve ser validado em dispositivo real.

## 10.2 Tempo prolongado

Se a inicialização exceder o tempo esperado:

- atualizar a mensagem;
- manter a animação ativa;
- não deixar o usuário sem feedback.

Exemplos:

- `Finalizando inicialização...`
- `Sincronização em andamento...`

## 10.3 Erro

O loading não pode ficar preso indefinidamente.

Quando houver falha real:

- sair do estado de loading;
- apresentar uma mensagem de erro compreensível;
- oferecer retry quando aplicável;
- preservar logs técnicos fora da interface de usuário.

## 10.4 Redução de movimento

Quando a plataforma oferecer preferência de redução de movimento:

- reduzir ou desativar rastros;
- reduzir HUD;
- manter uma versão estática ou de movimento mínimo;
- preservar todas as informações funcionais da tela.

---

# 11. Responsividade

## 11.1 Web

A tela deve funcionar em:

- desktop widescreen;
- notebooks;
- tablets;
- viewport web mobile.

O Malinois não pode:

- cortar a cabeça;
- cortar as patas;
- ultrapassar áreas de status;
- ficar ilegível em telas menores.

## 11.2 Mobile

Validar:

- diferentes aspect ratios;
- safe areas;
- notch;
- status bar;
- telas pequenas;
- tablets, se suportados.

---

# 12. Arquitetura sugerida — Mobile

## 12.1 Componente

Nome sugerido:

`K9OpsLoadingScreen`

## 12.2 Responsabilidades

- renderizar o layout;
- receber estado externo;
- não executar autenticação diretamente;
- não decidir autorização;
- não possuir regra de domínio.

## 12.3 Modelo conceitual

```text
K9OpsLoadingState
├── stage
├── progress
├── message
├── isComplete
└── error
```

## 12.4 Stages sugeridos

```text
initializing
validatingAccess
loadingPermissions
syncingModules
finalizing
ready
error
```

A lista final deve respeitar os estados reais existentes no app.

---

# 13. Arquitetura sugerida — Web

Criar um componente equivalente na stack real do projeto.

O componente deve:

- consumir estado externo;
- ser responsivo;
- usar o Lottie apenas como camada visual;
- manter progresso e status em componentes nativos;
- não bloquear navegação além do necessário;
- preservar comportamento de erro já existente.

Não assumir framework sem primeiro inspecionar o projeto.

---

# 14. Assets e convenções

Sugestões de nomes:

```text
assets/branding/loading/k9_ops_loading_dog.json
assets/branding/loading/k9_ops_loading_dog_reduced_motion.json
```

ou estrutura equivalente aprovada pelo repositório.

Não adicionar assets:

- sem origem conhecida;
- sem licença compatível;
- maiores do que o necessário;
- contendo texto rasterizado que deveria ser nativo.

---

# 15. Performance

## Mobile

Validar:

- tempo de carregamento do asset;
- uso de memória;
- frame pacing;
- fluidez em dispositivo físico;
- comportamento em aparelhos menos potentes.

## Web

Validar:

- tamanho transferido;
- lazy/preload adequado;
- ausência de layout shift relevante;
- carregamento em conexão mais lenta.

A animação deve ser visualmente premium, mas nunca atrasar o bootstrap real do produto.

---

# 16. Fallback

Se o Lottie falhar:

- exibir versão estática do Malinois;
- manter barra, textos e estados funcionais;
- permitir conclusão normal do bootstrap.

O loading nunca pode depender da animação para funcionar.

---

# 17. Critérios de aceite

## Visual

- [ ] identidade coerente com K9 Ops;
- [ ] Malinois reconhecível e anatômico;
- [ ] loop fluido;
- [ ] sem aparência cartunesca;
- [ ] glow controlado;
- [ ] HUD discreto;
- [ ] Web e Mobile pertencem à mesma família visual.

## Funcional

- [ ] loading reflete estados reais quando disponíveis;
- [ ] nenhuma lógica crítica depende da animação;
- [ ] erro não gera loading infinito;
- [ ] fallback funciona;
- [ ] navegação ocorre apenas quando o bootstrap está pronto;
- [ ] não há regressão de autenticação ou autorização.

## Performance

- [ ] animação fluida no Mobile;
- [ ] asset com tamanho aceitável;
- [ ] Web responsiva;
- [ ] reduced motion respeitado quando disponível;
- [ ] sem impacto relevante no tempo de inicialização.

---

# 18. Ordem oficial de execução

```text
Auditoria da implementação atual
↓
Mapeamento dos estados reais de boot
↓
Produção do asset animado
↓
Implementação estrutural Mobile
↓
Validação Mobile
↓
Implementação Web
↓
Validação Web
↓
Polimento e acessibilidade
↓
Documentação final
```

---

# 19. Decisão atual

A direção visual de Web e Mobile está aprovada.

A implementação deverá usar, como primeira opção:

**Lottie para o Malinois/HUD + UI nativa para progresso, textos e estados.**

A arte conceitual aprovada serve como **referência visual**, não como asset final pronto para produção.

A etapa seguinte é:

1. auditar a implementação atual de loading/boot;
2. identificar os pontos reais de progresso e estados;
3. produzir ou obter o asset Lottie final;
4. integrar sem alterar contratos funcionais de autenticação, permissão ou bootstrap.
