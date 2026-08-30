import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_traceability.dart';

/// Parser fail-closed do documento Firestore da projeção canônica health_timeline.
///
/// Refere-se a `dogs/{dogId}/health_timeline/{timelineId}`.
/// Valida integralmente o contrato do backend e descarte seguro em anomalias estruturais.
abstract final class CanonicalHealthTimelineEntryParser {
  CanonicalHealthTimelineEntryParser._();

  /// Converte um [DocumentSnapshot] ou mapa de dados no [HealthTimelineEntryView].
  ///
  /// Exige o [queryDogId] da consulta ativa para impedir contaminação cross-dog.
  /// Lança [HealthTimelineSourceException] se qualquer campo obrigatório for inválido.
  static HealthTimelineEntryView parseDocument({
    required String documentId,
    required Map<String, dynamic> data,
    required String queryDogId,
  }) {
    // 1. Validar dog_id (obrigatorio + mesmo escopo do K9)
    final rawDogId = _parseString(data['dog_id']);
    if (rawDogId == null || rawDogId.isEmpty) {
      throw const HealthTimelineSourceException('missing_dog_id');
    }
    if (rawDogId != queryDogId) {
      throw const HealthTimelineSourceException('cross_dog_contamination');
    }

    // 2. Validar timeline_type (obrigatorio)
    final rawType = _parseString(data['timeline_type']);
    if (rawType == null || rawType.isEmpty) {
      throw const HealthTimelineSourceException('invalid_document_type');
    }
    final typeView = HealthTimelineTypeView.parse(rawType);

    // 3. Validar source_collection e source_id (obrigatorios)
    final sourceCollection = _parseString(data['source_collection']);
    if (sourceCollection == null || sourceCollection.isEmpty) {
      throw const HealthTimelineSourceException('missing_source_collection');
    }
    final sourceId = _parseString(data['source_id']);
    if (sourceId == null || sourceId.isEmpty) {
      throw const HealthTimelineSourceException('missing_source_id');
    }

    // 4. Validar occurred_at (obrigatorio)
    final occurredAt = _parseTimestamp(data['occurred_at']);
    if (occurredAt == null) {
      throw const HealthTimelineSourceException('invalid_occurred_at');
    }

    // 5. Validar recorded_at (obrigatorio)
    final recordedAt = _parseTimestamp(data['recorded_at']);
    if (recordedAt == null) {
      throw const HealthTimelineSourceException('invalid_recorded_at');
    }

    // 6. Validar projected_at (obrigatorio no backend)
    final projectedAt = _parseTimestamp(data['projected_at']);
    if (projectedAt == null) {
      throw const HealthTimelineSourceException('missing_projected_at');
    }

    // 7. Validar title (obrigatorio)
    final title = _parseString(data['title']);
    if (title == null || title.isEmpty) {
      throw const HealthTimelineSourceException('missing_title');
    }

    // 8. Validar subtitle (opcional)
    final rawSubtitle = data['subtitle'];
    if (rawSubtitle != null && rawSubtitle is! String) {
      throw const HealthTimelineSourceException('invalid_subtitle');
    }
    final subtitle = _parseString(rawSubtitle);

    // 9. Validar recorded_by (obrigatorio)
    final recordedBy = _parseRecordedBy(data['recorded_by']);
    if (recordedBy == null) {
      throw const HealthTimelineSourceException('missing_recorded_by');
    }

    // 10. Validar status (obrigatorio)
    final rawStatus = data['status'];
    final status = HealthTimelineEntryStatus.tryParse(rawStatus);
    if (status == null) {
      throw const HealthTimelineSourceException('invalid_status');
    }

    // 11. Validar schema_version (obrigatorio + exatamente 1)
    final schemaVersion = data['schema_version'];
    if (schemaVersion == null || schemaVersion != 1) {
      throw const HealthTimelineSourceException('unsupported_schema_version');
    }

    // Campos Opcionais
    final caseId = _parseString(data['case_id']);
    final caseTitle = _parseString(data['case_title']);
    final professional = _parseProfessional(data['professional']);
    final operationalImpact = _parseOperationalImpact(
      data['operational_impact'],
    );

    // Anexos
    final attachmentCountRaw = data['attachment_count'];
    int? attachmentCount;
    if (attachmentCountRaw != null) {
      if (attachmentCountRaw is int && attachmentCountRaw >= 0) {
        attachmentCount = attachmentCountRaw;
      } else {
        throw const HealthTimelineSourceException('invalid_attachment_count');
      }
    }
    final hasAttachments = (attachmentCount ?? 0) > 0;

    // Adendos
    final amendments = _parseAmendments(data['amendments']);

    // Rastreabilidade / Migração
    final migrationBatchId = _parseString(data['migration_batch_id']);
    final traceability = HealthTimelineTraceability(
      sourceCollection: sourceCollection,
      sourceId: sourceId,
      legacySource: _parseString(data['legacy_source']),
      legacyId: _parseString(data['legacy_id']),
    );

    // Detail reference
    final detailReference = HealthTimelineDetailReference(
      sourceType: typeView.raw,
      sourceId: sourceId,
      caseId: caseId,
    );

    return HealthTimelineEntryView(
      id: documentId,
      dogId: rawDogId,
      type: typeView,
      occurredAt: occurredAt,
      recordedAt: recordedAt,
      title: title,
      subtitle: subtitle,
      status: status,
      caseId: caseId,
      caseTitle: caseTitle,
      recordedBy: recordedBy,
      professional: professional,
      operationalImpact: operationalImpact,
      hasAttachments: hasAttachments,
      attachmentCount: attachmentCount,
      amendments: amendments,
      detailReference: detailReference,
      traceability: migrationBatchId != null ? traceability : traceability,
    );
  }

