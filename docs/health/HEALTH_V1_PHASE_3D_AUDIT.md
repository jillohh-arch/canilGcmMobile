# Health v1.0 — Fase 3D — Auditoria Técnica e UX Adversarial

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD | `efeec66b2ea26f335dc2c5f4b59323d974f4518d` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0/0` |
| working tree | somente 3D (+ mínimas 3B) |

Preflight **OK**.

## 2. Arquivos auditados

- `docs/health/HEALTH_V1_PHASE_3D_REPORT.md`
- `lib/.../filters/**`
- `lib/.../detail/**`
- `health_timeline_interactive_host.dart`
- testes `*_3d_*.dart`
- 3B: `health_timeline_view.dart`, `status_views.dart`, `user_copy.dart`

## 3. Metodologia

Ataque a: draft/query isolation, apply no-op, period origin vs duration heuristic, exact vs related destinations, navigability⇔resolver, busy/double-tap, type×source mismatch, races, 3B defaults.

## 4. Achados

### CRÍTICA — Apply sempre recarregava

| Campo | Valor |
|-------|--------|
| problema | `apply()` sempre `setQuery` mesmo com seleção idêntica |
| impacto | reload inútil, flicker, races desnecessárias |
| correção | comparar `filterIdentity` antes de push; no-op se igual |
| teste | GATE B2 |

### CRÍTICA — Chip de período mentia (custom = preset)

| Campo | Valor |
|-------|--------|
| problema | label por duração (`30 dias` → `30 DIAS`) |
| impacto | custom de 30 dias parecia preset |
| correção | `periodOrigin` na selection; chip só pela origem |
| teste | GATE K |

### ALTA — “Detail” para destino related

| Campo | Valor |
|-------|--------|
| problema | `*DetailTarget` e copy “Detalhes completos…” |
| impacto | UX promete detalhe unitário inexistente |
| correção | renomear para `*HistoryTarget`; kind=`relatedHistory`; copy honesta |
| teste | GATE G relatedHistory |

### ALTA — type×source mismatch navegava

| Campo | Valor |
|-------|--------|
| problema | weight + source vacinas ainda resolved |
| correção | unavailable `typeSourceMismatch` |
| teste | GATE H |

### ALTA — Double-tap microtask / busy

| Campo | Valor |
|-------|--------|
| problema | `_busy` só após resolve; unavailable throw não preso mas race no busy |
| correção | `_busy=true` no início + try/finally em todos os ramos |
| teste | GATE I |

### MÉDIA — 6m/1a como 183/365 dias

| Campo | Valor |
|-------|--------|
| correção | calendário (`month - N`) |
| teste | calendar months / leap |

### MÉDIA — Resolver importava 3C mappers

| Campo | Valor |
|-------|--------|
| correção | constantes locais na presentation |

### BAIXA — Semantics do card 3B ainda genéricas

| Campo | Valor |
|-------|--------|
| residual | card não anuncia `navigationActionLabel` do target |
| decisão | 3E pode enriquecer; label existe no target |

### INFO — health_events unsupported

Confirmado; card não clicável.

## 5. Correções realizadas

1. Apply no-op por filterIdentity  
2. `periodOrigin` + chip sem heurística de duração  
3. Targets `WeightHistoryTarget` / Nutrition / Vaccination + kind relatedHistory  
4. Copy coordinator honesta  
5. type×source mismatch  
6. busy try/finally  
7. presets 6m/1a calendário  
8. endOfDay microsegundo inclusivo  
9. caseId/professional no-op  
10. cópias defensivas de Set  
11. testes G2/B2/K/I/H  

## 6–8. Filter model / draft / no-op

- Draft isolado com `_defensiveCopy`
- Apply: query igual → sem setQuery; UI applied atualiza (incl. origin)
- Clear vazio / remove chip inexistente → no-op

## 9–11. Period / timezone

- start = início dia local inclusivo  
- end = 23:59:59.999999 inclusivo  
- 6m/1a: calendário Dart  
- origin separada da query  

## 12–13. Contextuais / races

- case/professional no-op se igual  
- professional: igualdade do contrato 3A (case-sensitive name)  
- Gates D/E com source gated  

## 14. 3B regressions

Parâmetros 3D opcionais; sem `entryNavigable`/`onClearFilters` → comportamento anterior. Empty copy atualizada (filtrado).

## 15–16. Destinos

| origem | kind | status |
|--------|------|--------|
| health_events | none | unsupported |
| weight_records | relatedHistory | resolved |
| feeding_* | relatedHistory | resolved |
| vacinas | relatedHistory | resolved |
| mismatch type×source | none | unavailable |
| raw | none | unsupported |

**Não há exactDetail na v1 legada.**

## 17–19. Resolver / navigability

`isNavigable` ⇔ `resolveEntry is Resolved` — única fonte.

## 20–21. Coordinator

busy no início; finally; unavailable throw absorvido.

## 22–24. Harness / a11y / responsive

Harness GATE J; 360 overflow test.

## 25–26. Tests / Gates

Gates A, B, B2, C, D, E, F, G, G2, H, I, J, K + immutability/leap/case no-op.

**38 passed** nos arquivos 3D (pós-auditoria).

## 27. Validations

| Check | Resultado |
|-------|-----------|
| 3D tests dedicados | **38 passed** |
| timeline presentation | **217 passed** |
| health | **634 passed** |
| global | **817 passed, 1 skipped** |
| analyze timeline/3D | **No issues found** |
| analyze global | preexistentes; **0** novos da 3D |

## 28. Scope

Sem shell, 3C app wiring, writes, 3A changes. 3B mínimo documentado.

## 29. Risks remaining

1. Semantics do card 3B não usam ainda `navigationActionLabel`  
2. Telas related não focam `sourceId`  
3. fromQuery perde origin real → custom se período ativo  
4. 3E wiring real  

## 30. Git state

HEAD base `efeec66…`. 3D no working tree. **Sem commit.**

## 31. Conclusion

# APROVADA PARA COMMIT

Interação de filtros e navegação contextual com semântica honest (related ≠ exact), navigability única, apply no-op e busy seguro.
