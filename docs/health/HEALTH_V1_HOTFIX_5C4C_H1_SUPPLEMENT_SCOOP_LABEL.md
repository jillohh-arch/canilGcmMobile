# HOTFIX 5C.4C-H1
## SUPPLEMENT UNIT LABEL — SCOOP / MEDIDA DO DOSADOR

**Status:** READY FOR HUMAN AUDIT
**Date:** 2026-07-22
**Finding Origin:** MINOR-01 from Gate 5C.4C

---

## 1. Finding

| Field | Value |
|-------|-------|
| ID | MINOR-01 |
| Category | UX / Data Quality |
| Severity | MINOR |

**Description:**
During legitimate production supplement administration of Organew Pet to Bono, the operator physically used 1 scoop/measure from the supplement doser, but selected `unit = other` because the option presented as `dose (colher)` did not clearly communicate that it corresponded to the scoop/doser of the supplement.

---

## 2. Root Cause

| Issue | Detail |
|-------|--------|
| Wire value | `scoop` (correct, unchanged) |
| Form label | `dose (colher)` (unclear) |
| Card display | `scoop` (technical) |

The domain already supported `scoop` as a canonical unit, but:
- The form label `dose (colher)` was ambiguous
- Card displays showed the raw wire value `scoop` instead of user-friendly text

---

## 3. Decision

| Item | Decision |
|------|----------|
| Wire value `scoop` | PRESERVED — unchanged |
| Backend contract | PRESERVED — no changes |
| Existing `other` records | PRESERVED — historical data unchanged |
| Display labels | IMPROVED — user-friendly presentation |

---

## 4. Changes

### 4.1 Domain — supplement_log.dart

Added `displayLabel` getter to `SupplementDoseUnit`:

```dart
String get displayLabel => switch (this) {
  SupplementDoseUnit.mg => 'mg',
  SupplementDoseUnit.g => 'g',
  SupplementDoseUnit.ml => 'ml',
  SupplementDoseUnit.scoop => 'scoop',
  SupplementDoseUnit.tablet => 'comprimido',
  SupplementDoseUnit.drop => 'gota',
  SupplementDoseUnit.other => 'outra',
};
```

**Wire values unchanged:**
```dart
String get wireName => switch (this) {
  SupplementDoseUnit.scoop => 'scoop',  // unchanged
  // ...
};
```

### 4.2 Form — health_supplement_form_sheet.dart

**Before:**
```dart
SupplementDoseUnit.scoop => 'dose (colher)',
```

**After:**
```dart
SupplementDoseUnit.scoop => 'Scoop / medida do dosador',
```

### 4.3 Cards — health_nutrition_today_screen.dart

**Before:**
```dart
'${r.dose} ${r.unit.wireName} · ${r.frequency}'
'${a.dose} ${a.unit.wireName} · '
```

**After:**
```dart
'${r.dose} ${r.unit.displayLabel} · ${r.frequency}'
'${a.dose} ${a.unit.displayLabel} · '
```

---

## 5. Mapping Before/After

| Unit | Wire Value | Form Label Before | Form Label After | Card Before | Card After |
|------|------------|-------------------|------------------|-------------|------------|
| `mg` | `mg` | `mg (miligrama)` | `mg (miligrama)` | `mg` | `mg` |
| `g` | `g` | `g ( grama)` | `g ( grama)` | `g` | `g` |
| `ml` | `ml` | `ml (mililitro)` | `ml (mililitro)` | `ml` | `ml` |
| `scoop` | `scoop` | `dose (colher)` | **`Scoop / medida do dosador`** | `scoop` | **`scoop`** |
| `tablet` | `tablet` | `comprimido` | `comprimido` | `tablet` | **`comprimido`** |
| `drop` | `drop` | `gota` | `gota` | `drop` | **`gota`** |
| `other` | `other` | `outra` | `outra` | `other` | **`outra`** |

---

## 6. What Was NOT Changed

- Wire values (`scoop`, `tablet`, etc.) — PRESERVED
- Backend callable — NO CHANGE
- Firestore Rules — NO CHANGE
- Existing SupplementLog records — UNCHANGED
- `other` wire value — PRESERVED (historical Organew record shows `1.0 other`)
- Payload sent to callable — UNCHANGED (still sends `scoop`)
- Parser/validator — UNCHANGED

---

## 7. Tests

### 7.1 New Test — supplement_log_test.dart

```dart
test('unit expõe displayLabels amigáveis', () {
  // wire values unchanged
  expect(SupplementDoseUnit.scoop.wireName, 'scoop');
  // display labels are user-friendly
  expect(SupplementDoseUnit.scoop.displayLabel, 'scoop');
  expect(SupplementDoseUnit.tablet.displayLabel, 'comprimido');
  expect(SupplementDoseUnit.drop.displayLabel, 'gota');
  expect(SupplementDoseUnit.other.displayLabel, 'outra');
  // ...
});
```

### 7.2 Test Results

```
flutter test test/features/health/
00:51 +1123 ~5: All tests passed!
```

**Regressão:** 0 failures

---

## 8. Historical Data Preservation

The existing production SupplementLog for Organew:

```json
{
  "supplement_name": "Organew",
  "dose": 1,
  "unit": "other",
  "notes": "Administrado um scoopy junto com a refeição"
}
```

Will continue to display as:
- **Card:** `1.0 other`
- **Not converted** to `scoop`

This is correct — the historical record reflects what was submitted.

---

## 9. Git State

| Field | Value |
|-------|-------|
| Branch | `feature/health-v1-foundation` |
| Base HEAD | `3e5b72c2cafeb568e055d7399dbbaa6c9d3f1e1b` |
| Files changed | 4 |
| Tests | +1 (displayLabel test) |

**Files modified:**
1. `lib/features/health/domain/supplement_log.dart` — Added `displayLabel` getter
2. `lib/features/health/presentation/nutrition/health_supplement_form_sheet.dart` — Updated scoop label
3. `lib/features/health/presentation/nutrition/health_nutrition_today_screen.dart` — Use `displayLabel` in cards
4. `test/features/health/domain/supplement_log_test.dart` — Added `displayLabel` test

---

## 10. Verdict

```
┌────────────────────────────────────────────────────────────┐
│  HOTFIX 5C.4C-H1                                       │
│  SUPPLEMENT UNIT LABEL — SCOOP / MEDIDA DO DOSADOR      │
│                                                             │
│  STATUS: READY FOR HUMAN AUDIT                           │
│                                                             │
│  wire value scoop: PRESERVED                            │
│  form label: UPDATED to "Scoop / medida do dosador"      │
│  card display: UPDATED to user-friendly labels           │
│  historical data: PRESERVED                              │
│                                                             │
│  BLOCKER: 0                                             │
│  MAJOR: 0                                               │
│  MINOR: 0                                               │
│                                                             │
│  Tests: 1123 passed, 0 failed                           │
└────────────────────────────────────────────────────────────┘
```

---

**Documento criado em:** 2026-07-22T17:00:00Z
