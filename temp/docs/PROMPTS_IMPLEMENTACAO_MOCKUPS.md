# Prompts de Implementação — Sessão de Mockups (maio/2026)

Implementação do que foi desenhado: PDF v2 da ocorrência, arquitetura de detalhe de histórico (7 tipos), Triagem e bottom sheet de trocar cão.

## Como usar este documento

- **Cada bloco `PROMPT N` é UMA sessão separada do Claude Code.** Não rode tudo de uma vez — sessões focadas erram menos e são mais fáceis de validar.
- **Sequência recomendada:** 1 → 2 → 3 → 4. O PROMPT 2 (detalhe de ocorrência) usa o "Gerar PDF" do PROMPT 1, então o PDF vem antes.
- O PROMPT 4 (Triagem + trocar cão) é independente — pode ir a qualquer momento.
- Os PROMPTS 2 e 3 podem ser fundidos numa sessão só se quiser arriscar, mas recomendo separados (a casca + 7 corpos numa sessão só é muito código de uma vez).
- Todos os mockups estão em `temp/mockups/`. Copie o bloco do prompt (do título até o fim da seção) e cole no Claude Code.

---

## Preâmbulo — regras válidas para TODAS as sessões

> Cole este bloco junto com cada prompt, ou deixe claro que valem sempre.

Antes de qualquer código, leia: as skills do projeto relevantes (`canil-k9-context`, `audit-trail`, `firestore-coexistence`, `flutter-canil-conventions`, `flutter-visual-fidelity`, `pdf-generation`) e a seção da especificação citada no prompt.

Regras inegociáveis:

1. **Os mockups em `temp/mockups/` são referência VISUAL** (layout, hierarquia, cores, o que mostrar). **A especificação técnica manda na LÓGICA e nas regras de negócio.** Onde divergirem, a spec vence — e me avise a divergência.
2. **Trabalhe em branch**, nunca direto na `main`. Merge só com `--no-ff` e só depois de validado.
3. **Mantenha a `main` sempre buildável.** Os 6 testers usam build anterior; mudanças na main não os afetam até uma nova versão ser publicada — mas a main não pode quebrar.
4. **Trilha de auditoria e soft delete** em tudo que cria/edita/remove registro, conforme a skill `audit-trail`. Nada de hard delete.
5. **Filosofia de defensibilidade:** o filtro é "se um gestor questionar o trabalho do condutor 6 meses depois, esse registro o defende?". Não prometa no app o que não existe de verdade (ver regra 6).
6. **Não exiba garantias sem lastro.** Exemplo concreto desta entrega: desenhei o bloco de integridade (hash SHA-256) em todos os detalhes, mas isso só vale para registros que realmente têm hash/imutabilidade (ocorrência finalizada já tem — ver tela de confirmação final). Se treino/saúde/nutrição NÃO geram hash imutável na spec, **adapte o bloco**: mostre "sincronizado" + link de auditoria, sem afirmar integridade criptográfica que o registro não possui.
7. **Valide com evidência, não com narrativa.** Ao terminar, mostre `git log` da branch, e prints/saída de runtime (tela rodando, PDF gerado, doc no Firestore). Não basta descrever o que fez.
8. Painel React **não está em uso** — liberdade arquitetural total no app, sem dual-write nem compatibilidade com o painel.

---

## PROMPT 1 — PDF v2 da Ocorrência (Doc 2.6)

Refatore o PDF da ocorrência seguindo o novo design em `temp/mockups/pdf_ocorrencia_v2_*.html` (6 páginas: capa, localização, timeline, mídias, relato, assinaturas). Referência de spec: Doc 2.6 na ESPEC_TECNICA_PARTE_2. Skill principal: `pdf-generation`.

Direção visual (substitui o PDF antigo):
- Editorial institucional, **corpo claro** (fundo branco/cinza-claro) com **header escuro petróleo** — NÃO dark mode (o antigo era ruim para promotor/juiz/impressão).
- Tipografia: IBM Plex Sans no texto, IBM Plex Mono em dados técnicos (hash, GPS, IDs, horários).
- Estrutura de 6 páginas conforme os mockups.

