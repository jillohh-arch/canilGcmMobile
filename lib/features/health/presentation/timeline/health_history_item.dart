import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/domain/operational_restriction.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_labels.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';

/// Fases do ciclo de vida de uma restrição operacional na apresentação do histórico.
enum HealthRestrictionLifecyclePhase {
  issued,
  ended,
  cancelled;

  String get label => switch (this) {
    HealthRestrictionLifecyclePhase.issued => 'Restrição operacional aplicada',
    HealthRestrictionLifecyclePhase.ended => 'Restrição liberada clinicamente',
    HealthRestrictionLifecyclePhase.cancelled => 'Restrição invalidada',
  };
}

/// Rótulos amigáveis em PT-BR para eventos de restrição operacional.
///
/// Garante que nenhum identificador técnico nem valor raw de enum em snake_case
/// seja apresentado ao usuário como label primário.
abstract final class HealthRestrictionHistoryLabels {
  HealthRestrictionHistoryLabels._();

  static String levelLabel(RestrictionLevel level) {
    return switch (level) {
      RestrictionLevel.absolute => 'Restrição absoluta',
      RestrictionLevel.partial => 'Restrição relativa',
      RestrictionLevel.attention => 'Atenção operacional',
    };
  }

  static String categoryLabel(RestrictionCategory category) {
    return healthRestrictionCategoryLabel(category);
  }

  static String issuedSubtitle({
    required RestrictionLevel level,
    required RestrictionCategory category,
    required String description,
  }) {
    final lvl = levelLabel(level);
    final cat = categoryLabel(category);
    final desc = description.trim();
    if (desc.isEmpty) {
      return '$lvl • $cat';
    }
    return '$lvl • $cat — $desc';
  }

  static String endedSubtitle({
    String? endReason,
    String? professionalName,
  }) {
    final reason = endReason?.trim() ?? '';
    final prof = professionalName?.trim() ?? '';
    if (reason.isNotEmpty && prof.isNotEmpty) {
      return '$reason (Responsável: $prof)';
    }
    if (reason.isNotEmpty) {
      return reason;
    }
    if (prof.isNotEmpty) {
      return 'Responsável: $prof';
    }
    return 'Liberação clínica';
  }

  static String cancelledSubtitle({
    String? cancelReason,
    String? cancelledByName,
  }) {
    final reason = cancelReason?.trim() ?? '';
    final actor = cancelledByName?.trim() ?? '';
    if (reason.isNotEmpty && actor.isNotEmpty) {
      return '$reason (Por: $actor)';
    }
    if (reason.isNotEmpty) {
      return reason;
    }
    if (actor.isNotEmpty) {
      return 'Por: $actor';
    }
    return 'Cancelamento administrativo';
  }
}

/// Abstração de apresentação para o Histórico Clínico do K9.
///
/// Unifica entradas canônicas da timeline e eventos de ciclo de vida
/// de restrições operacionais em um modelo polimórfico de apresentação.
sealed class HealthHistoryItem {
  const HealthHistoryItem();

  String get id;
  String get dogId;
  DateTime get occurredAt;
  DateTime get recordedAt;
  String get title;
  String? get subtitle;

  /// Converte para [HealthTimelineEntryView] para renderização uniforme
  /// na visualização da timeline.
  HealthTimelineEntryView toEntryView();
}

/// Item de apresentação que encapsula uma entrada canônica da timeline existente.
final class CanonicalHealthTimelineHistoryItem extends HealthHistoryItem {
  const CanonicalHealthTimelineHistoryItem(this.entry);

  final HealthTimelineEntryView entry;

  @override
  String get id => entry.id;

  @override
  String get dogId => entry.dogId;

  @override
  DateTime get occurredAt => entry.occurredAt;

  @override
  DateTime get recordedAt => entry.recordedAt;

  @override
  String get title => entry.title;

  @override
  String? get subtitle => entry.subtitle;

  @override
  HealthTimelineEntryView toEntryView() => entry;
}

/// Item de apresentação que representa um evento do ciclo de vida de uma
/// restrição operacional persistida.
final class HealthRestrictionLifecycleHistoryItem extends HealthHistoryItem {
  const HealthRestrictionLifecycleHistoryItem({
    required this.restrictionId,
    required this.dogId,
    required this.phase,
    required this.occurredAt,
    required this.recordedAt,
    required this.title,
    this.subtitle,
    required this.level,
    required this.category,
    required this.description,
    this.recordedBy,
    this.professional,
    this.endReason,
    this.cancelReason,
    this.restriction,
  });

  final String restrictionId;
  @override
  final String dogId;
  final HealthRestrictionLifecyclePhase phase;
  @override
  final DateTime occurredAt;
  @override
  final DateTime recordedAt;
  @override
  final String title;
  @override
  final String? subtitle;
  final RestrictionLevel level;
  final RestrictionCategory category;
  final String description;
  final RecordedBy? recordedBy;
  final ProfessionalIdentitySummary? professional;
  final String? endReason;
  final String? cancelReason;
  final OperationalRestriction? restriction;

