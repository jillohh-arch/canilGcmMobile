import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:canil_gcm/core/services/storage_service.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_media_uploader.dart';
import 'package:canil_gcm/features/occurrences/domain/upload_cancellation_token.dart';
import 'package:canil_gcm/features/occurrences/domain/upload_failure_classifier.dart';
import 'package:canil_gcm/features/occurrences/domain/upload_orphan_tracker.dart';

void main() {
  late Directory tempDir;
  late UploadOrphanTracker orphanTracker;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('upload_test_');
    orphanTracker = UploadOrphanTracker.isolated();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  File createTestFile(String name, List<int> bytes) {
    final file = File('${tempDir.path}/$name');
    file.writeAsBytesSync(bytes);
    return file;
  }

  group('OccurrenceMediaUploader — UPLOAD-ROBUSTNESS-01 Regression Suite', () {
    test(
      '1. Retry apos erro transitorio: recupera na segunda tentativa com auto-retry',
      () async {
        final file = createTestFile('photo1.jpg', [1, 2, 3, 4, 5]);
        int calls = 0;

        final uploader = OccurrenceMediaUploader(
          customUploader:
              (file, folder, {customFileName, cancelToken, onProgress}) async {
                calls++;
                if (calls == 1) {
                  throw const SocketException('Falha temporária de rede');
                }
                return const UploadResult(
                  url: 'https://storage/photo1.jpg',
                  sha256Hash: 'hash1',
                );
              },
          orphanTracker: orphanTracker,
        );

        final result = await uploader.uploadBatch(
          files: [file],
          folder: 'occurrences/occ-1/events',
          occurrenceId: 'occ-1',
          maxAutoRetries: 1,
          retryDelay: const Duration(milliseconds: 10),
        );

        expect(result.isSuccess, isTrue);
        expect(result.isCancelled, isFalse);
        expect(result.completedResults.length, 1);
        expect(result.items.first.retryAttempts, 1);
        expect(result.items.first.status, MediaUploadItemStatus.completed);
        expect(calls, 2);
      },
    );

    test(
      '2. Erro permanente: aborta imediatamente sem retry desnecessario',
      () async {
        final file = createTestFile('photo2.jpg', [10, 20, 30]);
        int calls = 0;

        final uploader = OccurrenceMediaUploader(
          customUploader:
              (file, folder, {customFileName, cancelToken, onProgress}) async {
                calls++;
                throw FirebaseException(
                  plugin: 'storage',
                  code: 'permission-denied',
                  message: 'Sem permissão',
                );
              },
          orphanTracker: orphanTracker,
        );

        final result = await uploader.uploadBatch(
          files: [file],
          folder: 'occurrences/occ-2/events',
          occurrenceId: 'occ-2',
          maxAutoRetries: 3,
        );

        expect(result.isSuccess, isFalse);
        expect(result.isCancelled, isFalse);
        expect(result.items.first.status, MediaUploadItemStatus.failed);
        expect(
          calls,
          1,
          reason: 'Erro permanente nunca deve gastar retries em campo',
        );
        expect(result.friendlyErrorMessage, contains('Permissão negada'));
      },
    );

    test(
      '3. Idempotencia de Storage: usa nome deterministico baseado no hash SHA-256',
      () async {
        final file = createTestFile('photo3.jpg', [100, 101, 102]);
        String? capturedFileName;

        final uploader = OccurrenceMediaUploader(
          customUploader:
              (file, folder, {customFileName, cancelToken, onProgress}) async {
                capturedFileName = customFileName;
                return const UploadResult(
                  url: 'https://storage/photo3.jpg',
                  sha256Hash: 'dummy',
                );
              },
          orphanTracker: orphanTracker,
        );

        final result = await uploader.uploadBatch(
          files: [file],
          folder: 'occurrences/occ-3/finalization',
          occurrenceId: 'occ-3',
        );

        expect(result.isSuccess, isTrue);
        expect(capturedFileName, isNotNull);
        expect(capturedFileName, endsWith('.jpg'));
        // O hash sha256 dos bytes [100, 101, 102] deve ser o prefixo do arquivo
        expect(
          capturedFileName,
          equals('${result.items.first.contentHash}.jpg'),
        );
      },
    );

    test(
      '4. Primeira midia passa / segunda falha: resultado parcial preservado',
      () async {
        final file1 = createTestFile('f1.jpg', [1, 1, 1]);
        final file2 = createTestFile('f2.jpg', [2, 2, 2]);
        int callCount = 0;

        final uploader = OccurrenceMediaUploader(
          customUploader:
              (file, folder, {customFileName, cancelToken, onProgress}) async {
                callCount++;
                if (callCount == 1) {
                  return const UploadResult(
                    url: 'https://storage/f1.jpg',
                    sha256Hash: 'hash_f1',
                  );
                }
                throw TimeoutException('Tempo esgotado');
              },
          orphanTracker: orphanTracker,
        );

        final result = await uploader.uploadBatch(
          files: [file1, file2],
          folder: 'occurrences/occ-4/events',
          occurrenceId: 'occ-4',
          maxAutoRetries: 0,
        );

        expect(result.isSuccess, isFalse);
        expect(result.completedResults.length, 1);
        expect(result.completedResults.first.url, 'https://storage/f1.jpg');
        expect(result.items[0].status, MediaUploadItemStatus.completed);
        expect(result.items[1].status, MediaUploadItemStatus.failed);
      },
    );

    test(
      '5. Retry da segunda midia NAO reenvia a primeira (Skip de completados)',
      () async {
        final file1 = createTestFile('f1.jpg', [1, 1, 1]);
        final file2 = createTestFile('f2.jpg', [2, 2, 2]);

        final uploadedFiles = <String>[];

        final uploader = OccurrenceMediaUploader(
          customUploader:
              (file, folder, {customFileName, cancelToken, onProgress}) async {
                uploadedFiles.add(file.path);
                return UploadResult(
                  url: 'https://storage/${file.path.split('/').last}',
                  sha256Hash: 'hash_${file.path}',
                );
              },
          orphanTracker: orphanTracker,
        );

        // Simula que f1 já foi completado na tentativa anterior
        final alreadyCompleted = <String, UploadResult>{
          file1.path: const UploadResult(
            url: 'https://storage/f1.jpg',
            sha256Hash: 'hash_f1',
          ),
        };

        final result = await uploader.uploadBatch(
          files: [file1, file2],
          folder: 'occurrences/occ-5/events',
          occurrenceId: 'occ-5',
          alreadyCompleted: alreadyCompleted,
        );

        expect(result.isSuccess, isTrue);
        expect(result.completedResults.length, 2);
        expect(uploadedFiles.length, 1);
        expect(
          uploadedFiles.first,
          equals(file2.path),
          reason: 'f1 não deve ser reenviado no retry',
        );
      },
    );

    test(
      '6. Preservacao de progresso verdadeiro (FF-OCC-02) ao pular item ja concluido',
      () async {
        final file1 = createTestFile('f1.jpg', List.filled(1000, 1));
        final file2 = createTestFile('f2.jpg', List.filled(3000, 2));

        final progressSnapshots = <double?>[];

        final uploader = OccurrenceMediaUploader(
          customUploader:
              (file, folder, {customFileName, cancelToken, onProgress}) async {
                onProgress?.call(1500, 3000);
                onProgress?.call(3000, 3000);
                return const UploadResult(
                  url: 'https://storage/f2.jpg',
                  sha256Hash: 'h2',
                );
              },
          orphanTracker: orphanTracker,
        );

        // file1 já está completado (1000 de 4000 bytes totais = 25%)
        final alreadyCompleted = <String, UploadResult>{
          file1.path: const UploadResult(
            url: 'https://storage/f1.jpg',
            sha256Hash: 'h1',
          ),
        };

        final result = await uploader.uploadBatch(
          files: [file1, file2],
          folder: 'occurrences/occ-6/events',
          occurrenceId: 'occ-6',
          alreadyCompleted: alreadyCompleted,
          onProgress: (fileIndex, totalFiles, snapshot) {
            progressSnapshots.add(snapshot.fraction);
          },
        );

        expect(result.isSuccess, isTrue);
        // O progresso inicial com file1 completado deve ser exatamente 1000/4000 = 0.25!
        expect(progressSnapshots.first, closeTo(0.25, 0.001));
        // E progride monotonicamente até 1.0
        expect(progressSnapshots.last, closeTo(1.0, 0.001));
      },
    );

    test(
      '7. Cancelamento cooperativo com token: interrompe lote e marca cancelled',
      () async {
        final file1 = createTestFile('f1.jpg', [1]);
        final file2 = createTestFile('f2.jpg', [2]);
        final token = UploadCancellationToken();

        final uploader = OccurrenceMediaUploader(
          customUploader:
              (file, folder, {customFileName, cancelToken, onProgress}) async {
                if (file.path.contains('f1.jpg')) {
                  return const UploadResult(
                    url: 'https://storage/f1.jpg',
                    sha256Hash: 'h1',
                  );
                }
                // Durante f2, cancelamos o token
                token.cancel();
                throw const UploadCancelledException();
              },
          orphanTracker: orphanTracker,
        );

        final result = await uploader.uploadBatch(
          files: [file1, file2],
          folder: 'occurrences/occ-7/events',
          occurrenceId: 'occ-7',
          cancelToken: token,
        );

        expect(result.isSuccess, isFalse);
        expect(result.isCancelled, isTrue);
        expect(result.items[0].status, MediaUploadItemStatus.completed);
        expect(result.items[1].status, MediaUploadItemStatus.cancelled);
        expect(result.friendlyErrorMessage, contains('cancelado'));
      },
    );

    test(
      '8. Orphan Tracker: registra candidatos pendentes e comita com sucesso',
      () async {
        final file = createTestFile('orphan_test.jpg', [55, 66]);

        final uploader = OccurrenceMediaUploader(
          customUploader:
              (file, folder, {customFileName, cancelToken, onProgress}) async {
                return const UploadResult(
                  url: 'https://storage/orphan.jpg',
                  sha256Hash: 'hash_orphan',
                );
              },
          orphanTracker: orphanTracker,
        );

        // Executa upload
        final result = await uploader.uploadBatch(
          files: [file],
          folder: 'occurrences/occ-8/finalization',
          occurrenceId: 'occ-8',
        );

        expect(result.isSuccess, isTrue);

        // Antes do commit na ocorrência, a URL é candidata a órfão
        final candidates = orphanTracker.getOrphanCandidates('occ-8');
        expect(candidates.length, 1);
        expect(candidates.first.url, 'https://storage/orphan.jpg');
        expect(
          orphanTracker.isCommitted('https://storage/orphan.jpg'),
          isFalse,
        );

        // Ao comitar a ocorrência com sucesso no Firestore:
        orphanTracker.commit('occ-8');
        expect(orphanTracker.getOrphanCandidates('occ-8'), isEmpty);
        expect(orphanTracker.isCommitted('https://storage/orphan.jpg'), isTrue);
      },
    );

    test(
      '9. Arquivo inexistente: erro permanente pre-flight sem tentar upload',
      () async {
        final missingFile = File('${tempDir.path}/nao_existe.jpg');
        int uploaderCalls = 0;

        final uploader = OccurrenceMediaUploader(
          customUploader:
              (file, folder, {customFileName, cancelToken, onProgress}) async {
                uploaderCalls++;
                return null;
              },
          orphanTracker: orphanTracker,
        );

        final result = await uploader.uploadBatch(
          files: [missingFile],
          folder: 'occurrences/occ-9/events',
          occurrenceId: 'occ-9',
        );

        expect(result.isSuccess, isFalse);
        expect(
          uploaderCalls,
          0,
          reason: 'Não deve chamar uploader para arquivo inexistente',
        );
        expect(result.items.first.status, MediaUploadItemStatus.failed);
        expect(result.firstError, isA<FileSystemException>());
      },
    );

    test('10. UploadFailureClassifier categoriza corretamente as falhas', () {
      expect(
        UploadFailureClassifier.classify(const SocketException('no net')),
        UploadFailureType.recoverable,
      );
      expect(
        UploadFailureClassifier.classify(TimeoutException('timeout')),
        UploadFailureType.timeout,
      );
      expect(
        UploadFailureClassifier.classify(
          FirebaseException(plugin: 'storage', code: 'permission-denied'),
        ),
        UploadFailureType.permanent,
      );
      expect(
        UploadFailureClassifier.classify(const UploadCancelledException()),
        UploadFailureType.cancelled,
      );
      expect(
        UploadFailureClassifier.classify(
          FirebaseException(plugin: 'storage', code: 'network-request-failed'),
        ),
        UploadFailureType.recoverable,
      );
    });

    test(
      '11. Nomenclatura deterministica: passa customFileName baseado no hash do conteudo',
      () async {
        final bytes = [100, 101, 102];
        final file = createTestFile('evidence.jpg', bytes);
        String? capturedCustomFileName;

        final uploader = OccurrenceMediaUploader(
          customUploader:
              (file, folder, {customFileName, cancelToken, onProgress}) async {
                capturedCustomFileName = customFileName;
                return UploadResult(
                  url: 'https://storage/$customFileName',
                  sha256Hash: 'dummy-hash',
                );
              },
          orphanTracker: orphanTracker,
        );

        final result = await uploader.uploadBatch(
          files: [file],
          folder: 'occurrences/occ-11/events',
          occurrenceId: 'occ-11',
        );

        expect(result.isSuccess, isTrue);
        expect(capturedCustomFileName, isNotNull);
        expect(capturedCustomFileName, endsWith('.jpg'));
        expect(
          capturedCustomFileName,
          equals('${result.items.first.contentHash}.jpg'),
        );
      },
    );
  });
}
