import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/coexistence_health_summary_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_dog_context_mapper.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_shell_screen.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_controller.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dashboard.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_shell_section.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_shell_section_placeholder.dart';

/// Entrada de produção controlada do Health v1.0 (Fase 2E).
///
/// Compõe:
/// - [HealthShellScreen] (2A)
/// - [HealthSummaryController] + [HealthSummarySource] (2B/2D)
/// - [HealthSummaryDashboard] (2C)
/// - [HealthSummaryDogContextMapper] (2D)
///
/// Histórico / Agenda / Nutrição permanecem placeholders estruturais.
/// Sem writes. Sem cálculo de readiness.
class HealthV1EntryScreen extends StatefulWidget {
  final String dogId;

  /// Permite injetar source em testes (sem Firestore real).
  final HealthSummarySource? source;

  /// Contexto do K9 pré-resolvido (testes). Em produção, resolve via [DogViewModel].
  final HealthSummaryDogContextView? dogContextOverride;

  const HealthV1EntryScreen({
    super.key,
    required this.dogId,
    this.source,
    this.dogContextOverride,
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

  HealthSummaryController get controllerForTest => _controller;

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? CoexistenceHealthSummarySource();
    _controller = HealthSummaryController(source: _source);
    _controller.selectDog(widget.dogId);
  }

  @override
  void didUpdateWidget(covariant HealthV1EntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.dogId.trim();
    final prev = oldWidget.dogId.trim();
    if (next.isNotEmpty && next != prev) {
      _controller.selectDog(next);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectSection(HealthShellSection section) {
    _shellKey.currentState?.selectSection(section);
  }

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
    // Lista ainda carregando ou cão ausente do catálogo — identidade mínima.
    return HealthSummaryDogContextView(
      dogId: id,
      name: dogVM.isLoading ? 'Carregando…' : 'K9',
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
        historico: (_) => const HealthShellSectionPlaceholder(
          section: HealthShellSection.historico,
          message:
              'Histórico Health v1 em construção. O Resumo já usa dados reais.',
        ),
        agenda: (_) => const HealthShellSectionPlaceholder(
          section: HealthShellSection.agenda,
          message:
              'Agenda Health v1 em construção. O Resumo já usa dados reais.',
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
