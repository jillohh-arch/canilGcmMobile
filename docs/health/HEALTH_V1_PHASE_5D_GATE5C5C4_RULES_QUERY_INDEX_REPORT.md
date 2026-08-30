# Health v1 — Fase 5D Gate 5C.5C.4 Rules + Query/Index Proof

**Data:** 2026-07-23  
**Gate:** 5C.5C.4 (Rules + Query/Index Proof)  
**Rodada Corretiva:** 5C.5C.4.3  
**Status:** READY FOR HUMAN AUDIT  
**Branch:** `feature/health-v1-foundation`  
**Commit Base:** `73bda78a76c924b539d65898a228b890348e7082`

---

## RODADA CORRETIVA 5C.5C.4.3 — Executado

**Problema identificado e corrigido:**
1. ✅ Prova física de discrepancies usou `collectionGroup()` incorreta → Corrigida para usar query EXATA do runtime (`collection(path)`)
2. ✅ Índice de discrepancies COLLECTION_GROUP era desnecessário → Removido após prova física correta
3. ✅ Query test F usava collectionGroup incorreta → Corrigida para collection explícita
4. ✅ Script experimental de prova client-side → Removido (mantido apenas Admin SDK)

---

## 1. Preflight

```
branch: feature/health-v1-foundation
HEAD: 73bda78a76c924b539d65898a228b890348e7082
divergência: 4 ahead / 0 behind
status: ?? functions/audit_prod.mjs (permanently out of scope)
```

Estado exatamente como esperado.

---

## 2. Files Changed

### Modified Files:
1. **`firestore.rules`** – Added Health Timeline Rules (dog-scoped read, client write blocked)
2. **`firestore.indexes.json`** – Added 2 COLLECTION_GROUP indexes (meal_logs, supplement_logs)
3. **`tools/rules_tests/package.json`** – Added test:health-timeline script
4. **`firebase.json`** – No permanent changes

### Created Files:
1. **`tools/rules_tests/health_timeline_rules_tests.mjs`** – 19 Rules test cases
2. **`tools/rules_tests/health_timeline_query_index_tests.mjs`** – 8 query validation tests
3. **`tools/rules_tests/test_real_firestore_indexes_admin.mjs`** – Physical index proof script (Admin SDK)
4. **`docs/health/HEALTH_V1_PHASE_5D_GATE5C5C4_RULES_QUERY_INDEX_REPORT.md`** – This report

### No Changes:
- `functions/src/index.ts` – Zero modifications
- `functions/src/health_timeline_reconciliation.ts` – Zero modifications
- `functions/src/**/*.ts` – No runtime logic changes
- Mobile code – No changes
- Production – Zero exposure

---

## 3. Current Rules Architecture

Health v1 usa padrão dog-scoped estabelecido:
- `signedIn()` – User autenticado
- `canAccessDogRecord(dogId)` – Valida scope + dog assignment/active shift

**Access Model:**
- `access_scope: 'global'` → Acesso a todos os dogs
- `access_scope: 'own_records'` → Requer assignment ao dog ou active shift
- `isAdmin()` → Força global scope (ignora claim explícito)

**Collections existentes usando este padrão:**
- `dogs/{dogId}/health_schedule`
- `dogs/{dogId}/nutrition_plans`
- `dogs/{dogId}/meal_logs`
- `dogs/{dogId}/supplement_logs`

---

## 4. Timeline Rules Added

### 4.1 Health Timeline Client Access

**Path:** `dogs/{dogId}/health_timeline/{timelineId}`

**Rules:**
```javascript
match /health_timeline/{timelineId} {
  allow read: if signedIn() && canAccessDogRecord(dogId);
  allow create, update, delete: if false;
}
```

**Contract:**
- **Read:** Dog-scoped, requires authentication + dog access
- **Write:** Completely blocked for client
- **Backend:** Admin SDK bypasses client Rules

### 4.2 Internal State Rules

**Path:** `_health_projection_state/{document=**}`

