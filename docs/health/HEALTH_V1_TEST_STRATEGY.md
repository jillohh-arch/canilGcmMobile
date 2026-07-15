# Health v1.0 — Estratégia de Testes

| Campo | Valor |
|-------|-------|
| Status | Aprovado |
| Data | 2026-07-14 |
| Branch | `feature/health-v1-foundation` |
| Baseline | `2a0c1e65e592476bddb6e59378456c6f49f02a14` |
| Documentos relacionados | Todos os ADRs, HEALTH_V1_DOMAIN_MODEL.md, HEALTH_V1_FIRESTORE_SCHEMA.md |
| Escopo | Categorias de teste, gates por fase, cobertura mínima, ferramentas |
| Fora de escopo | Implementação dos testes, código Dart, CI/CD |

---

## 1. Categorias de teste

### 1.1 Testes de domínio (unit)

**O quê:** entidades, value objects, enums, transições de estado, invariantes de negócio.

**Cobertura esperada:**
- Todas as transições de `ClinicalCaseStatus` (válidas e inválidas).
- Todas as transições de `ClinicalEventStatus`.
- Todas as transições de `TreatmentStatus`.
- Todas as transições de `ExamStage` (requested → collected → resulted → interpreted → impact_assessed → cancelled).
- Precedência de restrições (absolute > partial > attention).
- Validações de campos obrigatórios por entidade.
- Cálculos derivados (divergence_percent, is_conforming, is_late, etc.).
- Derivação de estados temporais do HealthScheduleItem em tempo de leitura (scheduled, upcoming, today, pending, overdue).

**Ferramentas:** `flutter_test`, sem dependência de Firebase/Firestore.

**Critério de sucesso:** 100% das transições e invariantes documentados no Domain Model.

---

### 1.2 Testes de transição de estado

**O quê:** máquina de estados do ClinicalCase, ClinicalEvent e ExamProcess, validando que transições proibidas lançam exceção ou retornam erro.

**Cobertura esperada:**
- Cada par (estado_atual, ação) → estado_resultante OU erro.
- ClinicalCase: 6 estados × N ações = todas as combinações.
- ClinicalEvent: 3 estados × N ações (draft, final, cancelled).
- TreatmentProtocol: 4 estados × N ações.
- ExamProcess: 6 estados × N ações (requested, collected, resulted, interpreted, impact_assessed, cancelled).

**Ferramentas:** `flutter_test`, tabela de transições parametrizada.

**Critério de sucesso:** nenhuma transição possível fora do diagrama aprovado.

---

### 1.3 Testes de acesso a dados (repositories/services)

**O quê:** camada que acessa Firestore — seja via repository interface, service com injeção, ou padrão a definir no ADR de arquitetura interna.

**Cobertura esperada:**
- CRUD completo por entidade.
- CRUD do ExamProcess como subcoleção independente.
- Paginação por cursor.
- Filtros (por tipo, período, caso, status).
- Ordenação correta.
- Soft delete (campo deleted_at exclui de queries padrão).
- Campos de auditoria preenchidos corretamente.
- Idempotência de IDs determinísticos (backfill).
- Leitura de `legacy_health_records` (read-only, projeção na timeline).

**Ferramentas:** `fake_cloud_firestore` ou Firebase Emulator + `flutter_test`.

**Critério de sucesso:** cada método de acesso a dados tem ao menos 1 happy path + 1 erro esperado.

---

### 1.4 Testes de adapters legados

**O quê:** adapters que mapeiam formato legado → modelo novo.

**Cobertura esperada:**
- Cada adapter mapeia corretamente amostra representativa.
- Campos ausentes no legado geram defaults explícitos (não null inesperado).
- Campos extras no legado são ignorados sem erro.
- IDs determinísticos gerados são estáveis.
- `legacy_source` e `legacy_id` preenchidos corretamente.
- **Pré-backfill:** `RawHealthEventsAdapter` lê `dogs/{dogId}/health_events`, produz `LegacyHealthRecordView` ou DTO de timeline em memória, nunca produz `ClinicalEvent` e não grava no schema novo. **Pós-backfill:** `NewSchemaSource` lê `legacy_health_records` como fonte primária; durante dual-read, `RawHealthEventsAdapter` permanece apenas como fallback temporário.

