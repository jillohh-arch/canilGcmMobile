import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_session.dart';

/// Atalhos horizontais de tipo (mockup Histórico). Usam a mesma [FilterSession].
///
/// Single-select rápido:
/// - Todos → types vazio (preserva period/case/professional);
/// - tipo → types = {tipo};
/// - multi-type avançado → nenhum chip específico selecionado (estado neutro).
class HealthTimelineQuickTypeChips extends StatelessWidget {
  const HealthTimelineQuickTypeChips({
    super.key,
    required this.session,
    this.onChanged,
  });

  final HealthTimelineFilterSession session;
  final VoidCallback? onChanged;

  /// Categorias da faixa rápida (domínio suportado; não inventa tipos).
  static const quickEntries = <(String label, HealthTimelineType? type)>[
    ('Todos', null),
    ('Nutrição', HealthTimelineType.meal),
    ('Consultas', HealthTimelineType.consultation),
    ('Vacinas', HealthTimelineType.vaccination),
    ('Pesagens', HealthTimelineType.weight),
    ('Exames', HealthTimelineType.exam),
    ('Medicamentos', HealthTimelineType.dose),
    ('Intercorrências', HealthTimelineType.incident),
    ('Documentos', HealthTimelineType.document),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final multi = session.hasAdvancedMultiTypeSelection;
        return SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: quickEntries.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final (label, type) = quickEntries[index];
              final selected = type == null
                  ? session.isQuickAllSelected
                  : (!multi && session.isQuickTypeSelected(type));
              return _QuickChip(
                label: label,
                selected: selected,
                onTap: () async {
                  if (type == null) {
                    await session.applyQuickAllTypes();
                  } else {
                    await session.applyQuickType(type);
                  }
                  onChanged?.call();
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? '$label, selecionado' : label,
      child: Material(
        color: AppTheme.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.16)
                  : AppTheme.surfacePanelSoft,
              border: Border.all(
                color: selected
                    ? AppTheme.primary.withValues(alpha: 0.55)
                    : AppTheme.surfaceWhiteBorder,
              ),
            ),
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
