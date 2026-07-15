import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/core/mixins/soft_deletable.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_date_parse.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';

/// Item bruto para composição de registros recentes.
final class HealthSummaryRecentRawItem {
  const HealthSummaryRecentRawItem({
    required this.id,
    required this.type,
    required this.title,
    required this.occurredAt,
    this.subtitle,
  });

  final String id;
  final String type;
  final String title;
  final String? subtitle;
  final DateTime occurredAt;
}

/// Compõe registros recentes de fontes legadas (somente leitura).
///
/// Fontes:
/// - `health_events` (limitado);
/// - `weight_records` (últimas pesagens);
/// - `feeding_events` + `feedings` do dia (dual-read alinhado ao NutritionService).
///
/// Limite pequeno e explícito. Sem inventar status clínico.
/// Dedupe de feedings por doc id (mesmo fato espelhado nas duas coleções).
class HealthSummaryRecentRecordsReader {
  HealthSummaryRecentRecordsReader({
    FirebaseFirestore? firestore,
    Future<List<HealthSummaryRecentRawItem>> Function(String dogId)? loadItems,
    this.limit = 8,
  }) : _loadItems =
           loadItems ??
           ((dogId) => _loadFromFirestore(
             firestore ?? FirebaseFirestore.instance,
             dogId,
           ));

  final Future<List<HealthSummaryRecentRawItem>> Function(String dogId)
  _loadItems;
  final int limit;

  Future<HealthSummarySectionData<HealthSummaryRecentRecordsView>> read(
    String dogId,
  ) async {
    try {
      final items = await _loadItems(dogId);
      if (items.isEmpty) {
        return const HealthSummarySectionData.notRecorded(
          message: 'Nenhum registro recente',
        );
      }
      items.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      final take = items
          .take(limit)
          .map((raw) {
            return HealthSummaryRecentRecordView(
              id: raw.id,
              type: raw.type,
              title: raw.title,
              subtitle: raw.subtitle,
              occurredAt: raw.occurredAt,
            );
          })
          .toList(growable: false);
      return HealthSummarySectionData.available(
        HealthSummaryRecentRecordsView(items: take),
      );
    } on FirebaseException catch (e) {
      return HealthSummarySectionData.unavailable(
        message: e.message ?? 'Falha ao ler registros recentes [${e.code}]',
      );
    } catch (e) {
      return HealthSummarySectionData.unavailable(
        message: 'Falha ao ler registros recentes: $e',
      );
    }
  }

  static Future<List<HealthSummaryRecentRawItem>> _loadFromFirestore(
    FirebaseFirestore firestore,
    String dogId,
  ) async {
    final results = await Future.wait([
      _healthEvents(firestore, dogId),
      _weights(firestore, dogId),
      _todayFeedings(firestore, dogId),
    ]);
    return results.expand((e) => e).toList(growable: false);
  }

  static Future<List<HealthSummaryRecentRawItem>> _healthEvents(
    FirebaseFirestore firestore,
    String dogId,
  ) async {
    final query = firestore
        .collection('dogs')
        .doc(dogId)
        .collection('health_events');
    final snap = await SoftDeletable.activeOnly(
      query,
    ).orderBy('date', descending: true).limit(20).get();
    final items = <HealthSummaryRecentRawItem>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final type = (data['type'] ?? data['logType'] ?? 'other').toString();
      final at = HealthSummaryDateParse.tryParse(data['date']);
      if (at == null) continue;
      final subtype = data['subtype']?.toString().trim();
      final title = _healthTitle(type, subtype);
      final obs = data['healthObservations']?.toString().trim();
      items.add(
        HealthSummaryRecentRawItem(
          id: 'he-${doc.id}',
          type: type,
          title: title,
          subtitle: (obs == null || obs.isEmpty) ? null : obs,
          occurredAt: at,
        ),
      );
    }
    return items;
  }

  static Future<List<HealthSummaryRecentRawItem>> _weights(
    FirebaseFirestore firestore,
    String dogId,
  ) async {
    final snap = await firestore
        .collection('dogs')
        .doc(dogId)
        .collection('weight_records')
        .orderBy('measured_at', descending: true)
        .limit(5)
        .get();
    final items = <HealthSummaryRecentRawItem>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final at = HealthSummaryDateParse.tryParse(data['measured_at']);
      final kg = (data['weight_kg'] is num)
          ? (data['weight_kg'] as num).toDouble()
          : null;
      if (at == null || kg == null || !kg.isFinite || kg <= 0) continue;
      final label = kg == kg.roundToDouble()
          ? '${kg.toInt()} kg'
          : '${kg.toStringAsFixed(1).replaceAll('.', ',')} kg';
      items.add(
        HealthSummaryRecentRawItem(
          id: 'wt-${doc.id}',
          type: 'weight',
          title: 'Pesagem',
          subtitle: label,
          occurredAt: at,
        ),
      );
    }
    return items;
  }

  static Future<List<HealthSummaryRecentRawItem>> _todayFeedings(
    FirebaseFirestore firestore,
    String dogId,
  ) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    // Dual-read alinhado ao NutritionService (feeding_events + feedings).
    final snaps = await Future.wait([
      _feedingSnap(firestore, dogId, 'feeding_events', start, end),
      _feedingSnap(firestore, dogId, 'feedings', start, end),
    ]);
    final byId = <String, HealthSummaryRecentRawItem>{};
    for (final snap in snaps) {
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['deleted_at'] != null) continue;
        final at = HealthSummaryDateParse.tryParse(data['fed_at']);
        if (at == null) continue;
        final grams = data['amount_grams'];
        final subtitle = grams == null ? null : '$grams g';
        byId[doc.id] = HealthSummaryRecentRawItem(
          id: 'fd-${doc.id}',
          type: 'feeding',
          title: 'Alimentação registrada',
          subtitle: subtitle,
          occurredAt: at,
        );
      }
    }
    return byId.values.toList(growable: false);
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> _feedingSnap(
    FirebaseFirestore firestore,
    String dogId,
    String collection,
    DateTime start,
    DateTime end,
  ) {
    return firestore
        .collection('dogs')
        .doc(dogId)
        .collection(collection)
        .where('fed_at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('fed_at', isLessThan: Timestamp.fromDate(end))
        .orderBy('fed_at', descending: true)
        .limit(10)
        .get();
  }

  static String _healthTitle(String type, String? subtype) {
    final base = switch (type.toLowerCase()) {
      'vaccination' || 'vacina' || 'vacinação' => 'Vacina',
      'consultation' || 'consulta' => 'Consulta',
      'exam' || 'exame' => 'Exame',
      'medication' || 'medicação' || 'medicacao' => 'Medicação',
      'surgery' || 'cirurgia' => 'Cirurgia',
      'antiparasitic' => 'Antiparasitário',
      'symptom' => 'Sintoma',
      _ => 'Registro de saúde',
    };
    if (subtype != null && subtype.isNotEmpty) {
      return '$base · $subtype';
    }
    return base;
  }
}
