---

name: pdf-generation
description: Diretrizes para criação, manutenção, exportação, armazenamento e verificação de documentos PDF institucionais no K9 Ops. Use quando a tarefa envolver geração de PDFs, layout documental, integridade, QR Code, compartilhamento ou persistência de documentos. Não presume tipos fixos de relatório, URLs públicas ou mecanismos criptográficos sem verificar a arquitetura atual.
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Geração de PDFs · K9 Ops

## Objetivo

Os PDFs do K9 Ops são documentos institucionais gerados a partir de dados do sistema.

Dependendo do contexto, podem servir para:

* prestação de contas;
* gestão;
* auditoria;
* documentação operacional;
* acompanhamento veterinário;
* histórico de saúde;
* treinamento;
* relatórios administrativos;
* defesa profissional;
* compartilhamento formal de informações.

Por esse motivo, documentos PDF exigem precisão maior que uma simples exportação visual da tela.

## Regra principal

**Não invente arquitetura documental.**

Antes de criar ou modificar um PDF:

1. identifique o requisito real da tarefa;
2. procure geradores existentes;
3. verifique o padrão documental já adotado;
4. confirme quais dados são fonte da verdade;
5. determine se o PDF é dinâmico ou um snapshot fechado;
6. verifique requisitos reais de auditoria, assinatura, hash, QR Code e armazenamento;
7. implemente somente o que fizer parte do fluxo atual.

Não adicione automaticamente:

* hash;
* QR Code;
* assinatura;
* mapa;
* upload para Storage;
* página pública de validação;
* trilha completa de auditoria.

Esses recursos devem existir por requisito real.

## Hierarquia de autoridade

Em caso de conflito, siga esta ordem:

1. escopo explícito da tarefa atual;
2. `CLAUDE.md`, `AGENTS.md` e instruções vigentes;
3. código atual da branch;
4. documentação oficial atual em `docs/`;
5. decisões recentes do documento ou módulo;
6. esta skill;
7. especificações e mockups históricos.

Não use documentos antigos em `temp/` como contrato atual automaticamente.

## Tipos de documento

Esta skill não mantém uma lista fixa de PDFs obrigatórios.

O K9 Ops pode gerar documentos de diferentes domínios, por exemplo:

* ocorrências;
* saúde;
* prontidão;
* vacinação;
* peso;
* nutrição;
* treinamento;
* histórico operacional;
* relatórios administrativos.

Antes de criar um novo gerador, procure se o documento ou um padrão equivalente já existe.

Não crie múltiplos sistemas de geração de PDF sem necessidade.

## Identidade visual

PDF institucional não precisa reproduzir o tema dark do aplicativo.

Quando o padrão vigente utilizar documentos claros, priorize:

* fundo claro;
* texto com alto contraste;
* hierarquia formal;
* boa impressão em papel;
* tabelas legíveis;
* uso controlado das cores institucionais.

A identidade do K9 Ops deve aparecer de forma profissional, não como uma captura de tela do aplicativo.

## Layout

A estrutura deve seguir a necessidade real do documento.

Elementos possíveis incluem:

```text
identificação institucional
título
subtítulo
identificador do documento
data e período
responsáveis
resumo
dados principais
tabelas
timeline
gráficos
anexos
observações
auditoria
assinaturas
informações de integridade
```

Nenhuma dessas seções é universalmente obrigatória.

Não adicione páginas apenas para deixar o documento mais "completo".

## Cabeçalho

Em documentos multipágina, o cabeçalho pode ajudar a manter contexto.

Quando fizer parte do padrão atual, preserve informações como:

* instituição;
* tipo do documento;
* identificação do registro.

Exemplo conceitual:

```text
GCM LIMEIRA · RELATÓRIO DE SAÚDE              REG 2026-00142
──────────────────────────────────────────────────────────────
```

Não repita blocos grandes de capa em todas as páginas.

## Rodapé