**Ferramentas:** `flutter_test` com fixtures JSON de dados legados anônimos.

**Critério de sucesso:** 100% dos tipos de evento legado mapeados sem exceção.

---

### 1.5 Testes de idempotência

**O quê:** garantir que operações repetidas produzem o mesmo resultado.

**Cobertura esperada:**
- Backfill executado 2x: nenhuma duplicata.
- Function de projeção disparada 2x para mesmo evento: 1 doc na timeline.
- Dose administrada com retry: 1 registro (validação via `doseId = hash(protocolId + planned_dose_id)` — ID determinístico, derivado apenas desses dois valores, sem data nem timestamp de relógio).
- Restrição criada com retry: 1 documento.
- ExamProcess criado com retry: 1 documento na subcoleção.

**Ferramentas:** Firebase Emulator + testes de integração.

**Critério de sucesso:** toda operação idempotente testada com execução dupla.

---

### 1.6 Testes de migração

**O quê:** script de backfill produz resultado correto a partir de dados legados.

**Cobertura esperada:**
- Cada coleção fonte mapeada → destino correto.
- **Todos** os `health_events` (qualquer tipo, com ou sem agrupamento lógico detectável) → `dogs/{dogId}/legacy_health_records/{recordId}`. **Nenhum** `ClinicalEvent` é criado retroativamente em `clinical_cases/events`. Contrato conservador único.
- `legacy_health_records`: payload original preservado, visão normalizada correta, read-only.
- Documentos com formato inesperado → rejeição documentada (não crash).
- Relatório de contagem: source = migrated + rejected.
- Checksums: hash do payload fonte reproduzido no campo `migration_checksum`.
- `migration_batch_id` preenchido corretamente referenciando o batch.
- Manifest registra todas as operações com `operation_type`, alvo, checksums e `before_image`/`changed_fields` para updates.
- Rollback de `create` apaga apenas documento criado pelo batch.
- Rollback de `update` restaura `before_image` somente nos `changed_fields`.
- Rollback nunca apaga documento preexistente e é proibido após modificação por usuário ou cutover.
- Dry-run: nenhuma escrita real.
- Re-execução: zero novos writes.
- Documento de controle em `_migrations/health_v1/batches/{batchId}`.

**Ferramentas:** Firebase Emulator + Node.js test runner (para Functions).

**Critério de sucesso:** paridade 100% entre dry-run e execução real em emulador.

---

### 1.7 Testes de Rules

**O quê:** Firestore Security Rules validam acesso por capability e estado.

**Cobertura esperada por coleção:**
- Create permitido para capability correta com payload válido.
- Create bloqueado para capability ausente.
- Create bloqueado para payload inválido (campo obrigatório ausente).
- Update permitido em draft pelo autor.
- Update bloqueado em final (exceto cancelamento via `health.cancel_record`, que requer `cancel_reason`).
- Read permitido somente quando `isAuthenticated() && canAccessDogRecord(dogId) && hasCapability('health.read')`, inclusive para registros, timeline, summary e `legacy_health_records`.
- Leitura testada explicitamente em `clinical_cases`, `events`, `amendments`, `exams`, `treatment_protocols`, `doses`, `weight_records`, `nutrition_plans`, `meal_logs`, `supplement_logs`, `health_documents`, `operational_restrictions`, `vaccination_records`, `health_schedule`, `legacy_health_records`, `health_timeline` e `health_summary/current`.
- Usuário com `health.read` não recebe acesso acidental a coleções não-Health sob `dogs/{dogId}`.
- Delete bloqueado (hard delete proibido).
- **Projeções: write bloqueado para todos os clientes.** Admin SDK IGNORA Firestore Rules; portanto o bloqueio se aplica a clientes autenticados, não ao backend.
- **`legacy_health_records`: write bloqueado para clientes (read-only para clientes). `original_payload` permanece imutável; Admin SDK auditado pode atualizar `normalized_view`, `case_id` e metadados.**
- Restrições: create apenas por capability clínica (profissional externo registrado via `professional`).
- ExamProcess: transições de status validadas nas Rules.