  static String? _parseString(Object? val) {
    if (val == null) return null;
    if (val is! String) return null;
    final trimmed = val.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _parseTimestamp(Object? val) {
    if (val == null) return null;
    if (val is Timestamp) {
      return val.toDate();
    }
    if (val is DateTime) {
      return val;
    }
    return null;
  }

  static RecordedBy? _parseRecordedBy(Object? raw) {
    if (raw == null || raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final uid = _parseString(map['uid']);
    final name = _parseString(map['name']);
    final role = _parseString(map['internal_role']);

    if (uid == null || name == null || role == null) {
      return null;
    }
    return RecordedBy(uid: uid, name: name, internalRole: role);
  }

  static ProfessionalIdentitySummary? _parseProfessional(Object? raw) {
    if (raw == null || raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final name = _parseString(map['name']);
    if (name == null) return null;
    final specialty = _parseString(map['specialty']);
    return ProfessionalIdentitySummary(name: name, specialty: specialty);
  }

  static OperationalImpact? _parseOperationalImpact(Object? raw) {
    if (raw == null || raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final levelRaw = map['level'];
    if (levelRaw == null || levelRaw is! String) return null;
    final str = levelRaw.trim().toLowerCase();
    OperationalImpactLevel? level;
    for (final l in OperationalImpactLevel.values) {
      if (l.wireName == str || l.name == str) {
        level = l;
        break;
      }
    }
    if (level == null) return null;
    final description =
        _parseString(map['description']) ?? 'Impacto operacional registrado';
    return OperationalImpact(level: level, description: description);
  }

  static HealthTimelineAmendmentMetadata _parseAmendments(Object? raw) {
    if (raw == null || raw is! Map) return HealthTimelineAmendmentMetadata.none;
    final map = Map<String, dynamic>.from(raw);
    final hasAmendments = map['has_amendments'] == true;
    final countRaw = map['amendment_count'];
    final count = countRaw is int ? countRaw : 0;
    final lastAmendedAt = _parseTimestamp(map['last_amended_at']);
    if (!hasAmendments && count == 0) {
      return HealthTimelineAmendmentMetadata.none;
    }
    try {
      return HealthTimelineAmendmentMetadata(
        hasAmendments: hasAmendments,
        amendmentCount: count,
        lastAmendedAt: lastAmendedAt,
      );
    } catch (_) {
      return HealthTimelineAmendmentMetadata.none;
    }
  }
}
