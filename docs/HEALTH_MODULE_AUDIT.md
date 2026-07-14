# K9 Ops Mobile — Auditoria Completa do Módulo Saúde

**Data da auditoria:** 13/07/2026  
**Baseline estático:** branch `main`, commit `b19dc64`, checkout local `ahead 1` de `origin/main`  
**Modo:** somente leitura da implementação; nenhuma alteração funcional, regra, índice, migration, build, teste, branch ou commit foi executada  
**Alvo de comparação:** `docs/HEALTH_V1_ARCHITECTURE.md` e `docs/HEALTH_IMPLEMENTATION_ROADMAP.md`  
**Confiança:** análise estática do checkout atual. Não houve consulta ao conteúdo real do Firestore nem validação em dispositivo.

> O checkout já continha alterações locais, inclusive em `dog_health_prontuario_screen.dart`. Elas foram preservadas e consideradas como parte do estado auditado. Este documento não declara que essas alterações locais estejam validadas.

## 1. Resumo executivo

O módulo Saúde atual é um prontuário operacional funcional, porém distribuído e sem uma fronteira arquitetural única. O núcleo clínico usa `HealthLogModel` e grava eventos genéricos em `dogs/{dogId}/health_events`; pesagem, nutrição e documentos vivem em features e coleções próprias; histórico agrega parte dessas fontes na UI; alertas são calculados localmente ou vêm de uma coleção legada não integrada ao prontuário; notificações não possuem tipos de Saúde.

O que existe hoje e pode ser preservado é valioso: hub de registros, formulário clínico genérico, carteira de vacinas, pesagem canônica, alimentação e suplementos, documentos, histórico agregado, auditoria inline, soft delete em parte do domínio, upload protegido por regras, denormalização de indicadores no documento do K9 e análise nutricional. Entretanto, o desenho ainda não implementa o Centro de Prontidão Health v1.0.

As lacunas estruturais são:

- não há `ClinicalCase`, `TreatmentProtocol`, `ExamRequest/Collection/Result/Interpretation`, `HealthSchedule`, `HealthSummary`, restrição clínica ou estado canônico de prontidão;
- não há timeline persistida única: a timeline é uma composição em memória de fontes heterogêneas e limitada por cada consulta;
- não há repositório de Saúde nem camada de casos de uso; telas acessam serviços diretamente e também via `ChangeNotifier` global;
- não há streams de `health_events`, documentos ou peso na tela principal; apenas o K9 e refeições do dia são reativos;
- edição e exclusão existem na camada de serviço para `health_events`, mas não possuem fluxo real de UI; o menu de histórico apenas exibe mensagens simuladas;
- campos estruturados de medicação, sintomas e cirurgia são serializados dentro de texto livre;
- pesagem possui caminhos duplicados e, em uma tela legada, a mesma ação gera um `health_event` e um `weight_record`, que aparecem como duas entradas no histórico;
- documentos possuem três contratos concorrentes: coleção raiz `documentos`, anexos em `health_events` e subcoleção `dogs/{dogId}/documents` prevista nas regras mas não usada pelo mobile;
- Cloud Functions administrativas de Saúde existem, mas o mobile auditado não as chama e escreve diretamente no Firestore, criando dois contratos de autorização e auditoria;
- telas antigas de perfil exibem placeholders e conteúdo clínico fictício quando dados faltam, o que não pode ser reutilizado no Health v1.0 sem remoção;
- `HealthViewModel` mantém uma única lista global, sem chave por K9, paginação ou cancelamento de requisições; trocas rápidas de K9 podem produzir estado transitório incorreto;
- o score legado `Dog.calculateReadiness()` não implementa o modelo de prontidão aprovado e não considera bloqueios clínicos absolutos.

**Maior risco:** a ausência de um contrato clínico canônico e imutável. Decisões clínicas relevantes são hoje representadas como evento genérico/texto livre, podem ser atualizadas pelo cliente, não se vinculam a caso clínico ou protocolo e não impõem bloqueio operacional. Isso impede rastreabilidade clínica completa e pode deixar o score legado declarar prontidão apesar de uma restrição médica.

## 2. Escopo e fontes auditadas

Foram inspecionados estaticamente:

- `lib/features/health/**`;
- integrações em `nutrition`, `dogs`, `history`, `profiles`, `shifts`, `app_shell` e `core`;
- `functions/src/index.ts` nas funções administrativas e na análise nutricional;
- `firestore.rules`, `firestore.indexes.json` e `storage.rules`;
- `docs/HEALTH_V1_ARCHITECTURE.md` e `docs/HEALTH_IMPLEMENTATION_ROADMAP.md`;
- memórias históricas em `temp/memory` somente como contexto, nunca como prova do estado atual;
- testes existentes apenas por leitura. Nenhum teste foi executado.

Limites da auditoria:

- tipos de campo foram inferidos de models, serialização, Cloud Functions e regras; dados reais podem conter variações legadas adicionais;
- índices automáticos de campo único do Firestore não estão enumerados em `firestore.indexes.json`; o documento lista os índices compostos versionados e indica consultas que dependem de índices automáticos;
- não foi possível confirmar volume, cardinalidade, documentos órfãos ou distribuição real dos tipos sem ler o Firestore, o que foi expressamente proibido;
- “código morto” significa sem caminho de entrada encontrado por análise estática no checkout, não prova formal de inalcançabilidade em runtime.

## 3. Arquitetura atual

### 3.1 Diagrama textual

```text
MaterialApp / MultiProvider
├── DogViewModel (global)
├── HealthViewModel (global, ChangeNotifier, uma lista de eventos)
├── NutritionViewModel (global, ChangeNotifier + stream de refeições do dia)
└── ShiftViewModel (define K9 ativo)
    │
    └── MainRootScreen [tab Saúde]
        └── DogHealthProntuarioScreen
            ├── DogService.watchDog() ----------------> dogs/{dogId} [stream]
            ├── HealthService.getHealthLogsForDog() ---> dogs/{dogId}/health_events [get, 50]
            ├── WeightHistoryService.getHistory() ----> dogs/{dogId}/weight_records [get, 20]
            ├── DogProfileService.getDocuments() -----> documentos [query por caoId]
            ├── NutritionViewModel
            │   ├── NutritionService.watchTodayFeedings()
            │   │   ├── dogs/{dogId}/feeding_events [stream]
            │   │   └── dogs/{dogId}/feedings [stream legado]
            │   ├── prescriptions/supplements/history [gets]
            │   └── NutritionAiService -------------> generateNutritionAiInsight CF
            ├── HealthTypeSelectorScreen [hub]
            │   ├── HealthEventFormScreen ----------> HealthViewModel -> HealthService
            │   ├── _WeightRegistrationSheet -------> WeightHistoryService
            │   ├── FeedingRegistrationScreen ------> NutritionViewModel -> NutritionService
            │   └── _DocumentUploadSheet -----------> DogProfileService + StorageService
            └── HistoryScreen(healthProntuario)
                └── composição em memória:
                    health_events + weight_records + feeding_events/feedings

Entradas paralelas/legadas
├── K9ProfilePage
│   ├── VaccinationHistoryScreen
│   ├── WeightHistoryScreen
│   ├── NutritionFullScreen
│   └── HealthTypeSelectorScreen
├── BinomioHeader / ActiveShiftQuickActions -> DogHealthProntuarioScreen
└── DynamicActivitySheet (ramo Saúde implementado, sem entrada encontrada)

Backend
├── Firestore Rules: acesso por K9 + auditoria + soft delete; hard delete bloqueado
├── Storage Rules: anexos Saúde/documentos/fotos de alimentação
├── Cloud Functions administrativas de criação de evento/peso/documento
│   └── não chamadas pelo mobile auditado
└── Cloud Function de insight nutricional
    └── lê nutrição + peso + saúde + treino e grava nutrition_ai_insights
```

