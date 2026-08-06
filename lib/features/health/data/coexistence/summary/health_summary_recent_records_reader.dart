import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_date_parse.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_soft_delete.dart';
import 'package:canil_gcm/features/health/data/weight/weight_assessment_read_adapter.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_user_copy.dart';

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

  /// Quantos health_events **ativos** buscar antes de misturar com peso/feed.
  static const int healthEventsActiveTarget = 20;

  Future<HealthSummarySectionData<HealthSummaryRecentRecordsView>> read(
    String dogId,
  ) async {
    try {
      final items = await _loadItems(dogId);
      if (items.isEmpty) {
        return const HealthSummarySectionData.notRecorded(
          message: HealthSummaryUserCopy.recentNotRecorded,
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
    } on HealthSummaryScanTruncatedException catch (e) {
      debugPrint('[HealthSummaryRecentRecordsReader] truncated: $e');
      return const HealthSummarySectionData.unavailable(
        message: HealthSummaryUserCopy.recentUnavailable,
      );
    } on FirebaseException catch (e) {
      debugPrint(
        '[HealthSummaryRecentRecordsReader] unavailable [${e.code}]: ${e.message}',
      );
      return HealthSummarySectionData.unavailable(
        message: e.code == 'unavailable'
            ? HealthSummaryUserCopy.networkUnavailable
            : HealthSummaryUserCopy.recentUnavailable,
      );
    } catch (e) {
      debugPrint('[HealthSummaryRecentRecordsReader] unavailable: $e');
      return const HealthSummarySectionData.unavailable(
        message: HealthSummaryUserCopy.recentUnavailable,
      );
    }
  }

  static Future<List<HealthSummaryRecentRawItem>> _loadFromFirestore(
    FirebaseFirestore firestore,
    String dogId,
  ) async {
    // health_events primeiro: se truncado, NÃO misturar weights/feedings
    // como se o histórico estivesse completo.
    final events = await _healthEvents(firestore, dogId);

    // Subfontes restantes em paralelo: se **qualquer** falhar, propaga e o
    // bloco inteiro fica unavailable (intencional).
    final rest = await Future.wait([
      _weights(firestore, dogId),
      _todayFeedings(firestore, dogId),
    ]);
    return [...events, ...rest.expand((e) => e)];
  }

  static Future<List<HealthSummaryRecentRawItem>> _healthEvents(
    FirebaseFirestore firestore,
    String dogId,
  ) async {
    // Sem SoftDeletable.activeOnly + orderBy (índice composto).
    // Pagina até healthEventsActiveTarget ativos — evita perda silenciosa
    // quando a janela recente é dominada por soft-deletes.
    final ordered = firestore
        .collection('dogs')
        .doc(dogId)
        .collection('health_events')
        .orderBy('date', descending: true);

    final scan = await HealthSummarySoftDelete.paginateActiveMapped(
      orderedQuery: ordered,
      targetActive: healthEventsActiveTarget,
      debugScope: 'health_events/recent',
      tryMap: (doc) => mapHealthEventDoc(doc.id, doc.data()),
    );

    if (scan.truncated) {
      throw HealthSummaryScanTruncatedException(
        scope: 'health_events/recent',
        pageSize: HealthSummarySoftDelete.defaultPageSize,
        maxPages: HealthSummarySoftDelete.defaultMaxPages,
        targetActive: healthEventsActiveTarget,
        pagesScanned: scan.pagesScanned,
        itemsFound: scan.items.length,
      );
    }

    // Conclusivo (vazio ou com itens). Vazio esgotado = só pesos/refeições.
    return List.of(scan.items);
  }

  /// Mapeia um doc de health_events (null se soft-deleted / data inválida).
  @visibleForTesting
  static HealthSummaryRecentRawItem? mapHealthEventDoc(
    String id,
    Map<String, dynamic> data,
  ) {
    if (HealthSummarySoftDelete.isSoftDeleted(data)) return null;
    final type = (data['type'] ?? data['logType'] ?? 'other').toString();
    final at = HealthSummaryDateParse.tryParse(data['date']);
    if (at == null) return null;
    final subtype = data['subtype']?.toString().trim();
    final title = _healthTitle(type, subtype);
    final obs = data['healthObservations']?.toString().trim();
    return HealthSummaryRecentRawItem(
      id: 'he-$id',
      type: type,
      title: title,
      subtitle: (obs == null || obs.isEmpty) ? null : obs,
      occurredAt: at,
    );
  }

  /// Pesagens recentes via parser central (ADR-008 §11.3).
  ///
  /// - inclui apenas `valid` (o card não carrega autoria, então shapes legados
  ///   sem `recorder` também entram);
  /// - `invalidated` excluído;
  /// - `malformed`/`unsupported` nunca viram card;
  /// - bloqueio **antes** do primeiro `valid` → falha (sem promover registro
  ///   mais antigo como "mais recente"); o bloco fica `unavailable` pelo
  ///   mecanismo de erro já existente. Bloqueio **depois** de um `valid` é
  ///   ignorado.
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
    var seenValid = false;
    for (final doc in snap.docs) {
      final result = WeightAssessmentReadAdapter.read(
        documentId: doc.id,
        dogId: dogId,
        data: doc.data(),
      );
      switch (result.kind) {
        case WeightReadKind.invalidated:
          continue;
        case WeightReadKind.malformed:
        case WeightReadKind.unsupported:
          if (!seenValid) {
            throw StateError('weight_recent_inconclusive_${result.kind.name}');
          }
          continue;
        case WeightReadKind.valid:
          seenValid = true;
          final assessment = result.assessment!;
          final kg = assessment.weightKg;
          final label = kg == kg.roundToDouble()
              ? '${kg.toInt()} kg'
              : '${kg.toStringAsFixed(1).replaceAll('.', ',')} kg';
          items.add(
            HealthSummaryRecentRawItem(
              id: 'wt-${doc.id}',
              type: 'weight',
              title: 'Pesagem',
              subtitle: label,
              occurredAt: assessment.measuredAt,
            ),
          );
      }
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
        if (HealthSummarySoftDelete.isSoftDeleted(data)) continue;
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
