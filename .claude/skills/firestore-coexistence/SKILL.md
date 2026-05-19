---
name: firestore-coexistence
description: Regras críticas de coexistência com painel React que acessa o mesmo Firestore do app Flutter Canil K9. Use sempre antes de criar, modificar, renomear ou deletar campos ou coleções no Firestore. Define protocolo de 4 fases para mudanças destrutivas e protege produção contra quebras do painel web.
---

# Coexistência Firestore · Canil K9

## Contexto crítico

Existe um **painel web React em produção** que acessa o MESMO Firestore que o app 
Flutter. Ambos pertencem ao Jilles (gestor + condutor), mas o painel React **não pode 
quebrar**.

**Regra de ouro:** "Nunca quebre o painel React. Em dúvida, pergunte."

## Mudanças aditivas (SEGURAS)

Pode fazer sem cerimônia, apenas avise o Jilles:

✅ Adicionar campo NOVO em documento existente
✅ Adicionar coleção NOVA
✅ Adicionar subcoleção NOVA
✅ Adicionar índice composto
✅ Atualizar campo opcional (que pode ou não existir)

**Por quê são seguras:** painel React não vai notar (ignora campos que não lê).

## Mudanças destrutivas (PERIGOSAS)

Podem quebrar o painel:

❌ Remover campo existente
❌ Renomear campo
❌ Mudar tipo de campo (string → number, string → array)
❌ Mudar estrutura de objeto aninhado
❌ Migrar dados de uma coleção pra outra
❌ Excluir documentos massivamente
❌ Mudar regras de segurança restringindo acesso

**NUNCA faça diretamente.** Use o protocolo de 4 fases.

## Protocolo de 4 Fases para mudanças destrutivas

### Fase 1 — ADITIVA (não quebra ninguém)

Adicione o campo NOVO ao lado do antigo. Ambos coexistem.

```dart
// ANTES: doc tinha só { weight: 28.0 }
// AGORA: doc tem { weight: 28.0, weight_kg: 28.0 }

await doc.update({
  'weight': 28.0,      // antigo, mantido
  'weight_kg': 28.0,   // novo, em paralelo
});
```

Validação:
- ✅ App Flutter já usa o novo (`weight_kg`)
- ✅ Painel React continua usando o antigo (`weight`)
- ✅ Nenhum dos dois quebra

### Fase 2 — BACKFILL

Script ou Cloud Function preenche o campo novo retroativamente em documentos antigos.

```javascript
// Cloud Function ou script Node
const snapshot = await db.collection('weight_records').get();
for (const doc of snapshot.docs) {
  if (!doc.data().weight_kg && doc.data().weight) {
    await doc.ref.update({
      weight_kg: doc.data().weight,
    });
  }
}
```

Validação:
- ✅ 100% dos documentos têm o campo novo preenchido
- ✅ Campos antigo e novo refletem mesma informação

### Fase 3 — MIGRAÇÃO DO PAINEL REACT

Jilles atualiza o painel React pra ler/escrever no campo novo.

```javascript
// Painel React, antes:
const weight = doc.weight;

// Painel React, depois:
const weight = doc.weight_kg ?? doc.weight; // fallback de segurança
```

Validação:
- ✅ Painel React funciona com o novo campo
- ✅ Período de observação (~1 semana) sem erros
- ✅ Monitorar console/Sentry

### Fase 4 — CLEANUP

Após validação, remove campo antigo.

```dart
await doc.update({
  'weight': FieldValue.delete(), // remove o antigo
});
```

Validação final:
- ✅ Nenhum documento tem mais o campo antigo
- ✅ Painel e app continuam funcionando
- ✅ Código de migração removido
- ✅ Documentação atualizada

## Antes de qualquer mudança no Firestore, pergunte

1. **Essa mudança é aditiva ou destrutiva?**
2. **Se destrutiva, posso fazer aditiva primeiro?**
3. **O painel React lê esse campo?** (consulte Jilles se incerto)
4. **Vale a pena ou posso adaptar o código do app sem mudar Firestore?**
5. **Se for fazer, qual o plano em 4 fases?**

## Coleções e seus consumidores

| Coleção | App Flutter | Painel React | Cuidado especial |
|---------|-------------|--------------|------------------|
| `/users` | leitura/escrita | leitura/escrita | crítico (autenticação) |
| `/dogs` | leitura/escrita | leitura/escrita | crítico (entidade central) |
| `/shifts` | leitura/escrita | leitura | usado em relatórios |
| `/occurrences` | leitura/escrita | leitura | usado em relatórios |
| `/occurrences/{id}/events` | leitura/escrita | leitura | timeline |
| `/dogs/{id}/health_events` | leitura/escrita | leitura | histórico médico |
| `/dogs/{id}/training_sessions` | leitura/escrita | leitura | histórico treino |
| `/dogs/{id}/weight_records` | leitura/escrita | leitura | gráfico peso |

## Coleções marcadas NOVA na especificação (seguras pra criar)

- `/occurrence_types` — catálogo de naturezas de ocorrência
- `/dogs/{id}/specialties_state` — estado das especialidades por cão
- `/dogs/{id}/commands` — biblioteca de comandos por cão
- `/dogs/{id}/commands/{id}/stage_history` — histórico de estágios
- `/dogs/{id}/feeding_events` — refeições registradas
- `/dogs/{id}/nutritional_prescriptions` — prescrições nutricionais
- `/dogs/{id}/conditioning_sessions` — sessões de condicionamento
- `/dogs/{id}/triagem_evaluations` — triagens de aptidão
- `/dogs/{id}/documents` — laudos e certificações

**Todas podem ser criadas livremente** (são aditivas por definição).

## Regras de segurança

Quando criar coleção nova, **sempre** atualizar `firestore.rules`. Mostrar diff pro 
Jilles antes de fazer deploy.

Estrutura típica:
```
match /dogs/{dogId}/specialties_state/{specialtyId} {
  allow read: if isAuthenticated();
  allow write: if isAuthenticated() && (
    isHandlerOfDog(dogId) || 
    isManager()
  );
}
```

## Convenções pra documentos novos

Todo documento crítico tem:
```
{
  // ... campos específicos
  created_at: Timestamp,           // imutável
  updated_at: Timestamp,            // atualiza a cada edit
  created_by: string,               // uid
  audit_trail: Array<AuditEntry>    // ver skill audit-trail
}
```

## Em caso de dúvida sobre se quebra o painel

**Pause e pergunte ao Jilles.** Ele controla os dois sistemas, sabe o que cada um lê.

Não tente "deduzir" lendo o código do painel — pode estar desatualizado, pode ter 
queries dinâmicas que você não vê.

## Cuidados extras

- ⚠️ **NUNCA rode `collection.doc().delete()` em produção** sem confirmação explícita
- ⚠️ **NUNCA atualize muitos docs em batch** sem testar em ambiente dev primeiro
- ⚠️ **Backups antes de migração** — exportar coleção antes de Fase 2 (backfill)
- ⚠️ **Audit trail em mudanças de schema** — registrar a migração também

## Quando criar Cloud Functions

Pra operações que envolvem múltiplas coleções ou regras complexas, prefira Cloud 
Functions:

- Cálculo de selos de conformidade
- Geração de PDFs no servidor (quando crescer)
- Backfills de schema
- Notificações automáticas (vacinas vencendo)

Cloud Functions ficam no painel React (mesmo projeto Firebase), mas chamadas pelo app.