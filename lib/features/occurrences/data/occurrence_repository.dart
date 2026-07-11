import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/core/domain/occurrence_participation.dart';
import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/core/services/occurrence_transition_service.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_nature.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

class OccurrenceRepository {
  final FirebaseFirestore _firestore;

  OccurrenceRepository(this._firestore);

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('occurrences');

  CollectionReference<Map<String, dynamic>> _signatures(String occurrenceId) {
    return _collection.doc(occurrenceId).collection('signatures');
  }

  Future<Occurrence> create(Occurrence occurrence) async {
    final docRef = _collection.doc(occurrence.id);
    final now = DateTime.now();

    final entry = AuditService.buildInlineEntry(action: 'created');
    final primaryHandlerId = _primaryParticipationHandlerId(occurrence);
    final teamHandlerIds = occurrence.teamHandlerIds;
    final acceptedHandlerIds = primaryHandlerId == null
        ? <String>[]
        : <String>[primaryHandlerId];
    final pendingHandlerIds = teamHandlerIds
        .where((handlerId) => handlerId != primaryHandlerId)
        .toList();
    final created = occurrence.copyWith(
      createdAt: now,
      updatedAt: now,
      auditTrail: [entry],
      participationStatus: teamHandlerIds.isEmpty
          ? null
          : pendingHandlerIds.isEmpty
          ? 'accepted'
          : 'pending_acceptance',
      acceptedHandlerIds: acceptedHandlerIds,
      declinedHandlerIds: const [],
      pendingHandlerIds: pendingHandlerIds,
      editAuthorizedHandlerIds: acceptedHandlerIds,
      participationRevision: teamHandlerIds.isEmpty ? 0 : 1,
    );

    final batch = _firestore.batch();
    batch.set(docRef, created.toMap());
    final participationAt = DateTime.now();
    for (final member in created.team) {
      final handlerId = member.handlerId.trim();
      if (handlerId.isEmpty) continue;
      final participation = OccurrenceParticipation(
        handlerId: handlerId,
        status: handlerId == primaryHandlerId
            ? OccurrenceParticipationStatus.accepted
            : OccurrenceParticipationStatus.pending,
        at: participationAt,
        updatedBy: created.primaryHandlerRa,
      );
      batch.set(
        docRef.collection('participations').doc(handlerId),
        participation.toJson(),
      );
    }
    await batch.commit();

    unawaited(
      AuditService.log(
        action: 'created',
        entityType: 'occurrence',
        entityId: occurrence.id,
        summary: 'Ocorrencia criada: ${occurrence.typeName}',
        after: {
          'type_code': occurrence.typeCode,
          'status': occurrence.status.toMap(),
          'dog_id': occurrence.dogId,
          'vehicle_id': occurrence.vehicleId,
          'vehicle_label': occurrence.vehicleLabel,
          'team_handler_ids': occurrence.teamHandlerIds,
          'primary_handler_ra': occurrence.primaryHandlerRa,
        },
      ),
    );

    return created;
  }

  static String? _primaryParticipationHandlerId(Occurrence occurrence) {
    final primaryRa = occurrence.primaryHandlerRa?.trim();
    if (primaryRa != null && primaryRa.isNotEmpty) return primaryRa;

    for (final member in occurrence.team) {
      if (member.role == TeamRole.titular &&
          member.handlerId.trim().isNotEmpty) {
        return member.handlerId.trim();
      }
    }

    final primaryId = occurrence.primaryHandlerId.trim();
    if (primaryId.isNotEmpty && occurrence.teamHandlerIds.contains(primaryId)) {
      return primaryId;
    }
    return null;
  }

