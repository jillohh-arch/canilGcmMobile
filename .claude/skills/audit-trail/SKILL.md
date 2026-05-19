---
name: audit-trail
description: Padrão obrigatório de trilha de auditoria para escritas no Firestore do app Canil K9. Use sempre que criar, editar ou deletar documentos em coleções operacionais. Garante defesa profissional dos condutores K9 com rastreabilidade completa de quem, quando, o que foi alterado e por quê.
---

# Trilha de Auditoria · Padrão Obrigatório

## Por que existe

O app é arquivo de defesa profissional. Toda edição precisa ser rastreável.

Se um gestor questionar um registro 6 meses depois, precisamos provar:
- **Quem** fez (uid + nome + RA no momento do registro)
- **Quando** fez (timestamp do servidor, imutável)
- **O que** mudou (campo, valor antigo, valor novo)
- **Por quê** (em deletes obrigatório)

## Estrutura do audit_trail

Todo documento crítico tem campo `audit_trail` (array):

```typescript
interface AuditEntry {
  action: 'created' | 'updated' | 'deleted' | 'restored';
  at: Timestamp;
  by: string;          // uid do usuário
  by_name: string;     // snapshot do nome no momento
  by_ra: string;       // snapshot do RA no momento
  field?: string;      // só preenchido em 'updated'
  old_value?: any;
  new_value?: any;
  reason?: string;     // obrigatório em 'deleted'
}
```

**Por que snapshot de nome/RA?**
Porque o usuário pode mudar de nome ou RA. Mas o registro histórico precisa preservar 
quem era a pessoa **no momento da ação**.

## Coleções com audit_trail obrigatório

- `/occurrences/{id}` e subcoleção `events`
- `/dogs/{id}/health_events/{id}`
- `/dogs/{id}/feeding_events/{id}`
- `/dogs/{id}/weight_records/{id}`
- `/dogs/{id}/training_sessions/{id}`
- `/dogs/{id}/commands/{id}` (e estágios)
- `/dogs/{id}/conditioning_sessions/{id}`
- `/dogs/{id}/triagem_evaluations/{id}`
- `/dogs/{id}/nutritional_prescriptions/{id}`
- `/shifts/{id}`

## Coleções SEM audit_trail (mais simples)

- `/users/{uid}` (perfil próprio, edits raros)
- `/occurrence_types` (catálogo administrativo)
- Subcoleções de cache/preferências

## Como implementar

### Serviço centralizado de audit trail

Crie um serviço em `core/services/audit_trail.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_k9/features/auth/data/models/app_user.dart';

class AuditTrailService {
  /// Constrói entrada de criação
  Map<String, dynamic> buildCreateEntry(AppUser user) {
    return {
      'audit_trail': [
        {
          'action': 'created',
          'at': FieldValue.serverTimestamp(),
          'by': user.uid,
          'by_name': user.name,
          'by_ra': user.ra,
        },
      ],
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'created_by': user.uid,
    };
  }

  /// Constrói entrada de atualização (pra usar com FieldValue.arrayUnion)
  Map<String, dynamic> buildUpdateEntry({
    required String field,
    required dynamic oldValue,
    required dynamic newValue,
    required AppUser user,
  }) {
    return {
      'audit_trail': FieldValue.arrayUnion([
        {
          'action': 'updated',
          'at': Timestamp.now(),
          'by': user.uid,
          'by_name': user.name,
          'by_ra': user.ra,
          'field': field,
          'old_value': oldValue,
          'new_value': newValue,
        }
      ]),
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  /// Constrói entrada de soft delete
  Map<String, dynamic> buildDeleteEntry({
    required String reason,
    required AppUser user,
  }) {
    return {
      'deleted_at': FieldValue.serverTimestamp(),
      'deleted_by': user.uid,
      'deleted_reason': reason,
      'audit_trail': FieldValue.arrayUnion([
        {
          'action': 'deleted',
          'at': Timestamp.now(),
          'by': user.uid,
          'by_name': user.name,
          'by_ra': user.ra,
          'reason': reason,
        }
      ]),
    };
  }
}
```

### Uso ao criar documento

```dart
final auditTrail = AuditTrailService();

await _firestore.collection('weight_records').add({
  'dog_id': dogId,
  'weight_kg': weight,
  'measured_at': measuredAt,
  'observations': observations,
  ...auditTrail.buildCreateEntry(currentUser),
});
```

### Uso ao editar

```dart
// Buscar valor antigo PRIMEIRO (pra registrar na auditoria)
final doc = await ref.get();
final oldWeight = doc.data()?['weight_kg'];

// Atualizar com audit trail
await ref.update({
  'weight_kg': newWeight,
  ...auditTrail.buildUpdateEntry(
    field: 'weight_kg',
    oldValue: oldWeight,
    newValue: newWeight,
    user: currentUser,
  ),
});
```

### Uso ao soft-deletar