**Ferramentas:** `@firebase/rules-unit-testing` + Firebase Emulator.

**Critério de sucesso:** 100% das operações da Permission Matrix testadas.

---

### 1.8 Testes de Functions (backend)

**O quê:** Cloud Functions que projetam timeline, atualizam summary, gerenciam schedule, e realizam escritas administrativas.

**Cobertura esperada:**
- Trigger onCreate → projeção correta na timeline.
- Trigger onUpdate (status change) → projeção atualizada.
- Trigger de restrição → snapshot de prontidão recalculado.
- Trigger de dose → contadores de protocolo atualizados.
- Reconciliação → detecta e corrige divergências.
- Erro de Function → retry automático sem duplicação.
- **Escritas administrativas em projeções (health_summary, timeline) validadas.**
- **Escritas em `legacy_health_records` durante backfill são operações administrativas via Admin SDK** (Rules bloqueiam clientes). Testes de Functions validam o backfill; testes de Rules validam que clientes não podem escrever.
- **Validação de restrições canônicas ao iniciar turno (server-side).**

**Ferramentas:** Firebase Emulator + Jest/Mocha.

**Critério de sucesso:** cada trigger tem teste de happy path + caso de erro + idempotência.

---

### 1.9 Testes de widgets

**O quê:** componentes visuais do framework comum de Health.

**Cobertura esperada:**
- Renderização correta para cada estado (loading, data, error, empty).
- Badge de prontidão exibe cor e label corretos para cada estado.
- Timeline card exibe dados do modelo sem crash para campos opcionais null.
- Timeline card exibe registros de `legacy_health_records` corretamente.
- Formulários validam campos obrigatórios antes de submit.
- Componentes de restrição exibem nível com iconografia correta.
- ExamProcess card exibe etapas e status corretos.

**Ferramentas:** `flutter_test` + `golden_toolkit` (opcional para regressão visual).

**Critério de sucesso:** cada componente público tem teste de renderização.

---

### 1.10 Testes de navegação

**O quê:** fluxos de navegação dentro do módulo Health.

**Cobertura esperada:**
- Resumo → Histórico → Detalhe do evento.
- Resumo → + Registrar → Hub → Formulário → Salvar → Retorno.
- Resumo → Agenda → Item → Marcar concluído.
- Timeline → Filtrar por tipo → Resultado correto.
- Caso clínico → Eventos → Adendo → Retorno.
- Caso clínico → ExamProcess → Etapas → Retorno.
- Deep link de notificação → tela correta.

**Ferramentas:** `flutter_test` com `WidgetTester` e navigation mocking.

**Critério de sucesso:** cada rota principal alcançável por teste.

---

### 1.11 Testes offline

**O quê:** comportamento quando Firestore está offline.

**Cobertura esperada:**
- Leitura usa cache local (timeline, summary, schedule).
- Criação de rascunho funciona offline (enfileira write).
- Indicador visual de "offline" presente.
- Ao reconectar: writes pendentes são sincronizados.
- Conflito de write (outro dispositivo alterou) é tratado.

**Ferramentas:** Firebase Emulator com simulação de desconexão + integration test.

**Critério de sucesso:** fluxos principais de leitura e rascunho funcionam sem rede.

---

### 1.12 Testes de concorrência

**O quê:** operações simultâneas de múltiplos dispositivos/usuários.

**Cobertura esperada:**
- Dois condutores administram doses do mesmo protocolo simultaneamente: sem duplicação (garantia via `doseId = hash(protocolId + planned_dose_id)` determinístico).
- Usuário interno autorizado registra restrição emitida pelo profissional externo, enquanto condutor registra evento no mesmo caso: ambos persistem.
- Function de projeção e write do cliente em race condition: projeção eventual correta.
- Troca rápida de K9 (cenário §1.13).

**Ferramentas:** Integration tests com múltiplas instâncias contra emulador.

**Critério de sucesso:** nenhuma perda de dados ou estado inconsistente em cenários de race.

