import 'package:cloud_firestore/cloud_firestore.dart';

/// Registro de alimentação do cão.
/// Subcoleção: /dogs/{dogId}/feedings/{feedingId}
class Feeding {
  final String? id;
  final String period; // 'manha' | 'noite' | 'almoco'
  final int amountGrams;
  final int prescriptionAtTime; // snapshot da prescrição vigente
  final double divergencePercent; // calculado: (amount - prescription) / prescription * 100
  final String? divergenceReason;
  final String? photoBalanceUrl;
  final String? observations;
  final DateTime fedAt;
  final String fedBy;

  Feeding({
    this.id,
    required this.period,
    required this.amountGrams,
    required this.prescriptionAtTime,
    required this.divergencePercent,
    this.divergenceReason,
    this.photoBalanceUrl,
    this.observations,
    required this.fedAt,
    required this.fedBy,
  });

  factory Feeding.fromJson(Map<String, dynamic> json, {String? docId}) {
    return Feeding(
      id: docId ?? json['id'] as String?,
      period: json['period'] as String? ?? 'manha',
      amountGrams: json['amount_grams'] as int? ?? 0,
      prescriptionAtTime: json['prescription_at_time'] as int? ?? 0,
      divergencePercent: (json['divergence_percent'] as num?)?.toDouble() ?? 0.0,
      divergenceReason: json['divergence_reason'] as String?,
      photoBalanceUrl: json['photo_balance_url'] as String?,
      observations: json['observations'] as String?,
      fedAt: _toDateTime(json['fed_at']) ?? DateTime.now(),
      fedBy: json['fed_by'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'period': period,
      'amount_grams': amountGrams,
      'prescription_at_time': prescriptionAtTime,
      'divergence_percent': divergencePercent,
      if (divergenceReason != null) 'divergence_reason': divergenceReason,
      if (photoBalanceUrl != null) 'photo_balance_url': photoBalanceUrl,
      if (observations != null) 'observations': observations,
      'fed_at': Timestamp.fromDate(fedAt),
      'fed_by': fedBy,
    };
  }

  /// Calcula a divergência percentual entre quantidade e prescrição.
  static double calculateDivergence(int amount, int prescription) {
    if (prescription == 0) return 0.0;
    return ((amount - prescription) / prescription) * 100;
  }

  bool get isConform => divergencePercent == 0.0;

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}