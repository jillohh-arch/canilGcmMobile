# K9 Ops — Health Module v1.0

Roadmap Oficial

---

# Objetivo

Implementar completamente o novo módulo Saúde preservando os dados existentes e reduzindo riscos.

Nenhuma implementação deve ocorrer antes da auditoria completa.

---

# FASE 0

AUDITORIA

## Objetivos

- Mapear código
- Mapear Firestore
- Mapear Models
- Mapear Providers
- Mapear Services
- Mapear Fluxos
- Mapear UI
- Produzir documentação

## Entregável

`HEALTH_MODULE_AUDIT.md`

---

# FASE 1

BASE

- Criar arquitetura alvo.
- Reorganizar features.
- Padronizar Models.
- Criar entidades comuns.
- Criar framework de formulários.
- Criar componentes compartilhados.

---

# FASE 2

RESUMO

- Dashboard
- Indicadores
- Prontidão
- Alertas
- Registros recentes

---

# FASE 3

HISTÓRICO

- Timeline
- Filtros
- Pesquisa
- Agrupamentos
- Detalhamento

---

# FASE 4

AGENDA

- Agenda Preventiva
- Eventos
- Alertas
- Lembretes
- Pendências

---

# FASE 5

NUTRIÇÃO

Contrato canônico (5A/5B): `nutrition_plans` / `meal_logs` / `supplement_logs`.
Web define plano; Mobile executa via backend; zero dual-write novo.

Subfases:

```text
5A — Auditoria do operacional legado          [ENCERRADA]
5B — Decisões canônicas D1–D42                [ENCERRADA]
5C — Foundation domínio + read/adapters       [próxima; ZERO write]
5D — Writes canônicos de execução (callables)
5E — Plano backend + fechamento mobile write de plano
5F — UI Nutrição Hoje (shell + registro)
5G — Inventário produção + backfill
5H — Cutover e confronto final
```

Read model / UI:

- estados `loading | data | empty | offline | error` (erro ≠ empty silencioso)
- estado keyed por `dogId`
- timezone domínio default `America/Sao_Paulo`

Escopo de produto da fase:

- Plano (consulta mobile; gestão Web/backend)
- Consumo (offered/consumed/acceptance)
- Refeições (slots + meal_occurrence_id)
- Suplementos (regime no plano ≠ SupplementLog)
- Observações (no MealLog)
- Histórico (meals + admin logs + plano via timeline)

---

# FASE 6

PESAGEM

- Peso
- Curva
- Escore corporal
- Medidas
- Fotos

---

# FASE 7

VACINAÇÃO

- Protocolos
- Lotes
- Próximas doses
- Carteira
- Histórico

---

# FASE 8

CONSULTAS

- Consulta
- Diagnóstico
- Conduta
- Exames
- Restrições
- Alta

---

# FASE 9

EXAMES

- Solicitação
- Resultado
- Interpretação
- Impacto
- Anexos

---

# FASE 10

TRATAMENTOS

- Protocolos
- Administração
- Cronograma
- Acompanhamento
- Reavaliação

---

# FASE 11

INTERCORRÊNCIAS

- Registro
- Classificação
- Gravidade
- Conduta
- Caso Clínico

---

# FASE 12

PRONTIDÃO

- Atualização automática
- Bloqueios
- Restrições
- Indicadores
- Preparação para IPO

---

# FASE 13

DOCUMENTOS

- Receitas
- PDF
- Laudos
- Imagens
- Compartilhamento

---

# FASE 14

POLIMENTO

- Animações
- UX
- Performance
- Refatorações
- Acessibilidade

---

# Health v2

Futuras expansões:

- IPO
- IA
- Fisioterapia
- Internação
- Cirurgia
- Integração com Estoque
- Integração com Clínicas
- OCR
- Reconhecimento de exames
- Análises inteligentes

---

# Critérios de Conclusão

Cada fase somente poderá ser encerrada após:

- [ ] Código revisado
- [ ] Firestore validado
- [ ] UI validada
- [ ] Fluxos completos
- [ ] Auditoria aprovada
- [ ] Documentação atualizada
- [ ] Graphify atualizado
- [ ] Claude Memory atualizada

---

# Ordem obrigatória

```
Auditoria
↓
Arquitetura
↓
Implementação
↓
Testes
↓
Documentação
↓
Memórias
↓
Próxima fase
```

---

# Trilha canônica de Pesagem — APPROVED TARGET / NOT STARTED

| Fase | Objetivo | Dependências | Deploy | APK | Risco | Gate |
|---|---|---|---|---|---|---|
| WEIGHT-01 | Domínio, schema e bridge | WEIGHT-00C/00D | Não | Não | Médio | contrato + unit |
| WEIGHT-02 | Pesagem Rápida online | 01 | Functions | Sim | Alto | Emulator, Rules, Pixel |
| WEIGHT-03 | Pesagem Oficial online | 02 | Functions | Sim | Alto | retroatividade/projeção |
| WEIGHT-04 | Complementação e correção | 03 | Functions | Sim | Crítico | revisions/concurrency |
| WEIGHT-05 | Invalidação e reprojeção | 04 | Functions | Sim | Crítico | recomputação integral |
| WEIGHT-06 | Imagens e HealthDocument | 05 | Functions/Storage Rules | Sim | Alto | dedupe/retenção/falha parcial |
| WEIGHT-07 | Faixa, meta, alertas e BCS | 05 | Functions/Web | Sim | Alto | nenhuma restrição automática |
| WEIGHT-08 | Offline e sincronização | 02–07 | Não necessariamente | Sim | Crítico | relógio/multi-device/security soak |
| WEIGHT-09 | Histórico, filtros, gráficos e Web | 03–08 | Web | Sim | Médio | paridade dos readers |
| WEIGHT-10 | Clínica, nutrição e agenda | 07–09 | Functions/Web | Sim | Alto | nenhuma mutação implícita |
| WEIGHT-11 | Migração e homologação física | Todas | Controlado | Sim | Crítico | dry-run + reconciliação + rollback |

Nenhuma fase desta trilha foi iniciada por WEIGHT-00C.
