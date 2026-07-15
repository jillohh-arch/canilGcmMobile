# Health v1.0 — Plano de Migração

| Campo | Valor |
|-------|-------|
| Status | Aprovado |
| Data | 2026-07-14 |
| Branch | `feature/health-v1-foundation` |
| Baseline | `2a0c1e65e592476bddb6e59378456c6f49f02a14` |
| Documentos relacionados | ADR-006, HEALTH_V1_FIRESTORE_SCHEMA.md, HEALTH_MODULE_AUDIT.md §6 |
| Escopo | Fases, pré-condições, execução, validação, rollback e métricas de migração |
| Fora de escopo | Implementação de scripts, Functions, deploy de Rules |

---

## Fase 0 — Inventário Real

### Pré-condições
- Acesso de leitura ao Firestore de produção (Admin SDK ou console).
- Nenhuma alteração de dados.

### Execução
1. Contar documentos em cada coleção mapeada na auditoria (§6.1).
2. Identificar documentos com formato inesperado (campos ausentes, tipos divergentes).
3. Mapear IDs duplicados entre pares canônico/legado (`feeding_events` vs `feedings`, `weight_records` vs `weight_history`, etc.).
4. Verificar se `health_logs` (raiz) e `dogs/{dogId}/documents` contêm dados reais.
5. Amostrar 20 documentos de cada coleção para validar schema inferido na auditoria.

### Validação
- Relatório com contagens por coleção e por K9.
- Lista de formatos inesperados com exemplos (sem dados pessoais reais).
- Confirmação de quais coleções estão efetivamente vazias.

### Rollback
- N/A (somente leitura).

### Métricas
- Total de documentos por coleção.
- % de documentos conformes vs. não-conformes.
- Quantidade de K9s com dados de saúde.

### Saída obrigatória
- Documento `HEALTH_V1_INVENTORY_REPORT.md` com contagens e anomalias.
- Decisão sobre `health_logs` e `dogs/{dogId}/documents`: migrar ou ignorar.

---

## Fase 1 — Contratos (esta fase)

### Pré-condições
- Fase 0 concluída ou baseline documental aceita.
- Nenhum write novo conectado ao Firestore.

### Execução
1. Produzir ADRs, domain model, schema, permissões, readiness policy.
2. Revisar e aprovar contratos.
3. Definir IDs determinísticos para backfill.
4. Definir campos de rastreabilidade (`legacy_source`, `legacy_id`, `schema_version`, `migration_version`, `migration_checksum`, `migration_batch_id`).

### Validação
- Todos os documentos aprovados pelo responsável.
- Nenhuma ambiguidade nos mapeamentos (schema atual → alvo).
- Cada fonte legada tem destino definido.

### Rollback
- N/A (somente documentação).

### Métricas
- Cobertura: % de fontes legadas com destino definido = 100%.
- Questões abertas resolvidas.

### Saída obrigatória
- Documentos da Fase 1A aprovados (este conjunto).
- Decisão: quais fontes migram, quais são preservadas read-only para auditoria histórica, quais precisam de inventário.
- Definição de `legacy_health_records` como destino de todos os `health_events` anteriores ao go-live, independentemente de agrupamento lógico detectável.

---

## Fase 2 — Adapters Read-Only

### Pré-condições
- Contratos aprovados.
- Branch de implementação criada a partir do HEAD aprovado.

### Execução
1. Criar abstrações de acesso a dados por agregado (a forma exata — interfaces de repository, services com injeção, ou outro padrão — será definida em ADR próprio de arquitetura interna, respeitando a compatibilidade com Provider/ChangeNotifier e o padrão feature-first do app).
2. Implementar `RawHealthEventsAdapter` pré-backfill, que lê `dogs/{dogId}/health_events`, produz `LegacyHealthRecordView` ou DTO de timeline em memória, nunca produz `ClinicalEvent` e não grava no schema novo. Os demais adapters leem suas coleções legadas e retornam os modelos previstos pelo contrato.
3. Injetar adapters na camada de apresentação via Provider.
4. Manter writes no formato legado (sem alteração).

