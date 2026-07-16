import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_selection.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_period_preset.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_type_visuals.dart';

/// Labels humanas de filtros (sem raw de tipo desconhecido).
abstract final class HealthTimelineFilterLabels {
  HealthTimelineFilterLabels._();

  static List<HealthTimelineType> get selectableTypes =>
      List<HealthTimelineType>.unmodifiable(HealthTimelineType.values);

  static String typeLabel(HealthTimelineType type) {
    final visual = HealthTimelineTypeVisuals.resolve(
      HealthTimelineTypeView.known(type),
    );
    final raw = visual.label;
    if (raw.isEmpty) return type.wireName;
    return raw[0] + raw.substring(1).toLowerCase();
  }

  static String presetLabel(HealthTimelinePeriodPreset preset) {
    return switch (preset) {
      HealthTimelinePeriodPreset.days7 => '7 dias',
      HealthTimelinePeriodPreset.days30 => '30 dias',
      HealthTimelinePeriodPreset.days90 => '90 dias',
      HealthTimelinePeriodPreset.months6 => '6 meses',
      HealthTimelinePeriodPreset.year1 => '1 ano',
      HealthTimelinePeriodPreset.allHistory => 'Todo o histórico',
      HealthTimelinePeriodPreset.custom => 'Personalizado',
    };
  }

  static String typesChipLabel(Set<HealthTimelineType> types) {
    if (types.isEmpty) return '';
    if (types.length == 1) {
      return typeLabel(types.first).toUpperCase();
    }
    return '${types.length} TIPOS';
  }

  /// Chip de período pela **origem** da seleção — nunca infere preset pela duração.
  static String periodChipLabelForOrigin(HealthTimelinePeriodPreset origin) {
    return switch (origin) {
      HealthTimelinePeriodPreset.days7 => '7 DIAS',
      HealthTimelinePeriodPreset.days30 => '30 DIAS',
      HealthTimelinePeriodPreset.days90 => '90 DIAS',
      HealthTimelinePeriodPreset.months6 => '6 MESES',
      HealthTimelinePeriodPreset.year1 => '1 ANO',
      HealthTimelinePeriodPreset.allHistory => '',
      HealthTimelinePeriodPreset.custom => 'PERSONALIZADO',
    };
  }

  static const caseChipLabel = 'CASO CLÍNICO';

  static String professionalChipLabel(
    HealthTimelineProfessionalFilter professional,
  ) {
    final name = professional.name?.trim();
    if (name != null && name.isNotEmpty) {
      return name.toUpperCase();
    }
    return 'PROFISSIONAL';
  }

  static String removeChipSemantics(String chipLabel) =>
      'Remover filtro $chipLabel';

  static List<HealthTimelineFilterChipData> chipsFor(
    HealthTimelineFilterSelection selection,
  ) {
    final list = <HealthTimelineFilterChipData>[];
    if (selection.hasTypes) {
      list.add(
        HealthTimelineFilterChipData(
          kind: HealthTimelineFilterChipKind.types,
          label: typesChipLabel(selection.types),
        ),
      );
    }
    if (selection.hasPeriod) {
      final label = periodChipLabelForOrigin(selection.periodOrigin);
      if (label.isNotEmpty) {
        list.add(
          HealthTimelineFilterChipData(
            kind: HealthTimelineFilterChipKind.period,
            label: label,
          ),
        );
      }
    }
    if (selection.hasCaseId) {
      list.add(
        const HealthTimelineFilterChipData(
          kind: HealthTimelineFilterChipKind.caseId,
          label: caseChipLabel,
        ),
      );
    }
    if (selection.hasProfessional) {
      list.add(
        HealthTimelineFilterChipData(
          kind: HealthTimelineFilterChipKind.professional,
          label: professionalChipLabel(selection.professional!),
        ),
      );
    }
    return list;
  }
}

enum HealthTimelineFilterChipKind { types, period, caseId, professional }

final class HealthTimelineFilterChipData {
  const HealthTimelineFilterChipData({required this.kind, required this.label});

  final HealthTimelineFilterChipKind kind;
  final String label;
}
