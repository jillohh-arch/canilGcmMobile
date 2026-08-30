import '../domain/health_v1_models.dart';

import 'legacy_health_adapters.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LegacyDocumentAdapter — leitura defensiva de `documentos` (raiz).
// Fonte: `lib/features/dogs/data/dog_profile_service.dart` → DogDocument.
// Campos reais: id, caoId, nome, descricao, tipo, url, dataUpload, emissor.
// Comentário no modelo: tipo legado 'laudo' | 'certificado' | 'documento'
// — não são wireNames canônicos de HealthDocumentType.
//
// Política:
// - Sem aliases inventados;
// - Sem aceitar wireNames canônicos como “já migrado”;
// - Sem derivar storagePath de URL (sem regra formal no legado);
// - Sem inferir MIME por extensão;
// - Sem recorded_by → sempre LegacyHealthRecordView partial;
// - Códigos de issue: reutiliza `missing` e `no_recorded_by` existentes.
// ─────────────────────────────────────────────────────────────────────────────

final class LegacyDocumentAdapter {
  const LegacyDocumentAdapter();

  LegacyParseResult<Object> parse({
    required String sourceId,
    required String dogId,
    required Map<String, Object?> data,
  }) {
    final issues = <LegacyParseIssue>[];
    if (sourceId.trim().isEmpty) {
      issues.add(_error('missing', 'source_id', 'Identificador ausente'));
    }
    if (dogId.trim().isEmpty) {
      issues.add(_error('missing', 'dog_id', 'K9 ausente'));
    }

    final title = _nonEmptyString(data['nome']);
    if (title == null) {
      issues.add(_error('missing', 'title', 'Título ausente'));
    }

    final url = _nonEmptyString(data['url']);
    if (url == null) {
      issues.add(_error('missing', 'url', 'URL ausente'));
    }

    final uploadedAt = LegacyDateParser.parse(data['dataUpload']);
    if (!uploadedAt.hasValue) {
      final code = uploadedAt.issues.isNotEmpty
          ? uploadedAt.issues.first.code
          : 'missing';
      issues.add(
        _error(code, 'uploaded_at', 'Data de upload inválida ou ausente'),
      );
    }

    if (issues.isNotEmpty) return LegacyParseResult.failure(issues);

    // Preserva payload bruto (tipo, url, emissor, descricao, etc.).
    // Não promove a HealthDocument: falta recorded_by, storage_path, mime_type
    // canônicos e não há regra formal segura de derivação.
    final view = LegacyHealthRecordView(
      sourceId: sourceId,
      dogId: dogId,
      occurredAt: uploadedAt.value!,
      typeRaw: 'document',
      description: title ?? '',
      originalPayload: _withCanonicalDate(data, const [
        'dataUpload',
      ], uploadedAt.value!),
    );

    return LegacyParseResult.partial(view, const [
      LegacyParseIssue(
        code: 'no_recorded_by',
        field: 'recorded_by',
        severity: LegacyIssueSeverity.warning,
        message:
            'recorded_by ausente no schema legado; entidade canônica não produzida',
      ),
    ]);
  }
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

LegacyParseIssue _error(String code, String field, String message) =>
    LegacyParseIssue(
      code: code,
      field: field,
      severity: LegacyIssueSeverity.error,
      message: message,
    );

Map<String, Object?> _withCanonicalDate(
  Map<String, Object?> data,
  Iterable<String> candidateFields,
  DateTime parsed,
) {
  final copy = Map<String, Object?>.from(data);
  for (final field in candidateFields) {
    if (copy.containsKey(field)) {
      copy[field] = parsed;
      break;
    }
  }
  return copy;
}