  Future<void> update(String id, Map<String, dynamic> updates) async {
    final docRef = _collection.doc(id);
    final snap = await docRef.get();
    if (!snap.exists) return;

    final currentData = snap.data()!;
    final normalizedUpdates = Map<String, dynamic>.from(updates);
    if (_isLockedForEditing(currentData) &&
        !_isAllowedLockedOccurrenceUpdate(normalizedUpdates)) {
      throw StateError(
        'Ocorrencia bloqueada permite apenas metadados de PDF e auditoria.',
      );
    }

    const noAuditFields = {
      'updated_at',
      'audit_trail',
      'finalization_draft',
      'status',
    };

    final entries = <Map<String, dynamic>>[];

    for (final key in normalizedUpdates.keys) {
      if (noAuditFields.contains(key)) continue;
      final oldValue = currentData[key];
      final newValue = normalizedUpdates[key];
      if (oldValue != newValue) {
        entries.add(
          AuditService.buildInlineEntry(
            action: 'updated',
            fieldName: key,
            oldValue: _serializeForAudit(oldValue),
            newValue: _serializeForAudit(newValue),
          ),
        );
      }
    }

    normalizedUpdates['updated_at'] = FieldValue.serverTimestamp();
    if (entries.isNotEmpty) {
      normalizedUpdates['audit_trail'] = FieldValue.arrayUnion(entries);
    }

    await docRef.update(normalizedUpdates);
  }

