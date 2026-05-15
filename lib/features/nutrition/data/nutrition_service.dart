import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/core/services/storage_service.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_prescription.dart';

/// Service para gerenciar alimentação e prescrições nutricionais.
class NutritionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final StorageService _storage = StorageService();

  // ─── Feedings ─────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _feedingsCol(String dogId) =>
      _firestore.collection('dogs').doc(dogId).collection('feedings');

  /// Stream de refeições do dia.
  Stream<List<Feeding>> watchTodayFeedings(String dogId) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _feedingsCol(dogId)
        .where('fed_at', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('fed_at', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('fed_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Feeding.fromJson(doc.data(), docId: doc.id))
            .toList());
  }

  /// Busca refeições por período.
  Future<List<Feeding>> getFeedings(
    String dogId, {
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    Query<Map<String, dynamic>> query =
        _feedingsCol(dogId).orderBy('fed_at', descending: true);

    if (from != null) {
      query = query.where('fed_at',
          isGreaterThanOrEqualTo: Timestamp.fromDate(from));
    }
    if (to != null) {
      query = query.where('fed_at', isLessThan: Timestamp.fromDate(to));
    }
    if (limit != null) {
      query = query.limit(limit);
    }

    final snap = await query.get();
    return snap.docs
        .map((doc) => Feeding.fromJson(doc.data(), docId: doc.id))
        .toList();
  }

  /// Registra uma nova refeição.
  Future<String> addFeeding(String dogId, Feeding feeding) async {
    final docRef = await _feedingsCol(dogId).add(feeding.toJson());
    return docRef.id;
  }

  /// Faz upload da foto da balança e retorna a URL.
  Future<String?> uploadFeedingPhoto(String dogId, File photo) async {
    return _storage.uploadImage(photo, 'dogs/$dogId/feeding_photos');
  }

  /// Atualiza a URL da foto em um feeding existente.
  Future<void> updateFeedingPhoto(String dogId, String feedingId, String photoUrl) async {
    await _feedingsCol(dogId).doc(feedingId).update({
      'photo_balance_url': photoUrl,
    });
  }

  // ─── Prescriptions ────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _prescriptionsCol(String dogId) =>
      _firestore.collection('dogs').doc(dogId).collection('nutrition_prescriptions');

  /// Busca a prescrição vigente.
  Future<NutritionPrescription?> getActivePrescription(String dogId) async {
    final now = DateTime.now();
    final snap = await _prescriptionsCol(dogId)
        .where('vigent_from', isLessThanOrEqualTo: Timestamp.fromDate(now))
        .orderBy('vigent_from', descending: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;

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
      await _prescriptionsCol(dogId).doc(current!.id).update({
        'vigent_until': Timestamp.fromDate(prescription.vigentFrom),
      });
    }

    final docRef = await _prescriptionsCol(dogId).add(prescription.toJson());
    return docRef.id;
  }

  /// Histórico de prescrições.
  Future<List<NutritionPrescription>> getPrescriptionHistory(String dogId) async {
    final snap = await _prescriptionsCol(dogId)
        .orderBy('vigent_from', descending: true)
        .get();
    return snap.docs
        .map((doc) =>
            NutritionPrescription.fromJson(doc.data(), docId: doc.id))
        .toList();
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
}