import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_policy.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_revision.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';

/// Ações de mutação expostas na UI da Agenda (Gate 5).
///
/// Visibilidade **não** equivale a autorização — o backend continua
/// autoridade final. Preferir esconder ações claramente indisponíveis
/// a exibir botões desabilitados sem necessidade.
enum HealthScheduleItemAction { edit, complete, cancel }

/// Política pura de disponibilidade de ações na apresentação.
///
/// Não inventa roles (`gestor`, `health.manage_schedule`, etc.).
/// Cancelamento de item automático só aparece quando o caller prova
/// autoridade admin cliente confiável via [canCancelAutomaticAsAdmin].
/// No Gate 5, o mobile **não** possui helper seguro para isso → default false.
abstract final class HealthScheduleActionAvailability {
  HealthScheduleActionAvailability._();

  /// Timezone padrão da política operacional atual (não inventado neste Gate).
  static const defaultTimezone = 'America/Sao_Paulo';

  /// Limite real do backend (`MAX_CANCEL_REASON_LEN`).
  static const maxCancelReasonLength = 500;

  /// Ações para um item de view (com revision lida).
  static Set<HealthScheduleItemAction> forView(
    HealthScheduleItemView item, {
    bool canCancelAutomaticAsAdmin = false,
    bool isItemBusy = false,
  }) {
    if (isItemBusy) return const {};
    return forFields(
      lifecycleStatus: item.lifecycleStatus,
      sourceType: item.sourceType,
      revision: item.revision,
      canCancelAutomaticAsAdmin: canCancelAutomaticAsAdmin,
    );
  }

  /// Ações a partir de campos canônicos (testes / domínio).
  static Set<HealthScheduleItemAction> forFields({
    required ScheduleLifecycleStatus lifecycleStatus,
    required ScheduleSourceType sourceType,
    required HealthScheduleRevision revision,
    bool canCancelAutomaticAsAdmin = false,
  }) {
    if (lifecycleStatus != ScheduleLifecycleStatus.open) {
      return const {};
    }

    final isManual = sourceType == ScheduleSourceType.manual;
    final isAutomatic = HealthScheduleMutationPolicy.isAutomaticSource(
      sourceType,
    );

    final actions = <HealthScheduleItemAction>{
      HealthScheduleItemAction.complete,
    };

    // Editar: somente manual + open + revision presente (token não vazio).
    if (isManual && revision.token.trim().isNotEmpty) {
      actions.add(HealthScheduleItemAction.edit);
    }

    // Cancelar manual open: sempre na matriz UI (backend valida health.edit).
    if (isManual) {
      actions.add(HealthScheduleItemAction.cancel);
    } else if (isAutomatic && canCancelAutomaticAsAdmin) {
      // Gate 5: só se o caller comprovar admin real no cliente.
      actions.add(HealthScheduleItemAction.cancel);
    }

    return actions;
  }

  static bool canEdit(HealthScheduleItemView item) =>
      forView(item).contains(HealthScheduleItemAction.edit);

  static bool canComplete(
    HealthScheduleItemView item, {
    bool isItemBusy = false,
  }) => forView(
    item,
    isItemBusy: isItemBusy,
  ).contains(HealthScheduleItemAction.complete);

  static bool canCancel(
    HealthScheduleItemView item, {
    bool canCancelAutomaticAsAdmin = false,
    bool isItemBusy = false,
  }) => forView(
    item,
    canCancelAutomaticAsAdmin: canCancelAutomaticAsAdmin,
    isItemBusy: isItemBusy,
  ).contains(HealthScheduleItemAction.cancel);

  static bool showsMenu(
    HealthScheduleItemView item, {
    bool canCancelAutomaticAsAdmin = false,
    bool isItemBusy = false,
  }) => forView(
    item,
    canCancelAutomaticAsAdmin: canCancelAutomaticAsAdmin,
    isItemBusy: isItemBusy,
  ).isNotEmpty;

  /// Helper de domínio a partir de [HealthScheduleItem].
  static Set<HealthScheduleItemAction> forItem(
    HealthScheduleItem item, {
    bool canCancelAutomaticAsAdmin = false,
  }) {
    return forFields(
      lifecycleStatus: item.lifecycleStatus,
      sourceType: item.sourceType,
      revision: item.revision,
      canCancelAutomaticAsAdmin: canCancelAutomaticAsAdmin,
    );
  }
}
