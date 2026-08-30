# ADR-006 — Coexistência com Legado e Migração

| Campo | Valor |
|-------|-------|
| Status | Aprovado |
| Data | 2026-07-13 |
| Branch | `feature/health-v1-foundation` |
| Baseline | `2a0c1e65e592476bddb6e59378456c6f49f02a14` |
| Documentos relacionados | ADR-001, ADR-004, HEALTH_V1_MIGRATION_PLAN.md, HEALTH_MODULE_AUDIT.md §6 |
| Escopo | Estratégia de coexistência, dual-read, migração e aposentadoria de coleções legadas |
| Fora de escopo | Implementação de scripts, Functions, Rules, IPO |

---

## 1. Contexto

O módulo Saúde possui pelo menos 14 fontes de dados legadas em produção. Algumas são pares canônico/legado (ex: `feeding_events`/`feedings`), outras são coleções raiz sem consumidor mobile atual (ex: `health_logs`), e outras contêm dados valiosos em formato incompatível com o Health v1.0 (ex: `health_events` genéricos com medicação em texto livre).

A migração deve ser aditiva — nenhum dado pode ser apagado — e segura — nenhum write novo deve ir ao Firestore antes da aprovação dos contratos. O desafio é definir como ler dados antigos no formato novo, como migrar sem perda, e como aposentar coleções sem afetar funcionalidades ativas.

---

## 2. Problema

Como migrar dados de 14+ fontes legadas para o schema Health v1.0 sem perda, sem interrupção de funcionalidades existentes, com validação e rollback, e sem dual-write no cliente?

---

## 3. Requisitos obrigatórios

1. Nenhum hard delete de dados legados em nenhuma fase.
2. Nenhum dual-write no Mobile (complexidade proibitiva para condutor em campo).
3. Se dual-write for inevitável, deve ser server-side, transacional e idempotente.
4. Todo dado migrado carrega `legacy_source`, `legacy_id`, `schema_version`, `migration_version`.
5. Migração é idempotente: rodar novamente com os mesmos dados produz o mesmo resultado.
6. Dry-run obrigatório antes de qualquer escrita real.
7. Relatório de rejeições: documentos que não podem ser mapeados são listados, não descartados.
8. Reconciliação: contagem de origem = contagem no destino + rejeições documentadas.
9. Rollback: possível antes do cutover e registrado no manifest por operação (`create` ou `update`). Criações podem ser apagadas; updates restauram somente o estado anterior. Proibido após modificação por usuário.
10. Janela de dual-read: mobile lê do schema novo quando disponível, fallback para legado.
11. Encerramento de writes legados: somente após validação de paridade completa e confirmação de que nenhum produtor (Mobile, Web, Functions) ainda escreve no legado.

---

## 4. Opções consideradas

### Opção A — Big Bang Migration

Parar o sistema, migrar tudo de uma vez, religar apontando para schema novo. Sem coexistência.

### Opção B — Dual-write no Mobile

Mobile grava simultaneamente no schema antigo e novo. Após período de observação, desliga writes no antigo.

### Opção C — Adapter pattern com migração server-side progressiva

1. Adapters read-only mapeiam legado → modelo novo no cliente.
2. Backfill server-side preenche schema novo a partir do legado.
3. Dual-read no mobile: tenta schema novo, fallback para adapter legado.
4. Novos writes vão apenas para schema novo (após aprovação).
5. Cutover: desliga fallback quando paridade confirmada.

### Opção D — Projeção como ponte

A projeção de timeline (ADR-004) serve como camada de leitura unificada. Backfill projeta legados. Mobile lê apenas a projeção, nunca as fontes diretamente (exceto para detalhes).

---

## 5. Comparação das opções

| Critério | A (big bang) | B (dual-write mobile) | C (adapter + server) | D (projeção como ponte) |
|----------|-------------|----------------------|---------------------|------------------------|
| Risco de perda | Alto (se falhar) | Baixo | Baixo | Baixo |
| Downtime | Necessário | Zero | Zero | Zero |
| Complexidade mobile | Baixa (troca total) | Alta (2 schemas) | Média (adapters) | Baixa (1 coleção) |
| Complexidade backend | Média | Baixa | Alta | Alta |
| Rollback | Difícil | Médio | Fácil (legado intacto) | Fácil |
| Período de transição | Zero | Longo (meses) | Controlado | Controlado |
| Consistência durante transição | Sem transição | Risco de divergência | Eventual consistency | Eventual consistency |
| Dual-write mobile | Não | Sim (viola req. 2) | Não | Não |

