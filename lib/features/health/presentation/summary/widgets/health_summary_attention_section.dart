import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_card_surface.dart';

/// Seção REQUER ATENÇÃO com lista prioritária e callbacks (sem navegação).
class HealthSummaryAttentionSection extends StatelessWidget {
  final HealthSummarySectionData<HealthSummaryAttentionView> attention;
  final ValueChanged<HealthSummaryAttentionItem>? onAttentionItemTap;

  const HealthSummaryAttentionSection({
    super.key,
    required this.attention,
    this.onAttentionItemTap,
  });

  @override
  Widget build(BuildContext context) {
    final header = _headerStyle(attention);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          label: header.title,
          child: Text(
            header.title,
            style: GoogleFonts.inter(
              color: header.color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 10),
        HealthSummaryCardSurface(
          padding: EdgeInsets.zero,
          borderRadius: 14,
          borderColor: AppTheme.primary.withValues(alpha: 0.18),
          child: _body(),
        ),
      ],
    );
  }

  /// Título âmbar "REQUER ATENÇÃO" só quando há itens disponíveis.
  /// Unavailable / notRecorded / empty → título neutro (sem falso alerta).
  static ({String title, Color color}) _headerStyle(
    HealthSummarySectionData<HealthSummaryAttentionView> attention,
  ) {
    if (attention.status == HealthSummarySectionStatus.available) {
      final items = attention.value?.items ?? const [];
      if (items.isNotEmpty) {
        return (title: 'REQUER ATENÇÃO', color: AppTheme.warningAccent);
      }
    }
    return (title: 'ATENÇÕES', color: AppTheme.textMuted);
  }

  Widget _body() {
    switch (attention.status) {
      case HealthSummarySectionStatus.loading:
        return const Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            children: [
              HealthSummarySkeletonBar(height: 18),
              SizedBox(height: 12),
              HealthSummarySkeletonBar(height: 18),
            ],
          ),
        );
      case HealthSummarySectionStatus.unavailable:
        // Indisponível ≠ zero atenções / K9 clinicamente perfeito.
        return _messageRow(
          icon: Icons.cloud_off_outlined,
          color: AppTheme.textSoft,
          title:
              attention.message ??
              'Não foi possível determinar as atenções deste K9 no momento.',
        );
      case HealthSummarySectionStatus.notRecorded:
        return _positiveEmpty(
          message: attention.message ?? 'Nenhuma atenção prioritária',
        );
      case HealthSummarySectionStatus.available:
        final items = attention.value!.items;
        if (items.isEmpty) {
          // Empty list só quando a fonte entregou available com items=[].
          return _positiveEmpty(message: 'Nenhuma atenção prioritária');
        }
        return Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: AppTheme.surfaceWhiteBorder,
                ),
              _AttentionTile(
                item: items[i],
                onTap: onAttentionItemTap == null
                    ? null
                    : () => onAttentionItemTap!(items[i]),
              ),
            ],
          ],
        );
    }
  }

  Widget _positiveEmpty({required String message}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 20, color: AppTheme.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                color: AppTheme.success,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageRow({
    required IconData icon,
    required Color color,
    required String title,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionTile extends StatelessWidget {
  final HealthSummaryAttentionItem item;
  final VoidCallback? onTap;

  const _AttentionTile({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final actionLabel = _actionLabel(item.destinationHint);

    return Semantics(
      button: onTap != null,
      label:
          '${item.title}'
          '${item.subtitle != null ? '. ${item.subtitle}' : ''}'
          '${actionLabel != null ? '. $actionLabel' : ''}',
      excludeSemantics: true,
      child: Material(
        color: AppTheme.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.warningAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _iconFor(item),
                    size: 18,
                    color: AppTheme.warningAccent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      if (item.subtitle != null &&
                          item.subtitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle!.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: AppTheme.textSoft,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (actionLabel != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    actionLabel,
                    style: GoogleFonts.inter(
                      color: AppTheme.warningAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppTheme.warningAccent.withValues(alpha: 0.85),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(HealthSummaryAttentionItem item) {
    final hint = (item.destinationHint ?? '').toLowerCase();
    final title = item.title.toLowerCase();
    if (hint.contains('agenda') ||
        title.contains('vacina') ||
        title.contains('dose')) {
      return Icons.vaccines_outlined;
    }
    if (title.contains('pesagem') || title.contains('peso')) {
      return Icons.monitor_weight_outlined;
    }
    if (title.contains('exame') || title.contains('consulta')) {
      return Icons.medical_services_outlined;
    }
    return Icons.priority_high_rounded;
  }

  static String? _actionLabel(String? destinationHint) {
    final hint = destinationHint?.trim().toLowerCase();
    if (hint == null || hint.isEmpty) return null;
    if (hint.contains('agenda')) return 'Ver agenda';
    if (hint.contains('historico') || hint.contains('histórico')) {
      return 'Ver histórico';
    }
    if (hint.contains('nutri')) return 'Ver nutrição';
    return null;
  }
}
