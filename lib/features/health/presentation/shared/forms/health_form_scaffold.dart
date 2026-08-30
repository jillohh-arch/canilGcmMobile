import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/shared/forms/health_form_controller.dart';
import 'package:canil_gcm/features/health/presentation/shared/forms/health_unsaved_changes.dart';

/// Estrutura base de tela de formulário do Health v1.
///
/// Resolve de forma idiomática:
/// - scroll com dismiss de teclado;
/// - `resizeToAvoidBottomInset`;
/// - barra de ações opcional (sticky inferior);
/// - proteção de saída com alterações não salvas (via [controller]).
///
/// Não cria controllers de texto, não persiste dados e não conhece domínio
/// clínico específico.
class HealthFormScaffold extends StatefulWidget {
  final String title;
  final Widget body;
  final Widget? bottomBar;
  final HealthFormController? controller;
  final bool protectUnsavedChanges;
  final Color accentColor;
  final List<Widget>? actions;

  /// Quando informado, substitui o pop padrão do AppBar.
  ///
  /// O caller assume a navegação. O [HealthUnsavedChangesGuard] (sistema
  /// back / `maybePop`) continua ativo se [protectUnsavedChanges] e
  /// [controller] estiverem configurados.
  final VoidCallback? onBack;
  final EdgeInsetsGeometry bodyPadding;

  const HealthFormScaffold({
    super.key,
    required this.title,
    required this.body,
    this.bottomBar,
    this.controller,
    this.protectUnsavedChanges = true,
    this.accentColor = AppTheme.primary,
    this.actions,
    this.onBack,
    this.bodyPadding = const EdgeInsets.fromLTRB(16, 12, 16, 24),
  });

  @override
  State<HealthFormScaffold> createState() => _HealthFormScaffoldState();
}

class _HealthFormScaffoldState extends State<HealthFormScaffold> {
  bool _appBarExitConfirmationInFlight = false;

  @override
  Widget build(BuildContext context) {
    Widget scaffold = Scaffold(
      backgroundColor: AppTheme.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppTheme.surfacePanel,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        title: Text(
          widget.title,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: AppTheme.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => _handleBack(context),
        ),
        actions: widget.actions,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: Container(height: 3, color: widget.accentColor),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.deferToChild,
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: widget.bodyPadding,
                child: widget.body,
              ),
            ),
          ),
          if (widget.bottomBar != null)
            SafeArea(
              top: false,
              child: Material(
                color: AppTheme.surfacePanel,
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: widget.bottomBar,
                ),
              ),
            ),
        ],
      ),
    );

    final formController = widget.controller;
    if (widget.protectUnsavedChanges && formController != null) {
      scaffold = HealthUnsavedChangesGuard(
        controller: formController,
        child: scaffold,
      );
    }

    return scaffold;
  }

  Future<void> _handleBack(BuildContext context) async {
    final formController = widget.controller;
    if (formController != null && formController.isSubmitting) {
      return;
    }

    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }

    if (widget.protectUnsavedChanges &&
        formController != null &&
        formController.isDirty) {
      if (_appBarExitConfirmationInFlight) return;
      _appBarExitConfirmationInFlight = true;
      try {
        final shouldLeave = await showHealthUnsavedChangesDialog(context);
        if (!shouldLeave || !context.mounted) return;
        // Força o pop: maybePop respeitaria o PopScope (canPop:false) e
        // reabriria o diálogo do HealthUnsavedChangesGuard.
        Navigator.of(context).pop();
      } finally {
        _appBarExitConfirmationInFlight = false;
      }
      return;
    }

    if (context.mounted) {
      Navigator.of(context).maybePop();
    }
  }
}