Quando necessário, utilize:

* instituição;
* tipo do documento;
* paginação.

Exemplo conceitual:

```text
GCM Limeira · Canil K9 · Saúde                 Página 2 de 5
```

Não exponha dados sensíveis no rodapé.

## Margens e unidades

O pacote `pdf` não utiliza milímetros diretamente como números simples.

Não faça:

```dart
margin: const pw.EdgeInsets.all(30),
```

afirmando que isso representa 30 mm.

Para utilizar milímetros:

```dart
margin: pw.EdgeInsets.all(
  30 * PdfPageFormat.mm,
),
```

Use o valor definido pelo layout real.

Não imponha 30 mm para todos os documentos.

## Paginação

Para conteúdo que pode crescer, prefira estruturas capazes de quebrar páginas corretamente.

Considere:

```dart
pw.MultiPage
```

quando o conteúdo for dinâmico.

Não coloque grandes timelines, tabelas ou históricos em uma única `pw.Page` sem avaliar overflow.

Exemplo:

```dart
final pdf = pw.Document();

pdf.addPage(
  pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.all(
      20 * PdfPageFormat.mm,
    ),
    build: (context) => [
      header,
      content,
    ],
  ),
);
```

## Tipografia

Use fontes compatíveis com o padrão atual dos documentos.

Antes de carregar fontes remotamente:

* verifique a estratégia existente;
* considere disponibilidade offline;
* considere estabilidade;
* evite dependência de rede durante geração quando não for necessária.

Preserve hierarquia clara entre:

```text
título principal
seção
subseção
corpo
metadado
informação auxiliar
```

Não use tamanhos pequenos demais apenas para caber mais informação.

## Cores

Utilize cores institucionais com função clara.

Uma cor pode identificar:

* tipo de relatório;
* status;
* categoria;
* alerta;
* seção.

Não use cores semânticas apenas como decoração.

Sempre preserve contraste adequado para:

* visualização em tela;
* impressão;
* cópia em escala de cinza quando possível.

## Emojis

Evite emojis decorativos em documentos institucionais.

Quando for necessário representar um símbolo:

* prefira asset oficial;
* ícone vetorial;
* texto;
* forma gráfica simples.

Não dependa de suporte de emoji do PDF para elementos institucionais importantes.

## Brasões e logos

Use somente assets oficiais disponíveis no projeto.

Não invente brasão ou logo substituto.

Se o asset oficial ainda não existir, utilize placeholder apenas quando explicitamente permitido pela tarefa.

Não apresente placeholder como identidade definitiva.

## Dados do documento

Antes de gerar o PDF, determine a fonte dos dados.

Pode ser:

* documento atual do Firestore;
* conjunto de documentos;
* DTO;
* snapshot fechado;
* dados já carregados pelo fluxo.

Evite acoplar o gerador diretamente a múltiplas queries Firestore quando isso dificultar:

* testes;
* consistência;
* reprodutibilidade.

Quando apropriado, prepare primeiro uma estrutura de dados específica do documento.

Exemplo conceitual:

```dart
class HealthReportData {
  final Dog dog;
  final List<HealthEvent> events;
  final DateTime generatedAt;

  const HealthReportData({
    required this.dog,
    required this.events,
    required this.generatedAt,
  });
}
```

Não crie DTO apenas por formalidade se o gerador existente já possui contrato adequado.

## Documento dinâmico versus snapshot

Antes de implementar, determine qual comportamento é esperado.

### Documento dinâmico

Representa os dados atuais toda vez que é gerado.

Exemplo:

```text
Relatório atual de peso
```

Se os dados mudam, uma nova geração pode produzir conteúdo diferente.

### Snapshot institucional

Representa um estado fechado em determinado momento.

Exemplo:

```text
Relatório finalizado de uma ocorrência
```

Nesse caso, pode ser necessário preservar:

