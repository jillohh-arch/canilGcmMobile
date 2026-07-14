# Health v1.0 — Baseline Oficial

**Data de criação:** 2026-07-13  
**Autor:** Jilles Ragonha + Claude Fable 5  
**Status:** Aprovada para merge após validação documental

---

## Identificação

| Campo | Valor |
|-------|-------|
| Repositório | `github.com/jillohh-arch/canilGcmMobile` |
| Branch de preparação | `chore/health-v1-baseline` |
| Origin/main de referência | `80ad548723e092dd87f37e90c1310296f1e06132` |
| Ancestral documental | `b19dc649bfd55619b9547dc8eff1dc5bda86b92f` |
| Commit de publicação inicial da baseline | `3598f4de4367deabfef6b521acbb24d7698a73b3` |
| Ref oficial após merge | tag `health-v1-baseline-2026-07-13` |
| Data | 2026-07-13 |
| Working tree | Limpo |

---

## Documentos incluídos na baseline

| Documento | Origem | Propósito |
|-----------|--------|-----------|
| `docs/HEALTH_V1_ARCHITECTURE.md` | Commit `b19dc64` | Arquitetura alvo do Health v1.0 |
| `docs/HEALTH_IMPLEMENTATION_ROADMAP.md` | Commit `b19dc64` | Roadmap de 14 fases |
| `docs/HEALTH_MODULE_AUDIT.md` | Adicionado nesta baseline | Auditoria completa do estado atual |
| `docs/health/HEALTH_V1_BASELINE.md` | Adicionado nesta baseline | Este documento |

---

## Snapshot de segurança

| Campo | Valor |
|-------|-------|
| Branch | `backup/pre-health-v1-baseline-2026-07-13` |
| SHA do snapshot | `899dedcc872e0f2758c03e8f44aba98044f76158` |
| Remoto | Publicada em origin |
| Conteúdo | Working tree completo no momento da auditoria (Health + Shifts + testes) |

O snapshot preserva fielmente o estado sobre o qual a auditoria foi conduzida. A baseline limpa é um subconjunto documental desse snapshot.

---

## Arquivos funcionais excluídos da baseline

| Arquivo | Motivo da exclusão |
|---------|-------------------|
| `lib/core/widgets/binomio_header.dart` | Refatoração de Shifts (Dog→Dog?); não altera Health |
| `lib/features/health/.../dog_health_prontuario_screen.dart` | Ajuste posicional do FAB (bottom 22→96); não aprovado como parte da baseline documental |
| `lib/features/shifts/data/shift_service.dart` | Refatoração Shifts (+321 linhas) |
| `lib/features/shifts/.../active_shift_dashboard_screen.dart` | Refatoração Shifts (-238 linhas) |
| `lib/features/shifts/.../active_shift_dog_switcher.dart` | Ajuste Shifts |
| `lib/features/shifts/.../active_shift_header.dart` | Ajuste Shifts |
| `lib/features/shifts/.../active_shift_profile_cards.dart` | Refatoração Shifts (+179 linhas) |
| `lib/features/shifts/.../active_shift_quick_actions.dart` | Refatoração Shifts (+78 linhas) |
| `lib/features/shifts/.../vehicle_crew_post_sheet.dart` | Ajuste Shifts |
| `lib/features/shifts/.../shift_viewmodel.dart` | Expansão Shifts (+48 linhas) |
| `test/core/widgets/binomio_header_test.dart` | Teste do refactor de Shifts |
| `test/features/shifts/data/shift_service_test.dart` | Teste do refactor de Shifts |
| `test/features/shifts/presentation/vehicle_crew_post_sheet_test.dart` | Teste do refactor de Shifts |
| `docs/HEALTH_MODULE_AUDIT.pdf` | Versão PDF com tabelas truncadas; será regenerado |

---

## Auditoria de delta — resultado

Comparação: `chore/health-v1-baseline` vs. `backup/pre-health-v1-baseline-2026-07-13`

### Verificações realizadas

