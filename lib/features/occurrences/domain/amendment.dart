import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

/// Representa um aditamento/retificação de uma ocorrência selada.
/// Cada aditamento tem seu próprio hash de integridade e não altera
/// o documento original da ocorrência.
class Amendment {
  final String id;
  final String occurrenceId;
  final String reason;
  final Map<String, AmendmentCorrection> corrections;
  final String createdBy; // RA/handlerId canônico do autor
  final String createdByName;
  final String createdByRa;
  final DateTime createdAt;
  final String integrityHash; // SHA-256 do conteúdo do aditamento
  final int sequenceNumber; // 1, 2, 3... ordem cronológica

  const Amendment({
    required this.id,
    required this.occurrenceId,
    required this.reason,
    required this.corrections,
    required this.createdBy,
    required this.createdByName,
    required this.createdByRa,
    required this.createdAt,
    required this.integrityHash,
    required this.sequenceNumber,
  });

  factory Amendment.fromMap(Map<String, dynamic> map, String docId) {
    final correctionsMap = <String, AmendmentCorrection>{};
    final rawCorrections = map['corrections'] as Map<String, dynamic>? ?? {};
    for (final entry in rawCorrections.entries) {
      correctionsMap[entry.key] = AmendmentCorrection.fromMap(
        entry.value as Map<String, dynamic>,
      );
    }

    return Amendment(
      id: docId,
      occurrenceId: map['occurrence_id'] as String? ?? '',
      reason: map['reason'] as String? ?? '',
      corrections: correctionsMap,
      createdBy: map['created_by'] as String? ?? '',
      createdByName: map['created_by_name'] as String? ?? '',
      createdByRa: map['created_by_ra'] as String? ?? '',
      createdAt: _parseDateTime(map['created_at']),
      integrityHash: map['integrity_hash'] as String? ?? '',
      sequenceNumber: (map['sequence_number'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'occurrence_id': occurrenceId,
      'reason': reason,
      'corrections': corrections.map(
        (key, value) => MapEntry(key, value.toMap()),
      ),
      'created_by': createdBy,
      'created_by_name': createdByName,
      'created_by_ra': createdByRa,
      'created_at': Timestamp.fromDate(createdAt),
      'integrity_hash': integrityHash,
      'sequence_number': sequenceNumber,
    };
  }

  /// Calcula o hash de integridade do aditamento.
  /// Baseado no conteúdo determinístico: occurrence_id, reason, corrections,
  /// created_by (RA/handlerId), created_at, sequence_number.
  static String computeHash({
    required String occurrenceId,
    required String reason,
    required Map<String, AmendmentCorrection> corrections,
    required String createdBy,
    required DateTime createdAt,
    required int sequenceNumber,
  }) {
    // Ordenar chaves das correções para determinismo
    final sortedKeys = corrections.keys.toList()..sort();
    final correctionsPayload = {
      for (final key in sortedKeys)
        key: {
          'old_value': corrections[key]!.oldValue,
          'new_value': corrections[key]!.newValue,
        },
    };

    final payload = {
      'occurrence_id': occurrenceId,
      'reason': reason,
      'corrections': correctionsPayload,
      'created_by': createdBy,
      'created_at': createdAt.toUtc().toIso8601String(),
      'sequence_number': sequenceNumber,
    };

    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }
}

/// Representa uma correção individual dentro de um aditamento.
/// Guarda o valor anterior e o novo valor para um campo específico.
class AmendmentCorrection {
  final dynamic oldValue;
  final dynamic newValue;
  final String? description; // descrição opcional da correção

  const AmendmentCorrection({
    required this.oldValue,
    required this.newValue,
    this.description,
  });

  factory AmendmentCorrection.fromMap(Map<String, dynamic> map) {
    return AmendmentCorrection(
      oldValue: map['old_value'],
      newValue: map['new_value'],
      description: map['description'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'old_value': oldValue,
      'new_value': newValue,
      if (description != null) 'description': description,
    };
  }
}
