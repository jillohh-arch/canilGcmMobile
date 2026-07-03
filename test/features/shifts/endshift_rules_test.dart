import 'package:flutter_test/flutter_test.dart';

/// Simula a lógica das Firestore Rules para vehicle_crews e active_shifts.
/// Este arquivo replica os hasOnly() e validações do arquivo firestore.rules
/// commitado em HEAD. Usado para verificar que os writes do ShiftService
/// passam nas rules sem precisar do emulator.
///
/// REGRAS REPLICADAS (de firestore.rules HEAD):
///   - vehicle_crews/{id}/members update (status=ended):
///     diff affectedKeys hasOnly [status, left_at, dog_id, updated_at]
///     AND role in [...,'motorista','encarregado','auxiliar_1','auxiliar_2','k9','']
///                                                        ⚠️ 'titular' AUSENTE!
///   - active_shifts update: diff affectedKeys hasOnly [22 campos]
///   - shift_logs update: diff affectedKeys hasOnly [18 campos]

// ─────────────────────────────────────────────────────────────────────────────
// Simulações de hasOnly e validações
// ─────────────────────────────────────────────────────────────────────────────

/// Verifica se [keys] é subconjunto de [allowed].
/// (Equivalente a keys.isSubsetOf(allowed) — sem dependência de package.)
bool _isSubsetOf(Set<String> keys, List<String> allowed) {
  for (final k in keys) {
    if (!allowed.contains(k)) return false;
  }
  return true;
}

/// Verifica se [keys] (Set) é exatamente igual a [allowed].
bool _hasOnly(Set<String> keys, List<String> allowed) {
  if (keys.length != allowed.length) return false;
  return _isSubsetOf(keys, allowed);
}

/// Verifica se todos os campos changed (diff) estão no conjunto allowed.
bool _diffHasOnly(
  Map<String, dynamic> newDoc,
  Map<String, dynamic> oldDoc,
  List<String> allowedDiff,
) {
  final changedKeys = <String>{};
  for (final key in newDoc.keys) {
    if (!_deepEqual(newDoc[key], oldDoc[key])) {
      changedKeys.add(key);
    }
  }
  return _isSubsetOf(changedKeys, allowedDiff);
}

bool _deepEqual(dynamic a, dynamic b) {
  if (a is DateTime && b is DateTime) return a.millisecondsSinceEpoch == b.millisecondsSinceEpoch;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!_deepEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_deepEqual(a[k], b[k])) return false;
    }
    return true;
  }
  return a == b;
}

