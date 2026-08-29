/// Boundary neutra de seleção de evidência documental.
///
/// Existe para que emissão (B3) e encerramento (B4-C.3) compartilhem UM seam de
/// picker e UM mapeamento de rejeição sem que uma tela importe a outra.
///
/// Antes desta boundary, `health_restriction_end_form_screen.dart` e
/// `health_restriction_detail_screen.dart` importavam
/// `health_restriction_form_screen.dart` apenas para alcançar estes helpers —
/// um acoplamento screen→screen que não descreve nenhuma dependência real de
/// domínio. ISSUE e END são verticais irmãs, não pai e filho.
///
/// ## O que esta boundary deliberadamente não contém
///
/// - nenhum widget;
/// - nenhum controller;
/// - nenhuma regra de restrição (nível, categoria, motivo, profissional);
/// - nenhuma segunda whitelist de MIME e nenhum segundo limite de 20 MB — a
///   autoridade continua sendo `domain/health_evidence_file.dart`.
library;

import 'package:file_picker/file_picker.dart';

import '../../../domain/health_evidence_file.dart';

/// Seam do seletor de arquivos: mantém o picker fora da lógica de negócio e
/// permite teste de widget sem plugin de plataforma.
///
/// `null` significa cancelamento — não é erro.
typedef HealthEvidencePicker = Future<HealthEvidenceFileResult?> Function();

/// Mensagem operacional de rejeição de arquivo.
///
/// Um único texto por motivo técnico: duplicar o mapeamento faria emissão e
/// encerramento divergirem no primeiro ajuste de cópia.
String healthEvidenceRejectionMessage(HealthEvidenceFileRejection reason) {
  return switch (reason) {
    HealthEvidenceFileRejection.unsupportedExtension =>
      'Formato não suportado. Envie PDF, imagem (JPG, PNG, WEBP) '
          'ou documento Word.',
    HealthEvidenceFileRejection.empty => 'O arquivo selecionado está vazio.',
    HealthEvidenceFileRejection.tooLarge =>
      'O arquivo excede 20 MB. Envie um arquivo menor.',
    HealthEvidenceFileRejection.unreadable =>
      'Não foi possível acessar o arquivo escolhido. Selecione novamente.',
  };
}

/// Picker real de evidência, compartilhado por emissão e encerramento.
///
/// A validação preventiva (extensão, tamanho, MIME) vive em
/// [validateHealthEvidenceFile]; aqui só há a ponte com o plugin.
Future<HealthEvidenceFileResult?> defaultPickHealthEvidence() async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: kHealthEvidenceAllowedExtensions,
    allowMultiple: false,
  );
  if (picked == null || picked.files.isEmpty) return null;
  final file = picked.files.single;
  // `size` vem do picker: valida antes de materializar bytes em memória.
  return validateHealthEvidenceFile(
    name: file.name,
    path: file.path,
    size: file.size,
  );
}
