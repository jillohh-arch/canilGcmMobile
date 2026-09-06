import 'dart:async';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:canil_gcm/features/occurrences/domain/upload_cancellation_token.dart';

/// Classificação da severidade e recuperabilidade de uma falha de upload.
enum UploadFailureType {
  /// Falha transitória (rede instável, timeout, desconexão) que autoriza nova tentativa.
  recoverable,

  /// Falha definitiva (permissão, cota, arquivo ausente) que NÃO deve tentar novamente.
  permanent,

  /// Operação abortada cooperativamente por token ou cancelamento explícito.
  cancelled,

  /// Excedeu o tempo limite da operação.
  timeout,
}

/// Classificador de falhas para o pipeline de upload de mídias de ocorrências.
class UploadFailureClassifier {
  /// Classifica uma falha em [UploadFailureType].
  static UploadFailureType classify(Object error) {
    if (error is UploadCancelledException) {
      return UploadFailureType.cancelled;
    }

    if (error is TimeoutException) {
      return UploadFailureType.timeout;
    }

    if (error is FirebaseException) {
      final code = error.code.toLowerCase();
      // Erros de cancelamento
      if (code == 'canceled' || code == 'cancelled') {
        return UploadFailureType.cancelled;
      }

      // Erros permanentes conhecidos do Firebase / Storage
      if (code == 'permission-denied' ||
          code == 'unauthenticated' ||
          code == 'unauthorized' ||
          code == 'quota-exceeded' ||
          code == 'invalid-argument' ||
          code == 'invalid-checksum' ||
          code == 'object-not-found') {
        return UploadFailureType.permanent;
      }

      // Erros transitórios de rede/servidor do Firebase Storage
      if (code == 'network-request-failed' ||
          code == 'retry-limit-exceeded' ||
          code == 'unavailable' ||
          code == 'internal' ||
          code == 'deadline-exceeded' ||
          code == 'unknown') {
        return UploadFailureType.recoverable;
      }
    }

    // Erros do sistema de arquivos e IO
    if (error is FileSystemException || error is PathNotFoundException) {
      return UploadFailureType.permanent;
    }

    if (error is SocketException || error is HttpException) {
      return UploadFailureType.recoverable;
    }

    // String matches defensivas para exceções encapsuladas
    final msg = error.toString().toLowerCase();
    if (msg.contains('cancelado') || msg.contains('canceled')) {
      return UploadFailureType.cancelled;
    }
    if (msg.contains('timeout') || msg.contains('tempo excedido')) {
      return UploadFailureType.timeout;
    }
    if (msg.contains('permission') ||
        msg.contains('permissão') ||
        msg.contains('denied')) {
      return UploadFailureType.permanent;
    }
    if (msg.contains('network') ||
        msg.contains('conexão') ||
        msg.contains('socket') ||
        msg.contains('connection')) {
      return UploadFailureType.recoverable;
    }

    // Por padrão, se não classificado explicitamente como permanente,
    // tratamos como transitório/recuperável se for genérico de rede.
    return UploadFailureType.recoverable;
  }

  /// Retorna `true` se o erro for transitório e aceitar nova tentativa automática ou manual.
  static bool isRecoverable(Object error) {
    final type = classify(error);
    return type == UploadFailureType.recoverable ||
        type == UploadFailureType.timeout;
  }

  /// Retorna `true` se a falha decorre de cancelamento cooperativo.
  static bool isCancelled(Object error) {
    return classify(error) == UploadFailureType.cancelled;
  }

  /// Retorna uma mensagem amigável para exibição em campo na UI.
  static String getFriendlyMessage(Object error) {
    final type = classify(error);
    switch (type) {
      case UploadFailureType.cancelled:
        return 'Envio de fotos cancelado.';
      case UploadFailureType.timeout:
        return 'Tempo limite excedido ao enviar foto. Verifique o sinal e tente novamente.';
      case UploadFailureType.permanent:
        if (error is FirebaseException && error.code == 'permission-denied') {
          return 'Permissão negada para envio de fotos. Contate o administrador.';
        }
        if (error is FileSystemException) {
          return 'Arquivo de foto não encontrado ou corrompido no dispositivo.';
        }
        return 'Falha ao processar arquivo de foto. Verifique o arquivo e tente novamente.';
      case UploadFailureType.recoverable:
        return 'Instabilidade de conexão ao enviar foto. Toque para tentar novamente.';
    }
  }
}
