import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_formatters.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_metric_card.dart';

/// Grid 2×2 de indicadores: peso, vacinação, medicação, atenções.
class HealthSummaryMetricsGrid extends StatelessWidget {
  final HealthSummaryViewData data;

  const HealthSummaryMetricsGrid({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 10.0;
        final cardWidth = (constraints.maxWidth - gap) / 2;
        // Em larguras muito estreitas, empilha 1 coluna.
        final singleColumn = constraints.maxWidth < 300;

        final cards = [
          _weightCard(data.weight),
          _vaccinationCard(data.vaccination),
          _treatmentsCard(data.treatments),
          _attentionCard(data.attention),
        ];

        if (singleColumn) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                cards[i],
              ],
            ],
          );
        }

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }

  Widget _weightCard(
    HealthSummarySectionData<HealthSummaryWeightView> section,
  ) {
    String? primary;
    String? secondary;
    String semantics = 'Peso';

    if (section.isAvailable) {
      final v = section.value!;
      primary = HealthSummaryFormatters.weightKg(v.weightKg);
      secondary = HealthSummaryFormatters.lastWeighingLabel(v.measuredAt);
      semantics = 'Peso $primary. $secondary';
    } else if (section.isNotRecorded) {
      semantics = 'Peso não registrado';
    } else if (section.isUnavailable) {
      semantics = 'Peso indisponível';
    } else {
      semantics = 'Peso carregando';
    }

    return HealthSummaryMetricCard(
      key: const ValueKey('metric-weight'),
      label: 'PESO',
      icon: Icons.monitor_weight_outlined,
      accentColor: AppTheme.info,
      primaryValue: primary,
      secondaryValue: secondary,
      isLoading: section.isLoading,
      isNotRecorded: section.isNotRecorded,
      isUnavailable: section.isUnavailable,
      statusMessage:
          section.message ?? (section.isNotRecorded ? 'Não registrado' : null),
      semanticsLabel: semantics,
    );
  }

  Widget _vaccinationCard(
    HealthSummarySectionData<HealthSummaryVaccinationView> section,
  ) {
    String? primary;
    String? secondary;
    String semantics = 'Vacinação';

    if (section.isAvailable) {
      final v = section.value!;
      final summary = v.summaryLabel?.trim();
      final last = v.lastRecordLabel?.trim();
      final days = HealthSummaryFormatters.daysUntilLabel(v.nextDueAt);

      // Não inventar status positivo (ex.: "REGISTRADA") sem dado no contrato.
      if (summary != null && summary.isNotEmpty) {
        primary = summary.toUpperCase();
        secondary = days ?? (last != null && last.isNotEmpty ? last : null);
      } else if (last != null && last.isNotEmpty) {
        primary = last;
        secondary = days;
      } else if (days != null) {
        primary = days;
        secondary = null;
      } else {
        primary = null;
        secondary = null;
      }
      semantics =
          'Vacinação'
          '${primary != null ? ' $primary' : ''}'
          '${secondary != null ? '. $secondary' : ''}';
    } else if (section.isNotRecorded) {
      semantics = 'Vacinação sem registro';
    } else if (section.isUnavailable) {
      semantics = 'Vacinação indisponível';
    } else {
      semantics = 'Vacinação carregando';
    }

    return HealthSummaryMetricCard(
      key: const ValueKey('metric-vaccination'),
      label: 'VACINAÇÃO',
      icon: Icons.verified_user_outlined,
      accentColor: AppTheme.success,
      primaryValue: primary,
      secondaryValue: secondary,
      isLoading: section.isLoading,
      isNotRecorded: section.isNotRecorded,
      isUnavailable: section.isUnavailable,
      statusMessage:
          section.message ?? (section.isNotRecorded ? 'Sem registro' : null),
      semanticsLabel: semantics,
    );
  }

  Widget _treatmentsCard(
    HealthSummarySectionData<HealthSummaryTreatmentsView> section,
  ) {
    String? primary;
    String? secondary;
    String semantics = 'Medicação';

    if (section.isAvailable) {
      final v = section.value!;
      if (v.activeProtocolCount == 0) {
        primary = 'NENHUMA ATIVA';
        secondary = v.primarySummary?.trim().isNotEmpty == true
            ? v.primarySummary!.trim()
            : 'Sem tratamento em andamento';
      } else if (v.activeProtocolCount == 1) {
        primary = '1 ATIVA';
        secondary = v.primarySummary;
      } else {
        primary = '${v.activeProtocolCount} ATIVAS';
        secondary = v.primarySummary;
      }
      semantics =
          'Medicação $primary${secondary != null ? '. $secondary' : ''}';
    } else if (section.isNotRecorded) {
      semantics = 'Medicação sem registro';
    } else if (section.isUnavailable) {
      semantics = 'Medicação indisponível';
    } else {
      semantics = 'Medicação carregando';
    }

    return HealthSummaryMetricCard(
      key: const ValueKey('metric-treatments'),
      label: 'MEDICAÇÃO',
      icon: Icons.medication_outlined,
      accentColor: AppTheme.primary,
      primaryValue: primary,
      secondaryValue: secondary,
      isLoading: section.isLoading,
      isNotRecorded: section.isNotRecorded,
      isUnavailable: section.isUnavailable,
      statusMessage:
          section.message ??
          (section.isNotRecorded ? 'Nenhum plano registrado' : null),
      semanticsLabel: semantics,
    );
  }

  Widget _attentionCard(
    HealthSummarySectionData<HealthSummaryAttentionView> section,
  ) {
    String? primary;
    String? secondary;
    String semantics = 'Atenções';
    var accent = AppTheme.warningAccent;

    if (section.isAvailable) {
      final v = section.value!;
      final count = v.count;
      if (count == 0) {
        primary = 'NENHUMA';
        secondary = 'Sem pendências prioritárias';
        accent = AppTheme.success;
      } else if (count == 1) {
        primary = '1 ITEM';
        secondary = v.items.first.title;
      } else {
        primary = '$count ITENS';
        secondary = v.items.first.title;
      }
      semantics = 'Atenções $primary. $secondary';
    } else if (section.isNotRecorded) {
      semantics = 'Atenções sem registro';
      accent = AppTheme.textMuted;
    } else if (section.isUnavailable) {
      semantics = 'Atenções indisponíveis';
      accent = AppTheme.textSoft;
    } else {
      semantics = 'Atenções carregando';
    }

    return HealthSummaryMetricCard(
      key: const ValueKey('metric-attention'),
      label: 'ATENÇÕES',
      icon: Icons.warning_amber_rounded,
      accentColor: accent,
      primaryValue: primary,
      secondaryValue: secondary,
      isLoading: section.isLoading,
      isNotRecorded: section.isNotRecorded,
      isUnavailable: section.isUnavailable,
      statusMessage:
          section.message ??
          (section.isNotRecorded ? 'Sem atenções registradas' : null),
      semanticsLabel: semantics,
    );
  }
}