### 3.2 Organização por camada

| Camada | Estado atual | Observação |
|---|---|---|
| Feature clínica | `lib/features/health` | 1 model, 1 service, 1 viewmodel, 3 screens, 1 widget |
| Nutrição | `lib/features/nutrition` | domínio e estado próprios, integrado visualmente ao prontuário |
| Peso | `lib/features/dogs` | model/service canônicos fora de `health` e telas legadas |
| Documentos | `DogProfileService` | model e CRUD de criação misturados a perfil do K9 |
| Histórico | `lib/features/history` | modelo de apresentação e agregação em memória, não domínio de Saúde |
| Alertas | `DashboardService` + cálculo local | coleção legada separada e alertas derivados de `nextDueDate` |
| Notificações | `core/domain` e `core/services` | nenhuma categoria de Saúde |
| Backend | `functions/src/index.ts` | criação administrativa e insight nutricional |
| Estado | Provider/ChangeNotifier | não há Riverpod, Bloc ou repositório de Saúde |

Não há diretório `repositories` em Saúde. `HealthService`, `WeightHistoryService`, `NutritionService` e `DogProfileService` cumprem parcialmente esse papel, mas expõem Firestore diretamente e não compartilham transação, paginação ou contrato de evento.

## 4. Mapa completo das telas e navegação

O app não declara rotas nomeadas para Saúde. A navegação usa `MaterialPageRoute`, modais e a tab inferior.

| Tela/fluxo | Entrada | Consulta | Cria | Edita/exclui | Situação |
|---|---|---|---|---|---|
| `DogHealthProntuarioScreen` | tab Saúde; header; ação rápida de turno | K9 em stream; eventos, docs e pesos por `get`; nutrição via VM | abre hub | não | principal, ativa |
| `HealthTypeSelectorScreen` | FAB do prontuário; vacina legada; perfil K9 | nenhuma | roteia registros | não | ativa; callbacks fazem peso/nutrição/docs aparecerem só quando aberto pelo prontuário |
| `HealthEventFormScreen` | hub | K9 via `DogViewModel` | `health_events` + possível upload | não | ativa; formulário genérico |
| `_WeightRegistrationSheet` | hub | último peso carregado | `weight_records` + `weight_history` + snapshot no K9 | não | ativa; implementação privada dentro de tela de 4,6 mil linhas |
| `FeedingRegistrationScreen` | hub; nutrição completa; ação rápida | prescrição via VM | refeição ou suplemento | não | ativa |
| `_DocumentUploadSheet` | hub/aba Docs | nenhuma | Storage + `documentos` | não | ativa; privada e duplicada conceitualmente com anexo do evento |
| `HistoryScreen(healthProntuario)` | Resumo -> histórico | saúde, peso, nutrição; também carrega outras features antes de filtrar | não | menu simulado | ativa, mas não é uma timeline clínica persistida |
| `VaccinationHistoryScreen` | perfil K9 (inclusive cards Antipulgas e Exames) | `HealthViewModel.healthLogs` | abre hub | não | legada; recebe navegação semanticamente errada de Antipulgas/Exames |
| `WeightHistoryScreen` | perfil K9 | `HealthViewModel.healthLogs` | grava evento + peso canônico | referências de edição sem fluxo consolidado | legada e duplicadora |
| `NutritionFullScreen` | perfil K9 | histórico/prescrições via VM | abre alimentação | não | ativa, paralela à aba Nutrição do prontuário |
| `K9ProfilePage` | perfil | estado global de Saúde/Nutrição | abre hub/telas legadas | não | superfície paralela com placeholders clínicos |
| `DynamicActivitySheet` ramo Saúde | nenhuma instanciação `category: 'Saude'` encontrada | estado local + Health VM | implementado | update por `documentId` | código órfão provável |
| `HistorySaudeBody` | detalhe do histórico | model já carregado | não | “Editar” só mostra mensagem | ativa, mas contém placeholders clínicos |

### 4.1 Fluxo de rotas

```text
MainRootScreen
├── tab 0 Dashboard
│   └── ação Saúde -> tab 2 ou push DogHealthProntuarioScreen
├── tab 2 Saúde -> DogHealthProntuarioScreen(K9 ativo obrigatório)
│   ├── FAB -> HealthTypeSelectorScreen
│   │   ├── vacinação/antiparasitário/exame/consulta/medicação/sintoma/cirurgia/outro
│   │   │   └── HealthEventFormScreen
│   │   ├── peso -> modal privado de pesagem
│   │   ├── nutrição -> FeedingRegistrationScreen
│   │   └── documento -> modal privado de upload
│   └── histórico -> HistoryScreen(mode: healthProntuario)
└── tab 3 Histórico -> HistoryScreen(mode: full)

K9ProfilePage
├── Vacinas / Antipulgas / Exames -> VaccinationHistoryScreen
├── Peso -> WeightHistoryScreen
├── Nutrição -> NutritionFullScreen
└── Novo registro -> HealthTypeSelectorScreen sem callbacks de peso/nutrição/docs
```

### 4.2 Telas órfãs ou semanticamente órfãs

- o ramo Saúde de `DynamicActivitySheet`, `ActivitySheetHealthCtrl` e `HealthActivityFields` está implementado, mas todas as instanciações encontradas de `DynamicActivitySheet` usam `category: 'Treino'`;
- `HealthService.deleteHealthLog`/`HealthViewModel.deleteHealthLog` não têm chamada de UI encontrada;
- `HealthViewModel.addWeightRecord` não tem chamada encontrada;
- Cloud Functions `adminCreateHealthEvent`, `adminCreateK9WeightRecord` e `adminCreateK9HealthDocument` não têm chamada no mobile;
- a regra de `dogs/{dogId}/documents` não corresponde à implementação, que usa `documentos` raiz;
- a coleção raiz `health_logs` tem regras, mas não há leitura/gravação pelo mobile atual;
- `DogProfileService.getVaccines()` lê `vacinas`, mas o prontuário canônico lê vacinas em `health_events`.

