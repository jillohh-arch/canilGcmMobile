import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:canil_gcm/core/services/storage_service.dart';
import 'package:canil_gcm/features/occurrences/domain/upload_cancellation_token.dart';
import 'package:canil_gcm/features/occurrences/domain/upload_failure_classifier.dart';
import 'package:canil_gcm/features/occurrences/domain/upload_orphan_tracker.dart';
import 'package:canil_gcm/features/occurrences/domain/upload_progress_aggregator.dart';

/// Status do ciclo de vida de cada mídia individual no lote.
enum MediaUploadItemStatus {
  pending,
  uploading,
  retrying,
  completed,
  failed,
  cancelled,
}

/// Representa o estado e resultado de uma mídia individual no lote de upload.
class MediaUploadItem {
  final int index;
  final File file;
  final String contentHash;
  final int fileSize;
  MediaUploadItemStatus status;
  UploadResult? result;
  Object? error;
  int retryAttempts;

  MediaUploadItem({
    required this.index,
    required this.file,
    required this.contentHash,
    required this.fileSize,
    this.status = MediaUploadItemStatus.pending,
    this.result,
    this.error,
    this.retryAttempts = 0,
  });

  bool get isCompleted => status == MediaUploadItemStatus.completed;
  bool get isFailed => status == MediaUploadItemStatus.failed;
  bool get isCancelled => status == MediaUploadItemStatus.cancelled;
}

/// Resultado consolidado de uma tentativa de upload de lote de mídias.
class OccurrenceMediaUploadBatchResult {
  final bool isSuccess;
  final bool isCancelled;
  final List<UploadResult> completedResults;
  final List<MediaUploadItem> items;
  final Object? firstError;
  final String? friendlyErrorMessage;

  const OccurrenceMediaUploadBatchResult({
    required this.isSuccess,
    required this.isCancelled,
    required this.completedResults,
    required this.items,
    this.firstError,
    this.friendlyErrorMessage,
  });

  int get totalFiles => items.length;
  int get completedCount => items.where((item) => item.isCompleted).length;
}

/// Assinatura funcional para injeção e teste determinístico do uploader de arquivo individual.
typedef SingleFileUploader =
    Future<UploadResult?> Function(
      File file,
      String folder, {
      String? customFileName,
      UploadCancellationToken? cancelToken,
      void Function(int bytesTransferred, int totalBytes)? onProgress,
    });

/// Orquestrador resiliente de upload de mídias para ocorrências.
///
/// Implementa os 4 pilares contratuais de UPLOAD-ROBUSTNESS-01:
/// 1. Idempotência: Nomeação determinística baseada no hash SHA-256 do conteúdo + skip de mídias já enviadas.
/// 2. Retry Bounded: Separação estrita entre falhas recuperáveis e permanentes, com auto-retry limitado.
/// 3. Timeout & Cancelamento: Interrupção cooperativa via [UploadCancellationToken] sem tarefas zumbis.
/// 4. Orphan Handling: Rastreamento local seguro via [UploadOrphanTracker] sem deleção remota cega.
/// 5. Preservação FF-OCC-02: Cálculo fiel e ponderado de bytes via [UploadProgressAggregator].
class OccurrenceMediaUploader {
  final SingleFileUploader _uploader;
  final UploadOrphanTracker _orphanTracker;

  OccurrenceMediaUploader({
    StorageService? storageService,
    SingleFileUploader? customUploader,
    UploadOrphanTracker? orphanTracker,
  }) : _uploader =
           customUploader ??
           (storageService ?? StorageService()).uploadImageWithHash,
       _orphanTracker = orphanTracker ?? UploadOrphanTracker();

  /// Executa o upload sequencial resiliente de uma lista de [files].
  ///
  /// - [alreadyCompleted]: Mapeamento de resultados prévios (chave = hash ou path) para pular re-upload.
  /// - [onProgress]: Callback com o snapshot de progresso agregado real em bytes.
  /// - [onStatusChanged]: Notificação de transição de fase textual da UI.
  /// - [maxAutoRetries]: Quantidade máxima de auto-tentativas para erros transitórios (padrão: 1).
  Future<OccurrenceMediaUploadBatchResult> uploadBatch({
    required List<File> files,
    required String folder,
    required String occurrenceId,
    UploadCancellationToken? cancelToken,
    Map<String, UploadResult>? alreadyCompleted,
    void Function(
      int fileIndex,
      int totalFiles,
      UploadProgressSnapshot progress,
    )?
    onProgress,
    void Function(int fileIndex, int totalFiles, String statusMessage)?
    onStatusChanged,
    int maxAutoRetries = 1,
    Duration retryDelay = const Duration(milliseconds: 600),
  }) async {
    if (files.isEmpty) {
      return const OccurrenceMediaUploadBatchResult(
        isSuccess: true,
        isCancelled: false,
        completedResults: [],
        items: [],
      );
    }

    if (cancelToken?.isCancelled == true) {
      return OccurrenceMediaUploadBatchResult(
        isSuccess: false,
        isCancelled: true,
        completedResults: const [],
        items: const [],
        friendlyErrorMessage: 'Upload cancelado antes de iniciar.',
      );
    }

    // Fase 1: Pré-validação física e cálculo determinístico dos hashes dos binários
    final items = <MediaUploadItem>[];
    final fileSizes = <int>[];

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      if (!file.existsSync()) {
        final err = FileSystemException(
          'Arquivo não encontrado no dispositivo',
          file.path,
        );
        final item = MediaUploadItem(
          index: i,
          file: file,
          contentHash: '',
          fileSize: 0,
          status: MediaUploadItemStatus.failed,
          error: err,
        );
        items.add(item);
        return OccurrenceMediaUploadBatchResult(
          isSuccess: false,
          isCancelled: false,
          completedResults: const [],
          items: items,
          firstError: err,
          friendlyErrorMessage: UploadFailureClassifier.getFriendlyMessage(err),
        );
      }

      int length = 0;
      String hash = '';
      try {
        final bytes = await file.readAsBytes();
        length = bytes.length;
        hash = sha256.convert(bytes).toString();
      } catch (e) {
        final item = MediaUploadItem(
          index: i,
          file: file,
          contentHash: '',
          fileSize: 0,
          status: MediaUploadItemStatus.failed,
          error: e,
        );
        items.add(item);
        return OccurrenceMediaUploadBatchResult(
          isSuccess: false,
          isCancelled: false,
          completedResults: const [],
          items: items,
          firstError: e,
          friendlyErrorMessage: UploadFailureClassifier.getFriendlyMessage(e),
        );
      }

      fileSizes.add(length);
      items.add(
        MediaUploadItem(
          index: i,
          file: file,
          contentHash: hash,
          fileSize: length,
        ),
      );
    }

