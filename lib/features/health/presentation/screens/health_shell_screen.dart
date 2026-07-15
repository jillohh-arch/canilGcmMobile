import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_module_header.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_section_navigation.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_shell_section.dart';

/// Construtor de conteúdo de uma área do shell.
///
/// Chamado na **primeira visita** à seção e reutilizado nas rebuilds
/// enquanto a seção permanecer montada (preservação de estado).
typedef HealthShellSectionBuilder = Widget Function(BuildContext context);

/// Shell definitivo do módulo Health v1.0.
///
/// Fornece apenas a moldura:
/// - header (título + subtítulo + Registrar);
/// - navegação das quatro áreas oficiais;
/// - área de conteúdo com montagem **lazy por visita** e preservação
///   de estado após a primeira abertura de cada área.
///
/// Os builders de seção são **obrigatórios**: não há defaults de placeholder
/// em produção. Use [HealthShellSectionPlaceholder] explicitamente em
/// testes/demo se precisar de conteúdo estrutural neutro.
///
/// Não carrega dados clínicos, não conhece Firebase e não conecta o legado.
class HealthShellScreen extends StatefulWidget {
  /// Callback isolado do botão "+ Registrar". Sem I/O nesta fase.
  final VoidCallback? onRegister;

  /// Seção inicial (padrão: Resumo).
  final HealthShellSection initialSection;

  /// Conteúdo do Resumo (obrigatório — sem default de placeholder).
  final HealthShellSectionBuilder resumo;

  /// Conteúdo do Histórico (obrigatório).
  final HealthShellSectionBuilder historico;

  /// Conteúdo da Agenda (obrigatório).
  final HealthShellSectionBuilder agenda;

  /// Conteúdo da Nutrição (obrigatório).
  final HealthShellSectionBuilder nutricao;

  /// Notifica troca de seção (útil para testes e integração futura).
  final ValueChanged<HealthShellSection>? onSectionChanged;

  /// Padding horizontal/vertical do conteúdo do shell.
  final EdgeInsets contentPadding;

  const HealthShellScreen({
    super.key,
    required this.resumo,
    required this.historico,
    required this.agenda,
    required this.nutricao,
    this.onRegister,
    this.initialSection = HealthShellSection.resumo,
    this.onSectionChanged,
    this.contentPadding = const EdgeInsets.fromLTRB(16, 8, 16, 16),
  });

  @override
  State<HealthShellScreen> createState() => HealthShellScreenState();
}

/// Estado público o suficiente para testes (seção selecionada / selectSection).
class HealthShellScreenState extends State<HealthShellScreen> {
  late HealthShellSection _selectedSection;

  /// Seções já visitadas — permanecem montadas para preservar estado.
  final Set<HealthShellSection> _visitedSections = <HealthShellSection>{};

  HealthShellSection get selectedSection => _selectedSection;

  /// Exposto para testes: seções que já foram materializadas.
  @visibleForTesting
  Set<HealthShellSection> get visitedSectionsForTest =>
      Set<HealthShellSection>.unmodifiable(_visitedSections);

  @override
  void initState() {
    super.initState();
    _selectedSection = widget.initialSection;
    _visitedSections.add(_selectedSection);
  }

  void selectSection(HealthShellSection section) {
    if (_selectedSection == section) return;
    setState(() {
      _selectedSection = section;
      _visitedSections.add(section);
    });
    widget.onSectionChanged?.call(section);
  }

  HealthShellSectionBuilder _builderFor(HealthShellSection section) {
    switch (section) {
      case HealthShellSection.resumo:
        return widget.resumo;
      case HealthShellSection.historico:
        return widget.historico;
      case HealthShellSection.agenda:
        return widget.agenda;
      case HealthShellSection.nutricao:
        return widget.nutricao;
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.contentPadding.left;
    final bottom = widget.contentPadding.bottom;

    return ColoredBox(
      color: AppTheme.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 0),
              child: HealthModuleHeader(onRegister: widget.onRegister),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontal),
              child: HealthSectionNavigation(
                selected: _selectedSection,
                onSelected: selectSection,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, bottom),
                child: IndexedStack(
                  index: _selectedSection.navigationIndex,
                  sizing: StackFit.expand,
                  children: [
                    for (final section in HealthShellSection.navigationOrder)
                      if (_visitedSections.contains(section))
                        KeyedSubtree(
                          key: ValueKey<HealthShellSection>(section),
                          child: _builderFor(section)(context),
                        )
                      else
                        const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
