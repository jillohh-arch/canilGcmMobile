import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

/// Resultado de upload com hash do binário para integridade.
class UploadResult {
  final String url;
  final String sha256Hash;

  const UploadResult({required this.url, required this.sha256Hash});
}

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Uuid _uuid = const Uuid();

  /// Faz upload de uma imagem JPEG e retorna a URL pública gerada pelo Storage.
  Future<String?> uploadImage(File file, String folder) async {
    return uploadFile(file, folder, mimeType: 'image/jpeg', extension: 'jpg');
  }

  /// Faz upload de uma imagem e retorna URL + SHA-256 do binário.
  /// Usado para fotos que precisam de verificação de integridade.
  Future<UploadResult?> uploadImageWithHash(File file, String folder) async {
    return uploadFileWithHash(
      file,
      folder,
      mimeType: 'image/jpeg',
      extension: 'jpg',
    );
  }

  /// Mantido para chamadas semânticas de foto de perfil.
  Future<String?> uploadProfileImage(File file, String folder) {
    return uploadImage(file, folder);
  }

  /// Método genérico de upload: suporta imagens, PDFs e qualquer arquivo.
  /// [mimeType] será inferido pela extensão se não informado.
  Future<String?> uploadFile(
    File file,
    String folder, {
    String? mimeType,
    String? extension,
  }) async {
    try {
      final String ext = extension ?? _extensionFromPath(file.path);
      final String resolvedMime = mimeType ?? _mimeTypeFromExtension(ext);
      final String fileName = '${_uuid.v4()}.$ext';

      final String cleanFolder = folder.replaceAll(RegExp(r'^/+|/+$'), '');
      final Reference ref = _storage.ref().child(cleanFolder).child(fileName);

      final bytes = await file.readAsBytes();
      final UploadTask uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: resolvedMime),
      );

      final TaskSnapshot snapshot = await uploadTask;

      if (snapshot.state == TaskState.success) {
        final String downloadUrl = await snapshot.ref.getDownloadURL();
        return downloadUrl;
      } else {
        throw Exception('O upload não foi concluído com sucesso.');
      }
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') {
        debugPrint(
          '[StorageService] Aviso object-not-found (ignorado): ${e.message}',
        );
        return null;
      }
      debugPrint('[StorageService] Erro Firebase: ${e.code} - ${e.message}');
      throw Exception('Falha ao subir arquivo: ${e.message}');
    } catch (e) {
      debugPrint('[StorageService] Erro genérico: $e');
      throw Exception('Falha ao subir arquivo. Verifique sua conexão.');
    }
  }

  /// Upload genérico que também retorna o SHA-256 do binário.
  /// Calcula o hash sobre os bytes que efetivamente vão para o Storage.
  Future<UploadResult?> uploadFileWithHash(
    File file,
    String folder, {
    String? mimeType,
    String? extension,
  }) async {
    try {
      final String ext = extension ?? _extensionFromPath(file.path);
      final String resolvedMime = mimeType ?? _mimeTypeFromExtension(ext);
      final String fileName = '${_uuid.v4()}.$ext';

      final String cleanFolder = folder.replaceAll(RegExp(r'^/+|/+$'), '');
      final Reference ref = _storage.ref().child(cleanFolder).child(fileName);

      final bytes = await file.readAsBytes();

      // Calcular SHA-256 do binário antes do upload
      final hash = sha256.convert(bytes).toString();

      final UploadTask uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: resolvedMime),
      );

      final TaskSnapshot snapshot = await uploadTask;

      if (snapshot.state == TaskState.success) {
        final String downloadUrl = await snapshot.ref.getDownloadURL();
        return UploadResult(url: downloadUrl, sha256Hash: hash);
      } else {
        throw Exception('O upload não foi concluído com sucesso.');
      }
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') {
        debugPrint(
          '[StorageService] Aviso object-not-found (ignorado): ${e.message}',
        );
        return null;
      }
      debugPrint('[StorageService] Erro Firebase: ${e.code} - ${e.message}');
      throw Exception('Falha ao subir arquivo: ${e.message}');
    } catch (e) {
      debugPrint('[StorageService] Erro genérico: $e');
      throw Exception('Falha ao subir arquivo. Verifique sua conexão.');
    }
  }

  /// Faz upload de bytes para um caminho fixo no Storage.
  /// Usado para documentos institucionais que precisam de caminho estavel.
  Future<String?> uploadBytes(
    Uint8List bytes,
    String path, {
    String mimeType = 'application/octet-stream',
  }) async {
    try {
      final cleanPath = path.replaceAll(RegExp(r'^/+|/+$'), '');
      final Reference ref = _storage.ref().child(cleanPath);
      final UploadTask uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: mimeType),
      );

      final TaskSnapshot snapshot = await uploadTask;
      if (snapshot.state == TaskState.success) {
        return snapshot.ref.getDownloadURL();
      }
      throw Exception('O upload não foi concluído com sucesso.');
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') {
        debugPrint(
          '[StorageService] Aviso object-not-found (ignorado): ${e.message}',
        );
        return null;
      }
      debugPrint('[StorageService] Erro Firebase: ${e.code} - ${e.message}');
      throw Exception('Falha ao subir arquivo: ${e.message}');
    } catch (e) {
      debugPrint('[StorageService] Erro genérico: $e');
      throw Exception('Falha ao subir arquivo. Verifique sua conexão.');
    }
  }

  String _extensionFromPath(String path) {
    final parts = path.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : 'bin';
  }

  String _mimeTypeFromExtension(String ext) {
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  /// Exclui um arquivo baseado na URL pública.
  Future<void> deleteImageFromUrl(String imageUrl) async {
    if (imageUrl.isEmpty || !imageUrl.startsWith('http')) return;
    try {
      final Reference ref = _storage.refFromURL(imageUrl);
      await ref.delete();
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') {
        debugPrint(
          '[StorageService] Aviso: Arquivo não encontrado no servidor. Ignorando...',
        );
      } else {
        debugPrint('[StorageService] Erro ao deletar: ${e.message}');
      }
    } catch (e) {
      debugPrint('[StorageService] Erro genérico ao deletar: $e');
    }
  }
}
