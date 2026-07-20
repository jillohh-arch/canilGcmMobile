import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/app_shell/presentation/main_root_nav_metrics.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/screens/vaccination_history_screen.dart';
import 'package:canil_gcm/features/dogs/presentation/screens/weight_history_screen.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/coexistence_health_summary_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_dog_context_mapper.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_shell_screen.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_controller.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dashboard.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/detail/health_timeline_detail_target.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_session.dart';
import 'package:canil_gcm/features/health/data/coexistence/schedule/firestore_health_schedule_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source_factory.dart';
import 'package:canil_gcm/features/health/data/nutrition/firebase_functions_health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/data/schedule/firebase_functions_health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_pending_intent.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_read_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_today_screen.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_presentation_policy.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_screen.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_screen.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_shell_section.dart';
import 'package:canil_gcm/features/nutrition/presentation/screens/nutrition_full_screen.dart';

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

  /// Source de resumo injetável (testes).
  final HealthSummarySource? source;

  /// Source da timeline injetável (testes). Produção: Firestore read-only 3C.
  final HealthTimelineSource? timelineSource;

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

  const HealthV1EntryScreen({
    super.key,
    required this.dogId,
    this.source,
    this.timelineSource,
    this.scheduleSource,
    this.scheduleMutationGateway,
    this.nutritionMutationGateway,
    this.nutritionReadSource,
    this.nutritionPendingIntentHolder,
    this.dogContextOverride,
    this.onTimelineNavigate,
  });

  @override
  State<HealthV1EntryScreen> createState() => HealthV1EntryScreenState();
}

@visibleForTesting
class HealthV1EntryScreenState extends State<HealthV1EntryScreen> {
  final GlobalKey<HealthShellScreenState> _shellKey =
      GlobalKey<HealthShellScreenState>();

  late final HealthSummarySource _source;
  late final HealthSummaryController _controller;

  late final HealthTimelineSource _timelineSource;
  late final HealthTimelineController _timelineController;
  late final HealthTimelineFilterSession _filterSession;

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
  HealthTimelineController get timelineControllerForTest => _timelineController;

  @visibleForTesting
  HealthTimelineFilterSession get filterSessionForTest => _filterSession;

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

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? CoexistenceHealthSummarySource();
    _controller = HealthSummaryController(source: _source);
    _controller.selectDog(widget.dogId);

    // Ownership no entry: cria uma vez. Fallback vacinas permanece opt-in
    // (default false — política 3C conservadora).
    _timelineSource =
        widget.timelineSource ??
        CoexistenceHealthTimelineSourceFactory.forFirestore();
    _timelineController = HealthTimelineController(source: _timelineSource);
    _filterSession = HealthTimelineFilterSession(
      controller: _timelineController,
      dogId: widget.dogId,
    );

    // Agenda 4D Gate 2: default de produção = Firestore read-only após
    // índice READY + Rules publicadas + query autenticada real OK.
    // Injete [scheduleSource] nos testes (fake/empty). Sem fallback
    // silencioso para Empty em erro de rede/permissão.
    // Ver docs/health/HEALTH_V1_PHASE_4D_ACTIVATION_REPORT.md.
    _scheduleSource =
        widget.scheduleSource ?? FirestoreHealthScheduleSource.forDefault();
    _scheduleController = HealthScheduleController(
      source: _scheduleSource,
      temporalPolicy: healthSchedulePresentationPolicy(),
    );
    // Gate 4/5: gateway real como default. Mutações apenas por ação explícita
    // do usuário (forms/menu) — sem auto-write, sem listener de mutação.
    _scheduleMutationGateway =
        widget.scheduleMutationGateway ??
        FirebaseFunctionsHealthScheduleMutationGateway();
    _scheduleMutationController = HealthScheduleMutationController(
      gateway: _scheduleMutationGateway,
      scheduleController: _scheduleController,
    );
    // 5D Gate 4: read source Firestore real como default (não Empty/fake).
    // Lazy first-load: evita I/O canônico até refresh pós-mutation ou
    // UI futura. Rules canônicas ainda não deployadas em produção.
    _nutritionReadSource =
        widget.nutritionReadSource ??
        CoexistenceNutritionReadSourceFactory.forFirestore();
    _nutritionReadController = HealthNutritionReadController(
      source: _nutritionReadSource,
    );
    // 5D Gate 3+4: gateway real + read-after-write no read controller canônico.
    // Sem botão operacional / cutover de FeedingRegistrationScreen.
    _nutritionMutationGateway =
        widget.nutritionMutationGateway ??
        FirebaseFunctionsHealthNutritionMutationGateway();
    // Preferir holder injetado (sessão MainRoot / dog-keyed). Fallback local
    // só para testes sem host — NÃO é o owner de produção.
    _nutritionPendingIntentHolder =
        widget.nutritionPendingIntentHolder ??
        HealthNutritionPendingIntentHolder();
    _nutritionMutationController = HealthNutritionMutationController(
      gateway: _nutritionMutationGateway,
      pendingIntentHolder: _nutritionPendingIntentHolder,
      // Mutation success + refresh failure ≠ mutation failure (Gate 3/4).
      onRefreshAfterSuccess: () async {
        _nutritionReadPrimed = true;
        await _nutritionReadController.ensureDogAndRefresh(widget.dogId);
      },
    );
    // Sem selectDog de timeline/agenda/nutrição aqui: evita I/O se o usuário
    // não abrir a seção (ou até a 1ª mutation canônica).
  }

  @override
  void didUpdateWidget(covariant HealthV1EntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.dogId.trim();
    final prev = oldWidget.dogId.trim();
    if (next.isNotEmpty && next != prev) {
      _controller.selectDog(next);
      _filterSession.updateDogId(next);
      // Só recarrega timeline/agenda/nutrição se já foram abertas nesta vida.
      if (_timelinePrimed) {
        // ignore: discarded_futures
        _timelineController.selectDog(next);
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
    _filterSession.dispose();
    _timelineController.dispose();
    _scheduleMutationController.dispose();
    _nutritionMutationController.dispose();
    _nutritionReadController.dispose();
    _scheduleController.dispose();
    _controller.dispose();
    super.dispose();
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
    _timelineController.selectDog(widget.dogId);
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
  void primeNutritionForTest() => _primeNutritionIfNeeded();

  @visibleForTesting
  bool get nutritionReadPrimedForTest => _nutritionReadPrimed;

  void _onRegister() {
    AppFeedback.info(
      context,
      'Registro Health v1 em breve — use o fluxo legado se necessário.',
    );
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
            NutritionHistoryTarget() => NutritionFullScreen(dog: dog),
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
            final hint = (item.destinationHint ?? '').toLowerCase();
            if (hint.contains('agenda')) {
              _selectSection(HealthShellSection.agenda);
            } else if (hint.contains('nutri')) {
              _selectSection(HealthShellSection.nutricao);
            } else {
              _selectSection(HealthShellSection.historico);
            }
          },
          onRecentRecordTap: (_) {
            _selectSection(HealthShellSection.historico);
          },
        ),
        historico: (_) => HealthTimelineScreen(
          controller: _timelineController,
          filterSession: _filterSession,
          dogDisplayName: dogContext.name,
          bottomPadding: _timelineBottomPadding(context),
          onNavigate: _onTimelineNavigate,
        ),
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
          bottomPadding: _timelineBottomPadding(context),
        ),
      ),
    );
  }
}
