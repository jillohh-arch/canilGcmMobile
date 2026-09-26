import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:canil_gcm/features/health/domain/clinical_consultation_gateway.dart';
import 'package:canil_gcm/features/health/domain/dose_administration.dart';
import 'package:canil_gcm/features/health/domain/treatment_protocol.dart';
import 'package:canil_gcm/features/health/domain/treatment_protocol_command.dart';
import 'package:canil_gcm/features/health/domain/treatment_protocol_gateway.dart';
import 'treatment_protocol_callable_names.dart';

typedef TreatmentCallableInvoker = Future<Map<String, dynamic>> Function(
  String functionName,
  Map<String, dynamic> data,
);

final class FirebaseFunctionsTreatmentProtocolGateway
    implements TreatmentProtocolGateway {
  FirebaseFunctionsTreatmentProtocolGateway({
    FirebaseFirestore? firestore,
    TreatmentCallableInvoker? invoker,
  })  : _firestore = firestore,
        _invokerOverride = invoker;

  final FirebaseFirestore? _firestore;
  final TreatmentCallableInvoker? _invokerOverride;
  TreatmentCallableInvoker? _cachedInvoker;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  TreatmentCallableInvoker get _invoke {
    return _cachedInvoker ??= _invokerOverride ?? _defaultInvoker;
  }

  Future<Map<String, dynamic>> _defaultInvoker(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    final functions = FirebaseFunctions.instanceFor(
      region: TreatmentProtocolCallableNames.region,
    );
    final callable = functions.httpsCallable(functionName);
    final result = await callable.call(data);
    final payload = result.data;
    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }
    throw FirebaseFunctionsException(
      code: 'internal',
      message: 'Resposta do callable em formato inesperado.',
    );
  }

  static const _usableStatuses = {
    'open',
    'under_investigation',
    'under_treatment',
    'monitoring',
  };

  @override
  Future<List<ClinicalCaseOption>> loadUsableCases(String dogId) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _db
          .collection('dogs')
          .doc(dogId)
          .collection('clinical_cases')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      snapshot = await _db
          .collection('dogs')
          .doc(dogId)
          .collection('clinical_cases')
          .get();
    }

    final options = <ClinicalCaseOption>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = (data['clinical_status'] as String?)?.trim();
      if (status == null || !_usableStatuses.contains(status)) continue;

      final revision = data['revision'];
      if (revision is! int) continue;

      options.add(
        ClinicalCaseOption(
          caseId: doc.id,
          title: (data['title'] as String?)?.trim().isNotEmpty == true
              ? (data['title'] as String).trim()
              : 'Caso clínico',
          statusWireName: status,
          revision: revision,
          openedAt: (data['opened_at'] as Timestamp?)?.toDate(),
        ),
      );
    }

    options.sort((a, b) {
      final aDate = a.openedAt;
      final bDate = b.openedAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });

    return options;
  }

  @override
  Future<List<TreatmentProtocol>> loadProtocols({
    required String dogId,
    String? caseId,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('dogs')
        .doc(dogId)
        .collection('treatment_protocols');

    if (caseId != null) {
      query = query.where('case_id', isEqualTo: caseId);
    }

    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await query
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      snapshot = await query.get();
    }

    return snapshot.docs
        .map((doc) => TreatmentProtocol.fromMap(doc.data(), documentId: doc.id))
        .toList();
  }

  @override
  Stream<List<TreatmentProtocol>> watchProtocols({
    required String dogId,
    String? caseId,
  }) {
    Query<Map<String, dynamic>> query = _db
        .collection('dogs')
        .doc(dogId)
        .collection('treatment_protocols');

    if (caseId != null) {
      query = query.where('case_id', isEqualTo: caseId);
    }

    return query.snapshots().map((snapshot) {
      final protocols = snapshot.docs
          .map((doc) =>
              TreatmentProtocol.fromMap(doc.data(), documentId: doc.id))
          .toList();

      protocols.sort((a, b) => b.startDate.compareTo(a.startDate));
      return protocols;
    });
  }

  @override
  Future<List<DoseAdministration>> loadProtocolDoses({
    required String dogId,
    required String protocolId,
  }) async {
    final query = _db
        .collection('dogs')
        .doc(dogId)
        .collection('treatment_protocols')
        .doc(protocolId)
        .collection('doses');

    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await query
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      snapshot = await query.get();
    }

    return snapshot.docs
        .map(
            (doc) => DoseAdministration.fromMap(doc.data(), documentId: doc.id))
        .toList();
  }

  @override
  Stream<List<DoseAdministration>> watchProtocolDoses({
    required String dogId,
    required String protocolId,
  }) {
    final query = _db
        .collection('dogs')
        .doc(dogId)
        .collection('treatment_protocols')
        .doc(protocolId)
        .collection('doses');

    return query.snapshots().map((snapshot) {
      final doses = snapshot.docs
          .map((doc) =>
              DoseAdministration.fromMap(doc.data(), documentId: doc.id))
          .toList();

      doses.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      return doses;
    });
  }

  @override
  Stream<List<Map<String, dynamic>>> watchProtocolSchedules({
    required String dogId,
    required String protocolId,
  }) {
    final query = _db
        .collection('dogs')
        .doc(dogId)
        .collection('health_schedule')
        .where('source_id', isEqualTo: protocolId);

    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['schedule_id'] = doc.id;
        return data;
      }).toList();
    });
  }

  @override
  Future<TreatmentProtocolResult> createProtocol(
    CreateTreatmentProtocolCommand command,
  ) async {
    try {
      final payload = <String, dynamic>{
        'dogId': command.dogId,
        'caseId': command.caseId,
        'medicationName': command.medicationName,
        'dose': {
          'value': command.dose.value,
          'unit': command.dose.unit.wireName,
          'per_kg': command.dose.perKg,
          'route': command.dose.route.wireName,
        },
        'schedule': {
          'type': command.schedule.type.wireName,
          if (command.schedule.intervalMinutes != null)
            'interval_minutes': command.schedule.intervalMinutes,
          'times_of_day': command.schedule.timesOfDay,
          'timezone': command.schedule.timezone,
          'tolerance_minutes': command.schedule.toleranceMinutes,
        },
        'startDate': command.startDate.toUtc().toIso8601String(),
        if (command.endDate != null)
          'endDate': command.endDate!.toUtc().toIso8601String(),
        if (command.durationDays != null)
          'durationDays': command.durationDays,
        'professional': {
          'name': command.professional.name,
          'registration_type': command.professional.registrationType.wireName,
          'registration_number': command.professional.registrationNumber,
          'clinic': command.professional.clinic,
          if (command.professional.specialty != null)
            'specialty': command.professional.specialty,
        },
        'sourceDocument': {
          'health_document_id': command.sourceDocument.healthDocumentId,
          if (command.sourceDocument.description != null)
            'description': command.sourceDocument.description,
        },
        if (command.instructions != null)
          'instructions': command.instructions,
        if (command.dosageDisplay != null)
          'dosageDisplay': command.dosageDisplay,
        if (command.frequencyDisplay != null)
          'frequencyDisplay': command.frequencyDisplay,
        'operationId': command.operationId,
      };

      final res = await _invoke(
        TreatmentProtocolCallableNames.createTreatmentProtocol,
        payload,
      );
      final protocolId = res['protocolId'] as String;
      final protocol = await _fetchProtocol(command.dogId, protocolId);
      return TreatmentProtocolSuccess(protocol);
    } catch (e) {
      return _mapError(e);
    }
  }

  @override
  Future<TreatmentProtocolResult> pauseProtocol(
    PauseTreatmentProtocolCommand command,
  ) async {
    try {
      final payload = <String, dynamic>{
        'dogId': command.dogId,
        'protocolId': command.protocolId,
        'pauseReason': command.pauseReason,
        'operationId': command.operationId,
      };

      await _invoke(
        TreatmentProtocolCallableNames.pauseTreatmentProtocol,
        payload,
      );
      final protocol = await _fetchProtocol(command.dogId, command.protocolId);
      return TreatmentProtocolSuccess(protocol);
    } catch (e) {
      return _mapError(e);
    }
  }

  @override
  Future<TreatmentProtocolResult> resumeProtocol(
    ResumeTreatmentProtocolCommand command,
  ) async {
    try {
      final payload = <String, dynamic>{
        'dogId': command.dogId,
        'protocolId': command.protocolId,
        'operationId': command.operationId,
      };

      await _invoke(
        TreatmentProtocolCallableNames.resumeTreatmentProtocol,
        payload,
      );
      final protocol = await _fetchProtocol(command.dogId, command.protocolId);
      return TreatmentProtocolSuccess(protocol);
    } catch (e) {
      return _mapError(e);
    }
  }

  @override
  Future<TreatmentProtocolResult> completeProtocol(
    CompleteTreatmentProtocolCommand command,
  ) async {
    try {
      final payload = <String, dynamic>{
        'dogId': command.dogId,
        'protocolId': command.protocolId,
        'operationId': command.operationId,
      };

      await _invoke(
        TreatmentProtocolCallableNames.completeTreatmentProtocol,
        payload,
      );
      final protocol = await _fetchProtocol(command.dogId, command.protocolId);
      return TreatmentProtocolSuccess(protocol);
    } catch (e) {
      return _mapError(e);
    }
  }

  @override
  Future<TreatmentProtocolResult> cancelProtocol(
    CancelTreatmentProtocolCommand command,
  ) async {
    try {
      final payload = <String, dynamic>{
        'dogId': command.dogId,
        'protocolId': command.protocolId,
        'cancelReason': command.cancelReason,
        'operationId': command.operationId,
      };

      await _invoke(
        TreatmentProtocolCallableNames.cancelTreatmentProtocol,
        payload,
      );
      final protocol = await _fetchProtocol(command.dogId, command.protocolId);
      return TreatmentProtocolSuccess(protocol);
    } catch (e) {
      return _mapError(e);
    }
  }

  @override
  Future<TreatmentProtocolResult> administerDose(
    AdministerDoseCommand command,
  ) async {
    try {
      final payload = <String, dynamic>{
        'dogId': command.dogId,
        'protocolId': command.protocolId,
        'plannedDoseId': command.plannedDoseId,
        if (command.scheduleItemId != null)
          'scheduleItemId': command.scheduleItemId,
        if (command.administeredAt != null)
          'administeredAt': command.administeredAt!.toUtc().toIso8601String(),
        if (command.observations != null)
          'observations': command.observations,
        if (command.sideEffects != null)
          'sideEffects': command.sideEffects,
        'operationId': command.operationId,
      };

      final res = await _invoke(
        TreatmentProtocolCallableNames.administerTreatmentDose,
        payload,
      );
      final doseId = res['doseId'] as String;
      final dose = await _fetchDose(command.dogId, command.protocolId, doseId);
      return DoseAdministrationSuccess(dose);
    } catch (e) {
      return _mapError(e);
    }
  }

  @override
  Future<TreatmentProtocolResult> skipDose(
    SkipDoseCommand command,
  ) async {
    try {
      final payload = <String, dynamic>{
        'dogId': command.dogId,
        'protocolId': command.protocolId,
        'plannedDoseId': command.plannedDoseId,
        'skipReason': command.skipReason,
        if (command.scheduleItemId != null)
          'scheduleItemId': command.scheduleItemId,
        if (command.observations != null)
          'observations': command.observations,
        'operationId': command.operationId,
      };

      final res = await _invoke(
        TreatmentProtocolCallableNames.skipTreatmentDose,
        payload,
      );
      final doseId = res['doseId'] as String;
      final dose = await _fetchDose(command.dogId, command.protocolId, doseId);
      return DoseAdministrationSuccess(dose);
    } catch (e) {
      return _mapError(e);
    }
  }

  Future<TreatmentProtocol> _fetchProtocol(
    String dogId,
    String protocolId,
  ) async {
    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await _db
          .collection('dogs')
          .doc(dogId)
          .collection('treatment_protocols')
          .doc(protocolId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      doc = await _db
          .collection('dogs')
          .doc(dogId)
          .collection('treatment_protocols')
          .doc(protocolId)
          .get();
    }
    if (!doc.exists || doc.data() == null) {
      throw Exception('Protocolo $protocolId não encontrado após mutação.');
    }
    return TreatmentProtocol.fromMap(doc.data()!, documentId: doc.id);
  }

  Future<DoseAdministration> _fetchDose(
    String dogId,
    String protocolId,
    String doseId,
  ) async {
    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await _db
          .collection('dogs')
          .doc(dogId)
          .collection('treatment_protocols')
          .doc(protocolId)
          .collection('doses')
          .doc(doseId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      doc = await _db
          .collection('dogs')
          .doc(dogId)
          .collection('treatment_protocols')
          .doc(protocolId)
          .collection('doses')
          .doc(doseId)
          .get();
    }
    if (!doc.exists || doc.data() == null) {
      throw Exception('Dose $doseId não encontrada após mutação.');
    }
    return DoseAdministration.fromMap(doc.data()!, documentId: doc.id);
  }

  TreatmentProtocolFailure _mapError(Object e) {
    if (e is FirebaseFunctionsException) {
      return TreatmentProtocolFailure(
        code: e.code,
        message: e.message ?? e.details?.toString() ?? 'Erro no servidor.',
        cause: e,
      );
    }
    return TreatmentProtocolFailure(
      code: 'unknown',
      message: e.toString(),
      cause: e,
    );
  }
}