## 5. Fluxo funcional e responsabilidades

### 5.1 Eventos clínicos genéricos

**Cria:** condutor autenticado por `HealthEventFormScreen`; também há caminho provável legado no controlador do sheet.  
**Edita:** somente API interna via `HealthViewModel.updateHealthLog`, alcançável pelo ramo órfão do `DynamicActivitySheet`.  
**Consulta:** prontuário, histórico, perfil, carteira de vacina e cards de turno.  
**Exclui:** soft delete implementado em service/viewmodel, sem UI encontrada.

Fluxo:

```text
HealthEventFormScreen
-> valida K9 e campos
-> opcionalmente sobe anexo para health_attachments/{dogId}
-> constrói HealthLogModel
-> HealthViewModel.addHealthLog
-> HealthService.addHealthLog
-> dogs/{dogId}/health_events/{id}
-> VM insere na lista local
-> tenta atualizar snapshot do K9 via DogService
-> tenta gravar auditLogs adicional via AuditService.log
```

Há três efeitos não atômicos: evento, snapshot do K9 e `auditLogs`. Falha no snapshot é engolida após log; falha no `AuditService.log` também não integra uma transação com o registro. O evento pode existir sem denormalização ou log externo correspondente.

### 5.2 Pesagem

Fluxo principal atual:

```text
Prontuário -> modal de peso -> WeightHistoryService.addRecord
-> weight_records/{id}
-> weight_history/{mesmo id} [espelho legado]
-> dogs/{dogId}.weight + audit_trail
```

Fluxo legado em `WeightHistoryScreen`:

```text
Salvar
├── HealthViewModel.addHealthLog(type=other, subtype=Pesagem, weight=...)
└── WeightHistoryService.addRecord(...)
    ├── weight_records
    ├── weight_history
    └── dogs.weight
```

O histórico agrega `health_events` e `weight_records` sem deduplicação cruzada. Portanto, o fluxo legado produz duas linhas para uma pesagem.

### 5.3 Alimentação e suplementos

**Cria:** condutor via `FeedingRegistrationScreen`.  
**Edita/exclui:** não há UI ou método público de domínio para correção/soft delete.  
**Consulta:** aba Nutrição, tela completa, histórico unificado e Cloud Function de insight.

Refeições são duplicadas deliberadamente em `feeding_events` e `feedings` com o mesmo ID. Leitura e stream fazem merge e deduplicação por ID. Suplementos usam apenas `nutrition_supplements`. Prescrições têm pares canônico/legado, mas o mobile ainda possui método `addPrescription`, contrariando a decisão Health v1.0 “Web define; Mobile executa” se esse método voltar a ser exposto.

### 5.4 Documentos e anexos

Há dois fluxos ativos:

1. documento independente: upload para `documentos/{dogId}/...` no Storage + doc em `documentos/{id}`;
2. anexo de evento: upload para `health_attachments/{dogId}/...` + URL dentro de `health_events` (`attachmentUrl` ou `mediaAttachments`).

A aba Docs mescla ambos apenas em memória. Não há entidade comum, vínculo com caso clínico, hash, versão, soft delete ou ciclo de vida do arquivo. O nome “documento” também compete com `dogs/{dogId}/documents`, previsto nas regras mas não usado.

### 5.5 Histórico

`HistoryScreen` dispara carregamentos independentes para Saúde, peso, nutrição, treinos e ocorrências. Depois transforma models heterogêneos em `HistoryEntry`, ordena e filtra em memória. Em modo prontuário, mantém apenas `health` e `nutrition` e oferece filtros Todos, Vacinas, Peso, Exames e Nutrição.

Limitações:

- não inclui documentos raiz na timeline;
- não inclui suplementos na timeline;
- `health_events` está limitado aos 50 mais recentes e `weight_records` a 200;
- a paginação “ver mais” é apenas visual sobre a lista já carregada;
- consultas, medicações, sintomas, cirurgias e antiparasitários existem, mas não têm filtro dedicado;
- dados de autor são frequentemente substituídos por `Ragonha`;
- detalhe de Saúde contém lote, validade, CRMV e nome de arquivo fictícios quando ausentes;
- o menu “Editar registro” não edita e “Copiar resumo” não copia; apenas mostra feedback.

### 5.6 Alertas e prontidão

O prontuário calcula `openAlertsCount` localmente contando qualquer `nextDueDate` próxima/atrasada. Não existe entidade persistida de alerta, severidade clínica ou resolução.

O dashboard lê a coleção raiz legada `alertas`, separada dos eventos de Saúde. Regras permitem somente leitura e não há produtor de Saúde no código auditado.

O `Dog.calculateReadiness()` é um score local de 0–100 baseado em vacinação, peso, banho e treino. Ele não representa os estados Health v1.0, não lê restrições clínicas e pode ser atualizado em um tracker do turno. É **obsoleto como fonte clínica de prontidão**, embora possa servir como heurística operacional até a substituição.

## 6. Mapa Firestore

### 6.1 Coleções e contratos observados

