import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/core/services/storage_service.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_prescription.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_supplement.dart';

/// Service para gerenciar alimentação e prescrições nutricionais.
class NutritionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final StorageService _storage = StorageService();

  // ─── Feedings ─────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _feedingsCol(String dogId) =>
      _firestore.collection('dogs').doc(dogId).collection('feeding_events');

  CollectionReference<Map<String, dynamic>> _legacyFeedingsCol(String dogId) =>
      _firestore.collection('dogs').doc(dogId).collection('feedings');

  CollectionReference<Map<String, dynamic>> _supplementsCol(String dogId) =>
      _firestore
          .collection('dogs')
          .doc(dogId)
          .collection('nutrition_supplements');

  /// Stream de refeições do dia.
  Stream<List<Feeding>> watchTodayFeedings(String dogId) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _watchMergedFeedings(dogId, from: startOfDay, to: endOfDay);
  }

  /// Busca refeições por período.
  Future<List<Feeding>> getFeedings(
    String dogId, {
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    final feedings = await Future.wait([
      _getFeedingsFrom(_feedingsCol(dogId), from: from, to: to, limit: limit),
      _getFeedingsFrom(
        _legacyFeedingsCol(dogId),
        from: from,
        to: to,
        limit: limit,
      ),
    ]);
    final merged = _dedupeFeedings(feedings.expand((items) => items));
    return limit == null ? merged : merged.take(limit).toList();
  }

  /// Registra uma nova refeição.
  Future<String> addFeeding(String dogId, Feeding feeding) async {
    final docRef = _feedingsCol(dogId).doc();
    final entry = AuditService.buildInlineEntry(action: 'created');
    final data = {
      ...feeding.toJson(),
      'audit_trail': [entry],
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'created_by': feeding.fedBy,
    };
    await docRef.set(data);
    await _legacyFeedingsCol(dogId).doc(docRef.id).set(data);
    return docRef.id;
  }

  /// Faz upload da foto da balança e retorna a URL.
  Future<String?> uploadFeedingPhoto(String dogId, File photo) async {
    return _storage.uploadImage(photo, 'dogs/$dogId/feeding_photos');
  }

  /// Atualiza a URL da foto em um feeding existente.
  Future<void> updateFeedingPhoto(
    String dogId,
    String feedingId,
    String photoUrl,
  ) async {
    final primaryDoc = await _feedingsCol(dogId).doc(feedingId).get();
    final legacyDoc = primaryDoc.exists
        ? null
        : await _legacyFeedingsCol(dogId).doc(feedingId).get();
    final oldPhotoUrl =
        primaryDoc.data()?['photo_balance_url'] ??
        legacyDoc?.data()?['photo_balance_url'];
    final entry = AuditService.buildInlineEntry(
      action: 'updated',
      fieldName: 'photo_balance_url',
      oldValue: oldPhotoUrl,
      newValue: photoUrl,
    );
    final updates = {
      'photo_balance_url': photoUrl,
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    };
    await _feedingsCol(
      dogId,
    ).doc(feedingId).set(updates, SetOptions(merge: true));
    await _legacyFeedingsCol(
      dogId,
    ).doc(feedingId).set(updates, SetOptions(merge: true));
  }

  // ─── Prescriptions ────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _prescriptionsCol(String dogId) =>
      _firestore
          .collection('dogs')
          .doc(dogId)
          .collection('nutritional_prescriptions');

  CollectionReference<Map<String, dynamic>> _legacyPrescriptionsCol(
    String dogId,
  ) => _firestore
      .collection('dogs')
      .doc(dogId)
      .collection('nutrition_prescriptions');

  /// Busca a prescrição vigente.
  Future<NutritionPrescription?> getActivePrescription(String dogId) async {
    final now = DateTime.now();
    final snap = await _prescriptionsCol(dogId)
        .where('vigent_from', isLessThanOrEqualTo: Timestamp.fromDate(now))
        .orderBy('vigent_from', descending: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      return _getActivePrescriptionFrom(_legacyPrescriptionsCol(dogId));
    }

    final prescription = NutritionPrescription.fromJson(
      snap.docs.first.data(),
      docId: snap.docs.first.id,
    );

    // Verifica se não expirou
    if (prescription.vigentUntil != null &&
        now.isAfter(prescription.vigentUntil!)) {
      return null;
    }

    return prescription;
  }

  /// Adiciona nova prescrição (encerra a anterior automaticamente).
  Future<String> addPrescription(
    String dogId,
    NutritionPrescription prescription,
  ) async {
    // Encerra prescrição anterior
    final current = await getActivePrescription(dogId);
    if (current?.id != null) {
      final entry = AuditService.buildInlineEntry(
        action: 'updated',
        fieldName: 'vigent_until',
        oldValue: current!.vigentUntil?.toIso8601String(),
        newValue: prescription.vigentFrom.toIso8601String(),
      );
      final updates = {
        'vigent_until': Timestamp.fromDate(prescription.vigentFrom),
        'updated_at': FieldValue.serverTimestamp(),
        'audit_trail': FieldValue.arrayUnion([entry]),
      };
      await _prescriptionsCol(
        dogId,
      ).doc(current.id).set(updates, SetOptions(merge: true));
      await _legacyPrescriptionsCol(
        dogId,
      ).doc(current.id).set(updates, SetOptions(merge: true));
    }

    final docRef = _prescriptionsCol(dogId).doc();
    final entry = AuditService.buildInlineEntry(action: 'created');
    final data = {
      ...prescription.toJson(),
      'audit_trail': [entry],
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };
    await docRef.set(data);
    await _legacyPrescriptionsCol(dogId).doc(docRef.id).set(data);
    return docRef.id;
  }

  /// Histórico de prescrições.
  Future<List<NutritionPrescription>> getPrescriptionHistory(
    String dogId,
  ) async {
    final snapshots = await Future.wait([
      _prescriptionsCol(dogId).orderBy('vigent_from', descending: true).get(),
      _legacyPrescriptionsCol(
        dogId,
      ).orderBy('vigent_from', descending: true).get(),
    ]);
    final byKey = <String, NutritionPrescription>{};
    for (final snap in snapshots) {
      for (final doc in snap.docs) {
        final item = NutritionPrescription.fromJson(doc.data(), docId: doc.id);
        if (item.isDeleted) continue;
        byKey[doc.id] = item;
      }
    }
    final list = byKey.values.toList()
      ..sort((a, b) => b.vigentFrom.compareTo(a.vigentFrom));
    return list;
  }

  /// Calcula conformidade alimentar (% de refeições conformes no período).
  Future<double> calculateConformity(
    String dogId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final feedings = await getFeedings(dogId, from: from, to: to);
    if (feedings.isEmpty) return 0.0;
    final conformCount = feedings.where((f) => f.isConform).length;
    return (conformCount / feedings.length) * 100;
  }

  Future<List<NutritionSupplement>> getSupplements(String dogId) async {
    final snap = await _supplementsCol(
      dogId,
    ).orderBy('started_at', descending: true).get();
    return snap.docs
        .map((doc) => NutritionSupplement.fromJson(doc.data(), docId: doc.id))
        .where((supplement) => !supplement.isDeleted)
        .toList();
  }

  Future<String> addSupplement(
    String dogId,
    NutritionSupplement supplement,
  ) async {
    final docRef = _supplementsCol(dogId).doc();
    final entry = AuditService.buildInlineEntry(action: 'created');
    final data = {
      ...supplement.toJson(),
      'audit_trail': [entry],
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };
    await docRef.set(data);
    return docRef.id;
  }

  Future<List<Feeding>> _getFeedingsFrom(
    CollectionReference<Map<String, dynamic>> col, {
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    Query<Map<String, dynamic>> query = col.orderBy('fed_at', descending: true);

    if (from != null) {
      query = query.where(
        'fed_at',
        isGreaterThanOrEqualTo: Timestamp.fromDate(from),
      );
    }
    if (to != null) {
      query = query.where('fed_at', isLessThan: Timestamp.fromDate(to));
    }
    if (limit != null) query = query.limit(limit);

    final snap = await query.get();
    return snap.docs
        .map((doc) => Feeding.fromJson(doc.data(), docId: doc.id))
        .where((feeding) => !feeding.isDeleted)
        .toList();
  }

  Stream<List<Feeding>> _watchMergedFeedings(
    String dogId, {
    required DateTime from,
    required DateTime to,
  }) {
    final controller = StreamController<List<Feeding>>();
    List<Feeding> primary = [];
    List<Feeding> legacy = [];

    void emit() {
      if (!controller.isClosed) {
        controller.add(_dedupeFeedings([...primary, ...legacy]));
      }
    }

    Query<Map<String, dynamic>> query(
      CollectionReference<Map<String, dynamic>> col,
    ) => col
        .where('fed_at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('fed_at', isLessThan: Timestamp.fromDate(to))
        .orderBy('fed_at', descending: true);

    final primarySub = query(_feedingsCol(dogId)).snapshots().listen((snap) {
      primary = snap.docs
          .map((doc) => Feeding.fromJson(doc.data(), docId: doc.id))
          .where((feeding) => !feeding.isDeleted)
          .toList();
      emit();
    }, onError: controller.addError);

    final legacySub = query(_legacyFeedingsCol(dogId)).snapshots().listen((
      snap,
    ) {
      legacy = snap.docs
          .map((doc) => Feeding.fromJson(doc.data(), docId: doc.id))
          .where((feeding) => !feeding.isDeleted)
          .toList();
      emit();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await primarySub.cancel();
      await legacySub.cancel();
    };
    return controller.stream;
  }

  List<Feeding> _dedupeFeedings(Iterable<Feeding> items) {
    final byKey = <String, Feeding>{};
    for (final item in items) {
      final key = item.id ?? item.fedAt.microsecondsSinceEpoch.toString();
      byKey[key] = item;
    }
    final list = byKey.values.toList()
      ..sort((a, b) => b.fedAt.compareTo(a.fedAt));
    return list;
  }

  Future<NutritionPrescription?> _getActivePrescriptionFrom(
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    final now = DateTime.now();
    final snap = await col
        .where('vigent_from', isLessThanOrEqualTo: Timestamp.fromDate(now))
        .orderBy('vigent_from', descending: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    final prescription = NutritionPrescription.fromJson(
      snap.docs.first.data(),
      docId: snap.docs.first.id,
    );
    if (prescription.isDeleted) return null;
    if (prescription.vigentUntil != null &&
        now.isAfter(prescription.vigentUntil!)) {
      return null;
    }
    return prescription;
  }
}
