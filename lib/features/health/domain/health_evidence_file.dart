/// Arquivo de evidência documental selecionado pelo operador (B3).
///
/// Validação preventiva de UX: extensão, tamanho e MIME são checados ANTES de
/// qualquer PREPARE/upload, para não gastar rede com um arquivo que o backend
/// e as Storage Rules rejeitariam de todo modo.
///
/// Autoridade final continua sendo backend + Rules — esta camada só evita a
/// viagem inútil e dá mensagem melhor ao operador.
library;

/// Extensões suportadas pela UI, mapeadas para o MIME que o B0 aceita.
///
/// Whitelist deliberadamente pequena e explícita em vez de um pacote de
/// lookup: o conjunto é conhecido, estável e precisa casar exatamente com
/// `isAllowedContentType` do backend (image/*, PDF, Word).
const Map<String, String> kHealthEvidenceMimeByExtension = <String, String>{
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
};

/// Extensões oferecidas ao seletor de arquivos.
const List<String> kHealthEvidenceAllowedExtensions = <String>[
  'pdf',
  'jpg',
  'jpeg',
  'png',
  'webp',
  'doc',
  'docx',
];

/// Limite alinhado a `MAX_DOCUMENT_BYTES` do backend.
const int kHealthEvidenceMaxBytes = 20 * 1024 * 1024;

/// Motivo de recusa de um arquivo, para a UI traduzir sem expor detalhe técnico.
enum HealthEvidenceFileRejection {
  unsupportedExtension,
  empty,
  tooLarge,
  unreadable,
}

/// Natureza clínica do documento — distinta do tipo de arquivo.
///
/// Um PDF pode ser atestado ou laudo; a extensão não determina a natureza.
/// Mapeia para `HEALTH_DOCUMENT_TYPES` do backend; `restriction_evidence` NÃO
/// existe por decisão B0-A.2.
enum HealthEvidenceNature {
  certificate,
  report,
  other;

  String get wireName => switch (this) {
    HealthEvidenceNature.certificate => 'certificate',
    HealthEvidenceNature.report => 'report',
    HealthEvidenceNature.other => 'other',
  };

  String get label => switch (this) {
    HealthEvidenceNature.certificate => 'Atestado',
    HealthEvidenceNature.report => 'Laudo / Relatório',
    HealthEvidenceNature.other => 'Outro documento',
  };
}

/// Resultado da validação de um arquivo escolhido.
sealed class HealthEvidenceFileResult {
  const HealthEvidenceFileResult();
}

final class HealthEvidenceFileAccepted extends HealthEvidenceFileResult {
  const HealthEvidenceFileAccepted(this.file);

  final SelectedHealthEvidenceFile file;
}

final class HealthEvidenceFileRejected extends HealthEvidenceFileResult {
  const HealthEvidenceFileRejected(this.reason);

  final HealthEvidenceFileRejection reason;
}

/// Arquivo aceito, pronto para upload.
///
/// Carrega somente o que a orquestração precisa. Deliberadamente NÃO carrega
/// `downloadUrl`, path canônico, generation nem metadata de selo — nada disso
/// é autoridade do cliente.
final class SelectedHealthEvidenceFile {
  const SelectedHealthEvidenceFile({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.mimeType,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final String mimeType;

  /// Identidade local estável: usada para detectar troca de arquivo entre
  /// tentativas e invalidar a intenção documental.
  String get localIdentity => '$name|$sizeBytes|$mimeType';

  @override
  bool operator ==(Object other) =>
      other is SelectedHealthEvidenceFile &&
      other.name == name &&
      other.path == path &&
      other.sizeBytes == sizeBytes &&
      other.mimeType == mimeType;

  @override
  int get hashCode => Object.hash(name, path, sizeBytes, mimeType);
}

/// Extensão normalizada (sem ponto, minúscula) de um nome de arquivo.
String? healthEvidenceExtensionOf(String fileName) {
  final trimmed = fileName.trim();
  final dot = trimmed.lastIndexOf('.');
  if (dot < 0 || dot == trimmed.length - 1) return null;
  final ext = trimmed.substring(dot + 1).toLowerCase();
  return ext.isEmpty ? null : ext;
}

/// MIME explícito a partir da extensão. `null` quando não suportado.
String? healthEvidenceMimeFor(String fileName) {
  final ext = healthEvidenceExtensionOf(fileName);
  if (ext == null) return null;
  return kHealthEvidenceMimeByExtension[ext];
}

/// Valida um arquivo escolhido, sem ler bytes.
///
/// `size` vem do picker (`PlatformFile.size`), então a checagem de limite
/// acontece antes de materializar o conteúdo em memória.
HealthEvidenceFileResult validateHealthEvidenceFile({
  required String name,
  required String? path,
  required int size,
}) {
  final mime = healthEvidenceMimeFor(name);
  if (mime == null) {
    return const HealthEvidenceFileRejected(
      HealthEvidenceFileRejection.unsupportedExtension,
    );
  }
  if (size <= 0) {
    return const HealthEvidenceFileRejected(HealthEvidenceFileRejection.empty);
  }
  if (size > kHealthEvidenceMaxBytes) {
    return const HealthEvidenceFileRejected(
      HealthEvidenceFileRejection.tooLarge,
    );
  }
  final resolvedPath = path?.trim() ?? '';
  if (resolvedPath.isEmpty) {
    return const HealthEvidenceFileRejected(
      HealthEvidenceFileRejection.unreadable,
    );
  }
  return HealthEvidenceFileAccepted(
    SelectedHealthEvidenceFile(
      name: name.trim(),
      path: resolvedPath,
      sizeBytes: size,
      mimeType: mime,
    ),
  );
}