**Rules:**
```javascript
match /_health_projection_state/{document=**} {
  allow read, write: if false;
}
```

**Contract:**
- Completely invisible to client
- Zero read/write access
- Backend-only state

---

## 5. Rules Tests — EXECUTED

**Command:**
```bash
cd tools/rules_tests
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=canil-gcm \
node --input-type=module -e "import('./health_timeline_rules_tests.mjs').then(m => m.run())"
```

**Result:** ✅ **19/19 PASS**

**Test Coverage:**
1. ✅ Anonymous timeline read → DENY
2. ✅ Authenticated authorized dog read → ALLOW
3. ✅ Authenticated user with global scope can read any dog → ALLOW
4. ✅ Authenticated with own_records scope + active shift → ALLOW
5. ✅ Authenticated with own_records scope without access → DENY
6. ✅ Authenticated with own_records scope + dog assignment (no active shift) → ALLOW
7. ✅ Client timeline create → DENY
8. ✅ Client timeline update → DENY
9. ✅ Client timeline delete → DENY
10. ✅ Authorized dog-scoped timeline query → ALLOW
11. ✅ Dog-scoped timeline query with global scope → ALLOW
12. ✅ Anonymous state read → DENY
13. ✅ Authenticated state read → DENY
14. ✅ Authenticated state discrepancies read → DENY
15. ✅ Client state create → DENY
16. ✅ Client state update → DENY
17. ✅ Client state delete → DENY
18. ✅ Admin user always has global scope (ignores access_scope claim) → ALLOW
19. ✅ Admin user with global scope timeline read → ALLOW

**Critical Validations:**
- ✅ Client writes completely blocked
- ✅ State collection invisible to clients
- ✅ Dog-scoped access enforced for own_records users
- ✅ Global scope users can access all dogs (consistent with project pattern)
- ✅ Admin always gets global access

---

## 6. Query Tests — EXECUTED

**Command:**
```bash
cd tools/rules_tests
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=canil-gcm \
node --input-type=module -e "import('./health_timeline_query_index_tests.mjs').then(m => m.run())"
```

**Result:** ✅ **8/8 PASS**

**Query Coverage:**
1. ✅ Forward MealLog collection group query (10 docs, ordered correctly)
2. ✅ Forward SupplementLog collection group query (5 docs)
3. ✅ Overlap Meal/Supplement query with range (12 docs within window)
4. ✅ Historical source traversal by document name (8 docs, ordered by ID)
5. ✅ Orphan health_timeline traversal (5 docs)
6. ✅ Known discrepancy query (1 doc with status 'open') — **CORRECTED to use collection(path)**
7. ✅ Pagination with cursor (startAfter) - global tie-break (5+5 docs, no overlap)
8. ✅ Query cross-dog verification (2 dogs discovered)

**Note:** Tests use `withSecurityRulesDisabled` to simulate Admin SDK behavior (backend bypasses Rules).

---

## 7. Physical Index Proof — EXECUTED Against Real Cloud Firestore

**Command:**
```bash
cd tools/rules_tests
node test_real_firestore_indexes_admin.mjs
```

**Result:** **3 MISSING_INDEX, 3 SUCCESS**

**Queries Tested Against Cloud Firestore (canil-gcm):**

| Query | Shape | Result | Evidence |
|-------|-------|--------|----------|
| A. meal_logs forward | `collectionGroup("meal_logs").orderBy("recorded_at").orderBy("__name__")` | ✗ MISSING_INDEX | `FAILED_PRECONDITION: requires COLLECTION_GROUP_ASC index for meal_logs.recorded_at` |
| B. supplement_logs forward | `collectionGroup("supplement_logs").orderBy("recorded_at").orderBy("__name__")` | ✗ MISSING_INDEX | `FAILED_PRECONDITION: requires COLLECTION_GROUP_ASC index for supplement_logs.recorded_at` |
| C. meal_logs overlap | `collectionGroup("meal_logs").where("recorded_at", range).orderBy("recorded_at").orderBy("__name__")` | ✗ MISSING_INDEX | `FAILED_PRECONDITION: requires COLLECTION_GROUP_ASC index for meal_logs.recorded_at` |
| D. meal_logs historical | `collectionGroup("meal_logs").orderBy("__name__")` | ✅ SUCCESS | Automatic single-field index |
| E. health_timeline orphan | `collectionGroup("health_timeline").orderBy("__name__")` | ✅ SUCCESS | Automatic single-field index |
| F. discrepancies | `collection("_health_projection_state/health_timeline_v1/discrepancies").where("status", "==", "open").orderBy("__name__")` | ✅ SUCCESS | Automatic single-field indexes (collection query, not collection group) |