Correções de honestidade já decididas (aplicar todas — são o ponto central desta refatoração):
- **Duração honesta:** janela real do 1º evento à finalização. Não inventar "chegada"; usar a semântica de abertura já adotada ("Registro de ocorrência aberto").
- **Relato:** descrever como "transcrito de áudio e revisado/validado pelo condutor". Não enfatizar "gerado por IA".
- **Verificação online:** a página `/v/{id}` ainda NÃO existe. Mantenha o QR/link com **aviso âmbar** deixando claro que a verificação online estará disponível em breve — não prometa uma página que não responde.
- **Assinaturas:** apenas a equipe REAL (condutor + testemunha presente). A confirmação é via login autenticado (autenticação de nível 2 — NÃO assinatura digital ICP-Brasil). O documento mostra o estado honesto: condutor confirmado, testemunha "aguardando confirmação" quando for o caso.
- **Mapa:** Static Maps com zoom afastado (15–16, não 17) para mostrar o entorno do local.
- **Hash:** reaproveitar o SHA-256 já calculado na finalização (a tela de confirmação final já gera). O hash do PDF deve bater com o exibido no app.

Escopo desta sessão: SÓ o PDF. Não mexer em telas de histórico nem criar a página de verificação online (fica de backlog).

Pronto quando: o PDF de uma ocorrência finalizada de teste gera as 6 páginas com o layout dos mockups, hash conferindo com o app, e nenhuma informação falsa (durações, assinaturas, verificação). Anexe o PDF gerado.

---

## PROMPT 2 — Detalhe de Histórico: casca + Ocorrência e Detecção

Implemente a arquitetura de detalhe de histórico e os dois primeiros corpos. Mockups: `temp/mockups/detalhe_historico_ocorrencia.html` e `temp/mockups/detalhe_historico_deteccao.html`.

**Padrão arquitetural (decidido em design, não está na spec — leia com atenção):** todo detalhe de histórico é uma **casca comum + um corpo específico por tipo**.

- **Casca (`HistoryDetailScaffold` ou nome equivalente conforme `flutter-canil-conventions`):** header (tipo + id + compartilhar), card de identificação (tipo/data/binômio/status), bloco de integridade + trilha de auditoria, e barra de ações fixa (Gerar PDF + Compartilhar). Idêntica em todos os tipos.
- **Corpo:** widget recebido pela casca, específico do tipo.

Nesta sessão, dois corpos:
- **Ocorrência:** stats (eventos/mídias/resultados), resultados, localização (mini-mapa + GPS), timeline resumida com "ver todos", relato com preview, mídias em carrossel. O botão "Gerar PDF" desta tela chama o PDF v2 do PROMPT 1.
- **Detecção:** bloco do Protocolo Ragonha — linha (drogas/armas/cadáver), fase atual, contador de acertos consecutivos, roadmap das 5 fases — e a série de acertos/erros da sessão. Spec: Protocolo Ragonha na ESPEC_TECNICA_PARTE_3. **Use os dados reais da sessão de detecção** (a regra "1 erro zera o contador" e os critérios por fase vêm da spec, não do mockup).

Atenção ao bloco de integridade (ver regra 6 do preâmbulo): ocorrência finalizada tem hash; verifique na spec se sessão de detecção também tem antes de exibir o mesmo bloco.

Escopo: só casca + esses 2 corpos. Os outros 5 corpos vêm no PROMPT 3 reusando esta casca.

Pronto quando: abrir uma ocorrência e uma sessão de detecção do histórico renderiza as duas telas com a MESMA casca e corpos distintos; "Gerar PDF" na ocorrência produz o PDF v2. Anexe prints das duas telas.

---

## PROMPT 3 — Detalhe de Histórico: corpos restantes

Com a casca do PROMPT 2 pronta, implemente os 5 corpos restantes, cada um como widget de corpo plugado na MESMA casca. Não duplique header/identificação/integridade/ações — reuse a casca.

