import 'package:cloud_firestore/cloud_firestore.dart';

enum SignatureStatus {
  pending,
  signed,
  expired;

  String toMap() => switch (this) {
        pending => 'pending',
        signed => 'signed',
        expired => 'expired',
      };

  static SignatureStatus fromMap(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == 'signed') {
      return SignatureStatus.signed;
    }
    if (normalized == 'expired') {
      return SignatureStatus.expired;
    }
    return SignatureStatus.pending;
  }
}

enum SignatureMethod {
  biometric,
  password;

  String toMap() => switch (this) {
        biometric => 'biometric',
        password => 'password',
      };

  static SignatureMethod fromMap(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == 'password') {
      return SignatureMethod.password;
    }
    return SignatureMethod.biometric;
  }
}

class OccurrenceSignature {
  /// RA do integrante que assinou ou precisa assinar.
  final String handlerId;
  final SignatureStatus status;
  final DateTime? signedAt;
  final SignatureMethod signatureMethod;
  final String signatureHash;
  final String? reason;

  const OccurrenceSignature({
    required this.handlerId,
    required this.status,
    this.signedAt,
    this.signatureMethod = SignatureMethod.biometric,
    this.signatureHash = '',
    this.reason,
  });

  factory OccurrenceSignature.fromJson(Map<dynamic, dynamic> json) {
    return OccurrenceSignature(
      handlerId: _parseString(json['handler_id'] ?? json['handlerId']) ?? '',
      status: SignatureStatus.fromMap(_parseString(json['status'])),
      signedAt: _parseDateTime(json['signed_at'] ?? json['signedAt']),
      signatureMethod: SignatureMethod.fromMap(
        _parseString(json['signature_method'] ?? json['signatureMethod']),
      ),
      signatureHash:
          _parseString(json['signature_hash'] ?? json['signatureHash']) ?? '',
      reason: _parseString(json['reason']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'handler_id': handlerId,
      'status': status.toMap(),
      'signed_at': signedAt != null ? Timestamp.fromDate(signedAt!) : null,
      'signature_method': signatureMethod.toMap(),
      'signature_hash': signatureHash,
      if (reason != null) 'reason': reason,
    };
  }

  /// Payload usado no hash v3. O signature_hash fica fora para evitar ciclo.
  Map<String, dynamic> toHashPayload() {
    return {
      'handler_id': handlerId,
      'status': status.toMap(),
      'signed_at': signedAt?.toUtc().toIso8601String(),
      'signature_method': signatureMethod.toMap(),
      if (reason != null) 'reason': reason,
    };
  }

  OccurrenceSignature copyWith({
    String? handlerId,
    SignatureStatus? status,
    DateTime? signedAt,
    SignatureMethod? signatureMethod,
    String? signatureHash,
    String? reason,
  }) {
    return OccurrenceSignature(
      handlerId: handlerId ?? this.handlerId,
      status: status ?? this.status,
      signedAt: signedAt ?? this.signedAt,
      signatureMethod: signatureMethod ?? this.signatureMethod,
      signatureHash: signatureHash ?? this.signatureHash,
      reason: reason ?? this.reason,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String? _parseString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
