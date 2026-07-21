import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/legacy_nutrition_views.dart';
import 'package:canil_gcm/features/health/domain/meal_occurrence.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan_regimen.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_read_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_outcome.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_planned_meal_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_today_formatters.dart';
import 'package:canil_gcm/features/health/presentation/shared/states/health_state_views.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_card_surface.dart';

/// Nutrição Hoje — coexistência read + execução planned fail-closed (Gate 5C.2A).
class HealthNutritionTodayScreen extends StatelessWidget {
  final HealthNutritionReadController controller;
  final HealthNutritionMutationController? mutationController;
  final String dogDisplayName;
  final double bottomPadding;

  const HealthNutritionTodayScreen({
    super.key,
    required this.controller,
    this.mutationController,
    required this.dogDisplayName,
    this.bottomPadding = 24,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snap = controller.snapshotResult;
        final today = controller.todayResult;

        if (snap.isLoading || controller.isLoading) {
          return const HealthLoadingView(message: 'Carregando nutrição…');
        }

        if (snap.isOffline) {
          return HealthErrorView(
            title: 'Sem conexão',
            message:
                snap.message ??
                'Não foi possível carregar a nutrição. Verifique a conexão.',
            onRetry: () {
              // ignore: discarded_futures
              controller.refresh();
            },
          );
        }

        if (snap.isError) {
          return HealthErrorView(
            title: 'Não foi possível carregar',
            message:
                snap.message ??
                'Falha ao carregar os dados de nutrição. Tente novamente.',
            onRetry: () {
              // ignore: discarded_futures
              controller.refresh();
            },
          );
        }

        if (snap.isEmpty) {
          return HealthEmptyView(
            title: 'Sem registros de nutrição',
            message:
                'Não há plano nem refeições canônicas ou legadas para este K9.',
            icon: Icons.restaurant_outlined,
          );
        }

        // data ou degraded com valor utilizável
        final snapshot = snap.valueOrNull;
        if (snapshot == null) {
          return HealthErrorView(
            title: 'Não foi possível carregar',
            message: 'Snapshot de nutrição ausente.',
            onRetry: () {
              // ignore: discarded_futures
              controller.refresh();
            },
          );
        }

        final todayModel = today?.valueOrNull;
        final degraded = snap.isDegraded;
        // Integrity conflict com dados utilizáveis: manter tela + aviso (não empty).
        final integrityConflict =
            snapshot.activePlan is NutritionActivePlanIntegrityConflict ||
            (todayModel?.hasActivePlanIntegrityConflict ?? false);
        final mutationHealthy =
            !degraded &&
            !integrityConflict &&
            today?.isData == true &&
            mutationController != null &&
            _isCanonicalPlanEffectiveNow(snapshot.activePlan);

        return RefreshIndicator(
          color: AppTheme.primary,
          backgroundColor: AppTheme.surfacePanel,
          onRefresh: controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding + 16),
            children: [
              _Header(
                dogName: dogDisplayName,
                degraded: degraded,
                degradedMessage: snap.message,
                localDate: todayModel?.localServiceDate,
              ),
              if (degraded) ...[
                const SizedBox(height: 10),
                _DegradedBanner(
                  message:
                      snap.message ??
                      'Atualização parcial: alguns dados podem estar incompletos.',
                ),
              ],
              if (integrityConflict) ...[
                const SizedBox(height: 10),
                _DegradedBanner(
                  message:
                      'Não foi possível carregar Nutrição com segurança: '
                      'há mais de um plano canônico ativo.',
                ),
              ],
              const SizedBox(height: 14),
              _TodaySummaryCard(
                plan: snapshot.activePlan,
                meals: todayModel?.meals ?? const [],
              ),
              const SizedBox(height: 14),
              _PlanCard(plan: snapshot.activePlan),
              const SizedBox(height: 14),
              _MealsSection(
                plan: snapshot.activePlan,
                mealsToday: todayModel?.meals ?? const [],
                serverNow: DateTime.now().toUtc(),
                timezone: todayModel?.timezone ?? NutritionPlan.defaultTimezone,
                mutationEnabled: mutationHealthy,
                onRegister: (plan, slot) => _openPlannedMealForm(
                  context,
                  plan: plan,
                  slot: slot,
                  serviceDate: todayModel!.localServiceDate,
                ),
              ),
              const SizedBox(height: 14),
              _SupplementsSection(
                plan: snapshot.activePlan,
                administrations:
                    todayModel?.canonicalSupplementLogs ??
                    snapshot.canonicalSupplementLogs,
                legacyRegimens:
                    todayModel?.legacySupplementRegimens ??
                    snapshot.legacySupplementRegimens,
              ),
              const SizedBox(height: 14),
              _RecentMealsSection(
                meals: snapshot.mergedMeals.take(8).toList(growable: false),
                serviceDate:
                    todayModel?.localServiceDate ??
                    LocalServiceDate.fromInstant(
                      DateTime.now().toUtc(),
                      timezone:
                          todayModel?.timezone ?? NutritionPlan.defaultTimezone,
                    ).isoDate,
                timezone: todayModel?.timezone ?? NutritionPlan.defaultTimezone,
              ),
            ],
          ),
        );
      },
    );
  }

  bool _isCanonicalPlanEffectiveNow(NutritionActivePlanRef? ref) {
    if (ref is! NutritionActiveCanonicalPlan) return false;
    try {
      ref.plan.validateForActivation(DateTime.now().toUtc());
      return ref.plan.status == NutritionPlanStatus.active;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openPlannedMealForm(
    BuildContext context, {
    required NutritionPlan plan,
    required MealScheduleSlot slot,
    required String serviceDate,
  }) async {
    final mutation = mutationController;
    if (mutation == null) return;
    final pending = mutation.pendingIntent;
    final draft = pending?.plannedMealDraft;
    if (pending != null &&
        (draft == null ||
            draft.dogId != plan.dogId ||
            draft.planId != plan.id ||
            draft.plannedMealId != slot.id)) {
      final action = await showDialog<_PendingAction>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppTheme.surfacePanel,
          title: const Text('Registro pendente'),
          content: const Text(
            'Existe um registro de alimentação pendente de confirmação. '
            'Conclua ou descarte essa tentativa antes de iniciar outra.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            if (draft != null)
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, _PendingAction.resume),
                child: const Text('Retomar tentativa'),
              ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _PendingAction.discard),
              child: const Text('Descartar tentativa'),
            ),
          ],
        ),
      );
      if (!context.mounted || action == null) return;
      if (action == _PendingAction.discard) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppTheme.surfacePanel,
            title: const Text('Descartar tentativa?'),
            content: const Text(
              'A tentativa atual deixará de ser reutilizada. Isso não confirma '
              'que o backend deixou de receber um envio anterior.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Manter tentativa'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Descartar'),
              ),
            ],
          ),
        );
        if (confirmed == true) mutation.discardIntent();
        return;
      }
      if (action == _PendingAction.resume && draft != null) {
        MealScheduleSlot? pendingSlot;
        for (final item in plan.mealSchedule) {
          if (item.id == draft.plannedMealId) {
            pendingSlot = item;
            break;
          }
        }
        if (pendingSlot == null) return;
        slot = pendingSlot;
      }
    }

    final outcome =
        await showModalBottomSheet<HealthNutritionMutationUiOutcome>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: AppTheme.background,
          builder: (_) => HealthPlannedMealFormSheet(
            dogDisplayName: dogDisplayName,
            plan: plan,
            slot: slot,
            localServiceDate: serviceDate,
            controller: mutation,
            onRefreshRequested: controller.refresh,
          ),
        );
    if (!context.mounted || outcome == null) return;
    if (outcome is HealthNutritionMutationUiSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Refeição registrada com sucesso.')),
      );
    }
  }
}