---

### 1.13 Troca rápida de K9

**O quê:** condutor muda de K9 rapidamente na UI.

**Cobertura esperada:**
- Estado do K9 anterior é limpo antes de carregar o novo.
- Nenhum dado do K9 anterior "vaza" para o novo.
- Requests em andamento do K9 anterior são cancelados.
- Loading/error são por K9 (keyed state).

**Ferramentas:** `flutter_test` com widget tester simulando trocas rápidas.

**Critério de sucesso:** 10 trocas em sequência rápida → estado final correto.

---

### 1.14 Testes de paginação

**O quê:** cursor-based pagination em timeline e schedule.

**Cobertura esperada:**
- Primeira página retorna N itens.
- Próxima página começa onde a anterior parou (sem gap, sem duplicata).
- Última página retorna < N itens e sinaliza fim.
- Filtro + paginação: consistente.
- Inserção entre páginas: não duplica ao navegar de volta.

**Ferramentas:** Firebase Emulator com dataset de 200+ itens.

**Critério de sucesso:** paginação completa sem itens perdidos ou duplicados.

---

### 1.15 Testes de anexos

**O quê:** upload, referência e exibição de arquivos.

**Cobertura esperada:**
- Upload de imagem → `storage_path` persistido no `HealthDocument`; URL é derivada via Storage API sob demanda, **não** salva como fonte.
- Upload de PDF → `storage_path` persistido; URL é derivada.
- Arquivo > 20MB → rejeitado com mensagem.
- Tipo não permitido → rejeitado.
- Referência de anexo em evento migrado (URL legada) → exibe corretamente via lookup de `storage_path`.
- Storage Rules: acesso restrito a autenticados com acesso ao K9.
- Projeções (timeline) carregam apenas contagem de anexos (`attachment_count`), não URLs inline.

**Ferramentas:** Firebase Emulator (Storage) + integration test.

**Critério de sucesso:** upload/download funcionais; rejeições claras; identidade canônica é `storage_path`, URL é derivada.

---

### 1.16 Testes de permissões (capability-based)

**O quê:** capacidades de negócio verificadas por capability (não por role/custom claim).

**Cobertura esperada:**
- Cada célula da matriz: capability × operação → permitido/bloqueado.
- Capability clínica → permite ações clínicas (criar restrição, dar alta, etc.).
- Capability ausente → bloqueia ações clínicas.
- Executor candidato com `health.cancel_case` pode cancelar administrativamente com `cancel_reason`; o mapeamento para perfil permanece provisório até O1.
- Executor candidato com a capability específica pode registrar rotina ou intercorrência; alta exige `health.discharge_case` e seu contrato de evidência. Testes de perfil entram somente após O1.
- `professional` (externo) registrado no evento; `recorded_by` (interno) é quem digitou.
- Projeções (health_summary, timeline) → write bloqueado para qualquer cliente.

**Ferramentas:** `@firebase/rules-unit-testing` + Flutter integration tests.

**Critério de sucesso:** 100% da Permission Matrix coberta.

---

### 1.17 Testes de restrições clínicas

**O quê:** fluxo completo de restrição → impacto na prontidão → impacto no turno.

**Cobertura esperada:**
- Criar restrição absolute → snapshot muda para `temporarily_unfit`.
  - Registro: usuário interno autorizado cria `OperationalRestriction` com `professional` (ProfessionalIdentity) + `source_document`.
- Encerrar restrição → snapshot recalcula corretamente.
- Duas restrições simultâneas → estado mais restritivo prevalece.
- Restrição parcial → atividades específicas bloqueadas na seleção de K9.
- K9 `temporarily_unfit` → bloqueado de iniciar turno.
- **Validação server-side de restrições canônicas ao iniciar turno** (Function verifica prontidão antes de permitir embarque).

**Ferramentas:** Firebase Emulator + integration tests end-to-end.

**Critério de sucesso:** precedência funciona conforme Readiness Policy.

---

### 1.18 Testes de regressão (Training e Shifts)

**O quê:** garantir que Health não quebra módulos existentes.