### Validação
- Testes unitários: cada adapter mapeia corretamente amostra de dados legados.
- Testes de integração: tela principal exibe dados via adapter sem regressão visual.
- `flutter analyze` sem erros. `flutter test` verde.

### Rollback
- Reverter para branch anterior (adapters são aditivos, não alteram legado).

### Métricas
- % de telas que usam adapter vs. acesso direto.
- Cobertura de testes dos adapters.

### Saída obrigatória
- Adapters funcionais para: health_events, weight_records, feeding_events, documentos, vacinas.
- Abstrações de acesso a dados definidas e testadas (formato a confirmar em ADR de arquitetura interna).

---

## Fase 3 — Schema Novo (estrutura)

### Pré-condições
- Adapters read-only funcionais.
- Emulador Firestore configurado.

### Execução
1. Criar Rules para as novas coleções (em emulador, não deploy).
2. Criar índices compostos necessários em `firestore.indexes.json`.
3. Validar que Rules permitem os writes esperados e bloqueiam os proibidos.
4. Criar DTOs e mappers para o schema novo.
5. Definir estrutura de `legacy_health_records` (read-only, sem rules de write para clientes).

### Validação
- Suite de testes de Rules no emulador (create/read/update/delete por capability).
- Todos os índices validados com queries reais no emulador.
- DTOs cobrem 100% dos campos do schema aprovado.

### Rollback
- Rules e índices não são deployados. Apenas existem em código.
- Reverter commit se necessário.

### Métricas
- Cobertura de testes de Rules: 100% das operações definidas na Permission Matrix.
- Índices: nenhuma query falha por índice ausente no emulador.

### Saída obrigatória
- `firestore.rules` atualizado (não deployado).
- `firestore.indexes.json` atualizado (não deployado).
- Suite de testes de Rules verde.

---

## Fase 4 — Backfill Dry-Run

### Pré-condições
- Schema novo validado em emulador.
- Inventário real (Fase 0) disponível.
- Script de backfill implementado (Cloud Function administrativa ou script Node.js).

### Execução
1. Executar script em modo dry-run (lê produção, simula escrita, não grava).
2. Para cada documento fonte, produzir payload alvo e validar contra schema.
3. Registrar: migrável, rejeitado (com razão), já existente (idempotência).
4. Verificar IDs determinísticos: mesmo input → mesmo ID.
5. Classificar `health_events` (todos os registros, sem distinção por caso atribuível) → destino único `legacy_health_records`. Não existe classificação dual "com caso" vs. "sem caso" — o contrato conservador é absoluto: nenhum `ClinicalEvent` retroativo é criado em `clinical_cases/events`.

### Validação
- Relatório de dry-run: total_source = total_migrable + total_rejected.
- Nenhuma rejeição inesperada (rejeições são formatos não mapeáveis, já listados).
- IDs determinísticos confirmados (executar 2x, mesmos IDs gerados).
- Contagem de eventos direcionados para `legacy_health_records` (todos os `health_events` migram para lá — sem contagem comparativa com `clinical_cases/events`).

### Rollback
- N/A (nenhuma escrita foi feita).

### Métricas
- total_source por coleção.
- total_migrable vs. total_rejected (% de sucesso).
- total_legacy_health_records (todos os `health_events`).
- Tempo de execução estimado para batch real.

### Saída obrigatória
- Relatório de dry-run aprovado.
- Lista de rejeições com razões.
- Estimativa de tempo/custo do batch real.
- Go/no-go para Fase 5.

---

## Fase 5 — Backfill Real

### Pré-condições
- Dry-run aprovado.
- Rules deployadas (somente para as novas coleções).
- Índices deployados.
- Janela de manutenção comunicada (se necessário).

### Execução
1. Executar script de backfill com escrita real.
2. Usar batched writes (máx 500 por batch) para eficiência.
3. Cada documento escrito carrega `legacy_source`, `legacy_id`, `schema_version`, `migration_version`, `migrated_at`, `migration_checksum`, `migration_batch_id`.
4. IDs determinísticos garantem idempotência.
5. Registrar relatório de execução em `_migrations/health_v1/batches/{batchId}`.
6. O `manifest` registra cada operação com `operation_type: create | update`, `target_path`, `target_id`, `before_image` para update, `changed_fields`, `migrated_at`, `checksum_before` e `checksum_after`.
7. Todos os `health_events` → `dogs/{dogId}/legacy_health_records/{recordId}` com `original_payload` preservado. Nenhum `ClinicalEvent` é criado retroativamente em `clinical_cases/events`.