```dart
// SEMPRE pedir motivo ANTES
final reason = await showReasonDialog(context);
if (reason == null || reason.isEmpty) return; // cancelou

await ref.update({
  ...auditTrail.buildDeleteEntry(
    reason: reason,
    user: currentUser,
  ),
});
```

## Soft delete · padrão

**NUNCA** `doc.delete()`. **SEMPRE** soft delete com motivo:

```dart
// ❌ NUNCA
await doc.delete();

// ✅ SEMPRE
await doc.update({
  ...auditTrail.buildDeleteEntry(reason: motivo, user: user),
});
```

Queries devem filtrar deletados por padrão:

```dart
final query = _firestore
  .collection('feeding_events')
  .where('dog_id', isEqualTo: dogId)
  .where('deleted_at', isNull: true)  // ← filtro padrão
  .orderBy('timestamp', descending: true);
```

Pra ver deletados (recuperação ou auditoria):

```dart
final allIncludingDeleted = _firestore
  .collection('feeding_events')
  .where('dog_id', isEqualTo: dogId);
```

## Restaurar documento deletado

```dart
await ref.update({
  'deleted_at': FieldValue.delete(),
  'deleted_by': FieldValue.delete(),
  'deleted_reason': FieldValue.delete(),
  'audit_trail': FieldValue.arrayUnion([
    {
      'action': 'restored',
      'at': Timestamp.now(),
      'by': user.uid,
      'by_name': user.name,
      'by_ra': user.ra,
    }
  ]),
});
```

## Timestamps imutáveis

- `created_at` → **NUNCA muda**, definido na criação com `serverTimestamp()`
- `updated_at` → atualiza a cada edição
- Eventos dentro de subcoleções têm `timestamp` próprio (do evento, não do registro)

Exemplo:
```dart
{
  'created_at': '2026-05-12 09:42:00',     // imutável
  'updated_at': '2026-05-12 11:18:00',     // último update
  'timestamp': '2026-05-12 09:50:00',      // quando o evento aconteceu
}
```

## Fotos: preservar EXIF

Ao salvar fotos no Storage:
- ❌ NÃO comprimir/reprocessar a foto original
- ❌ NÃO remover EXIF
- ✅ Salvar metadata EXIF (data, hora, GPS, dispositivo)

Estrutura Storage:
```
/incidents/{id}/photos/
  ├── {photoId}_original.jpg     # com EXIF preservado
  └── {photoId}_thumb.jpg        # thumbnail comprimido (separado)
```

Implementação:
```dart
final imageFile = await picker.pickImage(source: ImageSource.camera);

// Original (com EXIF)
final originalRef = FirebaseStorage.instance.ref(
  'incidents/$incidentId/photos/${photoId}_original.jpg',
);
await originalRef.putFile(File(imageFile.path));

// Thumbnail (gerado a parte)
final thumbnail = await _generateThumbnail(imageFile.path);
final thumbRef = FirebaseStorage.instance.ref(
  'incidents/$incidentId/photos/${photoId}_thumb.jpg',
);
await thumbRef.putFile(thumbnail);
```

## Mostrar trilha de auditoria na UI

Quando o usuário tocar pra ver detalhes/edições:

```dart
Widget _buildAuditTrail(List<AuditEntry> entries) {
  // Ordenar por timestamp ASC (mais antigo primeiro)
  final sorted = entries.toList()..sort((a, b) => a.at.compareTo(b.at));
  
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: sorted.map((entry) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(_iconForAction(entry.action), size: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _describeEntry(entry),
                style: const TextStyle(fontSize: 11),
              ),
            ),
            Text(
              _formatDate(entry.at),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      );
    }).toList(),
  );
}

String _describeEntry(AuditEntry entry) {
  switch (entry.action) {
    case 'created':
      return '${entry.byName} criou o registro';
    case 'updated':
      return '${entry.byName} editou ${entry.field} '
             'de "${entry.oldValue}" para "${entry.newValue}"';
    case 'deleted':
      return '${entry.byName} excluiu: ${entry.reason}';
    case 'restored':
      return '${entry.byName} restaurou o registro';
  }
}
```

## No PDF, sempre incluir trilha

Quando gerar PDF de ocorrência, a última página deve mostrar a trilha completa em 
formato tabular legível. Isso é defesa profissional.

## Pontos de atenção

1. **Performance:** audit_trail pode crescer. Se um documento tiver 100+ entradas, 
   considere paginar ou mover entradas antigas pra subcoleção `audit_history`.

2. **Tamanho do documento:** Firestore limita docs a 1MB. Documentos com muitas 
   entradas no array podem se aproximar disso. Monitorar.

3. **Concorrência:** se dois condutores editam ao mesmo tempo, ambos os updates 
   precisam aparecer na trilha. `FieldValue.arrayUnion` resolve isso.

4. **Painel React:** confirme que ele NÃO sobrescreve o array `audit_trail` ao 
   editar (deveria fazer arrayUnion também). Se sobrescrever, vai apagar histórico.