**Proven Required Indexes:** 2

1. **meal_logs** / COLLECTION_GROUP_ASC / recorded_at
2. **supplement_logs** / COLLECTION_GROUP_ASC / recorded_at

**Proven NOT Required (additional indexes):**
- Historical pass (orderBy __name__ only) — uses automatic index
- Orphan pass (orderBy __name__ only) — uses automatic index
- Overlap pass — does not require an additional index; reuses the same COLLECTION_GROUP / recorded_at index already required by Forward
- **Discrepancy pass (collection explicit path)** — uses automatic single-field indexes

---

## 8. Exact Runtime Query Shapes

### 8.1 Forward Pass
```typescript
db.collectionGroup("meal_logs")
  .orderBy("recorded_at", "asc")
  .orderBy(FieldPath.documentId(), "asc")
  .limit(pageSize)
```

### 8.2 Overlap Pass
```typescript
db.collectionGroup("meal_logs")
  .where("recorded_at", ">=", windowStart)
  .where("recorded_at", "<=", windowEnd)
  .orderBy("recorded_at", "asc")
  .orderBy(FieldPath.documentId(), "asc")
  .limit(pageSize)
```

### 8.3 Historical Pass
```typescript
db.collectionGroup("meal_logs")
  .orderBy(FieldPath.documentId(), "asc")
  .limit(pageSize)
```

### 8.4 Orphan Pass
```typescript
db.collectionGroup("health_timeline")
  .orderBy(FieldPath.documentId(), "asc")
  .limit(pageSize)
```

### 8.5 Known Discrepancy Pass
```typescript
db.collection("_health_projection_state/health_timeline_v1/discrepancies")
  .where("status", "==", "open")
  .orderBy(FieldPath.documentId(), "asc")
  .limit(pageSize)
```

**Source:** `functions/src/health_timeline_reconciliation.ts:1129-1132`

**Note:** This is a **collection query** (explicit path), not a collection group query. Collection queries with single-field where + orderBy use automatic indexes.

---

## 9. Final Index Configuration

### 9.1 Deployed Indexes (Before Changes)

**Count:** 11 indexes (all COLLECTION scope)

No COLLECTION_GROUP indexes deployed.

### 9.2 Indexes Added: 2

1. **meal_logs (collection group):**
   - Collection group: `meal_logs`
   - Scope: `COLLECTION_GROUP`
   - Fields: `recorded_at ASC`
   - Supports: Forward pass, Overlap pass
   - Evidence: Cloud Firestore FAILED_PRECONDITION

2. **supplement_logs (collection group):**
   - Collection group: `supplement_logs`
   - Scope: `COLLECTION_GROUP`
   - Fields: `recorded_at ASC`
   - Supports: Forward pass
   - Evidence: Cloud Firestore FAILED_PRECONDITION

### 9.3 Why __name__ NOT Included

