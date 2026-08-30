import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_date_parse.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_soft_delete.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_user_copy.dart';

final class HealthSummaryMedicationFact {
  const HealthSummaryMedicationFact({
    required this.medicationName,
    required this.startedAt,
    required this.durationDays,
    required this.isContinuous,
  });

  final String medicationName;
  final DateTime startedAt;
  final int? durationDays;
  final bool isContinuous;

  bool isActiveAt(DateTime now) {
    if (startedAt.isAfter(now)) return false;
    if (isContinuous) return true;
    return now.isBefore(startedAt.add(Duration(days: durationDays!)));
  }
}

/// Adapta o evento canônico escrito pelo formulário Mobile para o card de
/// medicação, sem duplicar dados nem inferir protocolo terapêutico.
class HealthSummaryMedicationReader {
  HealthSummaryMedicationReader({
    FirebaseFirestore? firestore,
    Future<List<HealthSummaryMedicationFact>> Function(String dogId)? loadFacts,
    DateTime Function()? clock,
  }) : _loadFacts =
           loadFacts ??
           ((dogId) => _loadFromFirestore(
             firestore ?? FirebaseFirestore.instance,
             dogId,
           )),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final Future<List<HealthSummaryMedicationFact>> Function(String dogId)
  _loadFacts;
  final DateTime Function() _clock;

  Future<HealthSummarySectionData<HealthSummaryTreatmentsView>> read(
    String dogId,
  ) async {
    try {
      final facts = await _loadFacts(dogId);
      if (facts.isEmpty) {
        return const HealthSummarySectionData.notRecorded(
          message: HealthSummaryUserCopy.treatmentsNotRecorded,
        );
      }
      final active = facts.where((fact) => fact.isActiveAt(_clock())).toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return HealthSummarySectionData.available(
        HealthSummaryTreatmentsView(
          activeProtocolCount: active.length,
          primarySummary: active.isEmpty ? null : active.first.medicationName,
        ),
      );
    } on FirebaseException catch (e) {
      debugPrint(
        '[HealthSummaryMedicationReader] unavailable [${e.code}]: ${e.message}',
      );
      return HealthSummarySectionData.unavailable(
        message: e.code == 'unavailable'
            ? HealthSummaryUserCopy.networkUnavailable
            : HealthSummaryUserCopy.treatmentsUnavailable,
      );
    } on HealthSummaryScanTruncatedException catch (e) {
      debugPrint('[HealthSummaryMedicationReader] truncated: $e');
      return const HealthSummarySectionData.unavailable(
        message: HealthSummaryUserCopy.treatmentsUnavailable,
      );
    } catch (e) {
      debugPrint('[HealthSummaryMedicationReader] unavailable: $e');
      return const HealthSummarySectionData.unavailable(
        message: HealthSummaryUserCopy.treatmentsUnavailable,
      );
    }
  }

  static Future<List<HealthSummaryMedicationFact>> _loadFromFirestore(
    FirebaseFirestore firestore,
    String dogId,
  ) async {
    final ordered = firestore
        .collection('dogs')
        .doc(dogId)
        .collection('health_events')
        .orderBy('date', descending: true);
    final result = await HealthSummarySoftDelete.paginateActiveMapped(
      orderedQuery: ordered,
      targetActive:
          HealthSummarySoftDelete.defaultPageSize *
          HealthSummarySoftDelete.defaultMaxPages,
      debugScope: 'health_events/medication',
      tryMap: (doc) => _tryMap(doc.data()),
    );
    if (result.truncated) {
      throw HealthSummaryScanTruncatedException(
        scope: 'health_events/medication',
        pageSize: HealthSummarySoftDelete.defaultPageSize,
        maxPages: HealthSummarySoftDelete.defaultMaxPages,
        targetActive:
            HealthSummarySoftDelete.defaultPageSize *
            HealthSummarySoftDelete.defaultMaxPages,
        pagesScanned: result.pagesScanned,
        itemsFound: result.items.length,
      );
    }
    return List.of(result.items);
  }

  static HealthSummaryMedicationFact? _tryMap(Map<String, dynamic> data) {
    if (HealthSummarySoftDelete.isSoftDeleted(data)) return null;
    final type = (data['type'] ?? data['logType'])
        ?.toString()
        .trim()
        .toLowerCase();
    if (type != 'medication' && type != 'medicação' && type != 'medicacao') {
      return null;
    }
    final status = data['status']?.toString().trim().toLowerCase();
    if (status == 'cancelled' || status == 'canceled') return null;

    final startedAt = HealthSummaryDateParse.tryParse(data['date']);
    final name = data['subtype']?.toString().trim();
    final observations = data['healthObservations']?.toString() ?? '';
    final match = RegExp(
      r'^\[Dosagem:\s*[^|\]]+\|\s*Frequência:\s*[^|\]]+\|\s*Duração:\s*([^\]]+)\]',
      caseSensitive: false,
    ).firstMatch(observations.trim());
    if (startedAt == null || name == null || name.isEmpty || match == null) {
      throw const FormatException('canonical medication event malformed');
    }

    final duration = match.group(1)!.trim().toLowerCase();
    final dayMatch = RegExp(r'^(\d+)\s*dias?$').firstMatch(duration);
    final isContinuous = duration == 'contínuo' || duration == 'continuo';
    final days = dayMatch == null ? null : int.tryParse(dayMatch.group(1)!);
    if (!isContinuous && (days == null || days <= 0)) {
      throw const FormatException('canonical medication duration malformed');
    }
    return HealthSummaryMedicationFact(
      medicationName: name,
      startedAt: startedAt,
      durationDays: days,
      isContinuous: isContinuous,
    );
  }

  @visibleForTesting
  static List<HealthSummaryMedicationFact> mapHealthEventDocsForTest(
    List<Map<String, dynamic>> docs,
  ) => [for (final doc in docs) ?_tryMap(doc)];
}
