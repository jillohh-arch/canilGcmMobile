import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../core/services/storage_service.dart';
import '../../domain/health_document_gateway.dart';
import '../../domain/health_evidence_file.dart';
import '../../domain/health_restriction_flow_errors.dart';

/// Lê os bytes do arquivo escolhido. Seam para teste sem I/O real.
typedef HealthEvidenceBytesReader =
    Future<Uint8List> Function(SelectedHealthEvidenceFile file);

/// Envia bytes para um path exato do Storage.
///
/// Seam de função em vez de injetar `StorageService`: aquela classe inicializa
/// `FirebaseStorage.instance` em campo, então nem um fake nem uma subclasse
/// podem ser construídos em unit test sem Firebase inicializado.
typedef HealthEvidenceBytesSink =
    Future<String?> Function(
      Uint8List bytes,
      String path, {
      String mimeType,
    });

Future<Uint8List> _readFromDisk(SelectedHealthEvidenceFile file) {
  return File(file.path).readAsBytes();
}

/// Uploader FAIL-CLOSED do arquivo de evidência no staging do B0.
///
/// Motivo de existir: `StorageService.uploadBytes` devolve `null` em
/// `object-not-found` — um sucesso aparente. Aqui isso vira erro duro, porque
/// prosseguir para o FINALIZE sem bytes no staging produziria falha de
/// integridade mais adiante, com diagnóstico pior.
///
/// Nunca devolve download URL: URL não é autoridade e não participa da
/// construção do `HealthDocumentRef`.
final class StorageHealthEvidenceUploader implements HealthEvidenceUploader {
  StorageHealthEvidenceUploader({
    HealthEvidenceBytesSink? sink,
    HealthEvidenceBytesReader? bytesReader,
  }) : _sinkOverride = sink,
       _readBytes = bytesReader ?? _readFromDisk;

  final HealthEvidenceBytesSink? _sinkOverride;
  final HealthEvidenceBytesReader _readBytes;
  HealthEvidenceBytesSink? _cachedSink;

  /// Resolvido tardiamente: em produção constrói `StorageService` só no
  /// primeiro upload, nunca durante a composição da tela.
  HealthEvidenceBytesSink get _sink {
    return _cachedSink ??= _sinkOverride ?? StorageService().uploadBytes;
  }

  @override
  Future<void> upload({
    required SelectedHealthEvidenceFile file,
    required String uploadPath,
  }) async {
    const step = HealthRestrictionFlowStep.documentUpload;

    if (uploadPath.trim().isEmpty) {
      // Path de staging só vem do PREPARE; vazio aqui é bug de orquestração.
      throw const HealthRestrictionFlowIntegrity(step);
    }

    final Uint8List bytes;
    try {
      bytes = await _readBytes(file);
    } catch (e) {
      debugPrint('[HealthEvidenceUploader] falha ao ler arquivo: $e');
      throw const HealthRestrictionFlowValidation(
        step,
        'Não foi possível ler o arquivo selecionado. '
        'Escolha o arquivo novamente.',
      );
    }

    if (bytes.isEmpty) {
      throw const HealthRestrictionFlowValidation(
        step,
        'O arquivo selecionado está vazio.',
      );
    }

    try {
      final result = await _sink(bytes, uploadPath, mimeType: file.mimeType);
      if (result == null) {
        // FAIL-CLOSED: null é falha, nunca sucesso silencioso.
        debugPrint(
          '[HealthEvidenceUploader] uploadBytes devolveu null para $uploadPath',
        );
        throw const HealthRestrictionFlowIntegrity(step);
      }
      // `result` é a download URL. Deliberadamente descartada.
    } on HealthRestrictionFlowFailure {
      rethrow;
    } catch (e) {
      debugPrint('[HealthEvidenceUploader] falha de upload: $e');
      throw const HealthRestrictionFlowOffline(step);
    }
  }
}