| Caminho | Papel | Campos observados e tipos | Leitura/escrita |
|---|---|---|---|
| `dogs/{dogId}` | K9 e snapshots | `weight: number`, `lastVaccineDate: string`, `lastBathDate: string`, `_last_weight_kg: number`, `_last_weight_at: timestamp`, `_last_vaccine_at: timestamp`, `_last_vaccine_due_at: timestamp`, `_last_exam_at: timestamp`, `idealWeightMin/Max: number`, `readinessStreak: map`, `audit_trail: list<map>` | stream pelo prontuário; updates diretos e por CF |
| `dogs/{dogId}/health_events/{eventId}` | evento genérico de Saúde | `dogId/dogName: string`, `date: timestamp`, `type/subtype: string`, `weight/costBrl: number`, `healthObservations: string`, `nextDueDate: timestamp`, `professionalCrmv/professionalClinic/vetName: string`, `attachmentUrl: string`, `mediaAttachments: list<map>`, `createdBy/created_by/created_by_uid/updated_by: string`, timestamps, soft delete, `audit_trail` | `get` ativo, order date desc, limit 50; create/update/soft delete |
| `dogs/{dogId}/weight_records/{id}` | pesagem canônica | `weight_kg: number`, `measured_at: timestamp`, `measured_by/performed_by: string`, `context: string`, `photo_url/notes: string`, `dogId/dog_id: string`, timestamps, `audit_trail` | get/stream/create/update permitido |
| `dogs/{dogId}/weight_history/{id}` | espelho legado | mesmo payload de peso | escrita espelhada; leitura mobile atual não faz fallback |
| `dogs/{dogId}/feeding_events/{id}` | refeição canônica | `period: string`, `amount_grams/prescription_at_time: int`, `divergence_percent: number`, `divergence_reason/photo_balance_url/observations/fed_by/created_by: string`, `fed_at: timestamp`, timestamps, soft delete, `audit_trail` | stream do dia, get por período, create/update |
| `dogs/{dogId}/feedings/{id}` | espelho legado | mesmo contrato de refeição | escrita espelhada e merge de leitura |
| `dogs/{dogId}/nutritional_prescriptions/{id}` | prescrição canônica | `amount_grams_per_day/meals_per_day: int`, `food_type`, vet, laudo, `vigent_from/until`, hidratação/notas, soft delete/audit | get ativo/histórico; create/update no service |
| `dogs/{dogId}/nutrition_prescriptions/{id}` | prescrição legada | mesmo contrato | fallback e espelho de escrita |
| `dogs/{dogId}/nutrition_supplements/{id}` | suplemento | `name/dose/status/notes/created_by: string`, `started_at/ended_at: timestamp`, soft delete/audit | get ordenado e create |
| `dogs/{dogId}/nutrition_ai_insights/{id}` | resultado de análise | versão/modelo, `used_ai`, período, resumo, nível, recomendações e listas, `source_summary`, solicitante, timestamp | gravado por CF; nenhuma regra explícita encontrada sob `dogs`, portanto cai no deny-all final para cliente |
| `documentos/{id}` | documento/laudo do K9 | `caoId/nome/descricao/tipo/url/emissor: string`, `dataUpload: timestamp`, `audit_trail` | query por K9 e data; create/update metadados; delete bloqueado |
| `dogs/{dogId}/documents/{id}` | contrato alternativo | regras genéricas auditadas | não usado pelo mobile auditado |
| `vacinas/{id}` | vacina legada raiz | `caoId/nome/status: string`, `dataAplicacao/dataVencimento: timestamp`, `ativo: bool` | somente leitura; DogProfileService |
| `health_logs/{id}` | Saúde legada raiz | contrato exige acesso por dog data e auditoria | sem consumidor mobile encontrado |
| `alertas/{id}` | alertas legados do dashboard | `titulo/descricao/tipo/prioridade/cor/icone/caoId: string`, `ativo: bool`, `createdAt: timestamp` | somente leitura; não integrado ao prontuário |
| `notifications/{userId}/items/{id}` | notificações por usuário | tipos de turno/treino/ocorrência, leitura/resolução/arquivo | nenhum tipo Health |
| `auditLogs/{id}` | auditoria global | ação, entidade, ator, before/after/metadata, `performed_at` | escritas best-effort no cliente e administrativas na CF |

### 6.2 Consultas, streams e agregações

| Origem | Consulta | Tipo | Índice |
|---|---|---|---|
| `HealthService` | `deleted_at == null`, `orderBy(date desc)`, `limit(50)` | get | composto `deleted_at + date` potencialmente necessário; não versionado |
| `WeightHistoryService` | `orderBy(measured_at desc)`, limites; ranges opcionais | get/stream | campo único/range automático |
| `NutritionService` | `fed_at >= from`, `< to`, `orderBy(fed_at desc)` em duas coleções | stream/get | campo único em cada subcoleção |
| `NutritionService` | `vigent_from <= now`, `orderBy(vigent_from desc)`, `limit(1)` | get | campo único |
| `NutritionService` | `orderBy(started_at desc)` | get | campo único |
| `DogProfileService` | `documentos where caoId`, `orderBy(dataUpload desc)` | get | composto versionado como `documentos(caoId ASC, dataUpload DESC)` |
| `DogProfileService` | `vacinas where caoId + ativo`, `orderBy(dataVencimento desc)` | get | composto versionado |
| `DashboardService` | `alertas where caoId + ativo`, `orderBy(createdAt desc)` | get/count | composto não versionado; falha retorna vazio/zero |
| `NutritionViewModel` | merge/dedupe e conformidade | agregação cliente | nenhuma |
| `HistoryScreen` | merge, sort, filtro e paginação visual | agregação cliente | nenhuma |
| `DogHealthProntuarioScreen` | alertas por `nextDueDate`, status e próximos eventos | derivação cliente | nenhuma |
| `generateNutritionAiInsight` | carrega prescrição, refeições, suplementos, peso, saúde e treino por período | agregação servidor | consultas Admin SDK |

### 6.3 Índices versionados relacionados

`firestore.indexes.json` contém índices compostos para:

- `vacinas`: `caoId ASC`, `ativo ASC`, `dataVencimento DESC`;
- `documentos`: `caoId ASC`, `dataUpload DESC`;
- `registros`: `caoId ASC`, `dataHora DESC`;
- `aptidoes`: `caoId ASC`, `ativo ASC`, `ordem ASC`.

Não há índices compostos versionados para `health_events`, `weight_records`, nutrição ou `alertas`. Consultas simples podem usar índices automáticos, mas a combinação `deleted_at == null + orderBy(date)` de Saúde deve ser explicitamente validada antes da migração.

### 6.4 Regras e segurança

- hard delete é bloqueado em todos os caminhos de Saúde mapeados;
- create exige `canCreateAuditedRecord()` e update exige contrato auditado/soft delete;
- acesso às subcoleções do K9 depende de `canAccessDogRecord(dogId)`;
- `documentos` raiz possui whitelist estrita e não permite alterar URL/data/K9 após criação;
- `vacinas`, `alertas` e outros contratos legados são somente leitura;
- Storage aceita imagens/PDF/Office até 20 MB em anexos de Saúde e documentos, e imagens até 10 MB em fotos de alimentação;
- arquivos são imutáveis no Storage: update/delete bloqueados;
- existem três diretórios antigos `health`, `health/exams` e o atual `health_attachments/{dogId}`, aumentando risco de órfãos;
- regras não impõem schema específico por tipo de evento clínico, vínculo com caso, estado ou imutabilidade após conclusão.

## 7. Mapa dos models

### 7.1 Models centrais