---

## 6. Recomendação

**Opção C — Adapter pattern com migração server-side progressiva**, combinada com elementos da **Opção D** (projeção de timeline como camada de leitura unificada para o histórico).

O mobile NÃO faz dual-write. A migração é responsabilidade exclusiva do backend (Functions administrativas). A transição é gradual e controlada por feature flags.

---

## 7. Consequências positivas

- Coleções legadas preservadas permanecem intactas. Quando uma fonte canônica é normalizada in-place, o manifest registra `before_image` e campos alterados para restauração segura.
- Mobile tem complexidade controlada: adapters são uma camada fina.
- Backfill é repetível e auditável.
- Rollback é determinístico pelo manifest: apaga somente documentos criados pelo batch e restaura `before_image`/`changed_fields` em documentos atualizados in-place; nunca apaga documento preexistente.
- Projeção de timeline unifica a leitura independente da migração.
- Feature flags permitem rollout gradual e rollback rápido.

---

## 8. Consequências negativas

- Período de coexistência adiciona complexidade temporária ao código.
- Adapters são código descartável (debt consciente).
- Backend precisa de Functions administrativas robustas.
- Reconciliação exige monitoramento contínuo.
- Durante transição, há duas fontes de verdade para alguns dados.

---

## 9. Compatibilidade com o legado

### Inventário completo de fontes legadas

| # | Fonte legada | Caminho | Status mobile atual | Dados estimados | Destino no schema novo |
|---|-------------|---------|--------------------|-----------------|-----------------------|
| 1 | health_events | `dogs/{dogId}/health_events/{id}` | Ativo (CRUD) | Principal | **Todos os `health_events` anteriores ao go-live → `dogs/{dogId}/legacy_health_records/{recordId}`.** Nenhum `ClinicalEvent` retroativo é criado; nenhum `clinical_cases` retroativo é criado a partir de `health_events`. Operações administrativas futuras podem preencher `case_id`, atualizar `normalized_view` ou criar evento clínico curado separado quando necessário. |
| 2 | weight_records | `dogs/{dogId}/weight_records/{id}` | Ativo (canônico) | Peso | `weight_records` (mantém, normaliza) |
| 3 | weight_history | `dogs/{dogId}/weight_history/{id}` | Espelho legado | Duplicata | Não migrado como fonte canônica; preservado read-only para auditoria histórica |
| 4 | feeding_events | `dogs/{dogId}/feeding_events/{id}` | **LEGACY CURRENT** (ops dual-write mobile ainda ativo pré-cutover) | Refeições | `meal_logs` — HEALTH V1 TARGET; backfill conservador (offered=amount_grams; sem occurrence inventada) |
| 5 | feedings | `dogs/{dogId}/feedings/{id}` | Espelho legado | Duplicata | Não migrado como fonte canônica; preservado read-only |
| 6 | nutritional_prescriptions | `dogs/{dogId}/nutritional_prescriptions/{id}` | **LEGACY CURRENT** ops | Planos | `nutrition_plans` — TARGET; `vigent_*`→`valid_*` |
| 7 | nutrition_prescriptions | `dogs/{dogId}/nutrition_prescriptions/{id}` | Fallback legado | Duplicata | Read-only histórico |
| 8 | nutrition_supplements | `dogs/{dogId}/nutrition_supplements/{id}` | **LEGACY CURRENT** (regime “em uso”) | Regime, **não** admin pontual | **NÃO** backfill automático → `supplement_logs` (ZERO admin inventada); adapter de estado / curadoria de regimen |
| 9 | vacinas | `vacinas/{id}` (raiz) | Leitura legacy | Vacinas antigas | Backfill → `vaccination_records/{vaccinationId}` quando dados suficientes; caso contrário, `legacy_health_records/{recordId}` (read-only). **Não** backfilar para `clinical_cases/events` nem para "caso preventivo". |
| 10 | documentos | `documentos/{id}` (raiz) | Ativo (upload) | Documentos | `health_documents` (migra com referências) |
| 11 | dogs/{dogId}/documents | Subcoleção | Regras sem uso mobile | Desconhecido | Avaliar no inventário real |
| 12 | health_logs | `health_logs/{id}` (raiz) | Sem consumidor mobile | Desconhecido | Avaliar no inventário real |
| 13 | alertas | `alertas/{id}` (raiz) | Leitura dashboard | Alertas | Substituído por `health_schedule` + `health_summary` |
| 14 | Snapshots no K9 | `dogs/{dogId}._last_*` | Denormalização | Campos | Substituído por `health_summary/current` |
| 15 | health attachments (Storage) | Múltiplos paths | Ativo | Arquivos | Consolidar em path único |