* versão;
* data de fechamento;
* conteúdo utilizado;
* autoria;
* integridade.

Não misture os dois conceitos.

## Auditoria

Quando o documento precisar apresentar histórico de alterações, consulte:

```text
audit-trail
```

Não inclua automaticamente toda a auditoria interna.

Considere:

* público do documento;
* finalidade;
* dados sensíveis;
* clareza.

Uma versão destinada a auditoria pode ter conteúdo diferente de uma versão destinada a compartilhamento externo.

## Integridade documental

### Hash não é assinatura

Um hash SHA-256 simples pode detectar alteração de determinado conteúdo.

Ele não prova sozinho:

* autoria;
* identidade de quem gerou;
* legitimidade;
* origem;
* autenticidade criptográfica.

Não descreva um hash simples como:

```text
assinatura digital
```

ou:

```text
prova de autenticidade
```

sem arquitetura que realmente forneça isso.

## Quando usar hash

Use hash somente quando houver um fluxo real de verificação.

Antes de implementar, defina:

```text
qual conteúdo entra no hash
quando o hash é calculado
quem calcula
onde é armazenado
como é validado
o que acontece quando os dados mudam
```

Sem essas respostas, não introduza o mecanismo.

## Payload canônico

Nunca gere hash diretamente de:

```dart
jsonEncode(object.toJson())
```

sem definir uma serialização determinística.

Problemas possíveis:

* ordem de chaves;
* objetos aninhados;
* timestamps;
* doubles;
* listas;
* valores opcionais;
* campos derivados;
* próprio campo de hash.

O conteúdo protegido deve ter um contrato explícito.

Exemplo conceitual:

```dart
final payload = buildCanonicalIntegrityPayload(document);
final bytes = encodeCanonicalPayload(payload);
final hash = sha256.convert(bytes);
```

As funções concretas devem ser testadas.

## Campo de hash

O próprio campo onde o hash é armazenado não deve participar do payload utilizado para calcular o mesmo hash.

Defina explicitamente os campos protegidos.

Exemplo conceitual:

```text
PROTEGIDO:
id
type
occurred_at
responsible_id
events

NÃO PROTEGIDO:
integrity_hash
pdf_url
pdf_generated_at
```

A lista real depende do domínio.

## Alteração posterior

Se o documento protegido mudar, determine o comportamento correto.

Possibilidades:

* gerar nova versão;
* invalidar versão anterior;
* recalcular hash;
* criar retificação;
* impedir alteração após fechamento.

Não recalcule silenciosamente sem compreender o modelo documental.

## Assinatura criptográfica

Quando houver exigência real de autenticação criptográfica, considere mecanismo server-side com chave protegida.

Não implemente chave privada dentro do aplicativo mobile.

Não invente uma infraestrutura de assinatura sem requisito explícito.

## QR Code

Um QR Code é apenas uma forma de transportar informação.

Ele não prova autenticidade sozinho.

Antes de adicionar QR Code, determine o destino real.

Pode ser:

* URL de verificação;
* identificador;
* conteúdo resumido;
* outra informação.

Não invente automaticamente uma URL como:

```text
https://canilk9-limeira.web.app/v/{id}
```

sem confirmar que:

* a rota existe;
* o domínio é correto;
* o acesso é permitido;
* os dados expostos são seguros.

## Página de verificação

Se existir um fluxo de validação pública ou autenticada, confirme:

* quem pode acessar;
* quais dados são exibidos;
* qual dado é considerado fonte da verdade;
* como versões são tratadas;
* como documento revogado é apresentado.

Nunca exponha conteúdo operacional ou clínico sensível apenas para validar um hash.

## Storage

Gerar PDF e armazenar PDF são responsabilidades diferentes.

Fluxos possíveis:

```text
preview
share
download
persistência
arquivo final
```

Implemente somente os necessários.

Não faça upload automático para Firebase Storage apenas porque o PDF foi gerado.

