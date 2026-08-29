# ADR-007 — Organização interna do módulo Health

| Campo | Valor |
|-------|-------|
| Status | Proposto |
| Data | 2026-07-14 |
| Branch | `feature/health-v1-foundation` |
| Baseline | `52dae0b683f508affcae0d58cc0931288821d738` |
| Escopo | Organização interna mínima do Health v1 na Fase 1B |
| Fora de escopo | UI completa, persistência no schema novo, Rules, Functions, migração e deploy |

## Contexto

O K9 Ops Mobile é organizado por feature e usa Provider/ChangeNotifier na apresentação, services concretos para acesso remoto e models locais. O Health legado já vive em `lib/features/health/`, com `HealthViewModel`, `HealthService` e `HealthLogModel`, e agrega dados de Dogs e Nutrition na interface existente.

O Health v1 precisa evoluir sem refatoração global, coexistindo temporariamente com o legado. A Fase 1B exige contratos testáveis e adapters de leitura, mas não ativa writes, não substitui o fluxo atual e não conecta a nova fundação às telas.

## Decisão

O Health v1 continuará dentro da feature existente, com separações locais e concretas:

- `domain/`: enums, value objects, entidades e transições puras em Dart;
- `legacy/`: parsing defensivo e adapters de mapas legados para o domínio;
- `presentation/` e `data/` existentes permanecem inalterados nesta fase.

Não será criada uma cadeia global de repository/use case, service locator ou injeção de dependência. Provider/ChangeNotifier continua sendo o padrão para uma apresentação futura. Services Firestore atuais continuam isolados do novo domínio; nenhum service de escrita Health v1 é criado.

Os adapters iniciais cobrem somente fontes reais necessárias ao contrato aprovado: `health_events`, `weight_records` e `feeding_events`. A seleção e os destinos dessas fontes estão registrados no Domain Model (§§ 2.6, 2.8 e 2.13) e no ADR-006 (§§ 9 e 10). Eles recebem mapas já lidos e não possuem dependência de cliente remoto, o que torna a ausência de writes estrutural.

## Limites de dependência

- contratos em `domain/` não importam Flutter nem Firebase;
- contratos de domínio não conhecem DTOs ou nomes de campos legados;
- adapters podem conhecer os formatos legados e dependem do domínio;
- adapters não recebem `FirebaseFirestore`, `DocumentReference` ou interface de escrita;
- a apresentação futura poderá depender do domínio por Provider/ChangeNotifier;
- o Health legado não passa a depender do Health v1 nesta fase;
- nenhum adapter pode criar, atualizar ou excluir dados;
- parsing de tempo recebe o valor e não consulta relógio global.

## Consequências positivas

- regras e transições podem ser testadas sem Flutter/Firebase;
- formatos legados ficam isolados dos contratos canônicos;
- a integração pode avançar incrementalmente sem interromper telas atuais;
- a ausência de acesso remoto nos adapters reduz o risco de write acidental;
- a estrutura continua compatível com o padrão feature-first do app.

## Trade-offs

- modelos legados e v1 coexistem temporariamente;
- aliases e formatos históricos exigem mapeamento defensivo;
- há duplicação controlada de conceitos durante a transição;
- a fundação não produz ativação funcional nem persistência nova.

## Alternativas rejeitadas

- Clean Architecture global: ampliaria o escopo e contrariaria o app atual;
- reescrita completa do Health legado: risco alto e sem necessidade na Fase 1B;
- troca de Provider/ChangeNotifier: não há motivação funcional nesta fase;
- migração imediata do schema: viola os gates aprovados;
- adapters com dual-write: proibidos pelo contrato de coexistência;
- mover ou refatorar módulos compartilhados: criaria dependências externas ao Health;
- repositories/use cases genéricos sem consumidor: abstração prematura.

## Critérios para revisão futura

Este ADR deve ser revisitado antes de:

- iniciar writes no schema Health v1;
- conectar a nova camada de apresentação;
- definir Rules, índices ou Functions;
- executar dual-read, migração ou desativação do legado;
- introduzir um serviço remoto v1 concreto.

Até lá, a decisão permanece local ao Health e não estabelece arquitetura obrigatória para outras features.
