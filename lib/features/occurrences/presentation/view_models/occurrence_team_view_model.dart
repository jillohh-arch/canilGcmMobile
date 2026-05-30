import 'package:flutter/foundation.dart';

import 'package:canil_gcm/core/domain/notification_item.dart';
import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

class OccurrenceTeamViewModel extends ChangeNotifier {
  final OccurrenceRepository _occurrenceRepository;
  final SignatureRepository _signatureRepository;
  final NotificationService _notificationService;

  Occurrence? _occurrence;
  List<OccurrenceTeamMember> _team = [];
  List<OccurrenceSignature> _signatures = [];
  bool _isLoading = false;
  String? _error;

  OccurrenceTeamViewModel({
    required OccurrenceRepository occurrenceRepository,
    required SignatureRepository signatureRepository,
    required NotificationService notificationService,
  }) : _occurrenceRepository = occurrenceRepository,
       _signatureRepository = signatureRepository,
       _notificationService = notificationService;

  Occurrence? get occurrence => _occurrence;
  List<OccurrenceTeamMember> get team => List.unmodifiable(_team);
  List<OccurrenceSignature> get signatures => List.unmodifiable(_signatures);
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool get canAddTeamMember {
    // Parte 11: a equipe operacional e derivada da guarnicao da viatura.
    // O autocomplete manual fica fora do fluxo de ocorrencia.
    return false;
  }

  bool get canAddTeamMembers => canAddTeamMember;

  bool get canRemoveMembers => false;

  bool get canCloseForSignatures =>
      _occurrence?.status == OccurrenceStatus.inProgress &&
      _team.any(
        (member) =>
            member.role != TeamRole.titular &&
            _isParticipationActive(_occurrence!, member.handlerId),
      );

  bool get canSign =>
      _occurrence?.status == OccurrenceStatus.awaitingSignatures;

  bool get canRevertToDraft =>
      _occurrence?.status == OccurrenceStatus.awaitingSignatures;

  bool get shouldShowDeadlineWarning {
    final deadline = _occurrence?.signatureDeadline;
    if (_occurrence?.status != OccurrenceStatus.awaitingSignatures ||
        deadline == null) {
      return false;
    }
    final now = DateTime.now();
    final warningTime = deadline.subtract(const Duration(hours: 24));
    return now.isAfter(warningTime) && now.isBefore(deadline);
  }

  bool get areAllSignaturesCollected {
    final occurrence = _occurrence;
    if (occurrence == null ||
        occurrence.status != OccurrenceStatus.awaitingSignatures) {
      return false;
    }

    final coSignerIds = _team
        .where(
          (member) =>
              member.role != TeamRole.titular &&
              _isParticipationActive(occurrence, member.handlerId),
        )
        .map((member) => member.handlerId)
        .toSet();
    if (coSignerIds.isEmpty) return false;

    final signedIds = _signatures
        .where(
          (signature) =>
              signature.status == SignatureStatus.signed &&
              coSignerIds.contains(signature.handlerId),
        )
        .map((signature) => signature.handlerId)
        .toSet();

    return signedIds.length >= coSignerIds.length;
  }

