import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_provider.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/app_shell/presentation/main_root_nav_metrics.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/screens/vaccination_history_screen.dart';
import 'package:canil_gcm/features/dogs/presentation/screens/weight_history_screen.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source_factory.dart';
import 'package:canil_gcm/features/health/data/coexistence/schedule/firestore_health_schedule_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/coexistence_health_summary_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_readiness_convergence_gateway.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_dog_context_mapper.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/readiness_callable.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_flag_provider.dart';
import 'package:canil_gcm/features/health/data/config/health_timeline_mode.dart';
import 'package:canil_gcm/features/health/data/config/local_health_timeline_flag_provider.dart';
import 'package:canil_gcm/features/health/data/nutrition/firebase_functions_health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/data/schedule/firebase_functions_health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/data/restriction/firebase_functions_health_document_gateway.dart';
import 'package:canil_gcm/features/health/data/restriction/firebase_functions_health_restriction_issue_gateway.dart';
import 'package:canil_gcm/features/health/data/restriction/storage_health_evidence_uploader.dart';
import 'package:canil_gcm/features/health/data/canonical/restriction/firestore_health_restriction_read_gateway.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_detail_controller.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_detail_screen.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_form_screen.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_issue_controller.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_attention_destination.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_adhoc_meal_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_outcome.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_pending_intent.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_read_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_today_screen.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_supplement_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_presentation_policy.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_screen.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_shell_screen.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_type_selector_screen.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_controller.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dashboard.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_session.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_screen.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/widgets/health_timeline_status_views.dart';
import 'package:canil_gcm/features/health/presentation/weight/health_weight_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_shell_section.dart';
import 'package:canil_gcm/features/nutrition/presentation/screens/nutrition_full_screen.dart';

/// Factory injetável para construir a [HealthTimelineSource] a partir da resolução de modo.
typedef HealthTimelineSourceForResolution =
    HealthTimelineSource Function(HealthTimelineModeResolution resolution);

/// Entrada de produção controlada do Health v1.0 (Fase 2E + 3E-B + 4B).
///
/// ## Composition root
/// Possui lifecycle de Resumo, Timeline e Agenda:
/// - cria source/controller **fora** de [build];
/// - timeline/agenda: **lazy** no primeiro acesso ao slot;
/// - troca de cão via [selectDog] (sem recriar controller);
/// - dispose único ao sair do fluxo Health.
///
/// Integração controlada — reutiliza 3A–4A; sem arquitetura nova.
/// Agenda 4D Gate 2: leitura Firestore read-only. Sem writes cliente.
class HealthV1EntryScreen extends StatefulWidget {
  final String dogId;

  /// Autoridade temporal compartilhada pelo App Shell.
  final AuthoritativeTimeProvider? authoritativeTimeProvider;

  /// Source de resumo injetável (testes).
  final HealthSummarySource? source;

  /// Source da timeline injetável (testes). Produção: Firestore read-only 3C.
  final HealthTimelineSource? timelineSource;

  /// Callback de composição para construir a source a partir da resolução de modo (H3B2).
  final HealthTimelineSourceForResolution? timelineSourceForResolution;

  /// Timeout para resolução da flag de modo da timeline (H3B2). Default: 1 segundo.
  final Duration timelineFlagResolutionTimeout;

  /// Source da agenda injetável (testes). Produção: [FirestoreHealthScheduleSource].
  final HealthScheduleSource? scheduleSource;

  /// Gateway de mutação da Agenda (Gate 4/5).
  ///
  /// Produção: [FirebaseFunctionsHealthScheduleMutationGateway].
  /// Testes: injete [FailClosedHealthScheduleMutationGateway] ou spy.
  /// Gate 5: UI de mutações consome via [HealthScheduleMutationController].
  final HealthScheduleMutationGateway? scheduleMutationGateway;

