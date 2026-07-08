# Sessão 2026-07-08 — Sincronização Rules + Denormalização Saúde + Deploy completo

## Contexto

Dois repos divergiram no `firestore.rules` ao longo de sessões anteriores.
Mobile evoluiu rapidamente (guarnição, hardening, legados, turno sem K9).
Web recebeu por engano a regra de saúde denormalizada (`canUpdateDogDenormalizedStats`).
Necessário sincronizar antes de testar turno sem K9 com o Silva.

---

## Entrega 1 — Diagnóstico da divergência (14 diferenças semânticas)

**Diff literal executado.** Diferenças identificadas:
1. `canUpdateDogDenormalizedStats` — só no web
2. `shift_group_id/code/label` em whitelists — só no mobile
3. `vehicleChanges` em shift_logs — só no mobile
4. `dogId.size() > 0` removido (turno sem K9) — só no mobile
5. `active_shifts` create/update separados com diff-based — só no mobile
6. `vehicle_crews` create com `ended_at` — só no mobile
7. `vehicle_crews` update com `diff().affectedKeys()` — só no mobile
8. `vehicle_crews/members` roles expandidos — só no mobile
9. `vehicle_crews/members` transições completas — só no mobile
10. `vehicle_crew_history` coleção inteira — só no mobile
11. `users/{ra}` create whitelist — só no mobile
12. `users/{ra}` update whitelist — só no mobile
13. `documentos/{docId}` create/update com emissor — só no mobile
14. Coleções legadas (6 coleções) — só no mobile

**Decisão:** mobile é fonte canônica (13/14 items). Falta apenas portar saúde do web.

---

## Entrega 2 — Sincronização firestore.rules

**Ações:**
- Portada função `canUpdateDogDenormalizedStats()` do web → mobile
- Adicionado `|| canUpdateDogDenormalizedStats()` no `allow update` de `dogs/{dogId}`
- Copiado arquivo inteiro mobile → web (diff = zero)
- CLAUDE.md mobile: "fonte canônica, deploy só daqui"
- CLAUDE.md web: "espelho, nunca editar rules aqui"
- BACKLOG.md: registrado na seção ✅

**Validação:** emulador Firestore carregou rules sem erro.

---

## Entrega 3 — Patch das Cloud Functions (denormalização _last_*)

**Problema:** saúde criada pelo mobile via CFs não atualizava `_last_*` no doc
`dogs/{id}` → dashboard web ficava stale para registros feitos em campo.

**Solução em `functions/src/index.ts`:**

1. Nova função helper `buildHealthDenormPatch(type, eventDate, nextDueDate)`:
   - vaccination → `{ _last_vaccine_at, _last_vaccine_due_at? }`
   - exam → `{ _last_exam_at }`
   - outros → `{}`

2. `adminCreateHealthEvent`: adicionado `batch.set(dogRef, denormPatch, {merge: true})`
   antes do audit log, condicionado a patch não-vazio.

3. `adminCreateK9WeightRecord`: adicionado `_last_weight_kg` e `_last_weight_at`
   ao merge que já existia no dogRef.

**Build:** `npm run build` = ✅ sem erros.

---

## Entrega 4 — Deploy (executado pelo usuário)

Sequência executada:
```bash
firebase deploy --only firestore:rules      # mobile
firebase deploy --only functions            # mobile (CFs patchadas)
firebase deploy --only firestore:indexes    # indexes
node tools/denormalize_health_to_dogs.mjs   # migração dos _last_* existentes
firebase deploy --only hosting              # web
```

Todos concluídos com sucesso.

---

## Entrega 5 — Commits e push

**Mobile** (`canil-gcm`, branch `main`):
- Commit `5ad653c`: `feat(rules,functions): sync canônico + denormalizar _last_* nas CFs de saúde`
- Push: `main → origin/main` ✅

**Web** (`k9-ops`, branch `master`):
- Commit `efeee49`: `perf(dashboard): dados denormalizados + sync firestore.rules canônico do mobile`
- Push: `master → origin/master` ✅

---

## Resumo de tudo feito em 07-08/jul (sessões combinadas)

### Mobile (canil-gcm)
| Commit | Resumo |
|--------|--------|
| `6a266d8` | Multi-membro: 4 correções do teste com Silva (convites removidos, turno sem K9, troca K9 livre, card real-time) |
| `13d3bd2` | Hardening saveUser + rules legadas + composição configurável |
| `5ad653c` | Sync rules canônico + CFs denormalizam _last_* |

### Web (k9-ops)
| Commit | Resumo |
|--------|--------|
| `77a3a3a` | canUpdateDogDenormalizedStats para campos _last_* em dogs |
| `efeee49` | Dashboard denormalizado + sync firestore.rules do mobile |

### Infraestrutura Firebase
- **Rules:** versão canônica completa em produção (guarnição + turno sem K9 + saúde + legados + hardening)
- **Functions:** handlers de saúde agora denormalizam _last_* automaticamente
- **Migração:** _last_* populados para todos os dogs existentes
- **Hosting:** web atualizado com dashboard consumindo dados denormalizados

---

## Pendente

- [ ] Gerar build APK novo para o teste do Silva (turno sem K9 precisa do Dart atualizado)
- [ ] Smoke test: iniciar turno sem K9 → confirma rules no ar
- [ ] Smoke test: dashboard web mostra cards de saúde com dados reais
- [ ] Remover role `'titular'` transitório das rules após rollout completo do APK (BACKLOG item 3)

---

## Decisões registradas

1. **firestore.rules canônico = repo mobile.** Web é espelho. Deploy de rules SOMENTE do mobile.
2. **Denormalização _last_* = server-side + client-side.** CFs cobrem registros do mobile; web faz best-effort client-side.
3. **Ordem de deploy:** rules → functions → indexes → migração → hosting.