### Validação
- Contagem no destino = total_migrable do dry-run.
- Amostrar 50 documentos: comparar payload com fonte original.
- Verificar checksums: `migration_checksum` do doc alvo bate com hash da fonte.
- Reexecutar: nenhuma duplicata criada (idempotência).
- `legacy_health_records` populados com visão normalizada + `original_payload` (todos os `health_events` migrados, sem distinção por caso).

### Rollback
- Restrito às operações listadas no `manifest` do batch.
- `create`: apagar somente o documento criado pelo batch.
- `update`: restaurar `before_image` apenas nos `changed_fields`; nunca apagar documento preexistente.
- Proibido se qualquer alvo foi modificado por usuário ou se ocorreu cutover.
- Fontes legadas preservadas permanecem intactas; normalizações in-place são reversíveis pelo `before_image`.
- Atualizar doc de controle: `status: "rolled_back"`.

### Métricas
- Documentos migrados por coleção (incluindo `legacy_health_records`).
- Tempo total de execução.
- Custo de writes Firestore.
- Taxa de erro (retries necessários).

### Saída obrigatória
- Schema novo populado com dados legados.
- `legacy_health_records` populado com todos os `health_events` anteriores ao go-live, independentemente de agrupamento lógico detectável.
- Relatório de execução com contagens finais.
- Confirmação de idempotência (segunda execução = 0 novos writes).

---

## Fase 6 — Dual-Read

### Pré-condições
- Backfill completo e validado.
- Adapters legados ainda funcionais.
- Feature flag implementada no mobile.

### Execução
1. Ativar feature flag: mobile lê schema novo como primário.
2. Fallback para adapter legado quando documento não encontrado no schema novo.
3. Novos writes de funcionalidades implementadas vão para schema novo.
4. Writes de funcionalidades não migradas continuam no legado.
5. Monitorar divergências via logs.
6. `legacy_health_records` exibidos na timeline via projeção (read-only).

### Validação
- UI funciona identicamente com dados do schema novo.
- Nenhum erro de "dados não encontrados" que existia com adapter.
- Fallback é exercitado e funciona (testar com doc deletado no schema novo).
- Performance de leitura igual ou melhor.
- Timeline exibe registros de `legacy_health_records` corretamente.

### Rollback
- Desativar feature flag → mobile volta a ler exclusivamente via adapter legado.
- Imediato, sem perda de dados.

### Métricas
- % de leituras servidas pelo schema novo vs. fallback.
- Latência de leitura (schema novo vs. adapter).
- Erros por fonte (schema novo vs. legado).
- Período mínimo de observação: 30 dias.

### Saída obrigatória
- Feature flag ativa por ≥30 dias sem incidentes.
- Métrica de fallback < 1% (quase tudo servido pelo schema novo).
- Go/no-go para cutover.

---

## Fase 7 — Validação de Paridade

### Pré-condições
- Dual-read ativo há ≥30 dias.
- Nenhuma anomalia reportada.

### Execução
1. Script de reconciliação: comparar contagens fonte × destino para cada coleção.
2. Amostrar documentos e comparar conteúdo (hash do payload normalizado).
3. Verificar que nenhum documento legado criado após o backfill ficou fora do schema novo.
4. Caso existam: executar backfill incremental para documentos novos.

### Validação
- contagem_fonte = contagem_destino + rejeições_documentadas.
- Hash de amostra (100 docs/coleção) = 100% match.
- Documentos criados após backfill = 0 OU todos backfilados incrementalmente.

### Rollback
- Se divergência significativa: manter dual-read, investigar, corrigir backfill.

### Métricas
- % de paridade por coleção.
- Documentos faltantes no schema novo.
- Documentos extras no schema novo (sem fonte correspondente).