  /// Salva draft de finalizacao de forma leve. Nao gera audit trail.
  Future<void> saveDraft(String id, Map<String, dynamic> draft) async {
    final docRef = _collection.doc(id);
    await docRef.update({
      'status': OccurrenceStatus.finalizing.toMap(),
      'finalization_draft': draft,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> softDelete(String id, String userId, String reason) async {
    final docRef = _collection.doc(id);

    final entry = AuditService.buildInlineEntry(
      action: 'deleted',
      reason: reason,
    );

    await docRef.update({
      'deleted_at': FieldValue.serverTimestamp(),
      'deleted_by': userId,
      'delete_reason': reason,
      'deleted_reason': reason,
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    });

    unawaited(
      AuditService.log(
        action: 'deleted',
        entityType: 'occurrence',
        entityId: id,
        summary: 'Ocorrencia excluida: $reason',
        metadata: {'reason': reason},
      ),
    );
  }

  Future<void> finalize({
    required String id,
    required String integrityHash,
    required String finalReport,
    required List<OccurrenceResult> results,
    required Map<String, dynamic>? details,
    List<String> finalizationPhotos = const [],
    List<String> finalizationPhotoHashes = const [],
    int hashVersion = 2,
  }) async {
    if (hashVersion >= 4) {
      await OccurrenceTransitionService().sealOccurrenceV4(
        occurrenceId: id,
        finalReport: finalReport,
        results: results,
        details: details,
        finalizationPhotos: finalizationPhotos,
        finalizationPhotoHashes: finalizationPhotoHashes,
      );
      return;
    }

    final docRef = _collection.doc(id);
    final entry = AuditService.buildInlineEntry(action: 'finalized');

    debugPrint('[OccurrenceRepo] finalize: iniciando para $id');

    final updateData = <String, dynamic>{
      'status': OccurrenceStatus.finalized.toMap(),
      'finalized_at': FieldValue.serverTimestamp(),
      'integrity_hash': integrityHash,
      'hash_version': hashVersion,
      'final_report': finalReport,
      'results': results.map((r) => r.toMap()).toList(),
      'details': details,
      'finalization_photos': finalizationPhotos,
      'finalization_photo_hashes': finalizationPhotoHashes,
      'finalization_draft': FieldValue.delete(),
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    };

    final future = docRef.update(updateData);

    try {
      await future.timeout(const Duration(seconds: 15));
      debugPrint('[OccurrenceRepo] finalize: confirmado pelo servidor');
    } on TimeoutException {
      debugPrint(
        '[OccurrenceRepo] finalize: timeout; write enfileirado localmente',
      );
    }

    unawaited(
      AuditService.log(
        action: 'finalized',
        entityType: 'occurrence',
        entityId: id,
        summary: 'Ocorrencia finalizada',
        after: {
          'integrity_hash': integrityHash,
          'hash_version': hashVersion,
          'results': results.map((r) => r.toMap()).toList(),
        },
      ),
    );
  }

  Future<void> finalizeWithPending({
    required String id,
    required String integrityHash,
    required String finalReport,
    required List<OccurrenceResult> results,
    required Map<String, dynamic>? details,
    List<String> finalizationPhotos = const [],
    List<String> finalizationPhotoHashes = const [],
    int hashVersion = 2,
  }) async {
    if (hashVersion >= 4) {
      await OccurrenceTransitionService().sealOccurrenceV4(
        occurrenceId: id,
        finalReport: finalReport,
        results: results,
        details: details,
        finalizationPhotos: finalizationPhotos,
        finalizationPhotoHashes: finalizationPhotoHashes,
        withPending: true,
      );
      return;
    }

    final docRef = _collection.doc(id);
    final current = await getById(id);
    if (current == null) {
      throw StateError('Ocorrencia nao encontrada');
    }
    if (current.status != OccurrenceStatus.awaitingSignatures) {
      throw StateError(
        'So e possivel finalizar com pendencia ocorrencias aguardando assinaturas',
      );
    }
    if (finalReport.trim().isEmpty) {
      throw StateError('Relato final obrigatorio para selar a ocorrencia');
    }
    final entry = AuditService.buildInlineEntry(
      action: 'finalized_with_pending',
    );

    debugPrint('[OccurrenceRepo] finalizeWithPending: iniciando para $id');

    final updateData = <String, dynamic>{
      'status': OccurrenceStatus.finalizedWithPending.toMap(),
      'finalized_at': FieldValue.serverTimestamp(),
      'integrity_hash': integrityHash,
      'hash_version': hashVersion,
      'final_report': finalReport,
      'results': results.map((r) => r.toMap()).toList(),
      'details': details,
      'finalization_photos': finalizationPhotos,
      'finalization_photo_hashes': finalizationPhotoHashes,
      'finalization_draft': FieldValue.delete(),
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    };

    final future = docRef.update(updateData);

    try {
      await future.timeout(const Duration(seconds: 15));
      debugPrint(
        '[OccurrenceRepo] finalizeWithPending: confirmado pelo servidor',
      );
    } on TimeoutException {
      debugPrint(
        '[OccurrenceRepo] finalizeWithPending: timeout; write enfileirado localmente',
      );
    }

    unawaited(
      AuditService.log(
        action: 'finalized_with_pending',
        entityType: 'occurrence',
        entityId: id,
        summary: 'Ocorrencia finalizada com pendencias',
        after: {
          'integrity_hash': integrityHash,
          'hash_version': hashVersion,
          'status': OccurrenceStatus.finalizedWithPending.toMap(),
        },
      ),
    );
  }

  Future<void> recordPdfAccess({
    required String id,
    required String action,
    String? pdfUrl,
  }) async {
    final docRef = _collection.doc(id);
    final entry = AuditService.buildInlineEntry(action: action);
    final access = {
      'at': DateTime.now().toIso8601String(),
      'by': entry['performed_by'],
      'by_name': entry['by_name'],
      'by_ra': entry['by_ra'],
      'ip': 'client-unavailable',
      'action': action,
      if (pdfUrl?.trim().isNotEmpty == true) 'pdf_url': pdfUrl,
    };

    await docRef.update({
      'pdf_access_log': FieldValue.arrayUnion([access]),
      'audit_trail': FieldValue.arrayUnion([entry]),
    });

    unawaited(
      AuditService.log(
        action: action,
        entityType: 'occurrence',
        entityId: id,
        summary: action == 'pdf_shared'
            ? 'PDF da ocorrencia compartilhado'
            : 'PDF da ocorrencia acessado',
        metadata: access,
      ),
    );
  }

  Future<void> addTeamMember({
    required String occurrenceId,
    required OccurrenceTeamMember member,
  }) async {
    final docRef = _collection.doc(occurrenceId);
    final current = await getById(occurrenceId);
    if (current == null) {
      throw StateError('Ocorrencia nao encontrada');
    }
    if (current.status != OccurrenceStatus.inProgress) {
      throw StateError(
        'So e possivel adicionar membros em ocorrencias em andamento',
      );
    }
    if (current.team.any((m) => m.handlerId == member.handlerId)) {
      throw StateError('Membro ja esta na equipe');
    }
    if (current.team.length >= current.teamSizeMax) {
      throw StateError(
        'Equipe atingiu o limite maximo de ${current.teamSizeMax} membros',
      );
    }

    final normalizedMember = member.copyWith(
      handlerEmail: member.handlerEmail ?? _emailForRa(member.handlerId),
    );
    final entry = AuditService.buildInlineEntry(
      action: 'team_member_added',
      fieldName: 'team',
      newValue: normalizedMember.toJson(),
    );

    final updates = <String, dynamic>{
      'team': FieldValue.arrayUnion([normalizedMember.toJson()]),
      'team_handler_ids': FieldValue.arrayUnion([normalizedMember.handlerId]),
      'team_emails': FieldValue.arrayUnion([
        normalizedMember.handlerEmail ??
            _emailForRa(normalizedMember.handlerId),
      ]),
      'team_size_max': current.teamSizeMax,
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    };
    if (normalizedMember.authUid?.isNotEmpty == true) {
      updates['team_auth_uids'] = FieldValue.arrayUnion([
        normalizedMember.authUid,
      ]);
      updates['team_auth_keys'] = FieldValue.arrayUnion([
        '${normalizedMember.handlerId}:${normalizedMember.authUid}',
      ]);
    }

    await docRef.update(updates);

    unawaited(
      AuditService.log(
        action: 'team_member_added',
        entityType: 'occurrence',
        entityId: occurrenceId,
        summary: 'Membro adicionado a equipe: ${normalizedMember.handlerId}',
        after: {
          'team_size': current.team.length + 1,
          'team_member': normalizedMember.toJson(),
        },
      ),
    );
  }

  Future<void> removeTeamMember({
    required String occurrenceId,
    required String handlerId,
  }) async {
    final docRef = _collection.doc(occurrenceId);
    final current = await getById(occurrenceId);
    if (current == null) {
      throw StateError('Ocorrencia nao encontrada');
    }
    if (current.status != OccurrenceStatus.inProgress) {
      throw StateError(
        'So e possivel remover membros em ocorrencias em andamento',
      );
    }

    OccurrenceTeamMember? member;
    for (final teamMember in current.team) {
      if (teamMember.handlerId == handlerId) {
        member = teamMember;
        break;
      }
    }
    if (member == null) {
      throw StateError('Membro nao encontrado na equipe');
    }
    if (member.role == TeamRole.titular) {
      throw StateError('O titular da ocorrencia nao pode ser removido');
    }

    final updatedTeam = current.team
        .where((teamMember) => teamMember.handlerId != handlerId)
        .toList();
    final updatedOccurrence = current.copyWith(team: updatedTeam);
    final entry = AuditService.buildInlineEntry(
      action: 'team_member_removed',
      fieldName: 'team',
      oldValue: member.toJson(),
    );

    await docRef.update({
      'team': updatedTeam.map((teamMember) => teamMember.toJson()).toList(),
      'team_handler_ids': updatedOccurrence.teamHandlerIds,
      'team_emails': updatedOccurrence.teamEmails,
      'team_auth_keys': updatedOccurrence.teamAuthKeys,
      'team_size_max': current.teamSizeMax,
      'team_auth_uids': updatedTeam
          .map((teamMember) => teamMember.authUid)
          .whereType<String>()
          .where((uid) => uid.isNotEmpty)
          .toList(),
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    });

    unawaited(
      AuditService.log(
        action: 'team_member_removed',
        entityType: 'occurrence',
        entityId: occurrenceId,
        summary: 'Membro removido da equipe: $handlerId',
        before: {'team_member': member.toJson()},
      ),
    );
  }

  /// Frente C - transicao de estado:
  /// in_progress -> awaiting_signatures: trava a edicao, cria assinaturas
  /// pendentes para os integrantes e define o prazo padrao de 48h.
  /// awaiting_signatures -> in_progress: `revertToDraft` cancela o pedido.
  /// awaiting_signatures -> finalized/finalized_with_pending: feito pela
  /// camada de finalizacao, com hash de integridade.
  Future<void> closeForSignatures({
    String? id,
    String? occurrenceId,
    DateTime? deadline,
    Duration? signatureDeadline,
    String? finalReport,
    List<OccurrenceResult>? results,
    Map<String, dynamic>? details,
    List<String> finalizationPhotos = const [],
    List<String> finalizationPhotoHashes = const [],
  }) async {
    final resolvedId = occurrenceId ?? id;
    if (resolvedId == null || resolvedId.isEmpty) {
      throw ArgumentError('Informe o ID da ocorrencia');
    }

    final current = await getById(resolvedId);
    if (current == null) {
      throw StateError('Ocorrencia nao encontrada');
    }
    if (current.status != OccurrenceStatus.inProgress &&
        current.status != OccurrenceStatus.finalizing) {
      throw StateError(
        'So e possivel fechar ocorrencias em andamento ou finalizacao para assinaturas',
      );
    }

    final coSigners = current.team
        .where((member) => member.role != TeamRole.titular)
        .where((member) => _canRequestSignatureFor(current, member.handlerId))
        .toList();

    // Sem coassinantes elegíveis: selar diretamente sem fluxo de assinaturas.
    // A regra de negócio permite finalizar mesmo sem coassinantes (ex: condutor
    // solo ou participações não confirmadas).
    if (coSigners.isEmpty) {
      final draftPayload = _finalizationPayloadFromDraft(
        current.finalizationDraft,
      );
      final resolvedFinalReport =
          _nonEmpty(finalReport) ??
          _nonEmpty(current.finalReport) ??
          _nonEmpty(draftPayload.finalReport);
      if (resolvedFinalReport == null) {
        throw StateError(
          'Finalize o relato antes de fechar a ocorrencia',
        );
      }
      final resolvedResults = results ?? current.results;
      final finalResults = resolvedResults.isNotEmpty
          ? resolvedResults
          : draftPayload.results;
      final resolvedDetails =
          details ?? current.details ?? draftPayload.details;
      final resolvedPhotos = finalizationPhotos.isNotEmpty
          ? finalizationPhotos
          : current.finalizationPhotos;
      final resolvedPhotoHashes = finalizationPhotoHashes.isNotEmpty
          ? finalizationPhotoHashes
          : current.finalizationPhotoHashes;

      await OccurrenceTransitionService().sealOccurrenceV4(
        occurrenceId: resolvedId,
        finalReport: resolvedFinalReport,
        results: finalResults,
        details: resolvedDetails,
        finalizationPhotos: resolvedPhotos,
        finalizationPhotoHashes: resolvedPhotoHashes,
      );

      unawaited(
        AuditService.log(
          action: 'finalized_no_cosigners',
          entityType: 'occurrence',
          entityId: resolvedId,
          summary: 'Ocorrencia finalizada diretamente (sem coassinantes elegiveis)',
          after: {
            'status': 'finalized',
            'has_final_report': true,
            'team_size': current.team.length,
          },
        ),
      );
      return;
    }

    final draftPayload = _finalizationPayloadFromDraft(
      current.finalizationDraft,
    );
    final resolvedFinalReport =
        _nonEmpty(finalReport) ??
        _nonEmpty(current.finalReport) ??
        _nonEmpty(draftPayload.finalReport);
    if (resolvedFinalReport == null) {
      throw StateError(
        'Finalize o relato antes de fechar a ocorrencia para assinaturas',
      );
    }
    final resolvedResults = results ?? current.results;
    final finalResults = resolvedResults.isNotEmpty
        ? resolvedResults
        : draftPayload.results;
    final resolvedDetails = details ?? current.details ?? draftPayload.details;
    final resolvedPhotos = finalizationPhotos.isNotEmpty
        ? finalizationPhotos
        : current.finalizationPhotos;
    final resolvedPhotoHashes = finalizationPhotoHashes.isNotEmpty
        ? finalizationPhotoHashes
        : current.finalizationPhotoHashes;
    final resolvedDeadline =
        deadline ??
        DateTime.now().add(signatureDeadline ?? const Duration(hours: 48));
    final resolvedSignatureDeadline =
        signatureDeadline ?? resolvedDeadline.difference(DateTime.now());

    final signatureRound = current.signatureRound <= 0
        ? 1
        : current.signatureRound;
    await OccurrenceTransitionService().closeForSignatures(
      occurrenceId: resolvedId,
      finalReport: resolvedFinalReport,
      results: finalResults,
      details: resolvedDetails,
      finalizationPhotos: resolvedPhotos,
      finalizationPhotoHashes: resolvedPhotoHashes,
      signatureDeadline: resolvedSignatureDeadline.isNegative
          ? const Duration(hours: 48)
          : resolvedSignatureDeadline,
    );

    unawaited(
      AuditService.log(
        action: 'closed_for_signatures',
        entityType: 'occurrence',
        entityId: resolvedId,
        summary: 'Ocorrencia fechada para assinaturas',
        after: {
          'status': OccurrenceStatus.awaitingSignatures.toMap(),
          'signature_deadline': resolvedDeadline.toIso8601String(),
          'signature_round': signatureRound,
          'has_final_report': true,
          'pending_signatures': coSigners.map((m) => m.handlerId).toList(),
        },
      ),
    );
  }

  Future<void> addSignature({
    required String occurrenceId,
    required OccurrenceSignature signature,
  }) async {
    final current = await getById(occurrenceId);
    if (current == null) {
      throw StateError('Ocorrencia nao encontrada');
    }
    if (current.status != OccurrenceStatus.awaitingSignatures) {
      throw StateError(
        'So e possivel assinar ocorrencias aguardando assinaturas',
      );
    }
    OccurrenceTeamMember? signingMember;
    for (final member in current.team) {
      if (member.handlerId == signature.handlerId) {
        signingMember = member;
        break;
      }
    }
    if (signingMember == null) {
      throw StateError('Usuario nao esta na equipe da ocorrencia');
    }
    if (signingMember.role == TeamRole.titular) {
      throw StateError('O titular nao assina como integrante da equipe');
    }
    if (!_canRequestSignatureFor(current, signingMember.handlerId)) {
      throw StateError('Integrante sem participacao ativa nao pode assinar');
    }

    final round = current.signatureRound <= 0 ? 1 : current.signatureRound;
    final roundedSignature = signature.copyWith(round: round);

    await OccurrenceTransitionService().signOccurrence(
      occurrenceId: occurrenceId,
      signature: roundedSignature,
    );

    unawaited(
      AuditService.log(
        action: 'signature_added',
        entityType: 'occurrence',
        entityId: occurrenceId,
        summary: 'Assinatura adicionada: ${signature.handlerId}',
        after: {
          'signature_status': roundedSignature.status.toMap(),
          'signature_method': roundedSignature.signatureMethod.toMap(),
          'signature_round': roundedSignature.round,
        },
      ),
    );
  }

  Stream<List<OccurrenceSignature>> watchSignatures(String occurrenceId) {
    return _signatures(occurrenceId)
        .orderBy('handler_id')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => OccurrenceSignature.fromJson(doc.data()))
              .toList(),
        );
  }

  Future<List<OccurrenceSignature>> getSignatures(String occurrenceId) async {
    final snapshot = await _signatures(
      occurrenceId,
    ).orderBy('handler_id').get();
    return snapshot.docs
        .map((doc) => OccurrenceSignature.fromJson(doc.data()))
        .toList();
  }

  Future<bool> areAllSignaturesCollected(String occurrenceId) async {
    final occurrence = await getById(occurrenceId);
    if (occurrence == null ||
        occurrence.status != OccurrenceStatus.awaitingSignatures) {
      return false;
    }

    final coSigners = occurrence.team
        .where((member) => member.role != TeamRole.titular)
        .where(
          (member) => _canRequestSignatureFor(occurrence, member.handlerId),
        )
        .map((member) => member.handlerId)
        .toSet();
    if (coSigners.isEmpty) return false;

    final signatures = await getSignatures(occurrenceId);
    final round = occurrence.signatureRound <= 0
        ? 1
        : occurrence.signatureRound;
    final signed = signatures
        .where(
          (signature) =>
              signature.status == SignatureStatus.signed &&
              signature.round == round &&
              coSigners.contains(signature.handlerId),
        )
        .map((signature) => signature.handlerId)
        .toSet();

    return signed.length >= coSigners.length;
  }

  Future<void> revertToDraft({required String occurrenceId}) async {
    await OccurrenceTransitionService().requestCorrection(
      occurrenceId: occurrenceId,
      reason: 'Reabertura para correcao antes do selo',
    );
    unawaited(
      AuditService.log(
        action: 'reverted_to_draft',
        entityType: 'occurrence',
        entityId: occurrenceId,
        summary: 'Ocorrencia revertida para rascunho',
      ),
    );
    return;
  }

  Future<void> revertToDraftLocallyForLegacy({
    required String occurrenceId,
  }) async {
    final occurrence = await getById(occurrenceId);
    if (occurrence == null) {
      throw StateError('Ocorrencia nao encontrada');
    }
    if (occurrence.status != OccurrenceStatus.awaitingSignatures) {
      throw StateError(
        'So e possivel reverter ocorrencias aguardando assinaturas',
      );
    }

    final entry = AuditService.buildInlineEntry(action: 'reverted_to_draft');
    final signaturesSnapshot = await _signatures(occurrenceId).get();
    final batch = _firestore.batch();
    final currentRound = occurrence.signatureRound <= 0
        ? 1
        : occurrence.signatureRound;
    final correctionRef = _collection
        .doc(occurrenceId)
        .collection('correction_requests')
        .doc();
    batch.update(_collection.doc(occurrenceId), {
      'status': OccurrenceStatus.inProgress.toMap(),
      'signature_request_at': null,
      'signature_deadline': null,
      'signature_round': currentRound + 1,
      'signed_handler_ids': [],
      'signed_emails': [],
      'signed_auth_uids': [],
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    });
    batch.set(correctionRef, {
      'id': correctionRef.id,
      'round': currentRound,
      'requested_at': FieldValue.serverTimestamp(),
      'requested_by': entry['by_ra'] ?? entry['performed_by'],
      'reason': 'Reabertura para correcao antes do selo',
      'status': 'open',
    });
    for (final doc in signaturesSnapshot.docs) {
      final signature = OccurrenceSignature.fromJson(doc.data());
      if (signature.round != currentRound ||
          signature.status == SignatureStatus.obsolete) {
        continue;
      }
      batch.set(doc.reference, {
        'status': SignatureStatus.obsolete.toMap(),
        'invalidated_at': FieldValue.serverTimestamp(),
        'invalidated_by': entry['by_ra'] ?? entry['performed_by'],
        'invalidation_reason': 'Reabertura para correcao antes do selo',
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();

    unawaited(
      AuditService.log(
        action: 'reverted_to_draft',
        entityType: 'occurrence',
        entityId: occurrenceId,
        summary: 'Ocorrencia revertida para rascunho',
      ),
    );
  }

  Future<void> updateDeadline({
    required String occurrenceId,
    required DateTime newDeadline,
  }) async {
    final occurrence = await getById(occurrenceId);
    if (occurrence == null) {
      throw StateError('Ocorrencia nao encontrada');
    }
    if (occurrence.status != OccurrenceStatus.awaitingSignatures) {
      throw StateError(
        'So e possivel alterar prazo de ocorrencia aguardando assinaturas',
      );
    }

    final entry = AuditService.buildInlineEntry(
      action: 'signature_deadline_updated',
      fieldName: 'signature_deadline',
      oldValue: occurrence.signatureDeadline?.toIso8601String(),
      newValue: newDeadline.toIso8601String(),
    );

    await _collection.doc(occurrenceId).update({
      'signature_deadline': Timestamp.fromDate(newDeadline),
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    });
  }

  Future<Occurrence?> getById(String id) async {
    final snap = await _collection.doc(id).get();
    if (!snap.exists) return null;

    final occ = Occurrence.fromMap(snap.data()!, id);
    if (occ.isDeleted) return null;
    return occ;
  }

  Stream<List<Occurrence>> watchByDog(String dogId) {
    return _collection.where('dog_id', isEqualTo: dogId).snapshots().map((
      snap,
    ) {
      final occurrences =
          snap.docs
              .map((doc) => Occurrence.fromMap(doc.data(), doc.id))
              .where((occ) => !occ.isDeleted)
              .toList()
            ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return occurrences;
    });
  }

  Stream<Occurrence?> watchOpen(String dogId) {
    return _collection.where('dog_id', isEqualTo: dogId).snapshots().map((
      snap,
    ) {
      final open =
          snap.docs
              .map((doc) => Occurrence.fromMap(doc.data(), doc.id))
              .where((occ) => !occ.isDeleted && occ.status.isOpen)
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (open.isEmpty) return null;
      return open.first;
    });
  }

  Future<Occurrence?> findOpen(String dogId) async {
    final snap = await _collection.where('dog_id', isEqualTo: dogId).get();
    final open =
        snap.docs
            .map((doc) => Occurrence.fromMap(doc.data(), doc.id))
            .where((occ) => !occ.isDeleted && occ.status.isOpen)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (open.isEmpty) return null;
    return open.first;
  }

  Future<List<Occurrence>> getExpiredOccurrences(DateTime now) async {
    final snapshot = await _collection
        .where('status', isEqualTo: OccurrenceStatus.awaitingSignatures.toMap())
        .where(
          'signature_deadline',
          isLessThanOrEqualTo: Timestamp.fromDate(now),
        )
        .get();

    return snapshot.docs
        .map((doc) => Occurrence.fromMap(doc.data(), doc.id))
        .where((occurrence) => !occurrence.isDeleted)
        .toList();
  }

  Future<List<OccurrenceNature>> getOccurrenceNatures() async {
    try {
      final configured = await _getOccurrenceNaturesFrom('occurrence_types');
      if (configured.isNotEmpty) return configured;
    } catch (_) {
      // Mantem a tela funcional se a colecao nova ainda nao estiver populada.
    }

    try {
      return await _getOccurrenceNaturesFrom('occurrence_natures');
    } catch (_) {
      return OccurrenceNatureSeed.items;
    }
  }

  Future<List<OccurrenceNature>> _getOccurrenceNaturesFrom(
    String collectionName,
  ) async {
    final snapshot = await _firestore
        .collection(collectionName)
        .where('active', isEqualTo: true)
        .get();

    final natures = snapshot.docs.map((doc) {
      final data = doc.data();
      return OccurrenceNature.fromJson({
        ...data,
        'code': data['code'] ?? data['id'] ?? doc.id,
      });
    }).toList();

    natures.sort((a, b) {
      final byGroup = a.group.compareTo(b.group);
      if (byGroup != 0) return byGroup;
      return a.name.compareTo(b.name);
    });
    return natures;
  }

  static _DraftFinalizationPayload _finalizationPayloadFromDraft(
    Map<String, dynamic>? draft,
  ) {
    if (draft == null || draft.isEmpty) {
      return const _DraftFinalizationPayload();
    }

    final rawResults = draft['results'];
    final parsedResults = rawResults is List
        ? rawResults
              .map((value) => value?.toString())
              .whereType<String>()
              .map(OccurrenceResult.fromMap)
              .toList()
        : const <OccurrenceResult>[];

    final rawDetails = draft['details'];
    return _DraftFinalizationPayload(
      finalReport: draft['final_report']?.toString(),
      results: parsedResults,
      details: rawDetails is Map
          ? rawDetails.map((key, value) => MapEntry(key.toString(), value))
          : null,
    );
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static String _emailForRa(String ra) {
    return '${ra.trim().toLowerCase()}@gcm.com.br';
  }

  static dynamic _serializeForAudit(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    return value;
  }

  static bool _isLockedForEditing(Map<String, dynamic> data) {
    final status = data['status']?.toString();
    return status == OccurrenceStatus.awaitingSignatures.toMap() ||
        status == OccurrenceStatus.finalized.toMap() ||
        status == OccurrenceStatus.finalizedWithPending.toMap();
  }

  static bool _isAllowedLockedOccurrenceUpdate(Map<String, dynamic> updates) {
    const allowed = {
      'pdf_export_url',
      'pdf_generated_at',
      'pdf_access_log',
      'audit_trail',
      'updated_at',
    };
    return updates.keys.every(allowed.contains);
  }

  static bool _canRequestSignatureFor(Occurrence occurrence, String handlerId) {
    final accepted = occurrence.acceptedHandlerIds;
    if (accepted.isEmpty && occurrence.participationRevision == 0) {
      return true;
    }
    return accepted.contains(handlerId);
  }
}

class _DraftFinalizationPayload {
  final String? finalReport;
  final List<OccurrenceResult> results;
  final Map<String, dynamic>? details;

  const _DraftFinalizationPayload({
    this.finalReport,
    this.results = const [],
    this.details,
  });
}