**Cobertura esperada:**
- Todos os 183+ testes existentes permanecem verdes.
- Navegação de Shifts → Saúde funciona.
- `BinomioHeader.onDogHealthTap` alcança prontuário.
- `ActiveShiftQuickActions` → acessa Health sem erro.
- Training não é afetado por novos providers de Health.

**Ferramentas:** `flutter test` (suíte existente) + smoke tests manuais.

**Critério de sucesso:** zero regressões em testes existentes.

---

### 1.19 Testes de idempotência de doses

**O quê:** garantir que administração de doses com retry não duplica registros.

**Cobertura esperada:**
- Dose submetida com mesmo `doseId = hash(protocolId + planned_dose_id)` 2x → 1 registro (via ID determinístico ou create transacional/idempotente).
- `idempotency_key` (campo de rastreabilidade) repete o mesmo valor determinístico de `doseId` — **não** inclui `date`, `YYYYMMDD` nem timestamp de relógio.
- Submissões com `doseId` diferentes (planned_dose_id diferente) → registros distintos.
- Function de contagem de protocolo recalcula corretamente com dose duplicada rejeitada.
- A garantia de unicidade vem do `doseId` determinístico; `idempotency_key` é apenas rastreabilidade.

**Ferramentas:** Firebase Emulator + integration tests.

**Critério de sucesso:** nenhuma duplicação em cenário de retry; contadores consistentes; contrato `doseId = hash(protocolId + planned_dose_id)` estritamente respeitado.

---

### 1.20 Testes de legacy_health_records

**O quê:** coleção read-only para clientes que preserva **todos os `health_events` anteriores ao go-live** (contrato conservador único).

**Cobertura esperada:**
- Migração: **todos** os `health_events` (qualquer tipo, com ou sem agrupamento lógico detectável) → `legacy_health_records` com payload original + visão normalizada. Nenhum `ClinicalEvent` retroativo é criado em `clinical_cases/events`.
- Read: timeline exibe registros corretamente.
- Write bloqueado para clientes: cliente não consegue criar/atualizar/deletar.
- Updates administrativos via Admin SDK auditado: Admin SDK consegue atualizar `normalized_view`, `case_id` e metadados de reconciliação com auditoria.
- `original_payload` permanece **sempre imutável** — nenhuma escrita o altera.
- `case_id` opcional: preenchido somente via confirmação administrativa (operação backend/Admin SDK).
- Projeção: Function projeta na timeline unificada do K9 a partir de `legacy_health_records`, **não** diretamente de `health_events`.
- `legacy_source`, `legacy_id`, `legacy_collection` preenchidos corretamente.
- Pré-backfill: `RawHealthEventsAdapter` lê `health_events`, retorna `LegacyHealthRecordView` ou DTO de timeline em memória, nunca cria `ClinicalEvent` e não grava no schema novo.
- Pós-backfill: `NewSchemaSource` lê `legacy_health_records` como fonte primária; no dual-read, `RawHealthEventsAdapter` é fallback temporário.

**Ferramentas:** Firebase Emulator + `@firebase/rules-unit-testing` + integration tests.

**Critério de sucesso:** read-only para clientes; exibição correta na timeline; payload original intacto; Admin SDK auditado para atualizações administrativas.

---

### 1.21 Testes de cutover por agregado

**O quê:** validar que o cutover coordenado por agregado funciona sem impactar agregados ainda em transição.

**Cobertura esperada:**
- Cutover do agregado A não afeta leitura/escrita do agregado B (ainda em dual-read).
- Após cutover: mobile lê exclusivamente schema novo para o agregado.
- Após cutover: write na coleção legada do agregado retorna erro.
- Rollback de batch proibido após cutover (manifest-based rollback bloqueado).
- Versão mínima do app: versões anteriores recebem force update.
- Web não escreve mais na coleção legada do agregado migrado.

**Ferramentas:** Firebase Emulator + integration tests multi-agregado.

**Critério de sucesso:** isolamento entre agregados em fases diferentes confirmado.

---

### 1.22 Testes de HealthScheduleItem (estados temporais)