### Destino de todos os health_events anteriores ao go-live

Todos os `health_events` anteriores ao go-live são migrados para o destino abaixo, independentemente de haver agrupamento lógico detectável:

```
dogs/{dogId}/legacy_health_records/{recordId}
```

Características desta coleção:

- **`original_payload` é imutável.** Nenhum write no `original_payload` por nenhum ator.
- **Clientes (Mobile, Web) são read-only** — Rules bloqueiam writes de clientes autenticados.
- **Admin SDK pode atualizar, de forma auditada:** `normalized_view`, `case_id`, `migrated_at`, metadados de reconciliação, e metadados de batch. Não há afirmação absoluta de "nenhum write após o backfill" — há permissões controladas (Admin SDK auditado) para fins administrativos legítimos.
- **Preserva payload original** — campo `original_payload` com o documento fonte inalterado.
- **Visão normalizada** — campos mapeados para exibição na timeline (type, date, description, etc.).
- **Rastreabilidade** — `legacy_source`, `legacy_id`, `legacy_collection` preenchidos.
- **Alimenta a timeline** — Functions projetam na timeline unificada do K9.
- **`case_id` opcional** — preenchido somente via operação administrativa futura que vincule o registro a um caso real.

Novos `ClinicalEvent`s criados pelo sistema sempre pertencem a um `ClinicalCase` real — a subcoleção `clinical_cases/{caseId}/events` é a única localização canônica para eventos clínicos novos.

---

## 10. Impacto em Mobile

### Fase de adapters (leitura) — pré-backfill

> **Importante:** os adapters leem fontes legadas **antes** do backfill. A coleção `legacy_health_records` ainda não existe nessa fase — ela é criada pelo próprio backfill. Por isso, antes do backfill, o adapter lê `health_events` direto. Após o backfill, ele passa a ler `legacy_health_records` como fonte primária.

```text
HealthDataSource (abstração — forma TBD)
├── RawHealthEventsAdapter (lê dogs/{dogId}/health_events → LegacyHealthRecordView/DTO em memória; nunca produz ClinicalEvent; não grava no schema novo)
├── LegacyWeightAdapter (lê weight_records → mapeia para WeightAssessment)
├── LegacyNutritionAdapter (lê feeding_events → mapeia para MealLog)
├── LegacyDocumentAdapter (lê documentos → mapeia para HealthDocument — HealthDocument normalizado usa storage_path canônico; URLs antigas preservadas apenas no payload/metadado legado)
└── LegacyVaccineAdapter (lê vacinas → mapeia para VaccinationRecord ou legacy_health_records)
```

> O `RawHealthEventsAdapter` lê `dogs/{dogId}/health_events` **antes do backfill** e produz `LegacyHealthRecordView` ou DTO de timeline em memória. Ele **nunca** mapeia para `ClinicalEvent` canônico — não há caminho de promoção automática de registro legado a evento clínico.

### Fase de dual-read — pós-backfill

```text
HealthDataSource (abstração — forma TBD)
├── NewSchemaSource (fonte primária — lê legacy_health_records como fonte canônica pós-backfill)
├── RawHealthEventsAdapter (fallback temporário — lê dogs/{dogId}/health_events)
└── merge: quando ambos existem (período de transição)
```

### Fase final

```text
HealthDataSource (abstração — forma TBD)
└── NewSchemaSource (fonte única)
```

---

## 11. Impacto em Web

- Web escreve novos dados apenas no schema novo (desde o go-live).
- Web pode disparar backfill administrativo com dry-run.
- Web mostra dashboard de migração: % migrado, rejeições, divergências.
- Web controla feature flags de cutover.
- **Inventário de acesso por coleção renomeada:** antes do cutover de cada agregado, levantar quais módulos/telas do Web acessam a coleção legada correspondente para garantir que o Web também foi atualizado.

---

## 12. Impacto em Firestore

### Campos de rastreabilidade em todo documento migrado