## Caminhos de Storage

Utilize a estrutura atual do projeto.

Não misture vocabulários legados.

Antes de criar algo como:

```text
/incidents/
```

verifique se o domínio atual utiliza:

```text
/occurrences/
```

ou outra estrutura.

O código atual é a fonte da verdade.

## Arquivos finais

Quando um PDF for considerado documento final:

* defina quando ele é finalizado;
* defina se pode ser substituído;
* defina se versões anteriores precisam permanecer;
* preserve metadados necessários.

Não sobrescreva documento institucional histórico sem entender o requisito.

## Nomes de arquivos

Use nomes previsíveis e seguros.

Evite:

* caracteres inválidos;
* dados pessoais desnecessários;
* textos enormes.

Exemplo conceitual:

```text
ocorrencia_2026_00142.pdf
```

ou:

```text
historico_saude_bono_2026_07.pdf
```

Siga o padrão real do projeto.

## Compartilhamento

Ao utilizar `Printing.sharePdf` ou mecanismo equivalente:

* utilize nome de arquivo adequado;
* trate erros;
* não assuma que o compartilhamento foi concluído apenas porque a folha do sistema abriu.

Não salve automaticamente o documento no backend como efeito colateral do compartilhamento.

## Mapas

Não adicione mapa automaticamente a PDFs de ocorrência.

Quando o requisito exigir localização visual:

1. verifique o padrão atual;
2. confirme o provedor;
3. confirme credenciais;
4. trate falhas de rede;
5. defina fallback.

Nunca deixe API key hardcoded.

## Imagens

Ao incluir imagens:

* preserve proporção;
* limite resolução quando apropriado;
* considere tamanho final do PDF;
* trate falha de carregamento.

Não embuta automaticamente arquivos originais enormes quando uma versão adequada para documento for suficiente.

Isso não significa substituir ou destruir o original armazenado.

## Dados sensíveis

Antes de incluir informações, avalie o destinatário.

Dados que podem exigir cuidado incluem:

* dados clínicos;
* localização;
* identificação pessoal;
* informações operacionais;
* anexos;
* dados internos de auditoria.

O fato de uma informação existir no sistema não significa que ela deve aparecer em todo PDF.

## Linguagem institucional

Use linguagem clara, técnica e profissional.

Prefira:

```text
Indicação positiva do cão K9 durante procedimento de busca.
```

a:

```text
O cachorro achou droga.
```

Ao mesmo tempo, evite artificialidade.

Não escreva frases excessivamente burocráticas apenas para parecer institucional.

A linguagem deve representar corretamente os fatos.

## Dados e conclusões

Não transforme automaticamente um dado em conclusão.

Exemplo:

```text
Peso atual: 29,8 kg
```

não significa automaticamente:

```text
Condição corporal ideal
```

a menos que esse dado exista ou seja calculado por regra de negócio vigente.

PDF não deve inventar interpretação.

## Tabelas

Para tabelas:

* mantenha cabeçalhos claros;
* preserve alinhamento numérico;
* use contraste adequado;
* permita quebra entre páginas;
* evite colunas demais.

Zebra striping pode ser utilizada quando fizer parte do padrão visual.

Não é obrigatória.

## Gráficos

Quando o documento incluir gráficos:

* confirme unidade;
* confirme escala;
* rotule eixos;
* trate ausência de dados;
* não distorça tendência.

Não adicione gráfico apenas para preencher espaço.

## Datas e horários

Use o padrão definido pelo domínio e pelo contexto brasileiro.

Normalmente:

```text
DD/MM/AAAA
HH:mm
```

Quando timezone for relevante, trate explicitamente.

Não converta timestamps sem considerar o fuso esperado.

## Geração offline

Quando o fluxo precisar funcionar offline, não dependa de recursos remotos durante a geração.

Isso pode incluir:

* fontes;
* imagens;
* mapas;
* logos externos.