  /// Gateway de mutação canônica de Nutrição (5D Gate 3).
  ///
  /// Produção default: [FirebaseFunctionsHealthNutritionMutationGateway].
  /// **Não** conectado a fluxo operacional legado neste Gate (read/write gap).
  /// Testes: injete fake / [FailClosedHealthNutritionMutationGateway].
  final HealthNutritionMutationGateway? nutritionMutationGateway;

  /// Source de leitura de coexistência Nutrição (5D Gate 4).
  ///
  /// Produção default: [CoexistenceNutritionReadSourceFactory.forFirestore].
  /// **Local preparado ≠ Rules em produção** — até deploy (Gate 5), reads
  /// canônicos autenticados podem falhar com permission-denied.
  /// Testes: injete source com delegates fake/in-memory.
  final CoexistenceNutritionReadSource? nutritionReadSource;

  /// Holder de pending intent com lifecycle **maior** que este State.
  ///
  /// Produção: [HealthNutritionPendingIntentSession] no [MainRootScreen].
  /// Se null, cria holder local (apenas testes isolados) — **não** sobrevive
  /// a dispose desta tela (ex.: troca de ValueKey / perda de cão ativo).
  final HealthNutritionPendingIntentHolder? nutritionPendingIntentHolder;

  /// Contexto do K9 pré-resolvido (testes). Produção: [DogViewModel].
  final HealthSummaryDogContextView? dogContextOverride;

  /// Override de navegação relatedHistory (testes).
  final Future<void> Function(HealthTimelineDetailTarget target)?
  onTimelineNavigate;

  /// Provider de feature flag para resolução do modo da timeline.
  ///
  /// Produção: [LocalHealthTimelineFlagProvider] (síncrono, sempre legacyOnly).
  /// Testes: injete mock/fake para testar precedência.
  /// Remote Config: injeção explícita — não via default nesta Etapa 3B.
  final HealthTimelineFlagProvider timelineFlagProvider;

  const HealthV1EntryScreen({
    super.key,
    required this.dogId,
    this.authoritativeTimeProvider,
    this.source,
    this.timelineSource,
    this.timelineSourceForResolution,
    this.timelineFlagResolutionTimeout = const Duration(seconds: 1),
    this.scheduleSource,
    this.scheduleMutationGateway,
    this.nutritionMutationGateway,
    this.nutritionReadSource,
    this.nutritionPendingIntentHolder,
    this.dogContextOverride,
    this.onTimelineNavigate,
    this.timelineFlagProvider = const LocalHealthTimelineFlagProvider(),
  });

  @override
  State<HealthV1EntryScreen> createState() => HealthV1EntryScreenState();
}

