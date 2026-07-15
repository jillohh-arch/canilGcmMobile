import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_controller.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_state.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_attention_section.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_metrics_grid.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_nutrition_card.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_readiness_card.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_recent_records.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_status_banner.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_weight_trend_card.dart';

/// Dashboard visual completo da seção Resumo (Fase 2C).
///
/// Consome exclusivamente:
/// - [HealthSummaryDogContextView] (identidade cadastral do K9);
/// - [HealthSummaryController] / [HealthSummaryState] (contratos 2B).
///
/// Não calcula prontidão, não acessa Firestore e não navega.
class HealthSummaryDashboard extends StatelessWidget {
  final HealthSummaryDogContextView dogContext;
  final HealthSummaryController controller;

  final ValueChanged<HealthSummaryAttentionItem>? onAttentionItemTap;
  final VoidCallback? onOpenNutrition;
  final VoidCallback? onRegisterFeeding;
  final VoidCallback? onOpenHistory;
  final ValueChanged<HealthSummaryRecentRecordView>? onRecentRecordTap;

  const HealthSummaryDashboard({
    super.key,
    required this.dogContext,
    required this.controller,
    this.onAttentionItemTap,
    this.onOpenNutrition,
    this.onRegisterFeeding,
    this.onOpenHistory,
    this.onRecentRecordTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return _DashboardBody(
          dogContext: dogContext,
          state: controller.state,
          onRetry: _canRetry(controller.state) ? controller.refresh : null,
          onAttentionItemTap: onAttentionItemTap,
          onOpenNutrition: onOpenNutrition,
          onRegisterFeeding: onRegisterFeeding,
          onOpenHistory: onOpenHistory,
          onRecentRecordTap: onRecentRecordTap,
        );
      },
    );
  }

  static bool _canRetry(HealthSummaryState state) {
    return state is HealthSummaryError || state is HealthSummaryOffline;
  }
}

class _DashboardBody extends StatelessWidget {
  final HealthSummaryDogContextView dogContext;
  final HealthSummaryState state;
  final VoidCallback? onRetry;
  final ValueChanged<HealthSummaryAttentionItem>? onAttentionItemTap;
  final VoidCallback? onOpenNutrition;
  final VoidCallback? onRegisterFeeding;
  final VoidCallback? onOpenHistory;
  final ValueChanged<HealthSummaryRecentRecordView>? onRecentRecordTap;

  const _DashboardBody({
    required this.dogContext,
    required this.state,
    required this.onRetry,
    required this.onAttentionItemTap,
    required this.onOpenNutrition,
    required this.onRegisterFeeding,
    required this.onOpenHistory,
    required this.onRecentRecordTap,
  });

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      HealthSummaryInitial() => const _SurfaceMessage(
        key: ValueKey('summary-initial'),
        icon: Icons.pets_rounded,
        title: 'Selecione um K9',
        subtitle: 'O resumo de saúde e prontidão aparece após a seleção.',
      ),
      HealthSummaryLoading() => const _StructuralLoading(
        key: ValueKey('summary-loading'),
      ),
      HealthSummaryEmpty() => const _SurfaceMessage(
        key: ValueKey('summary-empty'),
        icon: Icons.inbox_outlined,
        title: 'Sem resumo disponível',
        subtitle: 'Não há dados de resumo para este K9 no momento.',
      ),
      HealthSummaryError(:final message, :final lastKnownData) =>
        lastKnownData != null
            ? _DataScroll(
                key: const ValueKey('summary-error-with-data'),
                dogContext: dogContext,
                data: lastKnownData,
                leadingBanners: [
                  HealthSummaryStatusBanner(
                    kind: HealthSummaryBannerKind.error,
                    message: message,
                    onRetry: onRetry,
                  ),
                  ..._contextMismatchBanners(dogContext, lastKnownData),
                ],
                onAttentionItemTap: onAttentionItemTap,
                onOpenNutrition: onOpenNutrition,
                onRegisterFeeding: onRegisterFeeding,
                onOpenHistory: onOpenHistory,
                onRecentRecordTap: onRecentRecordTap,
              )
            : _SurfaceMessage(
                key: const ValueKey('summary-error'),
                icon: Icons.error_outline_rounded,
                title: 'Não foi possível carregar',
                subtitle: message,
                actionLabel: onRetry == null ? null : 'Tentar novamente',
                onAction: onRetry,
              ),
      HealthSummaryOffline(:final cachedData) =>
        cachedData != null
            ? _DataScroll(
                key: const ValueKey('summary-offline-with-cache'),
                dogContext: dogContext,
                data: cachedData,
                leadingBanners: [
                  HealthSummaryStatusBanner(
                    kind: HealthSummaryBannerKind.offline,
                    message: 'Modo offline — exibindo último resumo disponível',
                    onRetry: onRetry,
                  ),
                  ..._contextMismatchBanners(dogContext, cachedData),
                  ..._freshnessBanners(cachedData, includeOfflineMeta: false),
                ],
                onAttentionItemTap: onAttentionItemTap,
                onOpenNutrition: onOpenNutrition,
                onRegisterFeeding: onRegisterFeeding,
                onOpenHistory: onOpenHistory,
                onRecentRecordTap: onRecentRecordTap,
              )
            : _SurfaceMessage(
                key: const ValueKey('summary-offline'),
                icon: Icons.cloud_off_outlined,
                title: 'Sem conexão',
                subtitle:
                    'Não há resumo em cache para exibir enquanto estiver offline.',
                actionLabel: onRetry == null ? null : 'Tentar novamente',
                onAction: onRetry,
              ),
      HealthSummaryData(:final data) => _DataScroll(
        key: const ValueKey('summary-data'),
        dogContext: dogContext,
        data: data,
        leadingBanners: [
          ..._contextMismatchBanners(dogContext, data),
          ..._freshnessBanners(data, includeOfflineMeta: true),
        ],
        onAttentionItemTap: onAttentionItemTap,
        onOpenNutrition: onOpenNutrition,
        onRegisterFeeding: onRegisterFeeding,
        onOpenHistory: onOpenHistory,
        onRecentRecordTap: onRecentRecordTap,
      ),
    };
  }

  /// Banner quando identidade cadastral e payload de saúde divergem.
  static List<Widget> _contextMismatchBanners(
    HealthSummaryDogContextView dogContext,
    HealthSummaryViewData data,
  ) {
    if (dogContext.dogId == data.dogId) return const [];
    return const [
      HealthSummaryStatusBanner(
        kind: HealthSummaryBannerKind.error,
        message:
            'Contexto do K9 não corresponde aos dados do resumo — verifique a seleção',
      ),
    ];
  }

  /// Freshness discreto; não aplica thresholds 5 min / 12 h e não altera readiness.
  ///
  /// Prioridade legível: stale > cache (evita empilhar banners redundantes).
  /// Offline de canal já é estado [HealthSummaryOffline]; metadata.isOffline
  /// em payload de data é secundário.
  static List<Widget> _freshnessBanners(
    HealthSummaryViewData data, {
    required bool includeOfflineMeta,
  }) {
    final meta = data.metadata;
    final banners = <Widget>[];
    if (meta.isStale) {
      banners.add(
        const HealthSummaryStatusBanner(
          kind: HealthSummaryBannerKind.stale,
          message: 'Dados possivelmente desatualizados',
        ),
      );
    } else if (meta.isFromCache) {
      banners.add(
        const HealthSummaryStatusBanner(
          kind: HealthSummaryBannerKind.cache,
          message: 'Exibindo dados em cache',
        ),
      );
    }
    if (includeOfflineMeta && meta.isOffline && !meta.isStale) {
      // Snapshot marcado offline pela fonte sem canal Offline do controller.
      banners.add(
        const HealthSummaryStatusBanner(
          kind: HealthSummaryBannerKind.offline,
          message: 'Origem reportou condição offline',
        ),
      );
    }
    return banners;
  }
}