**O quê:** derivação de estados temporais em tempo de leitura (não persistidos), com **data efetiva única** e precedência absoluta.

**Data efetiva única:**

```text
effective_due_until =
  due_until
  ?? resolveTolerance(schedule_type, scheduled_for, timezone)
```

Quando `due_until` ausente, a configuração por `schedule_type` deve fornecer tolerância válida. Sem default universal.

**Cobertura esperada (precedência absoluta; primeira condição verdadeira vence):**
1. `lifecycle_status == "completed"` → `completed` (terminal).
2. `lifecycle_status == "cancelled"` → `cancelled` (terminal).
3. `now > effective_due_until` → `overdue`.
4. `now >= scheduled_for` → `pending`.
5. `scheduled_for` é hoje (mesma data no timezone do item) → `today`.
6. item dentro da janela próxima (≤ N dias, configurável por `schedule_type`) → `upcoming`.
7. restante → `scheduled`.

- Não existe caso em que o mesmo item seja `pending` e `overdue` simultaneamente.
- Timezone do item é obrigatório em toda derivação.
- Lógica de derivação é pura (testável sem Firestore).
- Mudança de data do sistema altera o estado derivado corretamente.
- Nenhuma escrita em Firestore é necessária para mudança de estado temporal.

**Ferramentas:** `flutter_test` (unit puro, sem dependência de Firestore).
**Critério de sucesso:** todos os estados temporais derivados corretamente para combinações de datas; precedência única respeitada.

---

### 1.23 Testes de ExamProcess (agregado)

**O quê:** ciclo de vida completo do ExamProcess como subcoleção independente.

**Cobertura esperada:**
- Criação em `clinical_cases/{caseId}/exams/{examId}`.
- Transições de status: requested → collected → resulted → interpreted → impact_assessed (cancelled é terminal a partir de qualquer estado).
- Transições inválidas bloqueadas (ex: requested → impact_assessed direto).
- Cada transição de estágio gera ClinicalEvent imutável com `exam_id` correspondente.
- Múltiplos ExamProcess no mesmo caso: independentes entre si.
- Anexos de resultado vinculados ao ExamProcess via `attachment_refs` em ClinicalEvent.
- Projeção na timeline do caso (apenas estágios finalizados/cancelados).
- Rules: create/update por capability correta; read exige `canReadHealth(dogId)`, incluindo `health.read`.
- Catálogo principal de `ClinicalEvent.event_type` contém `reopen`, com payload `reopen_v1`.

**Ferramentas:** Firebase Emulator + `flutter_test` + integration tests.

**Critério de sucesso:** ciclo de vida completo testado; isolamento entre processos confirmado.

---

### 1.24 Testes de VaccinationRecord (13º agregado)

**O quê:** VaccinationRecord como agregado canônico independente, separado de ClinicalCase. Representa vacinação **efetivamente registrada** — não planejamento.

**Cobertura esperada:**
- Criação em `dogs/{dogId}/vaccination_records/{vaccinationId}` (independente de caso).
- `record_status` aceita **apenas** `final` ou `cancelled`. **Não** aceita `scheduled` nem `overdue` — esses estados vivem exclusivamente em `HealthScheduleItem`.
- `applied_at` é obrigatório quando `record_status == final`.
- Quando aplicação foi execução interna devidamente autorizada: `professional: null` e `source_document: null`; auditoria via `recorded_by`. Não se inventa profissional externo.
- Quando aplicação é externa: `professional` (ProfessionalIdentity) e `source_document` obrigatórios.
- `case_id` opcional: preenchido somente quando há reação adversa ou vínculo terapêutico real e documentado; não transforma o registro em evento do caso.
- Registro NÃO cria ClinicalCase automaticamente.
- Aplicação registrada cria `HealthScheduleItem` (schedule_type: vaccination) para a próxima dose — nunca coexiste como `VaccinationRecord scheduled`.
- VaccinationRecord gera entrada na HealthTimeline (timeline_type: vaccination).
- Migração de vacinas legadas com dados suficientes vai para VaccinationRecord; incompletos permanecem em `legacy_health_records` (read-only para clientes).
- ClinicalEvent do tipo `vaccination` só existe quando há relevância clínica dentro de um caso e referencia `vaccination_record_id`.
- Prontidão lê vacinação vigente de `vaccination_records`, não de `clinical_cases/events`.

