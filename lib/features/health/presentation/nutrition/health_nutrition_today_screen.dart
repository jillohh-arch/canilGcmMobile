import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
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
import 'package:canil_gcm/features/health/presentation/nutrition/health_supplement_form_sheet.dart';
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

        if ((snap.isLoading || controller.isLoading) &&
            snap.valueOrNull == null) {
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
        final hasSafeToday = today?.hasUsableValue == true;
        final temporalState = controller.temporalState;
        final temporalActionsAllowed = controller.temporalActionsAllowed;
        final temporalDiagnosticTitle = controller.temporalDiagnosticTitle;
        final temporalDiagnosticMessage = controller.temporalDiagnosticMessage;
        final temporalStale =
            temporalState == HealthNutritionTemporalState.stale;
        final sourceDegraded =
            snap.isDegraded ||
            (today?.isDegraded == true &&
                today?.code != 'authoritative_time_stale');
        final degraded = sourceDegraded || temporalStale;
        // Integrity conflict com dados utilizáveis: manter tela + aviso (não empty).
        final integrityConflict =
            snapshot.activePlan is NutritionActivePlanIntegrityConflict ||
            (todayModel?.hasActivePlanIntegrityConflict ?? false);
        final occurrenceIntegrityConflict =
            todayModel?.plannedSlotViews.any(
              (slot) => slot.hasOccurrenceConflict,
            ) ??
            false;
        final mutationHealthy =
            !degraded &&
            !integrityConflict &&
            today?.isData == true &&
            mutationController != null &&
            temporalActionsAllowed &&
            _isCanonicalPlanEffectiveAt(
              snapshot.activePlan,
              todayModel?.referenceNow,
            );
        final canonicalPlanLinkSafe =
            snapshot.activePlan is! NutritionActiveCanonicalPlan ||
            _isCanonicalPlanEffectiveAt(
              snapshot.activePlan,
              todayModel?.referenceNow,
            );
        final supplementDogId =
            todayModel?.dogId.trim() ?? snapshot.dogId.trim();
        final supplementIdentityValid = supplementDogId.isNotEmpty;
        final supplementActionEnabled =
            mutationController != null &&
            temporalActionsAllowed &&
            hasSafeToday &&
            today?.isData == true &&
            !degraded &&
            !integrityConflict &&
            canonicalPlanLinkSafe &&
            supplementIdentityValid;
        final planTemporalReason = _planTemporalUnavailableReason(
          snapshot.activePlan,
          todayModel?.referenceNow,
        );
        final supplementUnavailableReason = mutationController == null
            ? null
            : !supplementIdentityValid
            ? 'Identidade do K9 indisponível.'
            : temporalState == HealthNutritionTemporalState.stale
            ? 'Horário aguardando atualização. Atualize antes de registrar.'
            : temporalState == HealthNutritionTemporalState.synchronizing
            ? 'Horário confiável em atualização. Aguarde para registrar.'
            : temporalState == HealthNutritionTemporalState.unavailable
            ? 'Horário confiável indisponível. Registro temporariamente bloqueado.'
            : planTemporalReason ??
                  switch ((
                    mutationController,
                    supplementIdentityValid,
                    sourceDegraded,
                    integrityConflict,
                    canonicalPlanLinkSafe,
                    hasSafeToday && today?.isData == true,
                  )) {
                    (null, _, _, _, _, _) => null,
                    (_, false, _, _, _, _) => 'Identidade do K9 indisponível.',
                    (_, _, true, _, _, _) =>
                      'Registro indisponível enquanto os dados estão parciais.',
                    (_, _, _, true, _, _) =>
                      'Registro indisponível por conflito no plano ativo.',
                    (_, _, _, _, false, _) =>
                      'Registro indisponível porque o plano não está vigente.',
                    (_, _, _, _, _, false) =>
                      'Registro indisponível sem dados diários seguros.',
                    _ => null,
                  };

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
                degradedMessage: today?.message ?? snap.message,
                localDate: todayModel?.localServiceDate,
              ),
              if (temporalDiagnosticTitle != null &&
                  temporalDiagnosticMessage != null) ...[
                const SizedBox(height: 10),
                _TemporalDiagnosticBanner(
                  title: temporalDiagnosticTitle,
                  message: temporalDiagnosticMessage,
                ),
              ],
              if (sourceDegraded) ...[
                const SizedBox(height: 10),
                _DegradedBanner(
                  message:
                      today?.message ??
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
              if (occurrenceIntegrityConflict) ...[
                const SizedBox(height: 10),
                const _DegradedBanner(
                  message:
                      'Dados inconsistentes: execução duplicada detectada. '
                      'A ação deste slot está temporariamente indisponível.',
                ),
              ],
              const SizedBox(height: 14),
              if (hasSafeToday)
                _TodaySummaryCard(
                  plan: snapshot.activePlan,
                  meals: todayModel!.mealsForDailyTotals,
                  plannedMealsCompleted: todayModel.plannedMealsCompleted,
                )
              else
                const _DailyProjectionUnavailable(),
              const SizedBox(height: 14),
              _PlanCard(plan: snapshot.activePlan),
              const SizedBox(height: 14),
              if (hasSafeToday)
                _MealsSection(
                  plan: snapshot.activePlan,
                  mealsToday: todayModel!.meals,
                  serverNow: todayModel.referenceNow,
                  timezone: todayModel.timezone,
                  localServiceDate: todayModel.localServiceDate,
                  mutationEnabled: mutationHealthy,
                  onRegister: (plan, slot) => _openPlannedMealForm(
                    context,
                    plan: plan,
                    slot: slot,
                    serviceDate: todayModel.localServiceDate,
                    authorizedNow: todayModel.referenceNow,
                  ),
                ),
              const SizedBox(height: 14),
              _SupplementsSection(
                plan: snapshot.activePlan,
                administrations:
                    todayModel?.canonicalSupplementLogs ?? const [],
                administrationsAvailable:
                    hasSafeToday &&
                    todayModel!.canonicalSupplementLogsAvailable,
                legacyRegimens: snapshot.legacySupplementRegimens,
                timezone: todayModel?.timezone ?? NutritionPlan.defaultTimezone,
                mutationController: mutationController,
                dogId: supplementDogId,
                actionEnabled: supplementActionEnabled,
                authorizedNow: todayModel?.referenceNow,
                unavailableReason: supplementUnavailableReason,
                canonicalPlanLinkSafe: canonicalPlanLinkSafe,
                dogDisplayName: dogDisplayName,
                onRefreshRequested: controller.refresh,
              ),
              const SizedBox(height: 14),
              _RecentMealsSection(
                meals: snapshot.mergedMeals.take(8).toList(growable: false),
                serviceDate: todayModel?.localServiceDate,
                timezone: todayModel?.timezone ?? NutritionPlan.defaultTimezone,
              ),
            ],
          ),
        );
      },
    );
  }

  bool _isCanonicalPlanEffectiveAt(
    NutritionActivePlanRef? ref,
    DateTime? referenceNow,
  ) {
    if (ref is! NutritionActiveCanonicalPlan) return false;
    if (referenceNow == null) return false;
    try {
      ref.plan.validateForActivation(referenceNow);
      return ref.plan.status == NutritionPlanStatus.active;
    } catch (_) {
      return false;
    }
  }

  String? _planTemporalUnavailableReason(
    NutritionActivePlanRef? ref,
    DateTime? referenceNow,
  ) {
    if (ref is! NutritionActiveCanonicalPlan || referenceNow == null) {
      return null;
    }
    final plan = ref.plan;
    if (referenceNow.isBefore(plan.validFrom)) {
      return 'Registro indisponível: o plano ainda não está vigente.';
    }
    final validUntil = plan.validUntil;
    if (validUntil != null && !referenceNow.isBefore(validUntil)) {
      return 'Registro indisponível: o plano está expirado.';
    }
    return null;
  }

  Future<void> _openPlannedMealForm(
    BuildContext context, {
    required NutritionPlan plan,
    required MealScheduleSlot slot,
    required String serviceDate,
    required DateTime authorizedNow,
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
            'Existe um registro de refeição pendente de confirmação. '
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
            clock: () => authorizedNow,
          ),
        );
    if (!context.mounted || outcome == null) return;
    if (outcome is HealthNutritionMutationUiSuccess) {
      AppFeedback.success(
        context,
        'Refeição registrada com sucesso.',
        title: 'Refeição',
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

class _TemporalDiagnosticBanner extends StatelessWidget {
  const _TemporalDiagnosticBanner({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $message',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.schedule_rounded,
                size: 18,
                color: AppTheme.warningAccent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DegradedBanner extends StatelessWidget {
  const _DegradedBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      excludeSemantics: true,
      child: Container(
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
      ),
    );
  }
}

class _DailyProjectionUnavailable extends StatelessWidget {
  const _DailyProjectionUnavailable();

  @override
  Widget build(BuildContext context) {
    return HealthSummaryCardSurface(
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dados de hoje indisponíveis',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Não foi possível confirmar os registros deste dia. '
              'Tente atualizar.',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodaySummaryCard extends StatelessWidget {
  const _TodaySummaryCard({
    required this.plan,
    required this.meals,
    required this.plannedMealsCompleted,
  });

  final NutritionActivePlanRef? plan;
  final List<NutritionMealReadItem> meals;
  final int plannedMealsCompleted;

  @override
  Widget build(BuildContext context) {
    final planned = switch (plan) {
      NutritionActiveCanonicalPlan(:final plan) => plan.amountGramsPerDay,
      NutritionActiveLegacyPlan(:final view) => view.amountGramsPerDay,
      _ => null,
    };
    final offered = HealthNutritionTodayFormatters.offeredAggregation(meals);
    final consumed = HealthNutritionTodayFormatters.consumedAggregation(meals);
    final mealsPlanned = switch (plan) {
      NutritionActiveCanonicalPlan(:final plan) => plan.mealsPerDay,
      NutritionActiveLegacyPlan(:final view) => view.mealsPerDay,
      _ => null,
    };
    final completed = plannedMealsCompleted;

    final validPlan = planned != null && planned.isFinite && planned > 0;
    final validConsumedMeasured =
        consumed.knownSum != null && consumed.knownSum!.isFinite;

    final progressRatio = validPlan && validConsumedMeasured
        ? (consumed.knownSum! / planned).toDouble()
        : null;

    final progressClamped = progressRatio?.clamp(0.0, 1.0).toDouble();

    final hasRegisteredConsumption =
        consumed.knownSum != null || consumed.hasUnknownConsumed;

    final primaryText = switch ((
      validPlan,
      consumed.knownSum,
      consumed.hasUnknownConsumed,
    )) {
      (true, final double sum, false) =>
        '${HealthNutritionTodayFormatters.grams(sum)} de ${HealthNutritionTodayFormatters.grams(planned)}',
      (true, final double sum, true) =>
        '${HealthNutritionTodayFormatters.grams(sum)} mensurados',
      (true, null, true) => 'Quantidade consumida não medida',
      (true, null, false) => 'Consumo não registrado',
      (false, final double sum, true) =>
        '${HealthNutritionTodayFormatters.grams(sum)} mensurados',
      (false, final double sum, false) =>
        HealthNutritionTodayFormatters.grams(sum),
      (false, null, true) => 'Quantidade consumida não medida',
      (false, null, false) => 'Consumo não registrado',
    };

    final secondaryText = switch ((
      validPlan,
      consumed.knownSum,
      consumed.hasUnknownConsumed,
    )) {
      (true, final double sum, false) =>
        HealthNutritionTodayFormatters.percentageText(
          planned: planned,
          consumedMeasured: sum,
          hasUnknownConsumed: false,
        ),
      (true, _, _) =>
        'Meta diária: ${HealthNutritionTodayFormatters.grams(planned)}',
      (false, _, _) => 'Meta diária não informada',
    };

    final offeredText = offered.hasRegisteredOffer
        ? HealthNutritionTodayFormatters.grams(offered.sum)
        : 'Não registrado';

    final consumedText = consumed.knownSum != null
        ? '${HealthNutritionTodayFormatters.grams(consumed.knownSum)}${consumed.hasUnknownConsumed ? ' mensurados' : ''}'
        : (consumed.hasUnknownConsumed ? 'Não medido' : 'Não registrado');

    final remainingText = HealthNutritionTodayFormatters.remainingText(
      planned: planned,
      consumedMeasured: consumed.knownSum,
      hasUnknownConsumed: consumed.hasUnknownConsumed,
      hasRegisteredConsumption: hasRegisteredConsumption,
    );

    final statusBadge = HealthNutritionTodayFormatters.statusBadgeText(
      planned: planned,
      consumedMeasured: consumed.knownSum,
      hasUnknownConsumed: consumed.hasUnknownConsumed,
      hasAnyMeal: consumed.hasAnyMeal,
    );

    final String semanticsPrimary;
    if (primaryText.contains(' de ')) {
      semanticsPrimary = '$primaryText.';
    } else if (validPlan) {
      semanticsPrimary =
          '$primaryText. Meta diária de ${HealthNutritionTodayFormatters.grams(planned).replaceAll('g', 'gramas')}.';
    } else {
      semanticsPrimary = '$primaryText.';
    }

    final String semanticsOffered;
    if (offered.hasRegisteredOffer) {
      semanticsOffered =
          '${HealthNutritionTodayFormatters.grams(offered.sum).replaceAll('g', 'gramas')} oferecidos.';
    } else {
      semanticsOffered = 'Quantidade oferecida não registrada.';
    }

    final String semanticsConsumed;
    if (consumed.knownSum != null) {
      semanticsConsumed =
          '${HealthNutritionTodayFormatters.grams(consumed.knownSum).replaceAll('g', 'gramas')} consumidos${consumed.hasUnknownConsumed ? ' mensurados' : ''}.';
    } else if (consumed.hasUnknownConsumed) {
      semanticsConsumed = 'Consumo não medido.';
    } else {
      semanticsConsumed = 'Quantidade consumida não registrada.';
    }

    final String semanticsRemaining;
    if (remainingText == 'Não calculado') {
      semanticsRemaining = 'Restante não calculado.';
    } else if (remainingText.startsWith('Até ')) {
      final val = remainingText.substring(4).replaceAll('g', 'gramas');
      semanticsRemaining = 'Restante de até $val pela medição disponível.';
    } else {
      semanticsRemaining =
          'Restante: ${remainingText.replaceAll('g', 'gramas')}.';
    }

    final semanticsLabel = [
      if (statusBadge != null) 'Status: $statusBadge.',
      semanticsPrimary,
      semanticsOffered,
      semanticsConsumed,
      semanticsRemaining,
      if (consumed.hasUnknownConsumed)
        'Há refeição com quantidade consumida não medida.',
      mealsPlanned == null
          ? '$completed refeições executadas.'
          : '$completed de $mealsPlanned refeições executadas.',
    ].join(' ');

    return HealthSummaryCardSurface(
      child: Semantics(
        label: semanticsLabel,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
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
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (statusBadge != null)
                      _chip(statusBadge, _badgeColor(statusBadge)),
                    if (plan is NutritionActiveLegacyPlan)
                      _chip('Plano anterior', AppTheme.attention),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              primaryText,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              secondaryText,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (progressClamped != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progressClamped,
                  minHeight: 8,
                  backgroundColor: AppTheme.outlineVariant,
                  color: AppTheme.success,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                _metricColumn(
                  label: 'OFERECIDO',
                  value: offeredText,
                  valueColor: offered.hasRegisteredOffer
                      ? AppTheme.attention
                      : AppTheme.textMuted,
                ),
                _metricColumn(
                  label: 'CONSUMIDO',
                  value: consumedText,
                  valueColor: consumed.knownSum != null
                      ? AppTheme.success
                      : AppTheme.textMuted,
                ),
                _metricColumn(
                  label: 'RESTANTE',
                  value: remainingText,
                  valueColor: AppTheme.textPrimary,
                ),
              ],
            ),
            if (consumed.hasUnknownConsumed) ...[
              const SizedBox(height: 12),
              Text(
                'Cálculo baseado apenas nas quantidades medidas',
                style: GoogleFonts.inter(
                  color: AppTheme.warningAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              mealsPlanned == null
                  ? '$completed refeições executadas'
                  : '$completed de $mealsPlanned refeições executadas',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricColumn({
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.inter(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Color _badgeColor(String badge) {
    if (badge == 'Meta atingida' || badge == 'Acima da meta') {
      return AppTheme.success;
    }
    if (badge == 'Dentro do plano') {
      return AppTheme.primary;
    }
    if (badge == 'Medição incompleta') {
      return AppTheme.warningAccent;
    }
    return AppTheme.attention;
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
    final timezone = switch (plan) {
      NutritionActiveCanonicalPlan(:final plan) => plan.timezone,
      _ => NutritionPlan.defaultTimezone,
    };

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
                  'Início: ${HealthNutritionTodayFormatters.dateShort(from, timezone: timezone)}',
                ),
              if (until != null)
                _meta(
                  'Até: ${HealthNutritionTodayFormatters.dateShort(until, timezone: timezone)}',
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
    required this.localServiceDate,
    required this.mutationEnabled,
    required this.onRegister,
  });

  final NutritionActivePlanRef? plan;
  final List<NutritionMealReadItem> mealsToday;
  final DateTime serverNow;
  final String timezone;
  final String? localServiceDate;
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
          ...(localServiceDate == null
                  ? canonical.mealSchedule.map(
                      (slot) => NutritionSlotDayView(
                        slot: slot,
                        status: NutritionSlotDayStatus.pending,
                      ),
                    )
                  : NutritionSlotDayDerivation.derive(
                      plan: canonical,
                      mealsForDay: mealsToday,
                      localServiceDate: LocalServiceDate.fromIso(
                        localServiceDate!,
                      ),
                    ))
              .map((slotView) {
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
                    integrityConflict: slotView.hasOccurrenceConflict,
                    onRegister:
                        mutationEnabled &&
                            localServiceDate != null &&
                            !slotView.hasOccurrenceConflict &&
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
                  child: _AdhocMealCard(item: m, timezone: timezone),
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
              child: _AdhocMealCard(
                item: m,
                timezone: timezone,
                legacyPreferred: true,
              ),
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
    this.integrityConflict = false,
    this.onRegister,
  });

  final String periodLabel;
  final String timeLabel;
  final double targetGrams;
  final NutritionTodaySlotUiStatus status;
  final NutritionMealReadItem? meal;
  final bool integrityConflict;
  final VoidCallback? onRegister;

  @override
  Widget build(BuildContext context) {
    final statusColor = integrityConflict
        ? AppTheme.error
        : switch (status) {
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
                  integrityConflict
                      ? 'Dados inconsistentes'
                      : NutritionTodaySlotUi.label(status),
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
          if (integrityConflict) ...[
            const SizedBox(height: 10),
            Semantics(
              container: true,
              liveRegion: true,
              label:
                  'Execução duplicada detectada. '
                  'Ação temporariamente indisponível.',
              excludeSemantics: true,
              child: Text(
                'Execução duplicada detectada. '
                'Ação temporariamente indisponível.',
                style: GoogleFonts.inter(
                  color: AppTheme.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
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
                      ? 'Não informado'
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
            if (meal!.meal.acceptance.value == MealAcceptance.full &&
                meal!.meal.consumedGrams == null) ...[
              const SizedBox(height: 6),
              Text(
                'Quantidade consumida não medida',
                style: GoogleFonts.inter(
                  color: AppTheme.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
  const _AdhocMealCard({
    required this.item,
    required this.timezone,
    this.legacyPreferred = false,
  });

  final NutritionMealReadItem item;
  final String timezone;
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
            HealthNutritionTodayFormatters.timeShort(
              meal.fedAt,
              timezone: timezone,
            ),
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
                      ? 'Consumido: não informado'
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
            if (meal.acceptance.value == MealAcceptance.full &&
                meal.consumedGrams == null) ...[
              const SizedBox(height: 4),
              Text(
                'Quantidade consumida não medida',
                style: GoogleFonts.inter(
                  color: AppTheme.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SupplementsSection extends StatefulWidget {
  const _SupplementsSection({
    required this.plan,
    required this.administrations,
    required this.administrationsAvailable,
    required this.legacyRegimens,
    required this.timezone,
    this.mutationController,
    required this.dogId,
    required this.actionEnabled,
    required this.authorizedNow,
    this.unavailableReason,
    required this.canonicalPlanLinkSafe,
    required this.dogDisplayName,
    required this.onRefreshRequested,
  });

  final NutritionActivePlanRef? plan;
  final List<SupplementLog> administrations;
  final bool administrationsAvailable;
  final List<LegacySupplementRegimenView> legacyRegimens;
  final String timezone;
  final HealthNutritionMutationController? mutationController;
  final String? dogId;
  final bool actionEnabled;
  final DateTime? authorizedNow;
  final String? unavailableReason;
  final bool canonicalPlanLinkSafe;
  final String dogDisplayName;
  final Future<void> Function() onRefreshRequested;

  @override
  State<_SupplementsSection> createState() => _SupplementsSectionState();
}

class _SupplementsSectionState extends State<_SupplementsSection> {
  bool _isOpeningSupplementForm = false;

  NutritionActiveCanonicalPlan? get _activeCanonicalPlan {
    if (!widget.canonicalPlanLinkSafe) return null;
    final p = widget.plan;
    if (p is NutritionActiveCanonicalPlan) return p;
    return null;
  }

  Future<void> _openSupplementForm() async {
    final mutation = widget.mutationController;
    if (mutation == null) return;
    final dogId = widget.dogId?.trim();
    if (!widget.actionEnabled ||
        dogId == null ||
        dogId.isEmpty ||
        widget.authorizedNow == null ||
        _isOpeningSupplementForm) {
      return;
    }

    setState(() => _isOpeningSupplementForm = true);

    final activePlan = _activeCanonicalPlan;
    final tz = activePlan?.plan.timezone ?? NutritionPlan.defaultTimezone;

    HealthNutritionMutationUiOutcome? outcome;
    try {
      outcome = await showModalBottomSheet<HealthNutritionMutationUiOutcome>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppTheme.surfacePanel,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => HealthSupplementFormSheet(
          dogId: dogId,
          dogDisplayName: widget.dogDisplayName,
          controller: mutation,
          onRefreshRequested: widget.onRefreshRequested,
          timezone: tz,
          clock: () => widget.authorizedNow!,
          activePlan: activePlan,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isOpeningSupplementForm = false);
      }
    }

    if (!mounted) return;
    if (outcome is HealthNutritionMutationUiSuccess) {
      AppFeedback.success(
        context,
        'Suplemento registrado com sucesso.',
        title: 'Suplemento',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final planRegimens = switch (widget.plan) {
      NutritionActiveCanonicalPlan(:final plan) => plan.supplements,
      _ => const <NutritionPlanSupplementRegimen>[],
    };

    final hasMutation = widget.mutationController != null;
    final actionEnabled = widget.actionEnabled && !_isOpeningSupplementForm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'SUPLEMENTOS EM USO',
                style: GoogleFonts.inter(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.55,
                ),
              ),
            ),
            if (hasMutation)
              Semantics(
                button: true,
                enabled: actionEnabled,
                label: actionEnabled
                    ? 'Registrar suplemento'
                    : 'Registrar suplemento indisponível: '
                          '${widget.unavailableReason ?? 'contexto inseguro'}',
                child: ExcludeSemantics(
                  child: TextButton.icon(
                    onPressed: actionEnabled ? _openSupplementForm : null,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Registrar'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: AppTheme.primary,
                      textStyle: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (hasMutation &&
            !widget.actionEnabled &&
            widget.unavailableReason != null) ...[
          Text(
            widget.unavailableReason!,
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        if (planRegimens.isEmpty && widget.legacyRegimens.isEmpty)
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
                      '${r.dose} ${r.unit.displayLabel} · ${r.frequency}',
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
          ...widget.legacyRegimens.map(
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
          'ADMINISTRAÇÕES DE HOJE',
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.55,
          ),
        ),
        const SizedBox(height: 8),
        if (!widget.administrationsAvailable)
          HealthSummaryCardSurface(
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Administrações de hoje indisponíveis',
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Não foi possível confirmar os registros deste dia. '
                    'Tente atualizar.',
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (widget.administrations.isEmpty)
          HealthSummaryCardSurface(
            child: Text(
              planRegimens.isNotEmpty || widget.legacyRegimens.isNotEmpty
                  ? 'Nenhuma administração registrada hoje. '
                        'Os suplementos em uso aparecem acima.'
                  : 'Nenhuma administração registrada hoje.',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          )
        else
          ...widget.administrations.map(
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
                      '${a.dose} ${a.unit.displayLabel} · '
                      '${HealthNutritionTodayFormatters.timeShort(a.administeredAt, timezone: widget.timezone)}',
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
  final String? serviceDate;
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
                ? '${HealthNutritionTodayFormatters.grams(m.meal.offeredGrams)} oferecidos · consumo não informado'
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
                            '${HealthNutritionTodayFormatters.recentDateTimeLabel(instant: m.meal.fedAt, serviceDate: serviceDate ?? '0001-01-01', timezone: timezone)} · $line'
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
