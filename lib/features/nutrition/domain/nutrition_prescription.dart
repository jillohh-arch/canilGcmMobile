import 'package:cloud_firestore/cloud_firestore.dart';

/// Prescrição nutricional vigente do cão.
/// Subcoleção: /dogs/{dogId}/nutrition_prescriptions/{prescriptionId}
class NutritionPrescription {
  final String? id;
  final int amountGramsPerDay;
  final String foodType; // ex: "ração premium"
  final int mealsPerDay; // default 2
  final String? vetName;
  final String? vetCrmv;
  final String? vetInstitution;
  final String? laudoPdfUrl;
  final DateTime vigentFrom;
  final DateTime? vigentUntil;
  final String? notes;

  NutritionPrescription({
    this.id,
    required this.amountGramsPerDay,
    this.foodType = 'ração premium',
    this.mealsPerDay = 2,
    this.vetName,
    this.vetCrmv,
    this.vetInstitution,
    this.laudoPdfUrl,
    required this.vigentFrom,
    this.vigentUntil,
    this.notes,
  });

  /// Quantidade por refeição (gramas).
  int get amountPerMeal =>
      mealsPerDay > 0 ? (amountGramsPerDay / mealsPerDay).round() : amountGramsPerDay;

  /// Verifica se a prescrição está vigente na data informada.
  bool isVigentAt(DateTime date) {
    if (date.isBefore(vigentFrom)) return false;
    if (vigentUntil != null && date.isAfter(vigentUntil!)) return false;
    return true;
  }

  factory NutritionPrescription.fromJson(Map<String, dynamic> json, {String? docId}) {
    return NutritionPrescription(
      id: docId ?? json['id'] as String?,
      amountGramsPerDay: json['amount_grams_per_day'] as int? ?? 0,
      foodType: json['food_type'] as String? ?? 'ração premium',
      mealsPerDay: json['meals_per_day'] as int? ?? 2,
      vetName: json['vet_name'] as String?,
      vetCrmv: json['vet_crmv'] as String?,
      vetInstitution: json['vet_institution'] as String?,
      laudoPdfUrl: json['laudo_pdf_url'] as String?,
      vigentFrom: _toDateTime(json['vigent_from']) ?? DateTime.now(),
      vigentUntil: _toDateTime(json['vigent_until']),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'amount_grams_per_day': amountGramsPerDay,
      'food_type': foodType,
      'meals_per_day': mealsPerDay,
      if (vetName != null) 'vet_name': vetName,
      if (vetCrmv != null) 'vet_crmv': vetCrmv,
      if (vetInstitution != null) 'vet_institution': vetInstitution,
      if (laudoPdfUrl != null) 'laudo_pdf_url': laudoPdfUrl,
      'vigent_from': Timestamp.fromDate(vigentFrom),
      if (vigentUntil != null) 'vigent_until': Timestamp.fromDate(vigentUntil!),
      if (notes != null) 'notes': notes,
    };
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}