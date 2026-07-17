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
import 'package:canil_gcm/features/health/presentation/schedule/empty_health_schedule_source.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_presentation_policy.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_screen.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_controller.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_screen.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_shell_section.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_shell_section_placeholder.dart';
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
/// Agenda é read-only (Empty source em produção até 4C). Sem writes.
class HealthV1EntryScreen extends StatefulWidget {
  final String dogId;

  /// Source de resumo injetável (testes).
  final HealthSummarySource? source;

  /// Source da timeline injetável (testes). Produção: Firestore read-only 3C.
  final HealthTimelineSource? timelineSource;

  /// Source da agenda injetável (testes). Produção: [EmptyHealthScheduleSource].
  final HealthScheduleSource? scheduleSource;

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

  /// Primeira carga da timeline só após visitar Histórico (lazy).
  bool _timelinePrimed = false;

  /// Primeira carga da agenda só após visitar Agenda (lazy).
  bool _schedulePrimed = false;

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

    // Agenda 4B: source vazia honesta em produção; fake injetável em testes.
    _scheduleSource =
        widget.scheduleSource ?? const EmptyHealthScheduleSource();
    _scheduleController = HealthScheduleController(
      source: _scheduleSource,
      temporalPolicy: healthSchedulePresentationPolicy(),
    );
    // Sem selectDog aqui: evita I/O se o usuário não abrir Agenda.
  }

  @override
  void didUpdateWidget(covariant HealthV1EntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.dogId.trim();
    final prev = oldWidget.dogId.trim();
    if (next.isNotEmpty && next != prev) {
      _controller.selectDog(next);
      _filterSession.updateDogId(next);
      // Só recarrega timeline/agenda se já foram abertas nesta vida do entry.
      if (_timelinePrimed) {
        // ignore: discarded_futures
        _timelineController.selectDog(next);
      }
      if (_schedulePrimed) {
        // ignore: discarded_futures
        _scheduleController.selectDog(next);
      }
    }
  }

  @override
  void dispose() {
    _filterSession.dispose();
    _timelineController.dispose();
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

  @visibleForTesting
  void primeTimelineForTest() => _primeTimelineIfNeeded();

  @visibleForTesting
  void primeScheduleForTest() => _primeScheduleIfNeeded();

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
          dogDisplayName: dogContext.name,
          bottomPadding: _timelineBottomPadding(context),
        ),
        nutricao: (_) => const HealthShellSectionPlaceholder(
          section: HealthShellSection.nutricao,
          message:
              'Nutrição Health v1 em construção. O card do Resumo já lê dados reais.',
        ),
      ),
    );
  }
}