Per [Firebase composite index documentation](https://firebase.google.com/docs/firestore/query-data/indexing):

> "Every index automatically includes a `__name__` field as the last component following the order of the last explicitly ordered field."

**Therefore:**
- Index `recorded_at ASC` automatically includes `__name__` as tie-breaker
- Explicit `__name__` field is redundant

### 9.4 Why discrepancies Index NOT Required

**Runtime Query:**
```typescript
db.collection("_health_projection_state/health_timeline_v1/discrepancies")
  .where("status", "==", "open")
  .orderBy(FieldPath.documentId(), "asc")
```

**Reason:**
- This is a **collection query** (explicit path), not `collectionGroup()`
- Single-field `where()` on `status` uses automatic single-field index
- `orderBy(__name__)` uses automatic document ID index
- **No composite index required** for this query shape

**Physical Evidence:**
- Tested against Cloud Firestore real (canil-gcm)
- Result: ✅ SUCCESS (0 docs, no missing index error)

### 9.5 Final firestore.indexes.json

**Before:** 11 indexes (0 COLLECTION_GROUP)  
**After:** 13 indexes (+2 COLLECTION_GROUP)

```json
{
  "collectionGroup": "meal_logs",
  "queryScope": "COLLECTION_GROUP",
  "fields": [
    { "fieldPath": "recorded_at", "order": "ASCENDING" }
  ]
},
{
  "collectionGroup": "supplement_logs",
  "queryScope": "COLLECTION_GROUP",
  "fields": [
    { "fieldPath": "recorded_at", "order": "ASCENDING" }
  ]
}
```

---

## 10. Full Regression Results

### 10.1 Build
```bash
cd functions && npm run build
```
**Result:** ✅ SUCCESS

### 10.2 Reconciliation Unit
```bash
npx tsx src/health_timeline_reconciliation_test.ts
```
**Result:** ✅ 26/26 PASS

### 10.3 Reconciliation Emulator
```bash
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
GCLOUD_PROJECT=canil-gcm \
npx tsx src/health_timeline_reconciliation_emulator_test.ts
```
**Result:** ✅ 25/25 PASS

### 10.4 Runtime Unit
```bash
npx tsx src/health_timeline_runtime_test.ts
```
**Result:** ✅ 20/20 PASS

### 10.5 Runtime Emulator
```bash
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
GCLOUD_PROJECT=canil-gcm \
npx tsx src/health_timeline_trigger_emulator_test.ts
```
**Result:** ✅ 13/13 PASS

### 10.6 O3 Unit
```bash
npx tsx src/health_timeline_projection_test.ts
```
**Result:** ✅ 38/38 PASS

### 10.7 O3 Emulator
```bash
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
GCLOUD_PROJECT=canil-gcm \
npx tsx src/health_timeline_emulator_test.ts
```
**Result:** ✅ 15/15 PASS

### 10.8 Health/Nutrition
```bash
npm run test:health-nutrition
```
**Result:** ✅ ALL PASS

**Total Tests Executed:** 157+ (runtime) + 19 (Rules) + 8 (query) = 184+  
**Failed:** 0

---

## 11. Production Isolation

### 11.1 Zero Trigger Exports
```bash
git diff -- functions/src/index.ts
```
**Output:** (no changes)

### 11.2 Zero Runtime Changes
```bash
git diff -- functions/src/health_timeline_reconciliation.ts
```
**Output:** (no changes)

### 11.3 Verification
- ✅ No `onDocumentCreated` registered
- ✅ No `onSchedule` exported
- ✅ No `onWrite` triggers
- ✅ No deploy executed
- ✅ No backfill initiated
- ✅ No mobile changes
- ✅ No production SLA claimed
- ✅ No runtime logic altered

---

## 12. Findings

### 12.1 BLOCKER: 0
All blockers resolved.

### 12.2 MAJOR: 0
All major issues resolved.

### 12.3 MINOR: 0
All minor issues resolved.

### 12.4 OBSERVATION: 3

1. **Rules follow project pattern** — `access_scope: 'global'` gives access to all dogs; `access_scope: 'own_records'` requires assignment or active shift. Admins always get global scope.

2. **Discrepancy query uses collection, not collectionGroup** — Runtime query at `functions/src/health_timeline_reconciliation.ts:1129-1132` uses explicit collection path. No custom index required.

3. **Emulator cannot prove index requirements** — Firestore Emulator executes all queries regardless of indexes; only Cloud Firestore real validates index requirements.

---

## 13. Gate Verdict

### ✅ GATE 5C.5C.4 — READY FOR HUMAN AUDIT

**Criteria Met:**
1. ✅ Rules added (Timeline + State)
2. ✅ Client writes blocked
3. ✅ Client state access blocked
4. ✅ Dog-scoped access preserved (following project pattern)
5. ✅ Anonymous denial enforced
6. ✅ Query shapes documented (exact runtime queries)
7. ✅ Indexes proven physically (Cloud Firestore real)
8. ✅ Rules tests executed: 19/19 PASS
9. ✅ Query tests executed: 8/8 PASS (corrected to use exact runtime queries)
10. ✅ Full regression: 0 failed
11. ✅ Production isolation maintained
12. ✅ Zero trigger/scheduler registration
13. ✅ Zero mobile changes
14. ✅ Zero deployment
15. ✅ Zero runtime logic changes

**Test Results:**
- Rules tests: 19/19 ✅
- Query tests: 8/8 ✅ (corrected discrepancy query)
- Physical index proof: 2 required, 2 added ✅
- Reconciliation unit: 26/26 ✅
- Reconciliation emulator: 25/25 ✅
- Runtime unit: 20/20 ✅
- Runtime emulator: 13/13 ✅
- O3 unit: 38/38 ✅
- O3 emulator: 15/15 ✅
- Health/Nutrition: ALL PASS ✅
- **Total:** 184+ tests, 0 failed

**Physical Index Evidence:**
- ✅ Tested against real Cloud Firestore (canil-gcm)
- ✅ 2 indexes proven required via FAILED_PRECONDITION errors (meal_logs, supplement_logs)
- ✅ 3 queries proven NOT to require custom indexes (automatic indexes sufficient)
- ✅ Discrepancy query uses collection (explicit path), not collectionGroup

---

## 14. Index Configuration Summary

### Before:
- Deployed indexes: 11 (all COLLECTION scope)
- Local firestore.indexes.json: 11 indexes
- COLLECTION_GROUP indexes: 0

### After Correction:
- Local firestore.indexes.json: 13 indexes (+2)
- COLLECTION_GROUP indexes: 2 (both proven required)
- Physical evidence: Cloud Firestore FAILED_PRECONDITION errors

### Indexes Proven Required:
1. ✅ meal_logs / COLLECTION_GROUP / recorded_at ASC
2. ✅ supplement_logs / COLLECTION_GROUP / recorded_at ASC

### Indexes Proven NOT Required (additional indexes):
1. ✅ meal_logs historical (orderBy __name__ only) — automatic index
2. ✅ health_timeline orphan (orderBy __name__ only) — automatic index
3. ✅ Overlap — does not require an additional index; reuses the same COLLECTION_GROUP / recorded_at index already required by Forward
4. ✅ discrepancies (collection query with automatic indexes)

---

## 15. Recommended Scope for 5C.5C.5

**Next Gate:** Trigger Registration & First Reconciliation

**Scope:**
1. Register `onDocumentCreated` triggers:
   - `dogs/{dogId}/meal_logs/{mealId}`
   - `dogs/{dogId}/supplement_logs/{logId}`
2. Implement thin trigger wrappers
3. Connect triggers to runtime
4. Add scheduler foundation (daily reconciliation)
5. Execute smoke tests
6. Prepare deployment checklist

**Restrictions:**
- No automatic deploy
- No automatic backfill
- Human validation before production exposure

---

## 16. Git Status

```
M firestore.indexes.json
M firestore.rules
M tools/rules_tests/package.json
?? docs/health/HEALTH_V1_PHASE_5D_GATE5C5C4_RULES_QUERY_INDEX_REPORT.md
?? tools/rules_tests/health_timeline_query_index_tests.mjs
?? tools/rules_tests/health_timeline_rules_tests.mjs
?? tools/rules_tests/test_real_firestore_indexes_admin.mjs
?? functions/audit_prod.mjs (permanently out of scope)
```

**NO COMMIT**  
**NO PUSH**  
**NO DEPLOY**  
**NO PRODUCTION EXPOSURE**