  Future<void> initialize({required String occurrenceId}) async {
    _setLoading(true);
    _error = null;

    try {
      _occurrence = await _occurrenceRepository.getById(occurrenceId);
      final occurrence = _occurrence;
      if (occurrence == null) {
        _error = 'Ocorrencia nao encontrada';
        return;
      }

      _team = List<OccurrenceTeamMember>.from(occurrence.team);
      _signatures = await _signatureRepository.getSignatures(occurrenceId);
    } catch (error) {
      _error = error.toString();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> addTeamMember({
    required String handlerId,
    required String addedBy,
    String? displayName,
    String? handlerEmail,
    String? authUid,
    required void Function(String) onSuccess,
    required void Function(String) onError,
  }) async {
    final occurrence = _occurrence;
    if (occurrence == null || !canAddTeamMember) {
      onError('Nao e possivel adicionar membros a equipe no momento');
      return;
    }

    if (_team.any((member) => member.handlerId == handlerId)) {
      onError('Este membro ja esta na equipe');
      return;
    }

    try {
      final newMember = OccurrenceTeamMember(
        handlerId: handlerId,
        authUid: authUid,
        handlerEmail:
            handlerEmail ?? HandlerIdentityService.emailFromRa(handlerId),
        displayName: displayName,
        role: TeamRole.integrante,
        addedAt: DateTime.now(),
        addedBy: addedBy,
      );

      await _occurrenceRepository.addTeamMember(
        occurrenceId: occurrence.id,
        member: newMember,
      );

      _team = [..._team, newMember];
      _occurrence = occurrence.copyWith(team: _team);
      notifyListeners();
      onSuccess('Membro adicionado com sucesso');
    } catch (error) {
      onError(error.toString());
    }
  }

  Future<void> removeTeamMember({
    required String handlerId,
    required void Function(String) onSuccess,
    required void Function(String) onError,
  }) async {
    final occurrence = _occurrence;
    if (occurrence == null ||
        occurrence.status != OccurrenceStatus.inProgress) {
      onError('So e possivel remover membros em ocorrencias em andamento');
      return;
    }

    try {
      await _occurrenceRepository.removeTeamMember(
        occurrenceId: occurrence.id,
        handlerId: handlerId,
      );

      _team = _team.where((member) => member.handlerId != handlerId).toList();
      _occurrence = occurrence.copyWith(team: _team);
      notifyListeners();
      onSuccess('Membro removido com sucesso');
    } catch (error) {
      onError(error.toString());
    }
  }

  Future<void> closeForSignatures({
    required Duration signatureDeadline,
    required void Function(String) onSuccess,
    required void Function(String) onError,
  }) async {
    final occurrence = _occurrence;
    if (occurrence == null || !canCloseForSignatures) {
      onError('Nao e possivel fechar esta ocorrencia para assinaturas');
      return;
    }

    try {
      await _occurrenceRepository.closeForSignatures(
        occurrenceId: occurrence.id,
        signatureDeadline: signatureDeadline,
      );

      final coSigners = _team
          .where(
            (member) =>
                member.role != TeamRole.titular &&
                _isParticipationActive(occurrence, member.handlerId),
          )
          .toList();
      for (final member in coSigners) {
        await _notificationService.createNotification(
          userId: member.handlerId,
          type: NotificationType.signatureRequested,
          occurrenceId: occurrence.id,
          occurrenceTitle: occurrence.typeName,
          additionalData: member.handlerId,
          targetScreen: 'occurrence_review',
          actionRequired: true,
        );
      }

      _occurrence = await _occurrenceRepository.getById(occurrence.id);
      _signatures = await _signatureRepository.getSignatures(occurrence.id);
      notifyListeners();
      onSuccess('Ocorrencia fechada para assinaturas');
    } catch (error) {
      onError(error.toString());
    }
  }

  Future<void> addSignature({
    required OccurrenceSignature signature,
    required void Function(String) onSuccess,
    required void Function(String) onError,
  }) async {
    final occurrence = _occurrence;
    if (occurrence == null || !canSign) {
      onError('Nao e possivel assinar esta ocorrencia no momento');
      return;
    }

    try {
      await _occurrenceRepository.addSignature(
        occurrenceId: occurrence.id,
        signature: signature.copyWith(
          round: occurrence.signatureRound <= 0 ? 1 : occurrence.signatureRound,
        ),
      );

      _signatures = await _signatureRepository.getSignatures(occurrence.id);

      if (areAllSignaturesCollected) {
        final primaryRa = occurrence.primaryHandlerRa;
        if (primaryRa?.isNotEmpty == true) {
          await _notificationService.createNotification(
            userId: primaryRa!,
            type: NotificationType.signatureCompleted,
            occurrenceId: occurrence.id,
            occurrenceTitle: occurrence.typeName,
            additionalData: signature.handlerId,
          );
        }
      }

      notifyListeners();
      onSuccess('Assinatura adicionada com sucesso');
    } catch (error) {
      onError(error.toString());
    }
  }

  Future<void> markSignatureExpired({
    required String handlerId,
    String? reason,
    required void Function(String) onSuccess,
    required void Function(String) onError,
  }) async {
    final occurrence = _occurrence;
    if (occurrence == null ||
        occurrence.status != OccurrenceStatus.awaitingSignatures) {
      onError(
        'So e possivel marcar assinaturas como expiradas em ocorrencias aguardando assinaturas',
      );
      return;
    }

    try {
      await _signatureRepository.markSignatureExpired(
        occurrenceId: occurrence.id,
        handlerId: handlerId,
        reason: reason,
      );

      _signatures = await _signatureRepository.getSignatures(occurrence.id);
      notifyListeners();
      onSuccess('Assinatura marcada como expirada');
    } catch (error) {
      onError(error.toString());
    }
  }

  Future<void> revertToDraft({
    required void Function(String) onSuccess,
    required void Function(String) onError,
  }) async {
    final occurrence = _occurrence;
    if (occurrence == null || !canRevertToDraft) {
      onError('Nao e possivel reverter esta ocorrencia para rascunho');
      return;
    }

    try {
      await _occurrenceRepository.revertToDraft(occurrenceId: occurrence.id);
      _occurrence = await _occurrenceRepository.getById(occurrence.id);
      _signatures = await _signatureRepository.getSignatures(occurrence.id);
      notifyListeners();
      onSuccess('Ocorrencia revertida para rascunho');
    } catch (error) {
      onError(error.toString());
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  bool _isParticipationActive(Occurrence occurrence, String handlerId) {
    final id = handlerId.trim();
    if (id.isEmpty || occurrence.declinedHandlerIds.contains(id)) {
      return false;
    }
    if (occurrence.acceptedHandlerIds.isEmpty &&
        occurrence.participationRevision == 0) {
      return true;
    }
    return occurrence.acceptedHandlerIds.contains(id);
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