Mockups e specs por tipo:
- **Guarda & Proteção** (`detalhe_historico_guarda_protecao.html`): os 3 impulsos (Caça/Defesa/Agressão) com estado e qual foi trabalhado na sessão, avaliação do figurante, capacidades reforçadas, comando "Larga". Spec: G&P na ESPEC_TECNICA_PARTE_3.
- **Busca & Captura** (`detalhe_historico_busca_captura.html`): rastro percorrido (mapa do trajeto), métricas (distância, idade do rastro, tempo de busca), habilidades trabalhadas, configuração.
- **Obediência** (`detalhe_historico_obediencia.html`): modo da sessão (com/sem guia, distração, distância) e comandos trabalhados por categoria, cada um com estágio em 5 níveis e marca de evolução. Spec: Obediência (Telas 3.2 / 3.3) na ESPEC_TECNICA_PARTE_3.
- **Saúde** (`detalhe_historico_saude.html`): aplicação (vacina/medicamento, lote, validade), próximo reforço com agenda, responsável (veterinário + CRMV), anexo, observações. O layout serve para os vários tipos de evento (vacinação, antiparasitário, exame, consulta, medicação, cirurgia) — mudam só os campos. Spec: evento de saúde.
- **Nutrição** (`detalhe_historico_nutricao.html`): refeição servida (ração + quantidade), conformidade prescrito vs servido, vínculo ao laudo nutricional vigente, acompanhamento do dia, foto. Spec: nutrição/alimentação.

Reforço da regra 6: confira na spec quais desses tipos realmente têm hash/imutabilidade. Onde não houver, adapte o bloco de integridade em vez de exibir hash falso.

Pronto quando: os 5 tipos abrem do histórico sobre a casca compartilhada; cada corpo reflete a spec do seu tipo. Anexe prints dos 5.

---

## PROMPT 4 — Triagem (Tela 3.12) + Bottom Sheet Trocar Cão (1.8)

Duas telas independentes do resto. Mockups: `temp/mockups/tela_3_12_triagem.html` e `temp/mockups/componente_1_8_trocar_cao.html`.

**Triagem (Fase 0 da Detecção) — Tela 3.12, ESPEC_TECNICA_PARTE_3:**
- 5 critérios em escala 0–10 (drive pra bola, foco, persistência, independência, nervo), com soma automática /50 e sugestão de aptidão calculada.
- **Decisão é manual e separada da sugestão** (radio: continuar formação / reavaliar em 30 dias / sugerir redirecionamento). O instrutor pode divergir do score — registre a divergência.
- Aviso institucional no topo (a reprovação pode recomendar redirecionamento do cão).
- Grava em `triagem_evaluations` (conforme spec) com trilha de auditoria.

**Bottom Sheet Trocar Cão — Componente 1.8, ESPEC_TECNICA_PARTE_1:**
- **Primeiro verifique se já existe implementação** do trocar cão no código. Se existir, **refine o visual** para bater com o mockup, preservando a lógica. Se não existir, implemente conforme a spec 1.8.
- Regras de negócio: trocar o cão **não encerra o turno**; cão ativo destacado; outros cães mostram status de aptidão (pendências como vacina vencendo em âmbar); trocar para cão com pendência pede confirmação extra; condutor titular de 1 só cão recebe mensagem em vez do seletor.

Pronto quando: a triagem registra uma avaliação completa com decisão e auditoria; o seletor de cão troca o binômio ativo sem encerrar o turno. Anexe prints e o doc gravado no Firestore (triagem).

---

## Fora do escopo destes prompts (backlog conhecido)

- **Manutenção G&P** (tela de treino de manutenção) — ainda não mockada; quando for, segue o padrão das outras manutenções com os 3 impulsos + frescor de cada um.
- **Página de verificação online** `/v/{id}` — não existe; por isso o PDF leva aviso âmbar. Implementar (ou remover o QR) é sessão dedicada.
- **Pesagem** como tipo de registro de nutrição — mesma casca, corpo com curva de peso.
