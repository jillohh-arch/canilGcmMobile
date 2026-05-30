import 'package:cloud_functions/cloud_functions.dart';

import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';

class SealOccurrenceResult {
  final String integrityHash;
  final int hashVersion;
  final String status;

  const SealOccurrenceResult({
    required this.integrityHash,
    required this.hashVersion,
    required this.status,
  });

  factory SealOccurrenceResult.fromMap(Map<dynamic, dynamic> data) {
    return SealOccurrenceResult(
      integrityHash: data['integrity_hash']?.toString() ?? '',
      hashVersion: _parseInt(data['hash_version']) ?? 4,
      status: data['status']?.toString() ?? 'finalized',
    );
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class OccurrenceTransitionService {
  OccurrenceTransitionService({FirebaseFunctions? functions})
    : _functions =
          functions ??
          FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  final FirebaseFunctions _functions;

  Future<SealOccurrenceResult> sealOccurrenceV4({
    required String occurrenceId,
    required String finalReport,
    required List<OccurrenceResult> results,
    required Map<String, dynamic>? details,
    required List<String> finalizationPhotos,
    required List<String> finalizationPhotoHashes,
    bool withPending = false,
  }) async {
    final callable = _functions.httpsCallable('sealOccurrenceV4');
    final response = await callable.call<Map<dynamic, dynamic>>({
      'occurrence_id': occurrenceId,
      'final_report': finalReport,
      'results': results.map((result) => result.toMap()).toList(),
      'details': details,
      'finalization_photos': finalizationPhotos,
      'finalization_photo_hashes': finalizationPhotoHashes,
      'with_pending': withPending,
    });
    return SealOccurrenceResult.fromMap(response.data);
  }

  Future<void> requestCorrection({
    required String occurrenceId,
    required String reason,
  }) async {
    final callable = _functions.httpsCallable('requestOccurrenceCorrection');
    await callable.call<void>({
      'occurrence_id': occurrenceId,
      'reason': reason,
    });
  }

  Future<void> declineParticipation({
    required String occurrenceId,
    required String reason,
  }) async {
    final callable = _functions.httpsCallable('declineOccurrenceParticipation');
    await callable.call<void>({
      'occurrence_id': occurrenceId,
      'reason': reason,
    });
  }
}