    // Fase 2: Configuração do agregador FF-OCC-02
    final aggregator = UploadProgressAggregator(fileSizes);

    // Fase 3: Idempotência de Sessão — reconciliar itens já comitados em tentativa prévia
    final completedResults = <UploadResult>[];
    if (alreadyCompleted != null && alreadyCompleted.isNotEmpty) {
      for (final item in items) {
        final existing =
            alreadyCompleted[item.contentHash] ??
            alreadyCompleted[item.file.path];
        if (existing != null) {
          item.result = existing;
          item.status = MediaUploadItemStatus.completed;
          aggregator.completeFile(item.index);
          completedResults.add(existing);
        }
      }
    }

    // Notificar progresso inicial (pode já incluir arquivos pulados)
    onProgress?.call(0, files.length, aggregator.current);

    // Fase 4: Execução sequencial resiliente
    for (var i = 0; i < items.length; i++) {
      final item = items[i];

      // Pular arquivo se já concluído na sessão
      if (item.isCompleted) {
        continue;
      }

      if (cancelToken?.isCancelled == true) {
        item.status = MediaUploadItemStatus.cancelled;
        _markRemainingCancelled(items, i + 1);
        return OccurrenceMediaUploadBatchResult(
          isSuccess: false,
          isCancelled: true,
          completedResults: completedResults,
          items: items,
          friendlyErrorMessage: 'Upload cancelado pelo usuário.',
        );
      }

      final startSnap = aggregator.startFile(i);
      item.status = MediaUploadItemStatus.uploading;
      onProgress?.call(i, files.length, startSnap);

      final ext = _extensionFromPath(item.file.path);
      final deterministicName = '${item.contentHash}.$ext';

      int attempts = 0;
      bool itemSuccess = false;

      while (attempts <= maxAutoRetries && !itemSuccess) {
        if (cancelToken?.isCancelled == true) {
          item.status = MediaUploadItemStatus.cancelled;
          break;
        }

        try {
          final result = await _uploader(
            item.file,
            folder,
            customFileName: deterministicName,
            cancelToken: cancelToken,
            onProgress: (transferred, total) {
              if (cancelToken?.isCancelled == true) return;
              final snap = aggregator.updateFileProgress(i, transferred);
              onProgress?.call(i, files.length, snap);
            },
          );

          if (result != null) {
            item.result = result;
            item.status = MediaUploadItemStatus.completed;
            aggregator.completeFile(i);
            completedResults.add(result);
            _orphanTracker.trackCandidate(
              occurrenceId: occurrenceId,
              url: result.url,
              hash: result.sha256Hash,
              storagePath: '$folder/$deterministicName',
            );
            itemSuccess = true;
          } else {
            throw StateError('O serviço de upload retornou resultado nulo.');
          }
        } catch (e) {
          if (cancelToken?.isCancelled == true ||
              UploadFailureClassifier.isCancelled(e)) {
            item.status = MediaUploadItemStatus.cancelled;
            break;
          }

          final isRecoverable = UploadFailureClassifier.isRecoverable(e);
          attempts++;
          item.retryAttempts = attempts;

          if (isRecoverable && attempts <= maxAutoRetries) {
            item.status = MediaUploadItemStatus.retrying;
            onStatusChanged?.call(i, files.length, 'Reconectando...');
            await Future.delayed(retryDelay);
            continue;
          } else {
            item.status = MediaUploadItemStatus.failed;
            item.error = e;
            break;
          }
        }
      }

      // Se este item não concluiu com sucesso (falhou ou foi cancelado), abortamos o lote
      if (!itemSuccess) {
        final isCancelled =
            item.isCancelled || cancelToken?.isCancelled == true;
        _markRemainingCancelled(items, i + 1);

        return OccurrenceMediaUploadBatchResult(
          isSuccess: false,
          isCancelled: isCancelled,
          completedResults: completedResults,
          items: items,
          firstError: item.error,
          friendlyErrorMessage: isCancelled
              ? 'Upload cancelado pelo usuário.'
              : UploadFailureClassifier.getFriendlyMessage(
                  item.error ?? 'Erro desconhecido',
                ),
        );
      }
    }

    return OccurrenceMediaUploadBatchResult(
      isSuccess: true,
      isCancelled: false,
      completedResults: completedResults,
      items: items,
    );
  }

  void _markRemainingCancelled(List<MediaUploadItem> items, int startIndex) {
    for (var j = startIndex; j < items.length; j++) {
      if (items[j].status == MediaUploadItemStatus.pending) {
        items[j].status = MediaUploadItemStatus.cancelled;
      }
    }
  }

  String _extensionFromPath(String path) {
    final parts = path.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : 'jpg';
  }
}