| Afirmação da auditoria | Verificação | Resultado |
|------------------------|-------------|-----------|
| `ActiveShiftQuickActions` navega para `DogHealthProntuarioScreen` | grep `_openHealth`, `onOpenHealthTab` na baseline | ✅ Presente identicamente |
| `ActiveShiftDashboard` consome `HealthViewModel` | grep imports e `fetchHealthLogsForDog` na baseline | ✅ Presente identicamente |
| `BinomioHeader` oferece `onDogHealthTap` e navega ao prontuário | grep `onDogHealthTap`, `DogHealthProntuarioScreen` na baseline | ✅ Presente identicamente |
| Troca de K9 pode produzir estado transitório incorreto | Lógica do HealthViewModel (fetch sem key) | ✅ Inalterada — VM é o mesmo em ambas versões |
| `dog_health_prontuario_screen.dart` possui 4718 linhas | Baseline contém versão original (sem FAB fix) | ✅ 4718 linhas confirmadas |
| Score legado `Dog.calculateReadiness()` | Não alterado por nenhum dos diffs excluídos | ✅ Inalterado |

### Conclusão do delta

**Nenhuma conclusão da auditoria precisa de correção.** Todas as mudanças excluídas são de escopo Shifts (refatoração visual/funcional do dashboard ativo) ou cosmético (posição do FAB). Os caminhos de navegação, modelos de dados, services, Firestore e estado de Health existem identicamente na baseline limpa.

---

## Escopos explicitamente fora da baseline

1. **Refatoração Shifts** — preservada no snapshot; receberá branch própria.
2. **Ajuste FAB prontuário** — preservado no snapshot; receberá task própria.
3. **PDF da auditoria** — será regenerado após aprovação da baseline.
4. **Implementação do Health v1.0** — nenhuma linha funcional escrita.

---

## Instruções para reproduzir o checkout

```bash
# Clonar e posicionar na baseline
git clone https://github.com/jillohh-arch/canilGcmMobile.git
cd canilGcmMobile
git checkout chore/health-v1-baseline

# Verificar
git log --oneline -3
# Deve mostrar:
# <sha> docs(health): establish Health v1 baseline
# b19dc64 docs: adicionar arquitetura e roadmap oficiais do módulo Saúde v1.0
# 80ad548 docs(memory): record field validation of occurrence closing flow

# Working tree deve estar limpo
git status
# On branch chore/health-v1-baseline
# nothing to commit, working tree clean

# Documentos presentes:
ls docs/HEALTH_V1_ARCHITECTURE.md
ls docs/HEALTH_IMPLEMENTATION_ROADMAP.md
ls docs/HEALTH_MODULE_AUDIT.md
ls docs/health/HEALTH_V1_BASELINE.md
```

---

## Validações executadas

| Comando | Resultado | Observação |
|---------|-----------|------------|
| `flutter analyze` | Concluído com 8 ocorrências | 7 infos `use_build_context_synchronously` e 1 warning `unused_element`; nenhum erro e nenhuma ocorrência em Health |
| `flutter test` | 182 testes, 1 falha | Falha preexistente no módulo Training: `'Condicionamento'` versus `'Condicionamento Físico'` |
| `flutter build apk --debug` | Sucesso | APK debug gerado em ~115s |
| Firebase Rules/Indexes | Não executado | Não existe suíte de testes de Rules no repositório e nenhuma foi criada nesta fase |

### Estado de qualidade da baseline

A baseline está aprovada como baseline documental e arquitetural.

Ela não é uma baseline totalmente verde de testes porque existe uma falha preexistente no módulo Training, não relacionada ao Health v1.0. Essa falha deverá ser tratada em uma branch própria antes do primeiro commit funcional do Health v1.0.

---

## Próximos passos (após aprovação)

1. Merge de `chore/health-v1-baseline` em `main`.
2. Tag opcional: `health-v1-baseline-2026-07-13`.
3. Criar `feature/health-v1-foundation` a partir do SHA merged.
4. Iniciar Fase 1: ADRs, schema, permissões e estratégia de migração.
