import 'package:flutter/material.dart';

import 'package:canil_gcm/features/health/presentation/shared/states/health_presentation_status.dart';
import 'package:canil_gcm/features/health/presentation/shared/states/health_state_views.dart';

/// Corpo assíncrono por composição — escolhe a view conforme o status.
///
/// Em [HealthPresentationStatus.data] renderiza [data].
/// Não transforma erro em empty: cada status tem superfície própria.
class HealthAsyncBody extends StatelessWidget {
  final HealthPresentationStatus status;
  final Widget data;
  final String? loadingMessage;
  final String emptyMessage;
  final String? emptyTitle;
  final String errorMessage;
  final String? errorTitle;
  final String? offlineMessage;
  final String? offlineTitle;
  final String? submittingMessage;
  final VoidCallback? onRetry;
  final Widget? emptyAction;

  const HealthAsyncBody({
    super.key,
    required this.status,
    required this.data,
    this.loadingMessage,
    this.emptyMessage = 'Nenhum registro encontrado.',
    this.emptyTitle,
    this.errorMessage = 'Não foi possível carregar os registros.',
    this.errorTitle,
    this.offlineMessage,
    this.offlineTitle,
    this.submittingMessage,
    this.onRetry,
    this.emptyAction,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case HealthPresentationStatus.loading:
        return HealthLoadingView(message: loadingMessage ?? 'Carregando...');
      case HealthPresentationStatus.empty:
        return HealthEmptyView(
          message: emptyMessage,
          title: emptyTitle,
          action: emptyAction,
        );
      case HealthPresentationStatus.error:
        return HealthErrorView(
          message: errorMessage,
          title: errorTitle ?? 'Não foi possível carregar',
          onRetry: onRetry,
        );
      case HealthPresentationStatus.offline:
        return HealthOfflineView(
          message:
              offlineMessage ??
              'Sem conexão com a internet. Verifique a rede e tente novamente.',
          title: offlineTitle ?? 'Você está offline',
          onRetry: onRetry,
        );
      case HealthPresentationStatus.submitting:
        return HealthSubmittingView(
          message: submittingMessage ?? 'Salvando...',
        );
      case HealthPresentationStatus.data:
        return data;
    }
  }
}
