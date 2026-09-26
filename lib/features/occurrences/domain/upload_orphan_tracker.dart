import 'package:flutter/foundation.dart';

/// Registro local de uma mídia enviada ao Storage como candidata a vínculo com ocorrência.
class UploadOrphanCandidate {
  final String occurrenceId;
  final String url;
  final String hash;
  final String? storagePath;
  final DateTime uploadedAt;

  const UploadOrphanCandidate({
    required this.occurrenceId,
    required this.url,
    required this.hash,
    this.storagePath,
    required this.uploadedAt,
  });
}

/// Rastreador em memória de blobs remotos enviados que aguardam confirmação de vínculo
/// na ocorrência (Firestore).
///
/// Princípio de Fronteira Protegida:
/// Não executa exclusão remota em produção sem garantia formal de autorização e ownership.
/// Em vez disso, isola candidatos a órfão para diagnóstico, testes locais e futura auditoria.
class UploadOrphanTracker {
  // Singleton para persistência em memória durante o ciclo de vida do app
  static final UploadOrphanTracker _instance = UploadOrphanTracker._internal();
  factory UploadOrphanTracker() => _instance;
  UploadOrphanTracker._internal();

  /// Cria uma nova instância isolada para testes unitários.
  @visibleForTesting
  factory UploadOrphanTracker.isolated() => UploadOrphanTracker._internal();

  final Map<String, List<UploadOrphanCandidate>> _uncommitted = {};
  final Set<String> _committedUrls = {};

  /// Registra uma mídia recém-enviada ao Storage que ainda não foi vinculada à ocorrência no Firestore.
  void trackCandidate({
    required String occurrenceId,
    required String url,
    required String hash,
    String? storagePath,
  }) {
    final candidate = UploadOrphanCandidate(
      occurrenceId: occurrenceId,
      url: url,
      hash: hash,
      storagePath: storagePath,
      uploadedAt: DateTime.now(),
    );
    _uncommitted.putIfAbsent(occurrenceId, () => []).add(candidate);
  }

  /// Marca todas as mídias da ocorrência como comitadas com sucesso no Firestore.
  void commit(String occurrenceId) {
    final candidates = _uncommitted.remove(occurrenceId);
    if (candidates != null) {
      for (final c in candidates) {
        _committedUrls.add(c.url);
      }
    }
  }

  /// Retorna as URLs de mídias que foram enviadas mas nunca comitadas para a ocorrência informada.
  List<UploadOrphanCandidate> getOrphanCandidates(String occurrenceId) {
    return List.unmodifiable(_uncommitted[occurrenceId] ?? const []);
  }

  /// Retorna todas as ocorrências com candidatos a órfão pendentes.
  List<String> get pendingOccurrenceIds => List.unmodifiable(_uncommitted.keys);

  /// Verifica se uma URL específica já foi formalmente comitada no Firestore.
  bool isCommitted(String url) => _committedUrls.contains(url);

  /// Limpa os candidatos da ocorrência (usado em testes ou descarte explícito).
  void clear(String occurrenceId) {
    _uncommitted.remove(occurrenceId);
  }

  /// Limpa todo o estado do rastreador (para testes).
  @visibleForTesting
  void reset() {
    _uncommitted.clear();
    _committedUrls.clear();
  }
}