  /// ID determinístico para deduplicação segura (restrictionId + phase).
  @override
  String get id => 'restriction_${restrictionId}_${phase.name}';

  @override
  HealthTimelineEntryView toEntryView() {
    return HealthTimelineEntryView(
      id: id,
      dogId: dogId,
      type: HealthTimelineTypeView.known(HealthTimelineType.restriction),
      occurredAt: occurredAt,
      recordedAt: recordedAt,
      title: title,
      subtitle: subtitle,
      status: phase == HealthRestrictionLifecyclePhase.cancelled
          ? HealthTimelineEntryStatus.cancelled
          : HealthTimelineEntryStatus.finalised,
      recordedBy: recordedBy,
      professional: professional,
      detailReference: HealthTimelineDetailReference(
        sourceType: 'operational_restrictions',
        sourceId: restrictionId,
      ),
    );
  }
}

/// Derivador de eventos de ciclo de vida a partir do aggregate [OperationalRestriction].
///
/// Não inventa timestamps nem atores: deriva estritamente dos campos
/// canônicos persistidos (`issuedAt`, `actualEnd`, `cancelledAt`).
abstract final class HealthRestrictionLifecycleDeriver {
  HealthRestrictionLifecycleDeriver._();

  /// Deriva os itens de ciclo de vida correspondentes para a restrição.
  static List<HealthRestrictionLifecycleHistoryItem> derive(
    OperationalRestriction restriction,
  ) {
    final items = <HealthRestrictionLifecycleHistoryItem>[];

    // 1. ISSUED — toda restrição canônica possui issuedAt
    final professionalSummary =
        restriction.professional.name.trim().isNotEmpty
            ? ProfessionalIdentitySummary(
              name: restriction.professional.name.trim(),
            )
            : null;

    items.add(
      HealthRestrictionLifecycleHistoryItem(
        restrictionId: restriction.id,
        dogId: restriction.dogId,
        phase: HealthRestrictionLifecyclePhase.issued,
        occurredAt: restriction.issuedAt,
        recordedAt: restriction.issuedAt,
        title: HealthRestrictionLifecyclePhase.issued.label,
        subtitle: HealthRestrictionHistoryLabels.issuedSubtitle(
          level: restriction.level,
          category: restriction.category,
          description: restriction.description,
        ),
        level: restriction.level,
        category: restriction.category,
        description: restriction.description,
        recordedBy: restriction.recordedBy,
        professional: professionalSummary,
        restriction: restriction,
      ),
    );

    // 2. ENDED — se e somente se liberada clinicamente
    if (restriction.actualEnd != null &&
        restriction.status == RestrictionStatus.ended) {
      final endProfSummary =
          restriction.endProfessional?.name.trim().isNotEmpty == true
              ? ProfessionalIdentitySummary(
                name: restriction.endProfessional!.name.trim(),
              )
              : null;

      items.add(
        HealthRestrictionLifecycleHistoryItem(
          restrictionId: restriction.id,
          dogId: restriction.dogId,
          phase: HealthRestrictionLifecyclePhase.ended,
          occurredAt: restriction.actualEnd!,
          recordedAt: restriction.actualEnd!,
          title: HealthRestrictionLifecyclePhase.ended.label,
          subtitle: HealthRestrictionHistoryLabels.endedSubtitle(
            endReason: restriction.endReason,
            professionalName: restriction.endProfessional?.name,
          ),
          level: restriction.level,
          category: restriction.category,
          description: restriction.description,
          recordedBy: restriction.endedBy,
          professional: endProfSummary,
          endReason: restriction.endReason,
          restriction: restriction,
        ),
      );
    }

    // 3. CANCELLED — se e somente se invalidada administrativamente
    if (restriction.cancelledAt != null &&
        restriction.status == RestrictionStatus.cancelled) {
      items.add(
        HealthRestrictionLifecycleHistoryItem(
          restrictionId: restriction.id,
          dogId: restriction.dogId,
          phase: HealthRestrictionLifecyclePhase.cancelled,
          occurredAt: restriction.cancelledAt!,
          recordedAt: restriction.cancelledAt!,
          title: HealthRestrictionLifecyclePhase.cancelled.label,
          subtitle: HealthRestrictionHistoryLabels.cancelledSubtitle(
            cancelReason: restriction.cancelReason,
            cancelledByName: restriction.cancelledBy?.name,
          ),
          level: restriction.level,
          category: restriction.category,
          description: restriction.description,
          recordedBy: restriction.cancelledBy,
          professional: null,
          cancelReason: restriction.cancelReason,
          restriction: restriction,
        ),
      );
    }

    return items;
  }
}