**Ferramentas:** Firebase Emulator + `flutter_test` + integration tests.
**Critério de sucesso:** VaccinationRecord opera como agregado independente; apenas `final`/`cancelled` persistidos; planejamento de próxima dose vive em `HealthScheduleItem`; prontidão lê vacinação vigente de `vaccination_records`.

---

### 1.25 Testes de derivação temporal — sinopse (referência: §1.22)

**O quê:** este cenário é uma **sinopse de referência** ao §1.22. A especificação detalhada da precedência temporal, da `effective_due_until` e dos casos de borda vive em §1.22 e **não** é duplicada aqui. Esta seção existe apenas para confirmar que a regra temporal está coberta em uma categoria dedicada do gate da Fase 8.

**Cobertura esperada (resumo):**
- Mesma `effective_due_until`, mesma precedência absoluta e mesmo conjunto de estados derivados documentados em §1.22.
- Esta seção **não** redefine a regra; ela aponta para §1.22 e confirma que testes de borda adicionais (mudança de fuso, simulação de "agora" via injeção de clock) também pertencem a §1.22.
- Cobertura adicional específica deste cenário:
  - Inexistência de classificação simultânea `pending` + `overdue` para o mesmo item.
  - Configuração por `schedule_type` aplicada quando `due_until` ausente.
  - Regras bloqueiam qualquer write de campo temporal derivado.

**Ferramentas:** `flutter_test` (unit puro, sem dependência de Firestore).
**Critério de sucesso:** §1.22 passa; este cenário passa ao referenciar §1.22 sem redefinições.

---

### 1.26 Testes das quatro capabilities novas

**O quê:** capabilities adicionadas nesta rodada — `health.reopen_case`, `health.cancel_case`, `health.complete_treatment`, `health.manage_schedule`.

**Cobertura esperada por capability:**
- `health.reopen_case`:
  - Permitida apenas em `ClinicalCase` com `clinical_status == "discharged"`.
  - Atualiza `reopened_at`, `reopened_by`, `previous_status`, `reopened_count`, `reopen_reason`.
  - Cria ClinicalEvent com `event_type: reopen` e `payload_type: reopen_v1`.
  - Exige `reopen_reason` não vazio + `ProfessionalIdentity` + `source_document` quando representa decisão clínica externa.
  - Reabertura administrativa por erro exige capability + motivo + auditoria, sem inventar profissional ou documento externo.
- `health.cancel_case`:
  - Adiciona `cancel_reason` obrigatório.
  - Não exige `ProfessionalIdentity` para cancelamento administrativo.
  - Preserva histórico completo (não remove documentos).
- `health.complete_treatment`:
  - Transição explícita server-orchestrated para `monitoring`.
  - Não derivada de eventos.
- `health.manage_schedule`:
  - Permite cancelar/editar item criado por outro usuário ou por Function.
  - `cancel_reason` obrigatório quando cancelar.
  - Não encerra restrição clínica nem altera prontidão.

**Invariantes de contrato adicionais:**
- `ClinicalEvent` rejeita qualquer payload bruto legado; `original_payload` existe somente em `LegacyHealthRecord`.
- Liberação clínica externa de restrição valida `end_professional`, `end_source_document` e `end_reason`.
- Projeções de peso, refeição e suplemento entram na timeline com `status: final`; fontes canceladas/invalidadas usam `status: cancelled`; drafts nunca entram.

**Ferramentas:** `@firebase/rules-unit-testing` + Firebase Emulator + integration tests.
**Critério de sucesso:** cada capability testada em happy path + erro esperado; mapping capability → perfil marcado como provisório em comentários de teste.

---

## 2. Gates por fase

