import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_user_copy.dart';

/// Mapeamento visual exclusivo de apresentação para [HealthTimelineTypeView].
///
/// Não cria enum novo. Não aplica regra clínica.
final class HealthTimelineTypeVisual {
  const HealthTimelineTypeVisual({
    required this.label,
    required this.icon,
    required this.accent,
  });

  /// Label amigável em caixa alta (nível 1 do card).
  final String label;

  final IconData icon;

  /// Cor de acento controlada (ícone/marker), não “neon”.
  final Color accent;
}

/// Resolve ícone, label e acento a partir do tipo de timeline.
abstract final class HealthTimelineTypeVisuals {
  HealthTimelineTypeVisuals._();

  static HealthTimelineTypeVisual resolve(HealthTimelineTypeView type) {
    final known = type.known;
    if (known == null) {
      return const HealthTimelineTypeVisual(
        label: HealthTimelineUserCopy.unknownTypeLabel,
        icon: Icons.note_outlined,
        accent: AppTheme.textSecondary,
      );
    }
    return _forKnown(known);
  }

  static HealthTimelineTypeVisual _forKnown(HealthTimelineType type) {
    return switch (type) {
      HealthTimelineType.consultation => const HealthTimelineTypeVisual(
        label: 'CONSULTA VETERINÁRIA',
        icon: Icons.medical_services_outlined,
        accent: AppTheme.primary,
      ),
      HealthTimelineType.vaccination => const HealthTimelineTypeVisual(
        label: 'VACINAÇÃO',
        icon: Icons.verified_user_outlined,
        accent: AppTheme.healthAccent,
      ),
      HealthTimelineType.weight => const HealthTimelineTypeVisual(
        label: 'PESAGEM',
        icon: Icons.monitor_weight_outlined,
        accent: AppTheme.info,
      ),
      HealthTimelineType.meal => const HealthTimelineTypeVisual(
        label: 'ALIMENTAÇÃO',
        icon: Icons.restaurant_rounded,
        accent: AppTheme.attention,
      ),
      HealthTimelineType.supplement => const HealthTimelineTypeVisual(
        label: 'SUPLEMENTO',
        icon: Icons.spa_outlined,
        accent: AppTheme.attention,
      ),
      HealthTimelineType.exam => const HealthTimelineTypeVisual(
        label: 'EXAME',
        icon: Icons.science_outlined,
        accent: AppTheme.primary,
      ),
      HealthTimelineType.treatment => const HealthTimelineTypeVisual(
        label: 'TRATAMENTO',
        icon: Icons.healing_outlined,
        accent: AppTheme.warningAccent,
      ),
      HealthTimelineType.dose => const HealthTimelineTypeVisual(
        label: 'MEDICAÇÃO',
        icon: Icons.medication_outlined,
        accent: AppTheme.warningAccent,
      ),
      HealthTimelineType.incident => const HealthTimelineTypeVisual(
        label: 'INTERCORRÊNCIA',
        icon: Icons.warning_amber_rounded,
        accent: AppTheme.warning,
      ),
      HealthTimelineType.discharge => const HealthTimelineTypeVisual(
        label: 'ALTA',
        icon: Icons.task_alt_rounded,
        accent: AppTheme.success,
      ),
      HealthTimelineType.restriction => const HealthTimelineTypeVisual(
        label: 'RESTRIÇÃO',
        icon: Icons.gpp_maybe_outlined,
        accent: AppTheme.error,
      ),
      HealthTimelineType.document => const HealthTimelineTypeVisual(
        label: 'DOCUMENTO',
        icon: Icons.description_outlined,
        accent: AppTheme.textSecondary,
      ),
      HealthTimelineType.observation => const HealthTimelineTypeVisual(
        label: 'OBSERVAÇÃO',
        icon: Icons.visibility_outlined,
        accent: AppTheme.info,
      ),
      HealthTimelineType.preventive => const HealthTimelineTypeVisual(
        label: 'PREVENTIVO',
        icon: Icons.event_available_outlined,
        accent: AppTheme.success,
      ),
    };
  }
}