### Saída obrigatória
- Relatório de paridade com 100% de cobertura.
- Confirmação de que nenhum dado foi perdido.
- Go/no-go para cutover.

---

## Fase 8 — Cutover (por agregado)

### Pré-condições
- Paridade validada (100%) para o agregado em questão.
- Dual-read estável por ≥30 dias.
- Equipe pronta para suporte.
- **Coordenação cross-sistema confirmada:**
  - Mobile: atualizado para ler/escrever exclusivamente no schema novo para este agregado.
  - Web: inventário de acesso completo; todos os módulos que acessam a coleção legada foram atualizados.
  - Functions: triggers atualizados para o schema novo.
  - Rules: regras do schema novo deployadas e validadas.
  - Índices: todos os índices necessários deployados.
  - Versão mínima do app: definida e comunicada (force update se necessário).

### Execução
1. Remover fallback para adapter legado no mobile **para o agregado em questão**.
2. Mobile lê exclusivamente schema novo para este agregado.
3. Confirmar que Web não escreve mais na coleção legada correspondente.
4. Manter coleções legadas intactas (leitura permitida, escrita ainda ativa apenas se outros agregados ainda não migraram).

### Validação
- Smoke test completo pós-deploy para o agregado.
- Nenhum erro de "documento não encontrado".
- Todas as telas que consomem este agregado funcionais.
- Nenhum write na coleção legada proveniente de Mobile, Web ou Functions.

### Rollback
- Redeployar versão anterior (com adapters). Dados legados intactos.
- Período: até 48h após cutover. Após isso, dados novos no schema novo dificultam reversão.
- Rollback de batch (via manifest) é proibido após cutover.

### Métricas
- Taxa de erro pós-cutover por agregado.
- Performance de leitura.
- Feedback de usuários.
- Writes residuais na coleção legada (devem ser zero).

### Saída obrigatória
- Agregado operando exclusivamente no schema novo em todos os sistemas.
- Go/no-go para bloqueio de writes legados deste agregado.

---

## Fase 9 — Bloqueio de Writes Legados (por agregado)

### Pré-condições
- Cutover estável por ≥14 dias para o agregado.
- Confirmação de que nenhum produtor (Mobile, Web, Functions) escreve na coleção legada.
- Nenhum write no formato legado detectado nos últimos 7 dias.

### Execução
1. Atualizar `firestore.rules`: bloquear `create` e `update` nas coleções legadas migradas para este agregado.
2. Manter `read` permitido (compatibilidade com versões antigas do app).
3. Deploy de rules.

### Validação
- Tentar write em coleção legada → PERMISSION_DENIED.
- Read em coleção legada → OK.
- Nenhum impacto no app atual (que já não escreve no legado).
- Nenhum impacto em outros agregados ainda em transição.

### Rollback
- Reverter rules para versão anterior (restore write permission).
- Imediato.

### Métricas
- Writes rejeitados (devem ser 0 se cutover foi completo).
- Se > 0: investigar origem (versão antiga do app? outro sistema?).

### Saída obrigatória
- Rules deployadas com write bloqueado nas coleções legadas deste agregado.
- Zero writes rejeitados em produção (todas as fontes já usam schema novo).

---

## Fase 10 — Remoção dos Adapters (futuro, por agregado)

### Pré-condições
- Bloqueio de writes estável por ≥30 dias para o agregado.
- Nenhuma versão do app em uso que dependa do legado para este agregado.
- **Nenhum produtor pode escrever na coleção legada** (confirmado em Fase 9).

### Execução
1. Remover código de adapters legados para o agregado.
2. Remover models legados não mais referenciados.
3. Remover testes de adapters correspondentes.
4. Manter dados legados no Firestore indefinidamente (never delete).

### Validação
- Build e testes verdes sem adapters do agregado.
- Nenhuma referência a coleções legadas deste agregado no código mobile.

### Rollback
- Reverter commit (adapters voltam).

### Métricas
- Linhas de código removidas.
- Models removidos.

### Saída obrigatória
- Código limpo sem referências a formato legado do agregado.
- Dados legados preservados no Firestore (documentação histórica).
- Quando todos os agregados concluírem: migração oficialmente concluída.
