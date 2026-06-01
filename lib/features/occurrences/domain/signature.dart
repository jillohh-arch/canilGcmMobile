import 'package:cloud_firestore/cloud_firestore.dart';

class Signature {
  final String handlerId;
  final String status; // 'pending', 'signed', 'expired'
  final DateTime? signedAt;
  final String signatureMethod; // 'biometric', 'password'
  final String signatureHash;

  const Signature({
    required this.handlerId,
    required this.status,
    this.signedAt,
    required this.signatureMethod,
    required this.signatureHash,
  });

  factory Signature.fromJson(Map<String, dynamic> json) {
    return Signature(
      handlerId: json['handler_id'] ?? '',
      status: json['status'] ?? 'pending',
      signedAt: json['signed_at']?.toDate(),
      signatureMethod: json['signature_method'] ?? '',
      signatureHash: json['signature_hash'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'handler_id': handlerId,
      'status': status,
      'signed_at': signedAt != null ? Timestamp.fromDate(signedAt!) : null,
      'signature_method': signatureMethod,
      'signature_hash': signatureHash,
    };
  }

  Signature copyWith({
    String? handlerId,
    String? status,
    DateTime? signedAt,
    String? signatureMethod,
    String? signatureHash,
  }) {
    return Signature(
      handlerId: handlerId ?? this.handlerId,
      status: status ?? this.status,
      signedAt: signedAt ?? this.signedAt,
      signatureMethod: signatureMethod ?? this.signatureMethod,
      signatureHash: signatureHash ?? this.signatureHash,
    );
  }
}
