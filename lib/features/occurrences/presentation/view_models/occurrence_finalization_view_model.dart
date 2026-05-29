import 'package:flutter/foundation.dart';

import 'package:canil_gcm/core/domain/occurrence_signature.dart';
import 'package:canil_gcm/core/services/occurrence_finalization_service.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_team_view_model.dart';

class OccurrenceFinalizationViewModel extends OccurrenceTeamViewModel {
  OccurrenceFinalizationViewModel({
    required super.occurrenceRepository,
    required super.signatureRepository,
    required super.notificationService,
    OccurrenceFinalizationService? finalizationService,
  }) : _occurrenceRepository = occurrenceRepository,
       _finalizationService =
           finalizationService ?? OccurrenceFinalizationService();

  final OccurrenceRepository _occurrenceRepository;
  final OccurrenceFinalizationService _finalizationService;

  bool _isCheckingDeadline = false;
  bool _isAutoFinalizing = false;
  DateTime? _deadlineWarningShownAt;

  bool get isCheckingDeadline => _isCheckingDeadline;
  bool get isAutoFinalizing => _isAutoFinalizing;

  @override
  bool get shouldShowDeadlineWarning {
    final current = occurrence;
    if (current == null ||
        current.status != OccurrenceStatus.awaitingSignatures) {
      return false;
    }

    final deadline = current.signatureDeadline;
    if (deadline == null) return false;

    final now = DateTime.now();
    final warningTime = deadline.subtract(const Duration(hours: 24));
    return now.isAfter(warningTime) &&
        now.isBefore(deadline) &&
        (_deadlineWarningShownAt == null ||
            now.difference(_deadlineWarningShownAt!).inHours >= 24);
  }

  bool get isDeadlineExpired {
    final current = occurrence;
    final deadline = current?.signatureDeadline;
    return current?.status == OccurrenceStatus.awaitingSignatures &&
        deadline != null &&
        DateTime.now().isAfter(deadline);
  }

  @override
  Future<void> initialize({required String occurrenceId}) async {
    await super.initialize(occurrenceId: occurrenceId);

    if (occurrence?.status == OccurrenceStatus.awaitingSignatures) {
      await _checkDeadline();
      await _checkAutoFinalization();
    }
  }

  Future<void> _checkDeadline() async {
    final current = occurrence;
    if (current == null ||
        current.status != OccurrenceStatus.awaitingSignatures) {
      return;
    }

    _isCheckingDeadline = true;
    notifyListeners();

    try {
      final deadline = current.signatureDeadline;
      if (deadline != null && DateTime.now().isAfter(deadline)) {
        _deadlineWarningShownAt = DateTime.now();
        await _finalizationService.notifyDeadlineExpired(current);
      }
    } catch (error) {
      debugPrint(
        '[OccurrenceFinalizationViewModel] Erro ao verificar prazo: $error',
      );
    } finally {
      _isCheckingDeadline = false;
      notifyListeners();
    }
  }

  Future<void> _checkAutoFinalization() async {
    final current = occurrence;
    if (current == null ||
        current.status != OccurrenceStatus.awaitingSignatures) {
      return;
    }

    _isAutoFinalizing = true;
    notifyListeners();

    try {
      final finalized = await _finalizationService.checkForAutoFinalization(
        current.id,
      );
      if (finalized) {
        await super.initialize(occurrenceId: current.id);
      }
    } catch (error) {
      debugPrint(
        '[OccurrenceFinalizationViewModel] Erro ao verificar finalizacao automatica: $error',
      );
    } finally {
      _isAutoFinalizing = false;
      notifyListeners();
    }
  }

  Future<void> extendDeadline({
    required Duration extension,
    required void Function(String) onSuccess,
    required void Function(String) onError,
  }) async {
    final current = occurrence;
    if (current == null ||
        current.status != OccurrenceStatus.awaitingSignatures) {
      onError('Nao e possivel estender o prazo desta ocorrencia');
      return;
    }

    try {
      final newDeadline = DateTime.now().add(extension);
      await _occurrenceRepository.updateDeadline(
        occurrenceId: current.id,
        newDeadline: newDeadline,
      );
      await initialize(occurrenceId: current.id);
      onSuccess('Prazo estendido com sucesso');
    } catch (error) {
      onError(error.toString());
    }
  }

  Future<void> finalizeWithPending({
    required void Function(String) onSuccess,
    required void Function(String) onError,
  }) async {
    final current = occurrence;
    if (current == null ||
        current.status != OccurrenceStatus.awaitingSignatures) {
      onError('Nao e possivel finalizar esta ocorrencia com pendencias');
      return;
    }

    try {
      await _finalizationService.finalizeWithPending(current.id);
      await super.initialize(occurrenceId: current.id);
      onSuccess('Ocorrencia finalizada com pendencias');
    } catch (error) {
      onError(error.toString());
    }
  }

  @override
  Future<void> closeForSignatures({
    required Duration signatureDeadline,
    required void Function(String) onSuccess,
    required void Function(String) onError,
  }) async {
    const minDeadline = Duration(hours: 2);
    if (signatureDeadline < minDeadline) {
      onError('O prazo minimo de assinatura e de 2 horas');
      return;
    }

    await super.closeForSignatures(
      signatureDeadline: signatureDeadline,
      onSuccess: onSuccess,
      onError: onError,
    );
  }

  @override
  Future<void> addSignature({
    required OccurrenceSignature signature,
    required void Function(String) onSuccess,
    required void Function(String) onError,
  }) async {
    await super.addSignature(
      signature: signature,
      onSuccess: (message) async {
        if (areAllSignaturesCollected) {
          await _checkAutoFinalization();
        }
        onSuccess(message);
      },
      onError: onError,
    );
  }
}