```
├── legacy_source: string         # ex: "health_events", "vacinas", "documentos"
├── legacy_id: string             # ID original do documento fonte
├── legacy_collection: string     # caminho completo: "dogs/abc/health_events/xyz"
├── schema_version: number        # versão do schema alvo
├── migration_version: string     # versão do script de migração (ex: "1.0.0")
├── migrated_at: timestamp        # quando foi migrado
├── migration_checksum: string    # hash do payload original para detecção de alterações
├── migration_batch_id: string    # referência ao batch que criou este documento
```

### Idempotência

O ID do documento no schema novo é determinístico: `{legacy_source}_{legacy_id}` ou hash previsível. Isso garante que rodar o backfill novamente não cria duplicatas.

### Documento de controle de migração

```
_migrations/health_v1/batches/{batchId}
├── started_at: timestamp
├── completed_at: timestamp
├── source_collection: string
├── dog_id: string (ou "all" para batch global)
├── total_source: number
├── total_migrated: number
├── total_rejected: number
├── total_skipped: number (já migrados)
├── rejections: [ { source_id, reason } ]
├── manifest: [ {
│     operation_type: "create" | "update",
│     target_path: string,
│     target_id: string,
│     before_image: map | null,       # obrigatório para update
│     changed_fields: [string],
│     migrated_at: timestamp,
│     checksum_before: string | null,
│     checksum_after: string
│   } ]
├── dry_run: bool
├── migration_version: string
└── status: "running" | "completed" | "failed" | "rolled_back"
```

### Rollback baseado em manifest

O rollback de um batch é restrito exclusivamente aos documentos listados no campo `manifest` do documento de controle. Regras:

1. **Somente antes do cutover** — após cutover do agregado, rollback é proibido.
2. **Somente docs não modificados por usuário** — se qualquer documento listado no manifest foi alterado após a migração, o rollback é bloqueado.
3. **`operation_type: create`** — pode apagar exclusivamente o documento criado pelo batch.
4. **`operation_type: update`** — restaura `before_image` somente nos `changed_fields`; nunca apaga documento preexistente.
5. **Granularidade de batch** — rollback é por batch completo, não por documento individual.
6. **Status atualizado** — após rollback, o documento de controle recebe `status: "rolled_back"`.

---

## 13. Impacto em segurança

- Backfill é executado via operação administrativa backend/Admin SDK (Admin SDK ignora Rules; o controle vem da governança do backend e da auditoria, não de service account).
- Rules de coleções legadas permanecem ativas durante transição.
- Rules de schema novo são adicionadas incrementalmente.
- Feature flags controlam qual schema o mobile lê/escreve.
- Rollback não requer alteração de Rules (legado nunca foi desligado até cutover).
- Permissões são baseadas em capabilities (não em custom claims de role). O campo `professional` em eventos clínicos identifica o profissional externo responsável; `recorded_by` identifica o usuário interno que registrou o dado.

---

## 14. Impacto em testes

- Testes de adapter: cada adapter mapeia corretamente dados legados reais (anônimos).
- Testes de idempotência: backfill duplo não cria duplicatas.
- Testes de reconciliação: contagem fonte = destino + rejeições.
- Testes de dual-read: mobile funciona com dados em ambos os schemas.
- Testes de cutover por agregado: após desligar legado para um agregado, tudo continua funcionando.
- Testes de rollback: `create` apaga somente documento criado; `update` restaura `before_image`/`changed_fields`; documento preexistente nunca é apagado; rollback é bloqueado após alteração por usuário ou cutover.
- Testes de rejeição: documentos com formato inesperado geram relatório, não erro.
- Testes de `legacy_health_records`: todos os `health_events` pré-go-live migrados corretamente, read-only para clientes, projetados na timeline.

---

## 15. Questões abertas

1. **Dados em `health_logs` raiz:** existem dados reais? Precisamos de inventário antes de decidir. Proposta: incluir na Fase 0 do plano de migração (contagem real).
2. **Dados em `dogs/{dogId}/documents`:** idem. Pode ser coleção fantasma.
3. **Vacinas com formato antigo (antes de `health_events`):** como mapear se não têm os campos do schema novo? Proposta: migrar com campos obrigatórios preenchidos por defaults explícitos marcados como `inferred: true`.
4. **Attachments em Storage com paths antigos:** renomear/mover? Proposta: NÃO mover arquivos. Manter URLs originais nos documentos migrados. Storage é imutável e os paths antigos não conflitam.
5. **Dual-write server-side:** em quais cenários será necessário? Proposta: possivelmente para `weight_records` (durante transição, Function espelha no formato novo quando mobile grava no formato antigo). Avaliar na Fase 3.
6. **Período de dual-read:** quanto tempo? Proposta: mínimo 30 dias após backfill completo com métricas de uso. Máximo 90 dias.