enum _PendingAction { resume, discard }

// ── Sections ────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.dogName,
    required this.degraded,
    this.degradedMessage,
    this.localDate,
  });

  final String dogName;
  final bool degraded;
  final String? degradedMessage;
  final String? localDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NUTRIÇÃO',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Plano alimentar, consumo diário e acompanhamento · $dogName',
          style: GoogleFonts.inter(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        if (localDate != null) ...[
          const SizedBox(height: 6),
          Text(
            'Serviço: $localDate',
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

class _DegradedBanner extends StatelessWidget {
  const _DegradedBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppTheme.warningAccent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodaySummaryCard extends StatelessWidget {
  const _TodaySummaryCard({required this.plan, required this.meals});

  final NutritionActivePlanRef? plan;
  final List<NutritionMealReadItem> meals;

  @override
  Widget build(BuildContext context) {
    final planned = switch (plan) {
      NutritionActiveCanonicalPlan(:final plan) => plan.amountGramsPerDay,
      NutritionActiveLegacyPlan(:final view) => view.amountGramsPerDay,
      _ => null,
    };
    final offered = HealthNutritionTodayFormatters.offeredSum(meals);
    final consumed = HealthNutritionTodayFormatters.consumedAggregation(meals);
    final mealsPlanned = switch (plan) {
      NutritionActiveCanonicalPlan(:final plan) => plan.mealsPerDay,
      NutritionActiveLegacyPlan(:final view) => view.mealsPerDay,
      _ => null,
    };
    final completed = meals.length;

    final consumedLabel = consumed.knownSum == null
        ? '—'
        : HealthNutritionTodayFormatters.grams(consumed.knownSum);
    final consumedColor = consumed.knownSum == null
        ? AppTheme.textMuted
        : AppTheme.success;

    String? pctLabel;
    double progress = 0;
    if (planned != null &&
        planned > 0 &&
        consumed.knownSum != null &&
        !consumed.hasUnknownConsumed) {
      progress = (consumed.knownSum! / planned).clamp(0.0, 1.0);
      pctLabel = '${(progress * 100).round()}% da meta diária';
    } else if (consumed.hasUnknownConsumed) {
      pctLabel = 'Consumo parcialmente informado';
    }

    return HealthSummaryCardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 6,
            spacing: 8,
            children: [
              Text(
                'CONSUMO DE HOJE',
                style: GoogleFonts.inter(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              if (plan is NutritionActiveLegacyPlan)
                _chip('Plano anterior', AppTheme.attention),
              if (plan is NutritionActiveCanonicalPlan)
                _chip('Plano ativo', AppTheme.success),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: planned == null
                      ? 'Sem meta ativa'
                      : consumed.knownSum == null
                      ? '—'
                      : '${consumed.knownSum!.round()} g',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: planned == null ? 20 : 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (planned != null)
                  TextSpan(
                    text: ' de ${planned.round()} g',
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (pctLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              pctLabel,
              style: GoogleFonts.inter(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (planned != null && consumed.knownSum != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: AppTheme.outlineVariant,
                valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _metric(
                'Oferecido',
                HealthNutritionTodayFormatters.grams(offered),
              ),
              _metric('Consumido', consumedLabel, valueColor: consumedColor),
              _metric(
                'Refeições',
                mealsPlanned == null
                    ? '$completed'
                    : '$completed / $mealsPlanned',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, {Color? valueColor}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.inter(
              color: valueColor ?? AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});
  final NutritionActivePlanRef? plan;

  @override
  Widget build(BuildContext context) {
    if (plan == null) {
      return HealthSummaryCardSurface(
        child: Text(
          'Nenhum plano alimentar ativo encontrado.',
          style: GoogleFonts.inter(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      );
    }

    if (plan is NutritionActivePlanIntegrityConflict) {
      final c = plan! as NutritionActivePlanIntegrityConflict;
      return HealthSummaryCardSurface(
        borderColor: AppTheme.error.withValues(alpha: 0.45),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Integridade do plano',
              style: GoogleFonts.inter(
                color: AppTheme.error,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Há ${c.activeCount} planos canônicos ativos. '
              'A visualização não escolhe um plano automaticamente.',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    final isLegacy = plan is NutritionActiveLegacyPlan;
    final food = HealthNutritionTodayFormatters.foodTypeOf(plan);
    final planned = switch (plan) {
      NutritionActiveCanonicalPlan(:final plan) => plan.amountGramsPerDay,
      NutritionActiveLegacyPlan(:final view) => view.amountGramsPerDay,
      _ => null,
    };
    final mealsPerDay = switch (plan) {
      NutritionActiveCanonicalPlan(:final plan) => plan.mealsPerDay,
      NutritionActiveLegacyPlan(:final view) => view.mealsPerDay,
      _ => null,
    };
    final from = switch (plan) {
      NutritionActiveCanonicalPlan(:final plan) => plan.validFrom,
      NutritionActiveLegacyPlan(:final view) => view.vigentFrom,
      _ => null,
    };
    final until = switch (plan) {
      NutritionActiveCanonicalPlan(:final plan) => plan.validUntil,
      NutritionActiveLegacyPlan(:final view) => view.vigentUntil,
      _ => null,
    };
    final notes = HealthNutritionTodayFormatters.planNotes(plan);
    final responsible = HealthNutritionTodayFormatters.responsibleName(plan);

    return HealthSummaryCardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            HealthNutritionTodayFormatters.planSourceLabel(plan).toUpperCase(),
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.restaurant_rounded,
                size: 22,
                color: isLegacy ? AppTheme.attention : AppTheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  food,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              if (planned != null) _meta('Meta diária: ${planned.round()} g'),
              if (mealsPerDay != null) _meta('$mealsPerDay refeições'),
              if (from != null)
                _meta(
                  'Início: ${HealthNutritionTodayFormatters.dateShort(from)}',
                ),
              if (until != null)
                _meta(
                  'Até: ${HealthNutritionTodayFormatters.dateShort(until)}',
                ),
              if (responsible != null && responsible.isNotEmpty)
                _meta('Resp.: $responsible'),
            ],
          ),
          if (isLegacy) ...[
            const SizedBox(height: 8),
            Text(
              'Horários de refeição canônicos não disponíveis neste plano.',
              style: GoogleFonts.inter(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ],
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              notes,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _meta(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: AppTheme.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _MealsSection extends StatelessWidget {
  const _MealsSection({
    required this.plan,
    required this.mealsToday,
    required this.serverNow,
    required this.timezone,
    required this.mutationEnabled,
    required this.onRegister,
  });

  final NutritionActivePlanRef? plan;
  final List<NutritionMealReadItem> mealsToday;
  final DateTime serverNow;
  final String timezone;
  final bool mutationEnabled;
  final void Function(NutritionPlan plan, MealScheduleSlot slot) onRegister;

  @override
  Widget build(BuildContext context) {
    final canonical = plan is NutritionActiveCanonicalPlan
        ? (plan! as NutritionActiveCanonicalPlan).plan
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'REFEIÇÕES DE HOJE',
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.55,
          ),
        ),
        const SizedBox(height: 8),
        if (canonical != null) ...[
          ...NutritionSlotDayDerivation.derive(
            plan: canonical,
            mealsForDay: mealsToday,
          ).map((slotView) {
            final uiStatus = NutritionTodaySlotUi.statusFor(
              slot: slotView.slot,
              meal: slotView.meal,
              serverNow: serverNow,
              timezone: timezone,
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MealSlotCard(
                periodLabel: HealthNutritionTodayFormatters.periodLabel(
                  slotView.slot.period,
                ),
                timeLabel: slotView.slot.scheduledTime.value,
                targetGrams: slotView.slot.targetGrams,
                meal: slotView.meal,
                status: uiStatus,
                onRegister:
                    mutationEnabled &&
                        uiStatus != NutritionTodaySlotUiStatus.completed
                    ? () => onRegister(canonical, slotView.slot)
                    : null,
              ),
            );
          }),
          // Meals do dia sem slot (ad hoc canônico / não planejado)
          ...mealsToday
              .where((m) => m.meal.plannedMealId == null)
              .map(
                (m) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AdhocMealCard(item: m),
                ),
              ),
        ] else if (mealsToday.isEmpty) ...[
          HealthSummaryCardSurface(
            child: Text(
              plan is NutritionActiveLegacyPlan
                  ? 'Nenhuma refeição registrada hoje para o plano anterior.'
                  : 'Nenhuma refeição registrada hoje.',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ] else ...[
          // Legacy: listar refeições sem inventar slots
          ...mealsToday.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AdhocMealCard(item: m, legacyPreferred: true),
            ),
          ),
        ],
      ],
    );
  }
}

class _MealSlotCard extends StatelessWidget {
  const _MealSlotCard({
    required this.periodLabel,
    required this.timeLabel,
    required this.targetGrams,
    required this.status,
    this.meal,
    this.onRegister,
  });

  final String periodLabel;
  final String timeLabel;
  final double targetGrams;
  final NutritionTodaySlotUiStatus status;
  final NutritionMealReadItem? meal;
  final VoidCallback? onRegister;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (status) {
      NutritionTodaySlotUiStatus.completed => AppTheme.success,
      NutritionTodaySlotUiStatus.late => AppTheme.warning,
      NutritionTodaySlotUiStatus.pending => AppTheme.warningAccent,
    };

    return HealthSummaryCardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  periodLabel.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  NutritionTodaySlotUi.label(status),
                  style: GoogleFonts.inter(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$timeLabel · ${targetGrams.round()} g previstos',
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (meal != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _kv(
                  'Oferecido',
                  HealthNutritionTodayFormatters.grams(meal!.meal.offeredGrams),
                ),
                _kv(
                  'Consumido',
                  meal!.meal.consumedGrams == null
                      ? '—'
                      : HealthNutritionTodayFormatters.grams(
                          meal!.meal.consumedGrams,
                        ),
                  valueColor: meal!.meal.consumedGrams == null
                      ? AppTheme.textMuted
                      : AppTheme.success,
                ),
                _kv(
                  'Aceitação',
                  HealthNutritionTodayFormatters.acceptanceLabel(
                    meal!.meal.acceptance,
                  ),
                ),
              ],
            ),
          ] else if (onRegister != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRegister,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Registrar refeição'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {Color? valueColor}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k,
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            v,
            style: GoogleFonts.inter(
              color: valueColor ?? AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdhocMealCard extends StatelessWidget {
  const _AdhocMealCard({required this.item, this.legacyPreferred = false});

  final NutritionMealReadItem item;
  final bool legacyPreferred;

  @override
  Widget build(BuildContext context) {
    final meal = item.meal;
    final isLegacy =
        legacyPreferred || item.origin != NutritionDataOrigin.canonical;
    return HealthSummaryCardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  HealthNutritionTodayFormatters.periodLabel(
                    meal.period,
                  ).toUpperCase(),
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              if (isLegacy)
                Text(
                  HealthNutritionTodayFormatters.originBadge(item.origin),
                  style: GoogleFonts.inter(
                    color: AppTheme.attention,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            HealthNutritionTodayFormatters.timeShort(meal.fedAt),
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Oferecido: ${HealthNutritionTodayFormatters.grams(meal.offeredGrams)}',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  meal.consumedGrams == null
                      ? 'Consumido: —'
                      : 'Consumido: ${HealthNutritionTodayFormatters.grams(meal.consumedGrams)}',
                  style: GoogleFonts.inter(
                    color: meal.consumedGrams == null
                        ? AppTheme.textMuted
                        : AppTheme.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (!isLegacy || meal.acceptance.isKnown) ...[
            const SizedBox(height: 4),
            Text(
              HealthNutritionTodayFormatters.acceptanceLabel(meal.acceptance),
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SupplementsSection extends StatelessWidget {
  const _SupplementsSection({
    required this.plan,
    required this.administrations,
    required this.legacyRegimens,
  });

  final NutritionActivePlanRef? plan;
  final List<SupplementLog> administrations;
  final List<LegacySupplementRegimenView> legacyRegimens;

  @override
  Widget build(BuildContext context) {
    final planRegimens = switch (plan) {
      NutritionActiveCanonicalPlan(:final plan) => plan.supplements,
      _ => const <NutritionPlanSupplementRegimen>[],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SUPLEMENTOS EM USO',
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.55,
          ),
        ),
        const SizedBox(height: 8),
        if (planRegimens.isEmpty && legacyRegimens.isEmpty)
          HealthSummaryCardSurface(
            child: Text(
              'Nenhum suplemento em uso registrado.',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else ...[
          ...planRegimens.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HealthSummaryCardSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${r.dose} ${r.unit.wireName} · ${r.frequency}',
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if ((r.instructions ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        r.instructions!,
                        style: GoogleFonts.inter(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          ...legacyRegimens.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HealthSummaryCardSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.name,
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Text(
                          'Em uso (legado)',
                          style: GoogleFonts.inter(
                            color: AppTheme.attention,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (r.doseText.isNotEmpty) r.doseText,
                        if ((r.unitText ?? '').isNotEmpty) r.unitText,
                        if ((r.frequencyText ?? '').isNotEmpty) r.frequencyText,
                      ].whereType<String>().join(' · '),
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Não é uma administração pontual.',
                      style: GoogleFonts.inter(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'ADMINISTRAÇÕES REGISTRADAS',
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.55,
          ),
        ),
        const SizedBox(height: 8),
        if (administrations.isEmpty)
          HealthSummaryCardSurface(
            child: Text(
              planRegimens.isNotEmpty || legacyRegimens.isNotEmpty
                  ? 'Nenhuma administração registrada. '
                        'Os suplementos em uso aparecem acima.'
                  : 'Nenhuma administração registrada.',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          )
        else
          ...administrations.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HealthSummaryCardSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.supplementName,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${a.dose} ${a.unit.wireName} · '
                      '${HealthNutritionTodayFormatters.timeShort(a.administeredAt)}',
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if ((a.notes ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        a.notes!,
                        style: GoogleFonts.inter(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RecentMealsSection extends StatelessWidget {
  const _RecentMealsSection({
    required this.meals,
    required this.serviceDate,
    required this.timezone,
  });
  final List<NutritionMealReadItem> meals;
  final String serviceDate;
  final String timezone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'REGISTROS RECENTES',
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.55,
          ),
        ),
        const SizedBox(height: 8),
        if (meals.isEmpty)
          HealthSummaryCardSurface(
            child: Text(
              'Sem refeições recentes.',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          ...meals.map((m) {
            final consumed = m.meal.consumedGrams;
            final line = consumed == null
                ? '${HealthNutritionTodayFormatters.grams(m.meal.offeredGrams)} oferecidos'
                : '${HealthNutritionTodayFormatters.grams(consumed)} consumidos';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: HealthSummaryCardSurface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.restaurant_rounded,
                      size: 18,
                      color: m.origin == NutritionDataOrigin.canonical
                          ? AppTheme.primary
                          : AppTheme.attention,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            HealthNutritionTodayFormatters.periodLabel(
                              m.meal.period,
                            ),
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${HealthNutritionTodayFormatters.recentDateTimeLabel(instant: m.meal.fedAt, serviceDate: serviceDate, timezone: timezone)} · $line'
                            '${m.origin != NutritionDataOrigin.canonical ? ' · legado' : ''}',
                            style: GoogleFonts.inter(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