| Model | Papel | Problemas / destino |
|---|---|---|
| `HealthLogModel` | evento clínico genérico | `type` deve virar enum/union; mistura consulta, vacina, exame, medicamento, sintoma, cirurgia e peso; vários campos só servem a alguns tipos; detalhes estruturados viram texto; falta caso/status/impacto/restrição; `vetName` e profissional são redundantes; `dogName` é snapshot duplicado; `weight` é legado |
| `WeightRecord` | pesagem canônica | `context` deve ser enum; falta BCS, medidas, fotos múltiplas, auditoria no model, soft delete e vínculo de timeline/caso; comentário ainda cita `weight_history`, divergindo do código canônico |
| `Feeding` | refeição executada | `period` deve ser enum; `divergencePercent` é derivado mas persistido; `prescriptionAtTime` é snapshot útil; não há `dogId` no payload; soft delete existe sem UI |
| `NutritionPrescription` | plano alimentar | nomes `vigent_*` são erro de convenção consolidado; Web deveria ser única autora; vet fields podem usar entidade profissional; `amountPerMeal` é derivado correto |
| `NutritionSupplement` | suplemento em uso | `status` deve ser enum; não é administração/dose agendada; faltam frequência, agenda, responsável e execuções |
| `DogDocument` | metadado de arquivo | está dentro de `DogProfileService`; `tipo` deve ser enum; não tem auditoria/soft delete/versionamento/caso no model |
| `VaccineRecord` | leitura legada de `vacinas` | duplicado funcional de `HealthLogModel(vaccination)`; obsoleto após migração |
| `DashboardAlert` | alerta legado | não tem due date, resolução, origem clínica ou vínculo com schedule; separado de notificações |
| `NotificationItem` | central de notificações | enum fechado sem Saúde; campos são orientados a ocorrências/treino e não acomodam item de agenda clínica |
| `HistoryEntry`/`RecordDetail` | DTO de apresentação | não deve virar modelo de domínio; contém fallback inventado e inferências de UI |
| `Dog` | K9 e score legado | mistura perfil, snapshots e `readinessStreak`; readiness local é obsoleto para Health v1.0 |

### 7.2 Duplicações e redundâncias

- `HealthLogModel.weight` versus `WeightRecord.weightKg`;
- `HealthLogModel.vetName`, `professionalCrmv` e `professionalClinic` sem `Professional` comum;
- `dogName`/`dogId` dentro do evento apesar do caminho já conter `dogId`; o nome pode ser snapshot histórico útil, mas precisa ser explicitamente nomeado assim;
- `createdBy`, `created_by`, `created_by_uid`, `measured_by`, `performed_by` e `fed_by` representam ator em formatos distintos;
- `delete_reason` e `deleted_reason` são persistidos juntos;
- `lastVaccineDate` string e `_last_vaccine_at` timestamp coexistem no K9;
- `weight`, `_last_weight_kg` e último `weight_record` coexistem;
- `attachmentUrl`, `mediaAttachments` e `DogDocument` representam arquivos sem contrato comum;
- `feeding_events/feedings`, `nutritional_prescriptions/nutrition_prescriptions` e `weight_records/weight_history` são pares canônico/legado;
- `VaccineRecord` e `HealthLogModel(vaccination)` modelam vacina com schemas incompatíveis.

### 7.3 Campos obsoletos, nunca usados ou derivados

**Obsoletos/legados candidatos:** `HealthLogModel.weight`, `vaccines` getter legado, `mapLegacyLogType`, `VaccineRecord`, `lastVaccineDate` string, `lastBathDate` como parte de prontidão clínica, `readinessStreak` clínico.  
**Derivados:** `logType`, `vaccines`, `amountPerMeal`, `isVigentAt`, `isActive`, `isConform`, `divergencePercent` (recalculável), status de vencimento, alertas locais, estatísticas de peso, conformidade e score de prontidão.  
**Sem consumidor relevante encontrado:** `HealthViewModel.addWeightRecord`; ramo Saúde do sheet; `health_logs`; subcoleção `dogs/{dogId}/documents`.

Enums/values objects recomendados: `HealthEventType`, `ClinicalCaseStatus`, `ScheduleStatus`, `OperationalReadinessStatus`, `OperationalRestrictionLevel`, `ExamStage`, `TreatmentStatus`, `DoseStatus`, `DocumentType`, `WeightContext`, `MealPeriod`, `SupplementStatus` e `ProfessionalIdentity`.

## 8. Mapa dos services e backend

| Serviço | Responsabilidade atual | Acoplamentos / problemas |
|---|---|---|
| `HealthService` | CRUD + soft delete de eventos | Firestore direto; get limitado; sem stream/paginação; update genérico; sem transação com snapshot/audit global |
| `HealthViewModel` | estado global de eventos e sincronização do K9 | depende de `DogService`; lista única não indexada; erro de fetch é ocultado; não guarda erro; race entre K9s |
| `WeightHistoryService` | peso canônico, espelho legado, snapshot do K9 e stats | três escritas sequenciais não atômicas; sem injeção de Firestore; model não carrega audit/soft delete |
| `NutritionService` | refeições, prescrição, suplementos, fotos e coexistência | mistura read/write/storage/coexistência; dual write sequencial; prescription write conflita com “Web define” |
| `NutritionViewModel` | stream do dia, histórico, filtros, cálculos | estado global por um K9; erros degradam para vazio; não separa loading/error por fonte |
| `DogProfileService` | vacinas legadas, aptidões, registros, usuários e documentos | baixa coesão; documento de Saúde não deveria estar no service de perfil |
| `StorageService` / `PdfAttachmentService` / `ActivityMediaUploader` | upload | múltiplos caminhos e contratos; progresso/retry não uniforme |
| `DashboardService` | alertas legados e dados do dashboard | falha devolve vazio, indistinguível de ausência real; alertas não são Saúde canônica |
| `AuditService` | audit global e inline | auditoria dupla e best-effort; identidade/campos variam por fluxo |
| `NutritionAiService` + CF | insight operacional | bom candidato isolado; resultado persistido sem provider/histórico de UI unificado |
| Admin Health CFs | criação segura/denormalização/audit log | contrato melhor que escrita cliente, mas mobile não usa; só cria, não cobre ciclos clínicos |

### 8.1 Código morto/provavelmente morto

- ramo Saúde de `DynamicActivitySheet` e controladores auxiliares;
- `HealthViewModel.addWeightRecord`;
- regras/coleção `health_logs` no mobile atual;
- subcoleção `dogs/{dogId}/documents` no mobile atual;
- Admin CFs de criação do ponto de vista do mobile, embora possam atender o painel Web;
- placeholders e builders antigos do `K9ProfilePage` que replicam cards do prontuário;
- fallback mock de `history_data_loader` e conteúdo clínico fictício no detalhe devem ser removidos do modo produção.

## 9. Estado e atualização

Padrão encontrado: `provider` + `ChangeNotifier`; não há Riverpod, Bloc ou Redux.

```text
HealthViewModel (global)
├── _isLoading: bool único
└── _healthLogs: List<HealthLogModel> única
    ├── add/update/delete mutam localmente
    └── fetch substitui a lista inteira

NutritionViewModel (global)
├── _activeDogId
├── stream subscription de refeições do dia
├── prescrição/suplementos
└── histórico e filtros em memória

DogHealthProntuarioScreen (estado local)
├── Stream<Dog?>
├── Future<_HealthProntuarioData>
├── tab selecionada
└── acessa quatro services/VMs diretamente
```

Riscos de estado:

- `HealthViewModel.fetchHealthLogsForDog` não associa resultado ao K9 solicitado; resposta antiga pode substituir a lista após troca;
- tela principal não observa `HealthViewModel`; um evento criado pelo hub exige `_refresh()` para aparecer;
- eventos criados por outro cliente não aparecem em tempo real;
- `Future.wait` falha por inteiro se uma fonte falhar, apagando todas as áreas do prontuário no `FutureBuilder`;
- falhas são muitas vezes transformadas em listas vazias, confundindo “sem dados” com “sem permissão/rede/índice”;
- `isLoading` único bloqueia concorrência e não descreve create/update/fetch;
- VMs globais conservam estado do último K9 e são consumidas por telas paralelas.

## 10. UI e componentes

### 10.1 Componentes reaproveitáveis

- identidade/contexto do K9 no prontuário e hub;
- seletor de tabs e cards de status, após extração para arquivos públicos;
- card de próximas ações e status de vencimento;
- grid de métricas e curva/sparkline de peso;
- lista de timeline e filtros do histórico, após remoção de mocks;
- picker/upload de anexos, unificando `StorageService`, `PdfAttachmentService` e `ActivityMediaUploader`;
- `AppFeedback`, `BinomioHeader`, campos HUD/táticos, loading e empty states;
- cards de plano alimentar, rotina, suplementos e insight de nutrição;
- `AuditService.buildInlineEntry` como base, com identidade padronizada.

### 10.2 Duplicações de UI

- status médico no `K9ProfilePage` versus Resumo do prontuário;
- carteira de vacina em três superfícies;
- evolução/pesagem em prontuário, `WeightHistoryScreen` e perfil;
- nutrição em prontuário, `NutritionFullScreen` e perfil;
- dois formulários genéricos de Saúde: `HealthEventFormScreen` e ramo Saúde do `DynamicActivitySheet`;
- três seletores/pickers de anexo;
- cards/seções privados dentro de um arquivo de 150 KB, impossíveis de reutilizar sem extração.

### 10.3 Framework comum recomendado

Os componentes aprovados no Health v1.0 devem virar camada pública em `features/health/presentation/components` ou design system:

- `HealthDogContextCard` a partir do card de identidade existente;
- `HealthSectionCard` a partir dos containers repetidos;
- `OperationalImpactCard` novo;
- `ProfessionalCard` novo, substituindo campos soltos de veterinário;
- `AttachmentPicker` unificado;
- `AuditCard` ligado a auditoria real;
- `StickySaveBar` reaproveitando controles de save existentes;
- `StatusSelector` tipado;
- `ClinicalMetricGrid` a partir dos mini cards;
- `TimelineCard` a partir de `HistoryTimelineItem` sem dados fictícios.

## 11. Inventário Saúde atual versus Health v1.0

Legenda: **Existe**, **Parcial**, **Não existe**, **Obsoleto**, **Duplicado**.

| Funcionalidade | Classificação | Evidência / gap |
|---|---|---|
| Dashboard/Resumo | Parcial | resumo com status, peso, eventos e alertas derivados; sem readiness clínico canônico |
| Hub de Registros | Parcial | existe e é navegável; não cobre observação diária, agendamento, avaliação preventiva, tratamento, dose, reavaliação e alta como entidades |
| Consultas | Parcial | evento genérico + profissional/observações; sem diagnóstico, conduta, caso, restrição ou alta |
| Vacinas | Parcial / Duplicado | registro, próxima dose, carteira, PDF; duplicado entre `health_events` e `vacinas` |
| Pesagem | Existe / Duplicado | fonte canônica e curva existem; dual write legado e evento duplicado em tela antiga; faltam BCS/medidas/fotos reais |
| Exames | Parcial | evento e anexo; não separa solicitação, coleta, resultado, interpretação e impacto |
| Alimentação | Existe / Duplicado | plano visível, refeição, foto, conformidade e histórico; dual collections |
| Suplementação | Parcial | cadastro e lista; sem administração/dose/agenda/encerramento completo |
| Histórico clínico | Parcial | agregação em memória; não é timeline canônica, completa ou imutável |
| Agenda preventiva | Não existe | apenas `nextDueDate` e texto “agendado”; sem coleção, estados ou tela |
| Tratamentos | Não existe | medicação avulsa em evento genérico não é protocolo |
| Administração de doses | Não existe | sem entidade, schedule, confirmação ou responsável |
| Reavaliação | Não existe | somente datas livres em observação/next due |
| Alta clínica | Não existe | nenhum estado/transição |
| Intercorrências | Parcial | `symptom` genérico com gravidade embutida em texto; sem caso/conduta |
| Documentos | Parcial / Duplicado | upload e lista; contratos raiz/anexo/subcoleção concorrentes, sem vínculo clínico/versionamento |
| Anexos | Parcial / Duplicado | imagem/PDF/Office; múltiplos paths e campos |
| Alertas | Parcial / Obsoleto | cálculo local e coleção legada separada, sem resolução/origem clínica |
| Notificações Saúde | Não existe | enum e serviços não possuem tipos Health |
| Caso clínico | Não existe | não há model, collection ou vínculo |
| Auditoria | Parcial | inline e auditLogs, mas não transacional/uniforme; conteúdo clínico ainda mutável |
| Prontidão operacional | Obsoleto / Parcial | score local legado, sem estados Health v1.0 e sem bloqueios clínicos absolutos |
| Restrições clínicas | Não existe | nenhum contrato/precedência operacional |
| Plano alimentar Web define | Parcial | leitura mobile existe, porém service ainda permite criar plano |
| Timeline única | Não existe | somente view agregada e incompleta |
| Form framework | Parcial / Duplicado | dois formulários e componentes privados; falta contrato comum aprovado |

## 12. Problemas encontrados e riscos

### P0 — bloqueadores de arquitetura clínica

1. Eventos genéricos mutáveis não preservam decisão clínica imutável nem ciclo de vida.
2. Restrições clínicas não bloqueiam prontidão/turno; score legado pode contradizer decisão médica.
3. Não há caso clínico ou vínculo entre intercorrência, consulta, exame, tratamento, reavaliação e alta.
4. Escritas multi-documento do mobile não são atômicas e podem deixar espelhos/snapshots divergentes.
5. Timeline e alertas são derivados no cliente, limitados e incompletos.

### P1 — integridade e coexistência

1. Pesagem duplicada em `WeightHistoryScreen`.
2. Tipos e dados clínicos estruturados armazenados como strings/texto livre.
3. Contratos duplicados de documentos, vacina, peso, refeições e prescrições.
4. Escrita direta mobile diverge das Admin CFs e de sua denormalização `_last_*`.
5. `health_events` ativo depende de consulta composta não versionada.
6. autor/auditor usa UID, RA, email e fallback hardcoded de forma inconsistente.
7. leitura canônica de peso não faz fallback para `weight_history`; dados somente legados podem sumir.

### P1 — segurança e clínica