---

## 16. Critérios para aprovação

- [ ] Todas as 15 fontes legadas estão inventariadas com destino definido.
- [ ] Nenhuma fonte prevê hard delete.
- [ ] Dual-write no mobile está explicitamente descartado.
- [ ] Idempotência e reconciliação estão definidas.
- [ ] Rollback é possível antes do cutover, restrito a manifest do batch.
- [ ] Período e condições de cutover (por agregado) estão claros.
- [ ] Feature flags controlam a transição.
- [ ] Todos os `health_events` anteriores ao go-live têm destino definido (`legacy_health_records`), independentemente de agrupamento lógico detectável.

---

## 17. Agregados canônicos e subcoleções

### Distinção importante

| Agregado | Tipo | Observação |
|----------|------|-----------|
| ClinicalCase | Agregado raiz | Contém subcoleção `events` |
| ClinicalEvent | Subcoleção de ClinicalCase | Sempre pertence a um caso real |
| ExamProcess | Agregado próprio (subcoleção) | `clinical_cases/{caseId}/exams/{examId}` — ciclo de vida independente |
| HealthScheduleItem | Agregado canônico | Não é projeção; é a fonte de verdade para agendamento |
| legacy_health_records | Coleção read-only para clientes | Destino de todos os `health_events` anteriores ao go-live; não é agregado ativo |

### ExamProcess como agregado

O `ExamProcess` possui ciclo de vida próprio (requested → collected → resulted → interpreted → impact_assessed → cancelled) e é modelado como subcoleção independente sob o caso clínico:

```
clinical_cases/{caseId}/exams/{examId}
```

Cada transição de estágio gera um ClinicalEvent imutável. Não se confunde com eventos genéricos do caso — tem status, etapas e transições próprias.

### HealthScheduleItem como agregado canônico

`HealthScheduleItem` é a fonte de verdade para itens agendados (vacinas, vermífugos, retornos, exames periódicos). Não é uma projeção derivada de outra coleção — é o agregado canônico que origina notificações e controla compliance temporal.

---

## Diagrama de fases

