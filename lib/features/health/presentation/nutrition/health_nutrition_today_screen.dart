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
import 'package:canil_gcm/features/health/presentation/nutrition/widgets/health_nutrition_history_timeline.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/widgets/health_nutrition_period_grid.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/widgets/health_nutrition_period_visuals.dart';
import 'package:canil_gcm/features/health/presentation/shared/states/health_state_views.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_card_surface.dart';

/// Nutrição Hoje — coexistência read + execução planned fail-closed (Gate 5C.2A).
class HealthNutritionTodayScreen extends StatelessWidget {
  final HealthNutritionReadController controller;
  final HealthNutritionMutationController? mutationController;
  final String dogDisplayName;

  /// PASS 03C: repassa ao sheet planejado a foto já resolvida pelo chamador.
  /// Passthrough puro — esta tela não a renderiza nem a busca.
  final String? dogPhotoUrl;
  final double bottomPadding;

  const HealthNutritionTodayScreen({
    super.key,
    required this.controller,
    this.mutationController,
    required this.dogDisplayName,
    this.dogPhotoUrl,
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
            // PASS 03D: alinhamento horizontal com o card das tabs.
            // O `HealthShellScreen` já aplica `contentPadding.left/right` (16)
            // à área de seção, então o 16 que existia aqui era um SEGUNDO
            // inset, deixando o card 32px de cada lado — 16 mais estreito que
            // as tabs. Zero horizontal aqui é como Resumo, Agenda e Timeline
            // já se comportam: quem manda no eixo horizontal é o shell.
            padding: EdgeInsets.fromLTRB(0, 8, 0, bottomPadding + 16),
            children: [
              // PASS 02: o `_Header` grande saiu daqui. O contexto (K9 + data de
              // serviço) agora vive como linha discreta DENTRO do card
              // principal, abaixo.
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
              // ── CARD PRINCIPAL ÚNICO (PASS 02) ──────────────────────────
              // Antes eram três surfaces independentes empilhadas (consumo,
              // plano, grid), o que fazia a tela parecer uma sequência de
              // módulos soltos. Agora é UM card: contexto -> produto -> meta ->
              // consumo de hoje -> grid 2×2. Os conteúdos internos são os
              // mesmos widgets, apenas sem surface própria (`nested: true`).
              HealthSummaryCardSurface(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(
                      dogName: dogDisplayName,
                      degraded: degraded,
                      degradedMessage: today?.message ?? snap.message,
                      localDate: todayModel?.localServiceDate,
                    ),
                    const SizedBox(height: 10),
                    _PlanCard(plan: snapshot.activePlan, nested: true),
                    const SizedBox(height: 12),
                    if (hasSafeToday)
                      _TodaySummaryCard(
                        plan: snapshot.activePlan,
                        meals: todayModel!.mealsForDailyTotals,
                        plannedMealsCompleted: todayModel.plannedMealsCompleted,
                        nested: true,
                      )
                    else
                      const _DailyProjectionUnavailable(nested: true),
                    if (hasSafeToday) ...[
                      const SizedBox(height: 12),
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
                        supplementQuadrant: _buildSupplementQuadrant(
                          context,
                          plan: snapshot.activePlan,
                          administrationCount:
                              todayModel.canonicalSupplementLogsAvailable
                              ? todayModel.canonicalSupplementLogs.length
                              : null,
                          legacyRegimenCount:
                              snapshot.legacySupplementRegimens.length,
                          mutationController: mutationController,
                          dogId: supplementDogId,
                          actionEnabled: supplementActionEnabled,
                          authorizedNow: todayModel.referenceNow,
                          canonicalPlanLinkSafe: canonicalPlanLinkSafe,
                          dogDisplayName: dogDisplayName,
                          onRefreshRequested: controller.refresh,
                        ),
                      ),
                    ],
                  ],
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
                // Mesma fonte da seção "ADMINISTRAÇÕES DE HOJE" — só é passada
                // quando a leitura é confiável, para não exibir lista parcial
                // como se fosse completa.
                supplementAdministrations:
                    hasSafeToday && todayModel!.canonicalSupplementLogsAvailable
                    ? todayModel.canonicalSupplementLogs
                    : const [],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Monta o quarto quadrante (Suplemento).
  ///
  /// HONESTIDADE DE STATUS: este quadrante NÃO exibe Pendente/Concluída. O
  /// contrato de suplemento proíbe explicitamente inferir que uma administração
  /// completou uma frequência prescrita (ver `HealthSupplementFormSheet`), então
  /// um badge de status aqui seria semântica inventada. Mostramos contagens
  /// factuais: regimes previstos e administrações registradas hoje.
  ///
  /// `administrationCount == null` significa indisponível (não zero) — a
  /// distinção que o read model já carrega em
  /// `canonicalSupplementLogsAvailable`.
  HealthNutritionQuadrantData _buildSupplementQuadrant(
    BuildContext context, {
    required NutritionActivePlanRef? plan,
    required int? administrationCount,
    required int legacyRegimenCount,
    required HealthNutritionMutationController? mutationController,
    required String dogId,
    required bool actionEnabled,
    required DateTime? authorizedNow,
    required bool canonicalPlanLinkSafe,
    required String dogDisplayName,
    required Future<void> Function() onRefreshRequested,
  }) {
    final canonicalPlan = canonicalPlanLinkSafe &&
            plan is NutritionActiveCanonicalPlan
        ? plan
        : null;
    final regimenCount =
        (canonicalPlan?.plan.supplements.length ?? 0) + legacyRegimenCount;

    final lines = <String>[];
    if (regimenCount > 0) {
      lines.add(
        regimenCount == 1
            ? '1 regime previsto'
            : '$regimenCount regimes previstos',
      );
    }
    if (administrationCount == null) {
      // Copy deliberadamente distinta da seção de suplementos abaixo, que diz
      // "Administrações de hoje indisponíveis". Repetir a MESMA string aqui
      // duplicaria a mensagem na tela (e há teste que exige exatamente uma).
      // Indisponível continua sendo indisponível — nunca zero.
      lines.add('Administrações de hoje sem leitura');
    } else {
      lines.add(
        administrationCount == 1
            ? '1 administração hoje'
            : '$administrationCount administrações hoje',
      );
    }

    final canRegister =
        mutationController != null &&
        actionEnabled &&
        dogId.isNotEmpty &&
        authorizedNow != null;

    return HealthNutritionQuadrantData(
      group: HealthNutritionPeriodGroup.supplement,
      slots: const [],
      ctaLabel: 'Registrar suplemento',
      summaryLine: lines.join(' · '),
      onAction: canRegister
          ? () => openHealthSupplementFormSheet(
              context: context,
              dogId: dogId,
              dogDisplayName: dogDisplayName,
              mutation: mutationController,
              onRefreshRequested: onRefreshRequested,
              authorizedNow: authorizedNow,
              activePlan: canonicalPlan,
            )
          : null,
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
            dogPhotoUrl: dogPhotoUrl,
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
    // PASS 02: a apresentação grande de "NUTRIÇÃO" saiu — a tab ativa já
    // estabelece o contexto e o bloco custava altura sem hierarquia. Sobra uma
    // linha discreta DENTRO do card principal, com o K9 e a data de serviço,
    // que são contexto funcional (a data prova qual dia a tela projeta).
    // `Wrap` em vez de `Row`: a 320dp com textScale alto os dois rótulos não
    // cabem na mesma linha, e um `Row` com Text sem constraint estoura.
    return Wrap(
      spacing: 8,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'NUTRIÇÃO · $dogName',
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 0.6,
          ),
        ),
        if (localDate != null)
          Text(
            'Serviço: $localDate',
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
            ),
          ),
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
  const _DailyProjectionUnavailable({this.nested = false});

  /// Quando `true`, renderiza sem surface própria — o card principal já é a
  /// surface. Evita "card dentro de card".
  final bool nested;

  @override
  Widget build(BuildContext context) {
    final body = Semantics(
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
      );

    return nested ? body : HealthSummaryCardSurface(child: body);
  }
}

class _TodaySummaryCard extends StatelessWidget {
  const _TodaySummaryCard({
    required this.plan,
    required this.meals,
    required this.plannedMealsCompleted,
    this.nested = false,
  });

  final NutritionActivePlanRef? plan;
  final List<NutritionMealReadItem> meals;
  final int plannedMealsCompleted;

  /// Quando `true`, é uma FAIXA dentro do card principal, não uma surface.
  ///
  /// Todos os fatos continuam presentes (OFERECIDO/CONSUMIDO/RESTANTE, barra de
  /// progresso, avisos de medição parcial) e o `Semantics` que os testes usam
  /// como âncora é preservado — muda só a densidade e o container.
  final bool nested;

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
      (false, final double sum, false) => HealthNutritionTodayFormatters.grams(
        sum,
      ),
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

    final body = Semantics(
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
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  primaryText,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: nested ? 14 : 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  secondaryText,
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (progressClamped != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progressClamped,
                  minHeight: 5,
                  backgroundColor: AppTheme.outlineVariant,
                  color: AppTheme.success,
                ),
              ),
            ],
            const SizedBox(height: 8),
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
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  mealsPlanned == null
                      ? '$completed refeições executadas'
                      : '$completed de $mealsPlanned refeições executadas',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (consumed.hasUnknownConsumed)
                  Text(
                    'Cálculo baseado apenas nas quantidades medidas',
                    style: GoogleFonts.inter(
                      color: AppTheme.warningAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      );

    return nested ? body : HealthSummaryCardSurface(child: body);
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
    return AppTheme.textMuted;
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Miniatura do produto do plano.
///
/// [imageUrl] é o ponto de entrada para quando a integração com o estoque Web
/// existir. Enquanto o read model não tiver o campo, o parâmetro fica `null` e o
/// fallback é o que aparece — nenhuma imagem fictícia é usada.
class _ProductThumb extends StatelessWidget {
  const _ProductThumb({required this.isLegacy, this.imageUrl});

  final bool isLegacy;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final accent = isLegacy ? AppTheme.attention : AppTheme.primary;
    final url = imageUrl?.trim();

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: AppTheme.surfaceNutrition,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null || url.isEmpty
          ? Icon(Icons.restaurant_rounded, size: 22, color: accent)
          : Image.network(
              url,
              fit: BoxFit.cover,
              // Falha de rede não vira card quebrado: cai no mesmo fallback.
              errorBuilder: (_, _, _) =>
                  Icon(Icons.restaurant_rounded, size: 22, color: accent),
            ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, this.nested = false});
  final NutritionActivePlanRef? plan;

  /// Quando `true`, é o topo do card principal — sem surface própria.
  final bool nested;

  /// Aplica a surface só quando o widget é autônomo.
  Widget _wrap(Widget child, {Color? borderColor}) {
    if (nested) return child;
    return HealthSummaryCardSurface(borderColor: borderColor, child: child);
  }

  @override
  Widget build(BuildContext context) {
    if (plan == null) {
      return _wrap(
        Text(
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
      return _wrap(
        borderColor: AppTheme.error.withValues(alpha: 0.45),
        Column(
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

    return _wrap(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            HealthNutritionTodayFormatters.planSourceLabel(plan).toUpperCase(),
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Slot da imagem do produto.
              //
              // O read model atual NÃO possui campo de imagem (o plano só
              // carrega `foodType`, uma String). Então hoje isto renderiza
              // SEMPRE o fallback. O slot existe para aceitar a imagem quando o
              // dado passar a existir, sem inventar productId nem buscar
              // estoque agora.
              // `imageUrl: null` explícito: é aqui que a URL do produto entra
              // quando o read model passar a carregá-la.
              _ProductThumb(isLegacy: isLegacy, imageUrl: null),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  food,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    height: 1.2,
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
    this.supplementQuadrant,
  });

  final NutritionActivePlanRef? plan;
  final List<NutritionMealReadItem> mealsToday;
  final DateTime serverNow;
  final String timezone;
  final String? localServiceDate;
  final bool mutationEnabled;
  final void Function(NutritionPlan plan, MealScheduleSlot slot) onRegister;

  /// Quarto quadrante. Vem pronto de fora porque suplemento NÃO é MealPeriod —
  /// tem modelo, coleção e gating próprios. Ele ocupa o quadrante por decisão
  /// visual, sem virar período no domínio.
  final HealthNutritionQuadrantData? supplementQuadrant;

  /// Monta o grid 2×2 a partir dos slots derivados do plano canônico.
  ///
  /// PRESERVADO INTEGRALMENTE: a derivação (`NutritionSlotDayDerivation.derive`
  /// vs. fallback pending quando não há data de serviço), o status derivado
  /// (`NutritionTodaySlotUi.statusFor`) e as quatro condições de gating do CTA.
  /// A mudança é só de composição visual: slots passam a ser agrupados por
  /// faixa do dia em vez de listados verticalmente.
  Widget _buildPeriodGrid(NutritionPlan canonical) {
    final slotViews = localServiceDate == null
        ? canonical.mealSchedule
              .map(
                (slot) => NutritionSlotDayView(
                  slot: slot,
                  status: NutritionSlotDayStatus.pending,
                ),
              )
              .toList(growable: false)
        : NutritionSlotDayDerivation.derive(
            plan: canonical,
            mealsForDay: mealsToday,
            localServiceDate: LocalServiceDate.fromIso(localServiceDate!),
          ).toList(growable: false);

    final grouped = <HealthNutritionPeriodGroup, List<HealthNutritionSlotEntry>>{
      HealthNutritionPeriodGroup.morning: [],
      HealthNutritionPeriodGroup.afternoon: [],
      HealthNutritionPeriodGroup.night: [],
      HealthNutritionPeriodGroup.extra: [],
    };

    for (final slotView in slotViews) {
      final uiStatus = NutritionTodaySlotUi.statusFor(
        slot: slotView.slot,
        meal: slotView.meal,
        serverNow: serverNow,
        timezone: timezone,
      );
      final statusColor = slotView.hasOccurrenceConflict
          ? AppTheme.error
          : switch (uiStatus) {
              NutritionTodaySlotUiStatus.completed => AppTheme.success,
              NutritionTodaySlotUiStatus.late => AppTheme.warning,
              NutritionTodaySlotUiStatus.pending => AppTheme.warningAccent,
            };
      final group = HealthNutritionPeriodVisuals.groupFor(slotView.slot.period);

      // Fatos da refeição executada em formato compacto operacional.
      final meal = slotView.meal;
      final facts = <HealthNutritionFactLine>[];
      String? conflictMessage;
      String? measurementNote;
      if (meal != null) {
        final hasMeasured = meal.meal.consumedGrams != null;
        final acceptanceStr = HealthNutritionTodayFormatters.acceptanceLabel(
          meal.meal.acceptance,
        );

        if (hasMeasured) {
          facts.add(
            HealthNutritionFactLine(
              label: '',
              value: '${HealthNutritionTodayFormatters.grams(meal.meal.consumedGrams)} consumidos',
              valueColor: AppTheme.textPrimary,
            ),
          );
          facts.add(
            HealthNutritionFactLine(
              label: '',
              value: acceptanceStr,
              valueColor: AppTheme.success,
            ),
          );
        } else {
          facts.add(
            HealthNutritionFactLine(
              label: '',
              value: '${HealthNutritionTodayFormatters.grams(meal.meal.offeredGrams)} oferecidos',
              valueColor: AppTheme.textPrimary,
            ),
          );
          facts.add(
            HealthNutritionFactLine(
              label: '',
              value: '$acceptanceStr • consumo não medido',
              valueColor: AppTheme.textMuted,
            ),
          );
        }
      }

      if (slotView.hasOccurrenceConflict) {
        conflictMessage =
            'Execução duplicada detectada. '
            'Ação temporariamente indisponível.';
      }

      grouped[group]!.add(
        HealthNutritionSlotEntry(
          timeLabel: slotView.slot.scheduledTime.value,
          statusLabel: slotView.hasOccurrenceConflict
              ? 'Dados inconsistentes'
              : NutritionTodaySlotUi.label(uiStatus),
          statusColor: statusColor,
          targetGrams: slotView.slot.targetGrams,
          executedFacts: facts,
          conflictMessage: conflictMessage,
          measurementNote: measurementNote,
          onRegister:
              mutationEnabled &&
                  localServiceDate != null &&
                  !slotView.hasOccurrenceConflict &&
                  uiStatus != NutritionTodaySlotUiStatus.completed
              ? () => onRegister(canonical, slotView.slot)
              : null,
        ),
      );
    }

    HealthNutritionQuadrantData quadrant(HealthNutritionPeriodGroup group) {
      final slots = grouped[group]!;
      return HealthNutritionQuadrantData(
        group: group,
        slots: slots,
        summaryLine: slots.length > 1
            ? '${slots.length} refeições nesta faixa'
            : null,
        emptyLabel: 'Sem refeição prevista',
      );
    }

    return HealthNutritionPeriodGrid(
      quadrants: [
        quadrant(HealthNutritionPeriodGroup.morning),
        quadrant(HealthNutritionPeriodGroup.afternoon),
        quadrant(HealthNutritionPeriodGroup.night),
        ?supplementQuadrant,
      ],
      extraSlots: grouped[HealthNutritionPeriodGroup.extra]!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canonical = plan is NutritionActiveCanonicalPlan
        ? (plan! as NutritionActiveCanonicalPlan).plan
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sem heading próprio: o grid vive no contexto do plano (como no
        // mockup), então repetir "REFEIÇÕES DE HOJE" aqui só gastaria altura.
        // A faixa de cada quadrante já identifica o que é cada célula.
        if (canonical != null) ...[
          _buildPeriodGrid(canonical),
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

/// Abre o sheet de registro de suplemento.
///
/// Extraído de `_SupplementsSectionState._openSupplementForm` SEM alteração de
/// comportamento: mesma configuração de sheet, mesmo `HealthSupplementFormSheet`,
/// mesmo clock autoritativo e mesma mensagem de sucesso. Existe para que o CTA
/// do quadrante e o CTA do cabeçalho compartilhem UMA implementação, em vez de
/// duplicar o fluxo de mutação.
///
/// O gating (`actionEnabled`, dogId, `authorizedNow`) permanece no chamador.
Future<void> openHealthSupplementFormSheet({
  required BuildContext context,
  required String dogId,
  required String dogDisplayName,
  String? dogPhotoUrl,
  required HealthNutritionMutationController mutation,
  required Future<void> Function() onRefreshRequested,
  required DateTime authorizedNow,
  required NutritionActiveCanonicalPlan? activePlan,
}) async {
  final tz = activePlan?.plan.timezone ?? NutritionPlan.defaultTimezone;

  final outcome = await showModalBottomSheet<HealthNutritionMutationUiOutcome>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surfacePanel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => HealthSupplementFormSheet(
      dogId: dogId,
      dogDisplayName: dogDisplayName,
      dogPhotoUrl: dogPhotoUrl,
      controller: mutation,
      onRefreshRequested: onRefreshRequested,
      timezone: tz,
      clock: () => authorizedNow,
      activePlan: activePlan,
    ),
  );

  if (!context.mounted) return;
  if (outcome is HealthNutritionMutationUiSuccess) {
    AppFeedback.success(
      context,
      'Suplemento registrado com sucesso.',
      title: 'Suplemento',
    );
  }
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
    try {
      await openHealthSupplementFormSheet(
        context: context,
        dogId: dogId,
        dogDisplayName: widget.dogDisplayName,
        mutation: mutation,
        onRefreshRequested: widget.onRefreshRequested,
        authorizedNow: widget.authorizedNow!,
        activePlan: _activeCanonicalPlan,
      );
    } finally {
      if (mounted) {
        setState(() => _isOpeningSupplementForm = false);
      }
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: _SupplementSectionHeading(
                title: 'SUPLEMENTOS EM USO',
                subtitle: 'Regimes prescritos atualmente',
              ),
            ),
            const SizedBox(width: 8),
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
                      disabledForegroundColor: AppTheme.textMuted,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfacePanel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.outline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  color: AppTheme.textMuted,
                  size: 16,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    widget.unavailableReason!,
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        // PASS 02: ausência não ganha mais uma grande surface própria — o
        // quadrante Suplemento já iniciou essa informação acima. Vira uma linha
        // discreta. A copy é a MESMA (há teste ancorado nela) e a dica de ação
        // some porque o CTA do quadrante já a oferece.
        if (planRegimens.isEmpty && widget.legacyRegimens.isEmpty)
          Text(
            'Nenhum suplemento em uso registrado.',
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          )
        else ...[
          ...planRegimens.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ActiveSupplementCard(regimen: r),
            ),
          ),
          ...widget.legacyRegimens.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LegacySupplementCard(regimen: r),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _SupplementSectionHeading(
          title: 'ADMINISTRAÇÕES DE HOJE',
          subtitle: 'Fatos registrados no dia',
          trailing:
              widget.administrationsAvailable &&
                  widget.administrations.isNotEmpty
              ? '${widget.administrations.length} ${widget.administrations.length == 1 ? 'registro' : 'registros'}'
              : null,
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
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: widget.onRefreshRequested,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('Atualizar'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: AppTheme.primary,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
          )
        // PASS 02: "nenhuma administração hoje" vira linha discreta. O estado
        // INDISPONÍVEL acima conserva surface + botão Atualizar de propósito —
        // ali há ação a tomar, e há teste de Semantics e alvo de 48px nele.
        // Ausência de dado não merece o mesmo peso visual que falha de leitura.
        else if (widget.administrations.isEmpty)
          Text(
            planRegimens.isNotEmpty || widget.legacyRegimens.isNotEmpty
                ? 'Nenhuma administração registrada hoje. '
                      'Os suplementos em uso aparecem acima.'
                : 'Nenhuma administração registrada hoje.',
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          )
        else
          ...widget.administrations.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SupplementAdministrationCard(
                administration: a,
                timezone: widget.timezone,
              ),
            ),
          ),
      ],
    );
  }
}

class _SupplementSectionHeading extends StatelessWidget {
  const _SupplementSectionHeading({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.55,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          _SupplementMetadataBadge(label: trailing!, color: AppTheme.textMuted),
        ],
      ],
    );
  }
}

class _ActiveSupplementCard extends StatelessWidget {
  const _ActiveSupplementCard({required this.regimen});

  final NutritionPlanSupplementRegimen regimen;

  @override
  Widget build(BuildContext context) {
    return HealthSummaryCardSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SupplementIcon(
            icon: Icons.medication_rounded,
            color: AppTheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  regimen.name,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${_formatSupplementDose(regimen.dose)} ${regimen.unit.displayLabel}',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  regimen.frequency,
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                if ((regimen.instructions ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    regimen.instructions!,
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                const _SupplementMetadataBadge(
                  label: 'Plano ativo',
                  color: AppTheme.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegacySupplementCard extends StatelessWidget {
  const _LegacySupplementCard({required this.regimen});

  final LegacySupplementRegimenView regimen;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (regimen.doseText.isNotEmpty) regimen.doseText,
      if ((regimen.unitText ?? '').isNotEmpty) regimen.unitText!,
      if ((regimen.frequencyText ?? '').isNotEmpty) regimen.frequencyText!,
    ].join(' · ');

    return HealthSummaryCardSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SupplementIcon(
            icon: Icons.medication_outlined,
            color: AppTheme.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  regimen.name,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    height: 1.25,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    details,
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                const _SupplementMetadataBadge(
                  label: 'Registro legado',
                  color: AppTheme.textMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplementAdministrationCard extends StatelessWidget {
  const _SupplementAdministrationCard({
    required this.administration,
    required this.timezone,
  });

  final SupplementLog administration;
  final String timezone;

  @override
  Widget build(BuildContext context) {
    final time = HealthNutritionTodayFormatters.timeShort(
      administration.administeredAt,
      timezone: timezone,
    );
    final origin = _supplementAdministrationOrigin(administration);

    return HealthSummaryCardSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SupplementIcon(
            icon: Icons.check_rounded,
            color: AppTheme.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        administration.supplementName,
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      time,
                      maxLines: 1,
                      style: GoogleFonts.inter(
                        color: AppTheme.success,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${_formatSupplementDose(administration.dose)} ${administration.unit.displayLabel}',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (origin != null) ...[
                  const SizedBox(height: 7),
                  _SupplementMetadataBadge(
                    label: origin,
                    color: origin == 'Prescrito'
                        ? AppTheme.primary
                        : AppTheme.textMuted,
                  ),
                ],
                if ((administration.notes ?? '').isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    administration.notes!,
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplementIcon extends StatelessWidget {
  const _SupplementIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _SupplementMetadataBadge extends StatelessWidget {
  const _SupplementMetadataBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

String? _supplementAdministrationOrigin(SupplementLog administration) {
  final planId = administration.nutritionPlanId?.trim();
  final regimenId = administration.supplementRegimenId?.trim();
  if (planId?.isNotEmpty == true && regimenId?.isNotEmpty == true) {
    return 'Prescrito';
  }
  if ((planId == null || planId.isEmpty) &&
      (regimenId == null || regimenId.isEmpty)) {
    return 'Avulso';
  }
  return null;
}

String _formatSupplementDose(num dose) {
  final value = dose.toDouble();
  return value == value.truncateToDouble()
      ? value.toInt().toString()
      : value.toString();
}

class _RecentMealsSection extends StatelessWidget {
  const _RecentMealsSection({
    required this.meals,
    required this.serviceDate,
    required this.timezone,
    this.supplementAdministrations = const [],
  });
  final List<NutritionMealReadItem> meals;
  final String? serviceDate;
  final String timezone;

  /// Administrações de suplemento do dia, já presentes no read state.
  ///
  /// PASS 02: entram na MESMA timeline das refeições, em verde, ordenadas
  /// temporalmente. Não há projeção nova, nem leitura nova, nem persistência
  /// alterada — é composição de apresentação com dado que a tela já recebia
  /// (`todayModel.canonicalSupplementLogs`, o mesmo que alimenta a seção
  /// "ADMINISTRAÇÕES DE HOJE").
  final List<SupplementLog> supplementAdministrations;

  /// Constrói as entradas ordenadas por instante, refeições + suplementos.
  List<HealthNutritionHistoryEntry> _buildEntries() {
    // (instante, entrada) para ordenar as duas naturezas juntas.
    final rows = <(DateTime, HealthNutritionHistoryEntry)>[];

    for (final m in meals) {
      final consumed = m.meal.consumedGrams;
      final line = consumed == null
          ? '${HealthNutritionTodayFormatters.grams(m.meal.offeredGrams)} oferecidos · consumo não informado'
          : '${HealthNutritionTodayFormatters.grams(consumed)} consumidos';
      rows.add((
        m.meal.fedAt,
        HealthNutritionHistoryEntry(
          group: HealthNutritionPeriodVisuals.groupFor(m.meal.period),
          title: HealthNutritionPeriodVisuals.labelFor(m.meal.period),
          whenLabel: HealthNutritionTodayFormatters.recentDateTimeLabel(
            instant: m.meal.fedAt,
            serviceDate: serviceDate ?? '0001-01-01',
            timezone: timezone,
          ),
          detailLine: line,
          isLegacy: m.origin != NutritionDataOrigin.canonical,
        ),
      ));
    }

    for (final a in supplementAdministrations) {
      rows.add((
        a.administeredAt,
        HealthNutritionHistoryEntry(
          group: HealthNutritionPeriodGroup.supplement,
          title: HealthNutritionPeriodVisuals.resolve(
            HealthNutritionPeriodGroup.supplement,
          ).label,
          whenLabel: HealthNutritionTodayFormatters.recentDateTimeLabel(
            instant: a.administeredAt,
            serviceDate: serviceDate ?? '0001-01-01',
            timezone: timezone,
          ),
          // Nome + dose: os mesmos fatos do card da seção de administrações.
          detailLine:
              '${a.supplementName} · '
              '${_formatSupplementDose(a.dose)} ${a.unit.displayLabel}',
          // Suplemento canônico: a seção legada é de regimes, não de logs.
          isLegacy: false,
        ),
      ));
    }

    // Mais recente primeiro, como a lista de refeições já se comportava.
    rows.sort((a, b) => b.$1.compareTo(a.$1));
    return rows.map((r) => r.$2).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();

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
        if (entries.isEmpty)
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
          // Timeline local APROVADA na revisão física — anatomia, rail,
          // espaçamento, tipografia e cores preservados integralmente.
          // A única evolução desta pass: administrações de suplemento entram no
          // mesmo padrão, em verde. Cor = período/tipo; proveniência legada
          // continua sendo badge.
          HealthNutritionHistoryTimeline(entries: entries),
      ],
    );
  }
}