Consulte o comportamento atual da feature.

Não imponha suporte offline se não houver requisito.

## Erros

A geração deve tratar falhas previsíveis.

Exemplos:

* dados obrigatórios ausentes;
* asset não encontrado;
* imagem inválida;
* erro de armazenamento;
* falha de compartilhamento.

Não gere documento silenciosamente incompleto quando o conteúdo ausente for crítico.

## Testabilidade

Separe, quando fizer sentido:

```text
preparação dos dados
```

de:

```text
renderização do PDF
```

Isso facilita testes.

Não crie arquitetura adicional se o gerador for simples e já estiver testável.

## Validação mínima

Para lógica não trivial, valide:

* geração sem exceção;
* bytes não vazios;
* conteúdo essencial presente;
* comportamento com dados opcionais;
* paginação;
* nomes e datas;
* integridade determinística quando houver hash.

## Validação visual

Para documentos importantes:

1. gere o PDF;
2. abra o arquivo;
3. verifique todas as páginas;
4. confirme que não existem cortes;
5. confira tabelas;
6. confira caracteres especiais;
7. confira paginação;
8. confira imagens.

Não declare PDF concluído apenas porque `pdf.save()` retornou bytes.

## Compatibilidade de schema

Quando a geração depender de Firestore, considere documentos antigos.

Não assuma que todos os registros possuem campos novos.

Use parsers e fallbacks conforme o contrato atual.

Antes de modificar schema para facilitar um PDF, consulte:

```text
firestore-coexistence
```

Não altere o banco apenas porque o gerador ficou mais conveniente.

## Dependências

Antes de adicionar:

```text
pdf
printing
crypto
qr_flutter
http
```

verifique o `pubspec.yaml`.

Não adicione pacote duplicado ou desnecessário.

Exemplo: o próprio pacote `pdf` pode oferecer geração de código de barras/QR em determinados fluxos.

Não mantenha duas dependências para a mesma função sem necessidade.

## Segurança

Nunca inclua em código ou PDF:

* API keys;
* tokens;
* credenciais;
* URLs privadas com segredo;
* dados internos não destinados ao público.

Ao gerar URL de acesso, verifique o modelo de autorização.

## Auditoria do documento

Quando a geração ou finalização do PDF for uma ação institucional relevante, ela pode precisar ser auditada.

Consulte:

```text
audit-trail
```

Não gere uma entrada de auditoria para cada simples preview se o domínio não exigir.

## Checklist antes de implementar

* [ ] O requisito atual do PDF foi confirmado.
* [ ] O gerador existente foi procurado.
* [ ] O documento é dinâmico ou snapshot.
* [ ] Os dados de origem estão definidos.
* [ ] O layout segue o padrão atual.
* [ ] Conteúdo longo pode paginar corretamente.
* [ ] Dados sensíveis foram avaliados.
* [ ] Hash só foi incluído se houver fluxo real de integridade.
* [ ] Payload canônico foi definido quando necessário.
* [ ] QR Code só foi incluído se houver destino real.
* [ ] Nenhuma URL pública foi inventada.
* [ ] Storage só é utilizado se o fluxo exigir.
* [ ] Dependências existentes foram verificadas.
* [ ] O PDF foi inspecionado visualmente quando possível.
* [ ] Nenhuma mudança de Firestore foi feita sem consultar `firestore-coexistence`.

## Formato de reporte

Quando implementar ou alterar um documento, reporte:

```text
Documento:
Fonte dos dados:
Arquivos alterados:
Persistência:
Integridade:
Validações executadas:
Pendências:
```

Não afirme que o documento foi salvo em produção quando apenas a geração local foi testada.

## Regra final

**Um PDF institucional precisa ser tecnicamente defensável, não apenas visualmente bonito.**

Implemente somente os mecanismos que realmente existem no fluxo atual.

Nunca transforme uma ideia conceitual antiga em requisito técnico automático.