class _DataScroll extends StatelessWidget {
  final HealthSummaryDogContextView dogContext;
  final HealthSummaryViewData data;
  final List<Widget> leadingBanners;
  final ValueChanged<HealthSummaryAttentionItem>? onAttentionItemTap;
  final VoidCallback? onOpenNutrition;
  final VoidCallback? onRegisterFeeding;
  final VoidCallback? onOpenHistory;
  final ValueChanged<HealthSummaryRecentRecordView>? onRecentRecordTap;

  const _DataScroll({
    super.key,
    required this.dogContext,
    required this.data,
    required this.leadingBanners,
    required this.onAttentionItemTap,
    required this.onOpenNutrition,
    required this.onRegisterFeeding,
    required this.onOpenHistory,
    required this.onRecentRecordTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        // Lado a lado no padrão do mockup; empilha em estreito ou textScale alto.
        final sideBySide = constraints.maxWidth >= 340 && textScale <= 1.2;

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final banner in leadingBanners) ...[
                  banner,
                  const SizedBox(height: 10),
                ],
                HealthSummaryReadinessCard(
                  dogContext: dogContext,
                  readiness: data.readiness,
                ),
                const SizedBox(height: 12),
                HealthSummaryMetricsGrid(data: data),
                const SizedBox(height: 18),
                HealthSummaryAttentionSection(
                  attention: data.attention,
                  onAttentionItemTap: onAttentionItemTap,
                ),
                const SizedBox(height: 14),
                if (sideBySide)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: HealthSummaryNutritionCard(
                            nutrition: data.nutritionToday,
                            onOpenNutrition: onOpenNutrition,
                            onRegisterFeeding: onRegisterFeeding,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: HealthSummaryWeightTrendCard(
                            weightTrend: data.weightTrend,
                            currentWeight: data.weight,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  HealthSummaryNutritionCard(
                    nutrition: data.nutritionToday,
                    onOpenNutrition: onOpenNutrition,
                    onRegisterFeeding: onRegisterFeeding,
                  ),
                  const SizedBox(height: 10),
                  HealthSummaryWeightTrendCard(
                    weightTrend: data.weightTrend,
                    currentWeight: data.weight,
                  ),
                ],
                const SizedBox(height: 18),
                HealthSummaryRecentRecords(
                  recentRecords: data.recentRecords,
                  onOpenHistory: onOpenHistory,
                  onRecentRecordTap: onRecentRecordTap,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StructuralLoading extends StatelessWidget {
  const _StructuralLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SkeletonCard(height: 140),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _SkeletonCard(height: 96)),
              SizedBox(width: 10),
              Expanded(child: _SkeletonCard(height: 96)),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _SkeletonCard(height: 96)),
              SizedBox(width: 10),
              Expanded(child: _SkeletonCard(height: 96)),
            ],
          ),
          SizedBox(height: 18),
          _SkeletonCard(height: 88),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final double height;

  const _SkeletonCard({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.surfacePanel.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
      ),
    );
  }
}

class _SurfaceMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SurfaceMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppTheme.textMuted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppTheme.textSoft,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              Semantics(
                button: true,
                label: actionLabel,
                excludeSemantics: true,
                child: Material(
                  color: AppTheme.transparent,
                  child: InkWell(
                    onTap: onAction,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.8),
                        ),
                      ),
                      child: Text(
                        actionLabel!,
                        style: GoogleFonts.inter(
                          color: AppTheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