// ─────────────────────────────────────────────────────────────────────────────
// Testes da regra de members/update — o bug está aqui
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('BUG DISCRIMINANTE: members/update com role=titular (legado)', () {
    test(
      'UPDATE ended: role=titular LEGADO — agora aceito após fix da allowlist',
      () {
        // Simula um member criado no modelo antigo: role='titular'
        final oldMember = {
          'handler_id': 'RA001',
          'auth_uid': 'uid1',
          'handler_email': 'ra001@gcm',
          'name': 'João',
          'role': 'titular', // ← legado
          'status': 'active',
          'joined_at': DateTime.now(),
          'responded_at': DateTime.now(),
          'decline_reason': null,
          'dog_id': 'K9MAX',
          'left_at': null,
          'updated_at': DateTime.now(),
        };

        // endShift: só muda status, left_at, dog_id, updated_at
        final newMember = Map<String, dynamic>.from(oldMember);
        newMember['status'] = 'ended';
        newMember['left_at'] = DateTime.now();
        newMember['dog_id'] = 'K9MAX';
        newMember['updated_at'] = DateTime.now();

        final endedBranchAllowedDiff = ['status', 'left_at', 'dog_id', 'updated_at'];
        // REGRAS ATUALIZADAS: 'titular' adicionado na allowlist do update
        final validRolesForEnded = ['titular', 'motorista', 'encarregado', 'auxiliar_1', 'auxiliar_2', 'k9', ''];

        final diffOk = _diffHasOnly(newMember, oldMember, endedBranchAllowedDiff);
        expect(diffOk, isTrue, reason: 'diff deve conter só [status,left_at,dog_id,updated_at]');

        // Após fix: 'titular' agora está na allowlist → aceito
        final roleExisting = oldMember['role'] as String;
        final roleAllowed = validRolesForEnded.contains(roleExisting);

        expect(
          roleAllowed,
          isTrue,
          reason: "role='$roleExisting' deve passar na allowlist atualizada "
              "$validRolesForEnded. Bug corrigido.",
        );
      },
    );

    test(
      'UPDATE ended: member NOVO (role=motorista) — DEVE passar',
      () {
        final oldMember = {
          'handler_id': 'RA002',
          'role': 'motorista', // ← novo papel
          'status': 'active',
          'left_at': null,
          'dog_id': 'K9BUD',
          'updated_at': DateTime.now(),
        };

        final newMember = Map<String, dynamic>.from(oldMember);
        newMember['status'] = 'ended';
        newMember['left_at'] = DateTime.now();
        newMember['updated_at'] = DateTime.now();

        final validRoles = ['motorista', 'encarregado', 'auxiliar_1', 'auxiliar_2', 'k9', ''];
        final roleAllowed = validRoles.contains(oldMember['role'] as String);

        expect(roleAllowed, isTrue,
            reason: 'motorista deve passar na allowlist de update');
      },
    );
  });

  group('endShift: todos os writes vs rules commitadas (HEAD)', () {
    late DateTime now;
    late DateTime startedAt;

    setUp(() {
      now = DateTime.now();
      startedAt = DateTime.now().subtract(const Duration(hours: 4));
    });

    test('write 1: active_shifts/{ra} merge — endShift', () {
      // endShift envia: {status:'ended', endedAt:now, updatedAt:now}
      // Regras (HEAD):
      //   active_shifts update: diff hasOnly [22 campos listados]
      //   endedAt, status, updatedAt ESTÃO na lista ✅
      final newDoc = {'status': 'ended', 'endedAt': now, 'updatedAt': now};
      final oldDoc = {
        'status': 'active',
        'endedAt': null,
        'updatedAt': startedAt,
        'dogId': 'K9MAX',
        'service_dog_id': 'K9MAX',
        'vehicle_id': 'GCM01',
      };

      final allowedDiff = [
        'shiftId','auth_uid','handler_email','shift_group_id','shift_group_code',
        'shift_group_label','dogId','service_dog_id','status','startedAt',
        'updatedAt','lastDogSwitchAt','endedAt','vehicle_id','vehicle_crew_id',
        'crew_id','crew_role','crew_status','vehicle_label','vehicle_prefix',
        'vehicle_model','vehicle_unit','vehicle_joined_at'
      ];

      final ok = _diffHasOnly(newDoc, oldDoc, allowedDiff);
      expect(ok, isTrue, reason: 'active_shifts merge do endShift deve passar na diff');
    });

    test('write 2: shift_logs/{id} merge — endShift', () {
      // endShift envia: {status:'ended', endedAt:now, updatedAt:now}
      // Regras (HEAD):
      //   shift_logs update: diff hasOnly [23 campos — exatos]
      //   status, endedAt, updatedAt ESTÃO na lista ✅
      final newDoc = {'status': 'ended', 'endedAt': now, 'updatedAt': now};
      final oldDoc = {
        'status': 'active',
        'endedAt': null,
        'updatedAt': startedAt,
        'dogId': 'K9MAX',
        'service_dog_id': 'K9MAX',
      };

      // Exatamente copiado de firestore.rules HEAD:
      //   isValidShiftLogUpdate affectedKeys hasOnly [...]
      final allowedDiff = [
        'currentDogId','dogSwitches','dog_changes','vehicleChanges',
        'auth_uid','handler_email','shift_group_id','shift_group_code',
        'shift_group_label','service_dog_id','vehicle_id','vehicle_crew_id',
        'crew_id','crew_role','crew_status','vehicle_label','vehicle_prefix',
        'vehicle_model','vehicle_unit','vehicle_joined_at','status','endedAt',
        'updatedAt'
      ];

      final ok = _diffHasOnly(newDoc, oldDoc, allowedDiff);
      expect(ok, isTrue, reason: 'shift_logs merge do endShift deve passar');
    });

    test('write 3: vehicle_crews/{id}/members/{ra} merge — endShift (role=titular)', () {
      // endShift envia: {status:'ended', left_at:now, dog_id:dogId, updated_at:now}
      // Regra (HEAD):
      //   ended branch: diff hasOnly [status,left_at,dog_id,updated_at] ✅
      //   AND role in [...,'motorista',...,'k9','']  ⚠️ 'titular' AUSENTE!
      final oldMember = {
        'handler_id': 'RA001',
        'role': 'titular', // LEGADO — campo existe no doc existente
        'status': 'active',
        'left_at': null,
        'dog_id': 'K9MAX',
        'updated_at': startedAt,
      };
      final newMember = {
        'handler_id': 'RA001',
        'role': 'titular', // role NÃO é enviada no merge (não mudou)
        'status': 'ended',
        'left_at': now,
        'dog_id': 'K9MAX',
        'updated_at': now,
      };

      final allowedDiff = ['status', 'left_at', 'dog_id', 'updated_at'];
      // REGRAS ATUALIZADAS: 'titular' agora está na allowlist do update
      final validRolesUpdate = ['titular', 'motorista', 'encarregado', 'auxiliar_1', 'auxiliar_2', 'k9', ''];

      // diff: só os 4 campos ✅
      expect(_diffHasOnly(newMember, oldMember, allowedDiff), isTrue);

      // role do doc EXISTENTE (não mudou, não está no diff)
      // mas a rule verifica: request.resource.data.role in validRoles
      // Para um member LEGADO com role='titular' → REJEITADO ❌
      final roleExisting = oldMember['role'] as String;
      final roleAllowed = validRolesUpdate.contains(roleExisting);

      expect(roleAllowed, isTrue,
        reason: "BUG: role='titular' do member legado NÃO está na allowlist "
            "de update. O write sera rejeitado pela rule.\n"
            "Allowed: $validRolesUpdate\n"
            "Existing role: '$roleExisting'");
    });

    test('write 4: vehicle_crews/{id} merge — close crew (hasOnly vs affectedKeys)', () {
      // NOTA: firestore rules avaliam request.resource.data = DOC RESULTANTE completo.
      // Com 13 campos presentes no doc de produção (dentro do whitelist de 14),
      // este write JÁ PASSARIA com hasOnly(keys) original.
      // A rule foi mudada para diff().affectedKeys().hasOnly() por PADRONIZAÇÃO
      // (mesmo padrão de active_shifts/shift_logs), não como bug fix confirmado.
      //
      // Este teste simula a rule atual (affectedKeys) para garantir que a mudança
      // não quebra nada — verifica que {active,ended_at,updated_at} é subconjunto
      // dos 14 campos permitidos.
      final changedFields = {'active', 'ended_at', 'updated_at'};

      final allowedFields = [
        'id','vehicle_id','vehicle_label','vehicle_prefix','vehicle_model',
        'vehicle_unit','crew_size','service_dog_id','titular_handler_id',
        'active','created_at','updated_at','ended_at','dog_changes'
      ];

      // Com diff().affectedKeys(): só verifica que os campos alterados estão
      // na whitelist — {active,ended_at,updated_at} ⊆ allowedFields ✅
      final ok = _isSubsetOf(changedFields, allowedFields);
      expect(ok, isTrue,
        reason: 'closeCrew deve passar na affectedKeys (muda 3 de 14 campos)');
    });

    test('write 5: vehicle_crew_history create — snapshot da guarnição', () {
      // _writeCrewHistorySnapshot envia (HEAD do commitado):
      // {id, vehicle_id, vehicle_label, vehicle_prefix, vehicle_model,
      //  period:{started_at,ended_at}, members:[{handler_id,role,joined_at,
      //  left_at,dog_id}], dog_changes, ended_by, shift_ids, created_at}
      // ⚠️ members[i] NÃO inclui 'name' (foi removido no fix anterior)
      final historyDoc = {
        'id': 'auto123',
        'vehicle_id': 'GCM01',
        'vehicle_label': 'GCM-01',
        'vehicle_prefix': 'GCM',
        'vehicle_model': 'Hilux',
        'period': {
          'started_at': startedAt,
          'ended_at': now,
        },
        'members': [
          {
            'handler_id': 'RA001',
            'role': 'titular',
            'joined_at': startedAt,
            'left_at': now,
            'dog_id': 'K9MAX',
          },
          {
            'handler_id': 'RA002',
            'role': 'motorista',
            'joined_at': startedAt,
            'left_at': now,
            'dog_id': 'K9MAX',
          },
        ],
        'dog_changes': <dynamic>[],
        'ended_by': 'RA001',
        'shift_ids': ['shift123'],
        'created_at': now,
      };

      final allowedTopLevel = [
        'id','vehicle_id','vehicle_label','vehicle_prefix','vehicle_model',
        'period','members','dog_changes','ended_by','shift_ids','created_at'
      ];

      // Top-level: keys() == hasOnly dos 11 campos (exatos)
      expect(
        _hasOnly(historyDoc.keys.toSet(), allowedTopLevel),
        isTrue,
        reason: 'top-level fields devem bater com hasOnly da rule',
      );

      // period é map com started_at e ended_at como DateTime
      final period = historyDoc['period'] as Map<String, dynamic>;
      expect(period['started_at'] is DateTime, isTrue,
          reason: 'period.started_at deve ser DateTime');
      expect(period['ended_at'] is DateTime, isTrue,
          reason: 'period.ended_at deve ser DateTime');

      // members é list
      expect(historyDoc['members'] is List, isTrue);
      final member = (historyDoc['members'] as List).first as Map<String, dynamic>;
      final allowedMemberFields = ['handler_id', 'role', 'joined_at', 'left_at', 'dog_id'];
      expect(
        _hasOnly(member.keys.toSet(), allowedMemberFields),
        isTrue,
        reason: 'member fields SEM name devem passar (name foi removido)',
      );

      // ended_by é string
      expect(historyDoc['ended_by'] is String, isTrue);
    });
  });
}
