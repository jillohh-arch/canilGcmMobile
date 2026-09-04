import 'dart:math' as math;

/// Snapshot imutável do estado de progresso de upload agregado em bytes.
class UploadProgressSnapshot {
  final int completedFiles;
  final int totalFiles;
  final int transferredBytes;
  final int totalBytes;
  final double? fraction;

  /// True se o arquivo atualmente ativo reportou bytes transferidos > 0.
  final bool hasActiveFileProgress;

  const UploadProgressSnapshot({
    required this.completedFiles,
    required this.totalFiles,
    required this.transferredBytes,
    required this.totalBytes,
    required this.fraction,
    required this.hasActiveFileProgress,
  });

  @override
  String toString() =>
      'UploadProgressSnapshot(completedFiles: $completedFiles/$totalFiles, '
      'bytes: $transferredBytes/$totalBytes, fraction: $fraction, '
      'hasActiveFileProgress: $hasActiveFileProgress)';
}

/// Agregador puro de progresso ponderado em bytes para uploads sequenciais.
///
/// Mantém monotonicidade (a fração nunca regride na mesma operação),
/// comita o tamanho integral declarado ao concluir cada arquivo e
/// trata denominadores <= 0 como fração indeterminada (null).
class UploadProgressAggregator {
  List<int> _fileSizes;
  final Set<int> _completedIndices = <int>{};
  int _currentFileIndex = -1;
  int _currentFileTransferred = 0;
  double? _maxFraction;

  UploadProgressAggregator(List<int> fileSizes)
    : _fileSizes = List.unmodifiable(fileSizes);

  int get totalFiles => _fileSizes.length;

  int get totalBytes =>
      _fileSizes.fold<int>(0, (sum, size) => sum + (size > 0 ? size : 0));

  UploadProgressSnapshot get current => _computeSnapshot();

  /// Registra o início da transferência do arquivo [fileIndex], resetando
  /// o estado de progresso parcial ativo para este arquivo.
  UploadProgressSnapshot startFile(int fileIndex) {
    if (fileIndex >= 0 && fileIndex < totalFiles) {
      _currentFileIndex = fileIndex;
      _currentFileTransferred = 0;
    }
    return _computeSnapshot();
  }

  /// Atualiza o progresso em bytes do arquivo [fileIndex].
  UploadProgressSnapshot updateFileProgress(
    int fileIndex,
    int bytesTransferred,
  ) {
    if (fileIndex < 0 || fileIndex >= totalFiles) {
      return current;
    }

    _currentFileIndex = fileIndex;
    final declaredSize = _fileSizes[fileIndex];
    if (declaredSize > 0) {
      _currentFileTransferred = bytesTransferred.clamp(0, declaredSize);
    } else {
      _currentFileTransferred = 0;
    }

    return _computeSnapshot();
  }

  /// Marca o arquivo [fileIndex] como concluído, comitando seu tamanho
  /// declarado integral e liberando o progresso parcial do arquivo ativo.
  UploadProgressSnapshot completeFile(int fileIndex) {
    if (fileIndex >= 0 && fileIndex < totalFiles) {
      _completedIndices.add(fileIndex);
      if (_currentFileIndex == fileIndex) {
        _currentFileTransferred = 0;
        _currentFileIndex = -1;
      }
    }
    return _computeSnapshot();
  }

  /// Reinicia o estado do agregador para uma nova operação.
  UploadProgressSnapshot reset([List<int>? newFileSizes]) {
    if (newFileSizes != null) {
      _fileSizes = List.unmodifiable(newFileSizes);
    }
    _completedIndices.clear();
    _currentFileIndex = -1;
    _currentFileTransferred = 0;
    _maxFraction = null;
    return _computeSnapshot();
  }

  UploadProgressSnapshot _computeSnapshot() {
    final tBytes = totalBytes;
    final completedCount = _completedIndices.length;
    final hasActive = _currentFileIndex >= 0 && _currentFileTransferred > 0;

    int transferred = 0;
    for (final index in _completedIndices) {
      final size = _fileSizes[index];
      if (size > 0) {
        transferred += size;
      }
    }

    if (_currentFileIndex >= 0 &&
        !_completedIndices.contains(_currentFileIndex)) {
      transferred += _currentFileTransferred;
    }

    if (tBytes <= 0) {
      return UploadProgressSnapshot(
        completedFiles: completedCount,
        totalFiles: totalFiles,
        transferredBytes: transferred,
        totalBytes: tBytes,
        fraction: null,
        hasActiveFileProgress: hasActive,
      );
    }

    final effectiveTransferred = transferred.clamp(0, tBytes);
    final rawFraction = (effectiveTransferred / tBytes).clamp(0.0, 1.0);

    // Regra da monotonicidade: fração nunca decresce na mesma operação
    _maxFraction = _maxFraction != null
        ? math.max(_maxFraction!, rawFraction)
        : rawFraction;

    // Se todos os arquivos foram concluídos e o total > 0, garante 1.0
    final finalFraction = (completedCount == totalFiles && totalFiles > 0)
        ? 1.0
        : _maxFraction;

    return UploadProgressSnapshot(
      completedFiles: completedCount,
      totalFiles: totalFiles,
      transferredBytes: effectiveTransferred,
      totalBytes: tBytes,
      fraction: finalFraction,
      hasActiveFileProgress: hasActive,
    );
  }
}