```text
┌─────────────────────────────────────────────────────────────────────────┐
│ FASE 0 — Inventário Real                                                │
│ Contar documentos reais em cada coleção. Identificar formatos           │
│ inesperados. Mapear IDs duplicados entre pares canônico/legado.         │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ FASE 1 — Adapters Read-Only                                             │
│ Mobile usa adapters para ler legado no formato novo.                    │
│ Nenhum write novo. Nenhuma alteração no legado.                         │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ FASE 2 — Schema Novo (vazio)                                            │
│ Criar coleções e Rules do schema novo. Validar com emulador.            │
│ Mobile não lê/escreve ainda (feature flag off).                         │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ FASE 3 — Backfill Dry-Run                                               │
│ Function administrativa lê legado e simula escrita no schema novo.      │
│ Produz relatório: migráveis, rejeitados, já existentes.                 │
│ NENHUMA escrita real.                                                   │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ FASE 4 — Backfill Real                                                  │
│ Function escreve no schema novo com legacy_source/legacy_id.            │
│ Idempotente. Manifest no documento de controle.                         │
│ Fontes preservadas ficam intactas; updates in-place têm before_image.   │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ FASE 5 — Dual-Read                                                      │
│ Mobile lê schema novo como primário, fallback para adapter legado.      │
│ Writes novos vão para schema novo. Writes em features não migradas      │
│ continuam no legado.                                                    │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ FASE 6 — Validação de Paridade                                          │
│ Comparar contagens, hashes e amostras entre schema novo e legado.       │
│ Resolver divergências. Confirmar que nenhum dado foi perdido.           │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ FASE 7 — Cutover (por agregado)                                         │
│ Coordenado: Mobile + Web + Functions + Rules + índices atualizados.     │
│ Versão mínima do app definida. Adapters legados removidos por agregado. │
│ Fallback desligado para o agregado em questão.                          │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ FASE 8 — Bloqueio de Writes Legados (por agregado)                      │
│ Rules bloqueiam create/update nas coleções legadas migradas.            │
│ Leitura permanece aberta (compatibilidade reversa).                     │
│ Somente após confirmação de que nenhum produtor escreve no legado.      │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ FASE 9 — Remoção dos Adapters (futuro, por agregado)                    │
│ Código de adapters legados removido do mobile.                          │
│ Somente quando nenhum produtor pode escrever no legado.                 │
│ Dados legados permanecem no Firestore (never delete).                   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Tabela de mapeamento resumida

| Fonte legada | Schema alvo | Estratégia |
|--------------|-------------|-----------|
| `health_events` (qualquer tipo) | `dogs/{dogId}/legacy_health_records/{recordId}` | **Contrato conservador único:** todos os `health_events` anteriores ao go-live vão para `legacy_health_records` com `original_payload` preservado. Nenhum `ClinicalEvent` retroativo é criado em `clinical_cases/events`. Operações administrativas futuras podem vincular `case_id`, atualizar `normalized_view` ou criar evento clínico curado separado quando clinicamente justificado. |
| `weight_records` | `weight_records` (normalizado) | In-place normalization + campos extras |
| `weight_history` | — | Não migrado como fonte canônica; preservado read-only para auditoria histórica |
| `feeding_events` | `meal_logs` | Rename + normalização conservadora (5B D10/D32); **sem** inventar plan/occurrence |
| `feedings` | — | Não migrado como fonte canônica; read-only histórico |
| `nutritional_prescriptions` | `nutrition_plans` | Rename + normalização (valid_*, meal_schedule, 1 active) |
| `nutrition_prescriptions` | — | Read-only histórico |
| `nutrition_supplements` | **não** `supplement_logs` automático | Regime legado ≠ admin pontual; ZERO SupplementLog retroativo (5B D16) |

### Nutrição Health v1 — coexistência e cutover (Fase 5B)

```text
NOVO CÓDIGO (contrato canônico):
  ZERO dual-write permanente

LEGACY CURRENT (pré-cutover):
  NutritionService ainda pode dual-write feeding_events + feedings
  — não estender; cutover elimina writes legados

Migração:
  single-write canônico
  dual-read temporário (canônico vence em conflito)
  backfill idempotente (após inventário prod)
  paridade de leitores
  cutover
  legado read-only
  remoção futura de dual-write e paths mortos
```

Paths **HEALTH V1 TARGET:**

```text
dogs/{dogId}/nutrition_plans/{planId}
dogs/{dogId}/meal_logs/{mealId}
dogs/{dogId}/supplement_logs/{logId}
```

Writers TARGET: backend callables (plan Web-originated; meal/supplement Mobile-initiated).
Mobile plan: **read-only**.
| `vacinas` (raiz) | `vaccination_records/{vaccinationId}` (dados suficientes) ou `legacy_health_records/{recordId}` (incompletos) | Migração direta para VaccinationRecord quando há dados suficientes; caso contrário preservada em legacy_health_records read-only |
| `documentos` (raiz) | `health_documents` | Backfill; URLs de Storage mantidas |
| `dogs/{dogId}/documents` | Avaliar (possivelmente vazio) | Inventário na Fase 0 |
| `health_logs` (raiz) | Avaliar (possivelmente sem dados) | Inventário na Fase 0 |
| `alertas` (raiz) | Substituído por `health_schedule` + notificações | Não migrar; aposentar |
| `_last_*` no K9 | Substituído por `health_summary/current` | Manter como cache legado; não é mais fonte |

---

## Integração de Pesagem (WEIGHT-00C)

`weight_records` permanece canônico. O target proíbe novos writes em
`weight_history`. Registros sem campos do novo lifecycle usam bridge somente em
leitura: `legacy_simple`, `valid`, revision 1 no read model, sem inferir fatos
ausentes. BCS legado 1–9 não é convertido automaticamente.

`adminCreateK9WeightRecord`, `appendK9WeightRecord`, writes client-side e
denormalização Web best-effort são dívida bloqueante, não writers aceitos. Sua
retirada será controlada, com bridge antes de Rules endurecidas, lazy migration
somente auditada e backfill apenas após dry-run e aprovação. IDs, receipts,
histórico e os registros conhecidos do Apolo 32.0/33.3 kg devem ser preservados.
Ver ADR-008 e `../HEALTH_WEIGHT_CANONICAL_SPEC.md`.