| Fase | Testes obrigatórios antes de avançar |
|------|--------------------------------------|
| Fase 1 (Contratos) | N/A (documental) |
| Fase 2 (Adapters) | 1.4 (adapters), 1.18 (regressão) |
| Fase 3 (Schema) | 1.7 (Rules), 1.3 (repositories) |
| Fase 4 (Backfill dry-run) | 1.5 (idempotência), 1.6 (migração) |
| Fase 5 (Backfill real) | 1.6 confirmado em emulador |
| Fase 6 (Dual-read) | 1.3, 1.4, 1.9, 1.10, 1.11, 1.13, 1.18, 1.20 |
| Fase 7 (Paridade) | 1.6 (reconciliação) |
| Fase 8 (Cutover por agregado) | 1.1–1.26 TODOS para o agregado em questão |
| Fase 9 (Bloqueio writes por agregado) | 1.7 (Rules atualizadas), 1.21 (cutover por agregado) |
| Fase 10 (Remoção adapters) | 1.18 (regressão), build verde |

---

## 3. Cobertura mínima por camada

| Camada | Cobertura mínima | Métrica |
|--------|-----------------|---------|
| Domain (entities, VOs, enums) | 95% | Linhas |
| Lógica de negócio (transições, validações, derivação temporal) | 90% | Branches |
| Acesso a dados (adapters, services/repositories) | 85% | Linhas |
| Apresentação (state/viewmodels) | 80% | Branches |
| Apresentação (widgets) | 70% | Renderização sem crash |
| Rules | 100% | Operações da Permission Matrix |
| Functions | 90% | Triggers definidos |

---

## 4. Dados de teste

| Tipo | Fonte | Regras |
|------|-------|--------|
| Fixtures de entidade | Criados manualmente | Nenhum dado pessoal real |
| Fixtures legados | Amostrados do Firestore e anonimizados | UIDs, nomes e CRMVs fictícios |
| Fixtures de legacy_health_records | Criados a partir de todos os `health_events` pré-go-live | Payload original anonimizado |
| Dataset de paginação | Gerado por script | 200+ itens com timestamps espaçados |
| Dataset de concorrência | Gerado em tempo de teste | Múltiplos writes simultâneos |

---

## 5. Ferramentas e configuração

| Ferramenta | Uso |
|-----------|-----|
| `flutter_test` | Unit e widget tests |
| `fake_cloud_firestore` | Repository tests sem emulador |
| Firebase Emulator Suite | Rules, Functions, integration |
| `@firebase/rules-unit-testing` | Rules tests (Node.js) |
| `golden_toolkit` | Regressão visual (opcional) |
| `integration_test` | Fluxos end-to-end no dispositivo |
| `mockito` / `mocktail` | Mocks de services e repositories |

---

## 6. Notas sobre permissões e capabilities

### Modelo capability-based (não role-based)

Os testes de permissão NÃO testam custom claims de role (ex: não existe `isVet()` nas Rules). Em vez disso, testam **testes por capability** de negócio conforme a Permission Matrix. O mapping capability → perfil real (condutor/admin) está marcado como provisório na Permission Matrix e pendente da Fase 1B — testes devem manter essa marcação explícita.

- **Capability clínica:** permite criar restrições, dar alta, prescrever tratamentos.
- **Capability de registro:** permite registrar eventos de rotina, intercorrências.
- **Capability administrativa:** permite cancelar, encerrar, gerenciar cutover.

O campo `professional` nos eventos identifica o profissional externo responsável pelo ato clínico. O campo `recorded_by` identifica o usuário interno do sistema que registrou o dado. Ambos são validados nas Rules conforme a capability do `recorded_by`.

### Projeções e escritas administrativas

- Clientes (Mobile, Web) **não podem** escrever em coleções de projeção (health_summary, health_timeline). Rules bloqueiam explicitamente.
- Admin SDK IGNORA Firestore Rules — portanto operações administrativas de Functions (escrita em projeções, backfill, reconciliação) NÃO são validadas por Rules, e sim por testes separados de Functions.
- Testes de Rules verificam que clientes autenticados recebem `PERMISSION_DENIED` ao tentar write em projeções.
- Testes de Functions (separados dos testes de Rules) verificam que escritas administrativas funcionam corretamente sob Admin SDK.
