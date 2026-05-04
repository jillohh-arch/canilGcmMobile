import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Uuid _uuid = const Uuid();

  /// Faz o upload da foto e retorna a URL pública gerada pelo Storage
  Future<String?> uploadProfileImage(File file, String folder) async {
    return uploadFile(file, folder, mimeType: 'image/jpeg', extension: 'jpg');
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
        print("[StorageService] Aviso object-not-found (ignorado): ${e.message}");
        return null;
      }
      print("[StorageService] Erro Firebase: ${e.code} - ${e.message}");
      throw Exception('Falha ao subir arquivo: ${e.message}');
    } catch (e) {
      print("[StorageService] Erro genérico: $e");
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
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
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
        print("Aviso: Arquivo não encontrado no servidor. Ignorando...");
      } else {
        print("Erro ao deletar: ${e.message}");
      }
    } catch (e) {
      print("Erro genérico ao deletar: $e");
    }
  }
}