@visibleForTesting
class HealthV1EntryScreenState extends State<HealthV1EntryScreen>
    with WidgetsBindingObserver {
  final GlobalKey<HealthShellScreenState> _shellKey =
      GlobalKey<HealthShellScreenState>();

  late final HealthSummarySource _source;
  late final HealthSummaryController _controller;

  HealthTimelineSource? _timelineSource;
  HealthTimelineController? _timelineController;
  HealthTimelineFilterSession? _filterSession;

  late final HealthScheduleSource _scheduleSource;
  late final HealthScheduleController _scheduleController;
  late final HealthScheduleMutationGateway _scheduleMutationGateway;
  late final HealthScheduleMutationController _scheduleMutationController;
  late final HealthNutritionMutationGateway _nutritionMutationGateway;

  /// Holder de pending intent fora do lifecycle do controller (5D Gate 3).
  /// dispose técnico do controller não apaga intenção incerta.
  late final HealthNutritionPendingIntentHolder _nutritionPendingIntentHolder;
  late final HealthNutritionMutationController _nutritionMutationController;
  late final CoexistenceNutritionReadSource _nutritionReadSource;
  late final HealthNutritionReadController _nutritionReadController;

  /// Primeira carga da timeline só após visitar Histórico (lazy).
  bool _timelinePrimed = false;

  /// Primeira carga da agenda só após visitar Agenda (lazy).
  bool _schedulePrimed = false;

  /// Primeira carga do read model Nutrição canônico (lazy / pós-mutation).
  bool _nutritionReadPrimed = false;

  HealthSummaryController get controllerForTest => _controller;

  @visibleForTesting
  HealthTimelineSource? get timelineSourceForTest => _timelineSource;

  @visibleForTesting
  HealthTimelineController? get timelineControllerForTest =>
      _timelineController;

  @visibleForTesting
  HealthTimelineFilterSession? get filterSessionForTest => _filterSession;

  @visibleForTesting
  bool get timelinePrimedForTest => _timelinePrimed;

  @visibleForTesting
  HealthScheduleController get scheduleControllerForTest => _scheduleController;

  @visibleForTesting
  bool get schedulePrimedForTest => _schedulePrimed;

  /// Gateway permanente (ou fake injetado).
  @visibleForTesting
  HealthScheduleMutationGateway get scheduleMutationGatewayForTest =>
      _scheduleMutationGateway;

  @visibleForTesting
  HealthScheduleMutationController get scheduleMutationControllerForTest =>
      _scheduleMutationController;

  /// Gateway Nutrição canônico (real ou fake injetado). Sem UI operacional.
  @visibleForTesting
  HealthNutritionMutationGateway get nutritionMutationGatewayForTest =>
      _nutritionMutationGateway;

  @visibleForTesting
  HealthNutritionMutationController get nutritionMutationControllerForTest =>
      _nutritionMutationController;

  @visibleForTesting
  HealthNutritionReadController get nutritionReadControllerForTest =>
      _nutritionReadController;

  @visibleForTesting
  CoexistenceNutritionReadSource get nutritionReadSourceForTest =>
      _nutritionReadSource;

  @visibleForTesting
  AuthoritativeTimeProvider? get authoritativeTimeProviderForTest =>
      widget.authoritativeTimeProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final authoritativeTimeProvider = widget.authoritativeTimeProvider;
    if (authoritativeTimeProvider != null) {
      unawaited(authoritativeTimeProvider.synchronize());
    }
    _source =
        widget.source ??
        CoexistenceHealthSummarySource(
          authoritativeTimeProvider: widget.authoritativeTimeProvider,
        );
    _controller = HealthSummaryController(source: _source);
    _controller.selectDog(widget.dogId);

    // H3B2: Precedência absoluta da timelineSource explícita.
    final explicitTimelineSource = widget.timelineSource;
    if (explicitTimelineSource != null) {
      _installTimelineSource(explicitTimelineSource, notify: false);
    } else {
      unawaited(_initializeTimelineFromMode());
    }

    _scheduleSource =
        widget.scheduleSource ?? FirestoreHealthScheduleSource.forDefault();
    _scheduleController = HealthScheduleController(
      source: _scheduleSource,
      temporalPolicy: healthSchedulePresentationPolicy(),
    );
    _scheduleMutationGateway =
        widget.scheduleMutationGateway ??
        FirebaseFunctionsHealthScheduleMutationGateway();
    _scheduleMutationController = HealthScheduleMutationController(
      gateway: _scheduleMutationGateway,
      scheduleController: _scheduleController,
    );
    _nutritionReadSource =
        widget.nutritionReadSource ??
        CoexistenceNutritionReadSourceFactory.forFirestore();
    _nutritionReadController = HealthNutritionReadController(
      source: _nutritionReadSource,
      authoritativeTimeProvider: widget.authoritativeTimeProvider,
    );
    _nutritionMutationGateway =
        widget.nutritionMutationGateway ??
        FirebaseFunctionsHealthNutritionMutationGateway();
    _nutritionPendingIntentHolder =
        widget.nutritionPendingIntentHolder ??
        HealthNutritionPendingIntentHolder();
    _nutritionMutationController = HealthNutritionMutationController(
      gateway: _nutritionMutationGateway,
      pendingIntentHolder: _nutritionPendingIntentHolder,
      onRefreshAfterSuccess: () async {
        _nutritionReadPrimed = true;
        await _nutritionReadController.ensureDogAndRefresh(widget.dogId);
      },
    );
  }

  void _installTimelineSource(
    HealthTimelineSource source, {
    required bool notify,
  }) {
    if (_timelineController != null) return;
    _timelineSource = source;
    _timelineController = HealthTimelineController(source: source);
    _filterSession = HealthTimelineFilterSession(
      controller: _timelineController!,
      dogId: widget.dogId,
    );
    if (notify && mounted) {
      setState(() {});
    }
  }

  Future<void> _initializeTimelineFromMode() async {
    final resolution = await _resolveTimelineModeSafely(
      widget.timelineFlagProvider,
      widget.timelineFlagResolutionTimeout,
    );

    if (!mounted) return;
    if (_timelineController != null) return;

    final resolver =
        widget.timelineSourceForResolution ??
        ((_) => CoexistenceHealthTimelineSourceFactory.forFirestore());

    final source = resolver(resolution);

    if (!mounted) return;
    _installTimelineSource(source, notify: true);

    if (_timelinePrimed) {
      _timelineController?.selectDog(widget.dogId);
    }
  }

  Future<HealthTimelineModeResolution> _resolveTimelineModeSafely(
    HealthTimelineFlagProvider provider,
    Duration timeout,
  ) async {
    try {
      return await Future<HealthTimelineModeResolution>.sync(
        provider.resolveMode,
      ).timeout(timeout);
    } catch (_) {
      return const HealthTimelineModeResolution(
        mode: HealthTimelineMode.legacyOnly,
        kind: HealthTimelineModeResolutionKind.missingDefault,
      );
    }
  }

  @override
  void didUpdateWidget(covariant HealthV1EntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.dogId.trim();
    final prev = oldWidget.dogId.trim();
    if (next.isNotEmpty && next != prev) {
      _controller.selectDog(next);
      _filterSession?.updateDogId(next);
      if (_timelinePrimed) {
        // ignore: discarded_futures
        _timelineController?.selectDog(next);
      }
      if (_schedulePrimed) {
        // ignore: discarded_futures
        _scheduleController.selectDog(next);
      }
      if (_nutritionReadPrimed) {
        // ignore: discarded_futures
        _nutritionReadController.selectDog(next);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _filterSession?.dispose();
    _timelineController?.dispose();
    _scheduleMutationController.dispose();
    _nutritionMutationController.dispose();
    _nutritionReadController.dispose();
    _scheduleController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resynchronizeAfterResume());
    }
  }

  Future<void> _resynchronizeAfterResume() async {
    final provider = widget.authoritativeTimeProvider;
    if (provider == null) return;

    if (_nutritionReadPrimed) {
      await _nutritionReadController.refresh();
    } else {
      await provider.synchronize(force: true);
    }
    if (!mounted) return;
    final source = _source;
    if (source is CoexistenceHealthSummarySource) {
      source.useCurrentTemporalSnapshotOnNextRead();
    }
    _controller.refresh();
  }

  void _selectSection(HealthShellSection section) {
    _shellKey.currentState?.selectSection(section);
  }

  void _onShellSectionChanged(HealthShellSection section) {
    if (section == HealthShellSection.historico) {
      _primeTimelineIfNeeded();
    }
    if (section == HealthShellSection.agenda) {
      _primeScheduleIfNeeded();
    }
    if (section == HealthShellSection.nutricao) {
      _primeNutritionIfNeeded();
    }
  }

  /// Lazy first-load: uma única vez por vida do entry (ou após dog change se já primed).
  void _primeTimelineIfNeeded() {
    if (_timelinePrimed) return;
    _timelinePrimed = true;
    // ignore: discarded_futures
    _timelineController?.selectDog(widget.dogId);
  }

  void _primeScheduleIfNeeded() {
    if (_schedulePrimed) return;
    _schedulePrimed = true;
    // ignore: discarded_futures
    _scheduleController.selectDog(widget.dogId);
  }

  /// Gate 5B: prime real do read controller ao abrir Nutrição Hoje.
  void _primeNutritionIfNeeded() {
    if (_nutritionReadPrimed) return;
    _nutritionReadPrimed = true;
    // ignore: discarded_futures
    _nutritionReadController.selectDog(widget.dogId);
  }

  @visibleForTesting
  void primeTimelineForTest() => _primeTimelineIfNeeded();

  @visibleForTesting
  void primeScheduleForTest() => _primeScheduleIfNeeded();

  @visibleForTesting
  bool get nutritionReadPrimedForTest => _nutritionReadPrimed;

  Future<void> _onRegister() async {
    DogViewModel? dogVM;
    try {
      dogVM = context.read<DogViewModel>();
    } on ProviderNotFoundException {
      dogVM = null;
    }
    final dogContext =
        widget.dogContextOverride ??
        _resolveDogContext(dogVM ?? DogViewModel());
    final dog = _resolveDogForNavigation(
      dogId: widget.dogId,
      dogVM: dogVM,
      preferredContext: dogContext,
    ).dog;

    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => HealthTypeSelectorScreen(
          dogId: widget.dogId,
          dogName: dogContext.name,
          dogBreed: dogContext.breed,
          onRegisterRestriction: (hubContext) async {
            // Controller local à navegação: guarda o progresso das etapas
            // (PREPARE/upload/FINALIZE/ISSUE) enquanto a tela está aberta,
            // para que "tentar novamente" não refaça o que já concluiu.
            final controller = HealthRestrictionIssueController(
              documentGateway: FirebaseFunctionsHealthDocumentGateway(),
              uploader: StorageHealthEvidenceUploader(),
              restrictionGateway:
                  FirebaseFunctionsHealthRestrictionIssueGateway(),
              // Barreira causal (B4-R.C3): depois do ISSUE commitar, prova que a
              // projeção observável já reflete a restrição. Dependência
              // obrigatória de propósito — sem ela a mutation commitaria sem
              // nenhuma tentativa de convergência.
              convergenceGateway: HealthReadinessConvergenceGateway(
                invoke: FirebaseFunctionsReadinessCallableInvoker().call,
              ),
            );
            try {
              final saved = await Navigator.of(
                hubContext,
                rootNavigator: true,
              ).push<bool>(
                MaterialPageRoute(
                  builder: (_) => HealthRestrictionFormScreen(
                    dogId: widget.dogId,
                    dogName: dogContext.name,
                    controller: controller,
                  ),
                ),
              );
              return saved == true;
            } finally {
              controller.dispose();
            }
          },
          onRegisterWeight: (hubContext) async {
            final saved = await showHealthWeightFormSheet(
              context: hubContext,
              dog: dog,
              onRefreshAfterSuccess: () async {
                _controller.selectDog(widget.dogId);
              },
            );
            return saved == true;
          },
          onRegisterNutrition: (hubContext) async {
            // Mostrar seleção entre Alimentação Avulsa e Suplemento.
            final choice =
                await showModalBottomSheet<_NutritionRegistrationChoice>(
                  context: hubContext,
                  isScrollControlled: true,
                  backgroundColor: AppTheme.surfacePanel,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  builder: (_) => _NutritionRegistrationTypeSheet(
                    dogDisplayName: dogContext.name,
                  ),
                );

            if (!hubContext.mounted) return false;
            if (choice == null) return false;

            if (choice == _NutritionRegistrationChoice.adhocMeal) {
              final outcome =
                  await showModalBottomSheet<HealthNutritionMutationUiOutcome>(
                    context: hubContext,
                    isScrollControlled: true,
                    backgroundColor: AppTheme.surfacePanel,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    builder: (_) => HealthAdhocMealFormSheet(
                      dogId: widget.dogId,
                      dogDisplayName: dogContext.name,
                      dogPhotoUrl: dogContext.photoUrl,
                      controller: _nutritionMutationController,
                      onRefreshRequested: () async {
                        _primeNutritionIfNeeded();
                        await _nutritionReadController.ensureDogAndRefresh(
                          widget.dogId,
                        );
                        _controller.selectDog(widget.dogId);
                      },
                    ),
                  );

              if (outcome is HealthNutritionMutationUiSuccess) {
                _primeNutritionIfNeeded();
                await _nutritionReadController.ensureDogAndRefresh(
                  widget.dogId,
                );
                _controller.selectDog(widget.dogId);
                return true;
              }
              return false;
            }

            // choice == _NutritionRegistrationChoice.supplement
            final activePlan = _tryGetActiveCanonicalPlan();
            final tz =
                activePlan?.plan.timezone ?? NutritionPlan.defaultTimezone;

            final outcome =
                await showModalBottomSheet<HealthNutritionMutationUiOutcome>(
                  context: hubContext,
                  isScrollControlled: true,
                  backgroundColor: AppTheme.surfacePanel,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  builder: (_) => HealthSupplementFormSheet(
                    dogId: widget.dogId,
                    dogDisplayName: dogContext.name,
                    controller: _nutritionMutationController,
                    onRefreshRequested: () async {
                      _primeNutritionIfNeeded();
                      await _nutritionReadController.ensureDogAndRefresh(
                        widget.dogId,
                      );
                      _controller.selectDog(widget.dogId);
                    },
                    timezone: tz,
                    activePlan: activePlan,
                  ),
                );

            if (outcome is HealthNutritionMutationUiSuccess) {
              _primeNutritionIfNeeded();
              await _nutritionReadController.ensureDogAndRefresh(widget.dogId);
              _controller.selectDog(widget.dogId);
              return true;
            }
            return false;
          },
        ),
      ),
    );

    if (saved == true && mounted) {
      _primeNutritionIfNeeded();
      await _nutritionReadController.ensureDogAndRefresh(widget.dogId);
      _controller.selectDog(widget.dogId);
    }
  }

  HealthSummaryDogContextView _resolveDogContext(DogViewModel dogVM) {
    final id = widget.dogId.trim();
    Dog? dog;
    for (final d in dogVM.dogs) {
      if (d.id == id) {
        dog = d;
        break;
      }
    }
    if (dog != null) {
      return HealthSummaryDogContextMapper.fromDog(dog);
    }
    return HealthSummaryDogContextView(
      dogId: id,
      name: dogVM.isLoading ? 'Carregando…' : 'K9',
    );
  }

  /// Resolve [Dog] pelo id do **target** (não por closure de build stale).
  ///
  /// Nunca retorna null: catálogo → contexto preferido → fallback mínimo.
  /// Falha de catálogo **não** cancela a navegação silenciosamente (3E-D2).
  ({Dog dog, bool fromCatalog}) _resolveDogForNavigation({
    required String dogId,
    DogViewModel? dogVM,
    HealthSummaryDogContextView? preferredContext,
  }) {
    final id = dogId.trim();
    if (dogVM != null) {
      for (final d in dogVM.dogs) {
        if (d.id == id) {
          return (dog: d, fromCatalog: true);
        }
      }
    }
    if (preferredContext != null && preferredContext.dogId.trim() == id) {
      return (
        dog: Dog(
          id: preferredContext.dogId.trim(),
          name: preferredContext.name,
          breed: preferredContext.breed ?? '—',
          dateOfBirth: DateTime(2000, 1, 1),
        ),
        fromCatalog: false,
      );
    }
    return (
      dog: Dog(
        id: id.isEmpty ? widget.dogId.trim() : id,
        name: preferredContext?.name ?? 'K9',
        breed: preferredContext?.breed ?? '—',
        dateOfBirth: DateTime(2000, 1, 1),
      ),
      fromCatalog: false,
    );
  }

  DogViewModel? _tryReadDogViewModel() {
    try {
      return context.read<DogViewModel>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _onTimelineNavigate(HealthTimelineDetailTarget target) async {
    final override = widget.onTimelineNavigate;
    if (override != null) {
      await override(target);
      return;
    }
    if (!mounted) return;

    try {
      // Preferir dogId do target (entry clicada), não captura de build.
      final dogVM = _tryReadDogViewModel();
      final preferred = widget.dogContextOverride;
      final resolved = _resolveDogForNavigation(
        dogId: target.dogId,
        dogVM: dogVM,
        preferredContext: preferred,
      );
      final dog = resolved.dog;

      // Mesmo padrão do prontuário legado / ocorrências: root navigator
      // garante push acima do shell (IndexedStack + bottom nav + PopScope).
      final navigator = Navigator.of(context, rootNavigator: true);

      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => switch (target) {
            WeightHistoryTarget() => WeightHistoryScreen(dog: dog),
            VaccinationHistoryTarget() => VaccinationHistoryScreen(dog: dog),
            NutritionHistoryTarget() => NutritionFullScreen(
              dog: dog,
              onRegisterAdhoc: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: AppTheme.transparent,
                  builder: (_) => HealthAdhocMealFormSheet(
                    dogId: dog.id,
                    dogDisplayName: dog.name,
                    dogPhotoUrl: dog.profileImageUrl,
                    controller: _nutritionMutationController,
                    onRefreshRequested: () async {
                      _primeNutritionIfNeeded();
                      await _nutritionReadController.ensureDogAndRefresh(
                        dog.id,
                      );
                      _controller.selectDog(dog.id);
                    },
                  ),
                );
              },
            ),
          },
        ),
      );
    } catch (e, st) {
      debugPrint('[HealthV1Entry] timeline navigate failed: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      AppFeedback.error(
        context,
        e,
        fallback: 'Não foi possível abrir o histórico relacionado.',
      );
    }
  }

  /// Abre o detalhe canônico de UMA restrição operacional (B4-C.2).
  ///
  /// `dogId` é o K9 cujo Health está aberto e `restrictionId` é o id canônico já
  /// traduzido pela boundary do B4-C.1 — a tela nunca deriva identidade da
  /// descrição, do nível nem da posição do item tocado.
  Future<void> _openRestrictionDetail({
    required String dogId,
    required String restrictionId,
  }) async {
    final controller = HealthRestrictionDetailController(
      dogId: dogId,
      restrictionId: restrictionId,
      gateway: FirestoreHealthRestrictionReadGateway(),
    );
    try {
      // Read-only neste gate: back comum, sem resultado de mutation.
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              HealthRestrictionDetailScreen(controller: controller),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  /// Id de projeção corrompido: informa sem expor diagnóstico técnico e sem
  /// tentar leitura canônica com identidade não confiável.
  void _notifyRestrictionUnavailable() {
    if (!mounted) return;
    AppFeedback.warning(context, 'Não foi possível abrir esta restrição.');
  }

  /// Clearance real: bottom nav + safe area + folga FAB (mesmo contrato do Resumo).
  double _timelineBottomPadding(BuildContext context) {
    return MainRootNavMetrics.scrollBottomClearance(
      systemBottomInset: MediaQuery.paddingOf(context).bottom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dogContext =
        widget.dogContextOverride ??
        _resolveDogContext(context.watch<DogViewModel>());

    return ColoredBox(
      color: AppTheme.background,
      child: HealthShellScreen(
        key: _shellKey,
        onRegister: _onRegister,
        onSectionChanged: _onShellSectionChanged,
        resumo: (_) => HealthSummaryDashboard(
          dogContext: dogContext,
          controller: _controller,
          onOpenHistory: () => _selectSection(HealthShellSection.historico),
          onOpenNutrition: () => _selectSection(HealthShellSection.nutricao),
          onRegisterFeeding: () => _selectSection(HealthShellSection.nutricao),
          onAttentionItemTap: (item) {
            // Roteamento pela boundary congelada em B4-C.1: nenhum parsing de
            // `restriction:<id>` acontece aqui. `destinationHint` não é
            // autoridade para restrição — nenhum produtor de produção o
            // preenche hoje, então sem esta classificação toda restrição cairia
            // no fallback de histórico e o id canônico seria descartado.
            final destination = classifyHealthSummaryAttentionDestination(item);
            switch (destination) {
              case HealthSummaryAttentionRestrictionDestination(
                :final canonicalRestrictionId,
              ):
                _openRestrictionDetail(
                  dogId: dogContext.dogId,
                  restrictionId: canonicalRestrictionId,
                );
              case HealthSummaryAttentionUnavailableDestination():
                // Id de projeção corrompido: falha fechada. Nenhuma leitura
                // canônica é tentada com identidade não confiável.
                _notifyRestrictionUnavailable();
              case HealthSummaryAttentionAgendaDestination():
                _selectSection(HealthShellSection.agenda);
              case HealthSummaryAttentionNutritionDestination():
                _selectSection(HealthShellSection.nutricao);
              case HealthSummaryAttentionHistoryDestination():
                _selectSection(HealthShellSection.historico);
            }
          },
          onRecentRecordTap: (_) {
            _selectSection(HealthShellSection.historico);
          },
        ),
        historico: (_) {
          final controller = _timelineController;
          final filterSession = _filterSession;
          if (controller == null || filterSession == null) {
            return const HealthTimelineLoadingView();
          }
          return HealthTimelineScreen(
            controller: controller,
            filterSession: filterSession,
            dogDisplayName: dogContext.name,
            bottomPadding: _timelineBottomPadding(context),
            onNavigate: _onTimelineNavigate,
          );
        },
        agenda: (_) => HealthScheduleScreen(
          controller: _scheduleController,
          mutationController: _scheduleMutationController,
          dogDisplayName: dogContext.name,
          bottomPadding: _timelineBottomPadding(context),
        ),
        nutricao: (_) => HealthNutritionTodayScreen(
          controller: _nutritionReadController,
          mutationController: _nutritionMutationController,
          dogDisplayName: dogContext.name,
          dogPhotoUrl: dogContext.photoUrl,
          bottomPadding: _timelineBottomPadding(context),
        ),
      ),
    );
  }

  /// Tenta obter o plano ativo canônico da Nutrição.
  NutritionActiveCanonicalPlan? _tryGetActiveCanonicalPlan() {
    final snapshot = _nutritionReadController.snapshotOrNull;
    if (snapshot == null) return null;
    final plan = snapshot.activePlan;
    if (plan is NutritionActiveCanonicalPlan) return plan;
    return null;
  }
}

/// Escolha de tipo de registro nutricional.
enum _NutritionRegistrationChoice { adhocMeal, supplement }

/// Sheet de seleção de tipo de registro nutricional.
class _NutritionRegistrationTypeSheet extends StatelessWidget {
  const _NutritionRegistrationTypeSheet({required this.dogDisplayName});

  final String dogDisplayName;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(Icons.restaurant_rounded, color: AppTheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'REGISTRAR NUTRIÇÃO',
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              dogDisplayName,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            _RegistrationChoiceCard(
              icon: Icons.restaurant_menu_rounded,
              title: 'Alimentação avulsa',
              subtitle: 'Registrar refeição fora do plano',
              color: AppTheme.attention,
              onTap: () => Navigator.pop(
                context,
                _NutritionRegistrationChoice.adhocMeal,
              ),
            ),
            const SizedBox(height: 12),
            _RegistrationChoiceCard(
              icon: Icons.medication_rounded,
              title: 'Suplemento',
              subtitle: 'Registrar administração de suplemento',
              color: AppTheme.primary,
              onTap: () => Navigator.pop(
                context,
                _NutritionRegistrationChoice.supplement,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RegistrationChoiceCard extends StatelessWidget {
  const _RegistrationChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withAlpha(12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color),
          ],
        ),
      ),
    );
  }
}