1. Regras validam auditoria genérica, mas não campos obrigatórios por tipo clínico.
2. Update genérico permite reescrever conteúdo clínico em vez de emitir correção/adendo.
3. Upload é imutável, porém o registro pode perder/reapontar referência em alguns fluxos.
4. Não há regra de autorização específica para veterinário versus condutor nos writes diretos.

### P2 — UX, confiabilidade e manutenção

1. `dog_health_prontuario_screen.dart` concentra mais de 4,6 mil linhas e dezenas de widgets privados.
2. perfil K9 e detalhe de histórico exibem valores fictícios (peso 28 kg, datas, lote, validade, CRMV, arquivo) quando não há dado.
3. cards Antipulgas e Exames navegam para a tela de vacinação.
4. erros de rede/permissão/índice viram estado vazio em vários services.
5. formulários criam `TextEditingController` dentro de `build`, com risco de estado/recursos.
6. histórico carrega ocorrências/treino mesmo no modo prontuário para depois descartá-los.
7. não há pesquisa textual na timeline, embora esteja no roadmap.

### Oportunidades

- transformar peso e nutrição, hoje os subdomínios mais maduros, nos primeiros agregados do novo contrato;
- usar a projeção de timeline para eliminar agregação pesada, duplicação visual e filtros incompletos no cliente;
- concentrar autorização, auditoria, denormalização e dual-write em casos de uso server-side idempotentes;
- extrair os bons componentes visuais do prontuário monolítico para o framework comum aprovado;
- fazer da agenda a origem única de alertas e notificações, substituindo cálculos locais e a coleção `alertas` isolada;
- manter adapters legados como camada explícita e temporária, permitindo evolução sem perda de dados;
- reutilizar o cruzamento já feito pela análise nutricional entre peso, alimentação, treino e Saúde para futuras projeções operacionais, sem permitir que IA decida estado clínico.

## 13. Plano de migração

### 13.1 Reaproveitar

- shells visuais, card de contexto do K9, hub, cards de status, curva de peso e timeline visual;
- `WeightRecord`, `Feeding`, `NutritionPrescription`, `NutritionSupplement` como ponto de partida, após normalização;
- upload e regras de Storage, consolidando paths;
- padrão de auditoria inline e hard-delete bloqueado;
- `NutritionAiService`/CF como recurso adicional, não decisor clínico;
- `HealthTypeSelectorScreen` como catálogo, tornando ações configuráveis e tipadas;
- `HistoryScreen` apenas como referência de UX/filtros, não como persistência;
- denormalização `_last_*` como cache derivado, nunca fonte clínica.

### 13.2 Remover ou aposentar após coexistência

- `HealthLogModel.weight` e `health_event` de pesagem;
- criação duplicada de peso em `WeightHistoryScreen`;
- `VaccineRecord`/coleção `vacinas` quando o backfill e o corte forem comprovados;
- `health_logs` raiz e regras correspondentes se confirmação de dados mostrar ausência de consumidores;
- ramo Saúde órfão do `DynamicActivitySheet` ou, alternativamente, torná-lo o único framework e remover o formulário paralelo;
- placeholders clínicos e fallback mock em telas de produção;
- score local `Dog.calculateReadiness()` como autoridade de Saúde;
- métodos mobile de alteração de plano alimentar após o painel Web assumir o contrato.

### 13.3 Refatorar

- extrair domínio, data, application e presentation em Saúde;
- introduzir repository interface por agregado e casos de uso;
- particionar o prontuário em telas/widgets menores;
- unificar documento/anexo em `HealthDocument` com referências a evento/caso;
- padronizar identidade do ator e timestamps;
- substituir strings por enums/values;
- tornar histórico paginado, consultável e reativo;
- trocar updates clínicos por adendos/correções auditadas;
- mover dual-write/coexistência para backend idempotente ou adaptadores explícitos;
- usar estado keyed por `dogId` com loading/error/data por recurso.

### 13.4 Criar do zero

- `ClinicalCase`, `ClinicalEvent`, `HealthSummary`, `HealthScheduleItem`;
- `TreatmentProtocol` e `DoseAdministration`;
- pipeline de exame com cinco etapas;
- `OperationalImpact`/restrições clínicas e estado de prontidão;
- agenda preventiva e motor de status;
- notificações e deep links de Saúde;
- reavaliação e alta como transições;
- API de correção/adendo imutável;
- framework comum de formulários aprovado;
- política de acesso clínico por papel;
- estratégia de projeção/timeline canônica.

### 13.5 Estratégia de coexistência segura

1. Congelar e documentar os contratos atuais antes de qualquer write novo.
2. Definir IDs idempotentes e `legacy_source/legacy_id` no modelo alvo.
3. Criar adaptadores de leitura que produzam o contrato novo sem alterar dados.
4. Fazer backfill administrativamente, com relatório de contagem e rejeições; nunca pelo mobile.
5. Habilitar dual-read antes de dual-write.
6. Se dual-write for necessário, fazê-lo server-side e em batch/transaction, com retry idempotente.
7. Deduplicar peso e documentos por origem/ID, não por heurística de data.
8. Só desligar coleções legadas após métricas e período de observação.
9. Manter bloqueio de hard delete e transformar correções em eventos/adendos.

## 14. Arquitetura alvo recomendada

```text
features/health/
├── domain/
│   ├── entities/ (case, event, schedule, treatment, dose, exam, document, readiness)
│   ├── value_objects/ (types, statuses, actor, professional, impact)
│   ├── repositories/ (interfaces)
│   └── policies/ (readiness precedence, transitions, validation)
├── application/
│   ├── use_cases/ (register, amend, schedule, administer, discharge)
│   └── projections/ (summary, timeline, agenda)
├── data/
│   ├── firestore/ (DTOs, mappers, query sources)
│   ├── repositories/ (implementations)
│   └── coexistence/ (legacy adapters)
└── presentation/
    ├── state/ (keyed por dogId)
    ├── screens/ (summary, timeline, agenda, nutrition, register)
    └── components/ (framework comum)
```

Modelo lógico alvo alinhado à especificação, com recomendação de evitar múltiplas subcoleções como fontes independentes da timeline:

```text
dogs/{dogId}
├── health_summary/current                    # projeção derivada
├── clinical_cases/{caseId}                  # agregado clínico
│   └── events/{eventId}                     # eventos imutáveis/adendos
├── health_timeline/{eventId}                # projeção unificada e paginável
├── health_schedule/{scheduleId}             # agenda e estados
├── treatment_protocols/{protocolId}
│   └── dose_administrations/{doseId}
├── exam_results/{examId}                    # ou agregado com etapas explícitas
├── weight_records/{id}
├── nutrition_plans/{id}                     # Web escreve
├── meal_logs/{id}                           # Mobile executa
├── supplement_logs/{id}
└── health_documents/{id}
```

