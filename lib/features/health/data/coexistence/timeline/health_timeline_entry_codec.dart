import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';

/// Codec **mínimo** de [HealthTimelineEntryView] para residual no cursor.
///
/// Princípio de privacidade: o token de paginação **não** transporta PHI/clínico
/// desnecessário (observações, profissional, recordedBy, impacto operacional,
/// paths de anexo, traceability completa).
///
/// Campos retidos — apenas o necessário para:
/// - reemitir a entrada na página seguinte sem reconsulta;
/// - preservar ordenação (`occurredAt` + `id`);
/// - preservar tipo/status e referência de detalhe (ids).
abstract final class HealthTimelineEntryCodec {
  HealthTimelineEntryCodec._();

  /// Campos proibidos no residual serializado (assert de privacidade).
  static const forbiddenResidualKeys = <String>{
    'subtitle',
    'professional',
    'recordedBy',
    'operationalImpact',
    'caseTitle',
    'trace',
    'attachmentCount',
    'lastAmendedAtMs',
  };

  static Map<String, Object?> encode(HealthTimelineEntryView e) {
    return {
      'id': e.id,
      'dogId': e.dogId,
      'typeRaw': e.type.raw,
      'occurredAtMs': e.occurredAt.toUtc().millisecondsSinceEpoch,
      'recordedAtMs': e.recordedAt.toUtc().millisecondsSinceEpoch,
      // Título de lista é necessário para reemitir a linha sem reconsulta.
      // Não inclui observações clínicas (subtitle) nem identidade profissional.
      'title': e.title,
      'status': e.status.wireName,
      if (e.caseId != null) 'caseId': e.caseId,
      'hasAttachments': e.hasAttachments,
      'hasAmendments': e.amendments.hasAmendments,
      if (e.detailReference != null)
        'detail': {
          'sourceType': e.detailReference!.sourceType,
          'sourceId': e.detailReference!.sourceId,
          if (e.detailReference!.caseId != null)
            'caseId': e.detailReference!.caseId,
        },
    };
  }

  static HealthTimelineEntryView? tryDecode(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    try {
      final id = map['id']?.toString();
      final dogId = map['dogId']?.toString();
      final typeRaw = map['typeRaw']?.toString();
      final title = map['title']?.toString();
      final occurredMs = map['occurredAtMs'];
      final recordedMs = map['recordedAtMs'];
      if (id == null ||
          dogId == null ||
          typeRaw == null ||
          title == null ||
          occurredMs is! int ||
          recordedMs is! int) {
        return null;
      }

      final status =
          HealthTimelineEntryStatus.tryParse(map['status']) ??
          HealthTimelineEntryStatus.finalised;

      HealthTimelineDetailReference? detail;
      final d = map['detail'];
      if (d is Map) {
        final st = d['sourceType']?.toString() ?? '';
        final sid = d['sourceId']?.toString() ?? '';
        if (st.isNotEmpty && sid.isNotEmpty) {
          detail = HealthTimelineDetailReference(
            sourceType: st,
            sourceId: sid,
            caseId: d['caseId']?.toString(),
          );
        }
      }

      final hasAmendments = map['hasAmendments'] == true;

      return HealthTimelineEntryView(
        id: id,
        dogId: dogId,
        type: HealthTimelineTypeView.parse(typeRaw),
        occurredAt: DateTime.fromMillisecondsSinceEpoch(
          occurredMs,
          isUtc: true,
        ),
        recordedAt: DateTime.fromMillisecondsSinceEpoch(
          recordedMs,
          isUtc: true,
        ),
        title: title,
        // Campos clínicos/PHI deliberadamente omitidos do residual.
        subtitle: null,
        status: status,
        caseId: map['caseId']?.toString(),
        caseTitle: null,
        recordedBy: null,
        professional: null,
        operationalImpact: null,
        hasAttachments: map['hasAttachments'] == true,
        attachmentCount: null,
        amendments: HealthTimelineAmendmentMetadata(
          hasAmendments: hasAmendments,
          amendmentCount: hasAmendments ? 1 : 0,
        ),
        detailReference: detail,
        traceability: null,
      );
    } catch (_) {
      return null;
    }
  }
}