Cada entidade deve carregar `dog_id`, `case_id?`, `event_type/status`, `occurred_at`, `recorded_at`, `actor`, `professional?`, `operational_impact`, `source`, `schema_version` e auditoria. A timeline deve ser projeção do servidor e não gravação arbitrária do cliente.

## 15. Roadmap técnico

### Fase 0 — contrato e segurança

- aprovar schema, enums, transições e matriz de papéis;
- definir imutabilidade, adendos e precedência de restrições;
- inventariar dados reais por contagem fora do mobile;
- validar índices necessários e estratégia de backfill.

### Fase 1 — fundação

- criar domínio/application/repositories;
- criar framework de formulários e componentes;
- implementar adapters read-only para fontes atuais;
- criar estado por K9 e tratamento explícito de erro.

### Fase 2 — projeções

- criar `health_summary`, timeline e agenda;
- backfill server-side idempotente;
- expor paginação/cursors;
- incluir documentos, suplementos e todos os tipos.

### Fase 3 — módulos já maduros

- migrar peso, alimentação, suplementos e vacina;
- remover duplicação de pesagem;
- consolidar documentos/anexos;
- manter dual-read temporário.

### Fase 4 — clínica estruturada

- casos clínicos, consulta, intercorrência e restrições;
- pipeline de exames;
- protocolos, doses, reavaliação e alta;
- correções/adendos imutáveis.

### Fase 5 — prontidão, agenda e notificações

- estados de prontidão Health v1.0;
- bloqueios clínicos absolutos;
- agenda preventiva e geração server-side de alertas;
- tipos Health em notificações e deep links.

### Fase 6 — corte e limpeza

- comparar contagens e hashes de projeção;
- desligar writes legados;
- remover telas/services/models órfãos;
- manter readers legados por janela definida;
- atualizar regras/índices somente em tarefa própria, revisada e validada.

## 16. Checklist de implementação

### Contrato

- [ ] Aprovar schema versionado e convenção de nomes.
- [ ] Definir enums e transições válidas.
- [ ] Definir ator/profissional e matriz de autorização.
- [ ] Definir política de imutabilidade, correção e soft delete.
- [ ] Definir precedência de restrição clínica sobre score/IPO.

### Dados

- [ ] Levantar contagens reais de todas as coleções mapeadas.
- [ ] Definir `legacy_source` e chaves idempotentes.
- [ ] Implementar adapters de leitura.
- [ ] Implementar backfill administrativo com dry-run e relatório.
- [ ] Deduplicar pesagens e anexos.
- [ ] Validar todos os índices em emulador antes de produção.
- [ ] Definir rollback/cutover de coexistência.

### Aplicação

- [ ] Criar repositories e use cases.
- [ ] Criar estado keyed por K9.
- [ ] Criar paginação real da timeline.
- [ ] Criar agenda preventiva.
- [ ] Criar casos clínicos e workflow de exame/tratamento/alta.
- [ ] Criar restrições e prontidão.
- [ ] Criar notificações e deep links.

### UI

- [ ] Extrair componentes privados do prontuário.
- [ ] Unificar formulário e anexos.
- [ ] Remover dados fictícios e mocks de produção.
- [ ] Corrigir rotas semânticas do perfil.
- [ ] Implementar loading/error/empty distintos por seção.
- [ ] Validar acessibilidade, alturas, teclado, offline e anexos grandes.

### Integridade e validação futura

- [ ] Garantir batch/transaction/idempotência nas escritas compostas.
- [ ] Garantir auditoria obrigatória e não editável.
- [ ] Testar regras por papel e tipo clínico.
- [ ] Testar concorrência e troca rápida de K9.
- [ ] Testar migração com dados legados reais anonimizados.
- [ ] Validar Web define/Mobile executa em nutrição.
- [ ] Validar bloqueio clínico no turno e prontidão.
- [ ] Só remover legados após observabilidade e aprovação formal.

## 17. Decisões arquiteturais registradas para Health v1.0

1. O mobile prioriza execução rápida; Web administra planos.
2. Evento clínico concluído é imutável; correção gera adendo auditado.
3. Caso clínico conecta intercorrência, consulta, exame, tratamento, reavaliação e alta.
4. Timeline e resumo são projeções server-side de fontes canônicas.
5. Restrição clínica absoluta sempre prevalece sobre score/IPO.
6. Atores, profissionais, anexos e impacto operacional usam contratos comuns.
7. Coexistência é aditiva, idempotente e observável; nenhum hard delete de legado.
8. Dual-write, quando inevitável, ocorre no backend e não em telas.
9. A UI nunca exibe placeholder clínico como se fosse dado real.
10. Falha de fonte não é representada como “sem dados”.

## 18. Payload resumido para memórias externas

### Graphify

- Arquitetura encontrada: feature Saúde central + domínios adjacentes de peso, nutrição, histórico, documentos, alertas e turno.
- Relações: K9 possui eventos, peso, nutrição, documentos e projeções; timeline atual agrega em memória; CF nutricional cruza saúde/peso/nutrição/treino.
- Dependências críticas: `ShiftViewModel -> K9 ativo`, `DogHealthProntuarioScreen -> quatro services + NutritionViewModel`, `HealthViewModel -> HealthService + DogService`.
- Padrões: Provider/ChangeNotifier global, services Firestore diretos, auditoria inline, soft delete, dual collections de coexistência.
- Riscos: evento genérico mutável, duplicação de pesagem, ausência de caso/agenda/tratamento/restrição, telas com placeholder clínico e contratos backend/mobile divergentes.

### Claude Memory (claude-mem)

- Health v1.0 é um Centro de Prontidão, não apenas prontuário.
- Modelo alvo: casos clínicos + eventos imutáveis + timeline/summary/schedule projetados + protocolos/doses/exames/documentos/restrições.
- Restrições: Web define planos; Mobile executa; bloqueios clínicos vencem IPO; hard delete proibido; migração aditiva e idempotente.
- Reutilizar: hub, peso, nutrição, uploads, auditoria, cards e timeline visual.
- Remover/refatorar: score legado como autoridade, placeholders, dual-write em UI, `HealthLogModel` monolítico, telas paralelas e código órfão.
- Roadmap: contrato -> fundação -> projeções -> módulos maduros -> clínica estruturada -> prontidão/agenda/notificações -> corte.

## 19. Conclusão

Há base operacional suficiente para acelerar Health v1.0, especialmente em UI, pesagem, nutrição, anexos e auditoria. Não é seguro, porém, evoluir o `HealthLogModel` genérico adicionando mais campos. A reescrita deve começar pelo contrato clínico, imutabilidade e projeções, mantendo readers legados e movendo writes compostos para o backend. Sem essa fundação, cada nova tela ampliará as duplicações atuais e não resolverá o risco central: prontidão operacional desconectada de decisões clínicas rastreáveis.
