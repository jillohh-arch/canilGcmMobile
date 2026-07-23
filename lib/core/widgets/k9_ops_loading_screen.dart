import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/theme/animation_constants.dart';
import 'package:canil_gcm/core/widgets/k9_ops_loading_stage.dart';
import 'package:canil_gcm/core/widgets/k9_ops_loading_visual.dart';

/// Loading oficial do K9 Ops (Mobile) — camada **puramente apresentacional**.
///
/// O widget recebe o estágio, o progresso e a mensagem externamente. Ele não
/// autentica, não consulta permissões, não lê Firestore e não decide
/// navegação. A conexão com o bootstrap real é responsabilidade da fase de
/// integração.
///
/// ## Área do asset ([visual])
///
/// O elemento visual central do Malinois é **injetável e opcional**. Enquanto o
/// asset Lottie oficial (`k9_ops_loading_dog.json`) e o fallback estático
/// oficial não estiverem disponíveis no repositório, o widget renderiza um
/// marcador HUD neutro — sem depender da existência de nenhum arquivo futuro,
/// sem quebrar build nem runtime.
///
/// Quando os assets oficiais forem entregues, basta passar o widget do Malinois
/// (Lottie ou imagem estática) via [visual]. Nenhuma outra parte da tela
/// precisa mudar.
class K9OpsLoadingScreen extends StatelessWidget {
  const K9OpsLoadingScreen({
    super.key,
    this.stage = K9OpsLoadingStage.initializing,
    this.progress,
    this.message,
    this.errorMessage,
    this.onRetry,
    this.visual,
    this.version,
  });

  /// Estágio visual atual do loading.
  final K9OpsLoadingStage stage;

  /// Progresso semideterminado de 0.0 a 1.0. Quando `null`, a barra opera em
  /// modo indeterminado (sem exibir percentual mentiroso).
  final double? progress;

  /// Mensagem de status principal. Quando `null`, usa o rótulo do [stage].
  final String? message;

  /// Mensagem de erro exibida quando [stage] é `error`.
  final String? errorMessage;

  /// Callback opcional de retry, exibido apenas no estado de erro.
  final VoidCallback? onRetry;

  /// Widget do Malinois (Lottie ou imagem estática oficial), injetado
  /// externamente. Quando `null`, um marcador HUD neutro é exibido.
  final Widget? visual;

  /// Versão/build exibida no rodapé (ex.: `v1.0.0`).
  final String? version;

  /// Etapas visíveis na interface Mobile (spec: apenas duas).
  static const List<K9OpsLoadingStage> _visibleSteps = [
    K9OpsLoadingStage.validatingAccess,
    K9OpsLoadingStage.syncingModules,
  ];

  /// Índice ordinal de um estágio para comparação de progresso entre etapas.
  int _stageOrder(K9OpsLoadingStage value) {
    switch (value) {
      case K9OpsLoadingStage.initializing:
      case K9OpsLoadingStage.validatingAccess:
        return 0;
      case K9OpsLoadingStage.syncingModules:
      case K9OpsLoadingStage.finalizing:
        return 1;
      case K9OpsLoadingStage.ready:
        return 2;
      case K9OpsLoadingStage.error:
        return -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool animate = shouldAnimate(context);
    final double? clampedProgress = progress?.clamp(0.0, 1.0);
    final double horizontalPadding =
        MediaQuery.of(context).size.width < 360 ? 16.0 : 24.0;
    final isError = stage.isError;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.35),
            radius: 0.9,
            colors: [
              AppTheme.primaryChipBackground, // ciano translúcido no centro
              AppTheme.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Column(
              children: [
                const Spacer(flex: 3),

                // ── Área do asset (injetável/opcional) ──────────────────
                _AssetStage(visual: visual, animate: animate),
                const SizedBox(height: 32),

                // ── Título principal ────────────────────────────────────
                Semantics(
                  header: true,
                  child: SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'INICIALIZANDO SISTEMA...',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.robotoMono(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                          letterSpacing: 2.5,
                        ),
                      ),
                    ),
                  ),
                ),
                // ── Status atual (apenas quando há mensagem explícita) ──
                // Evita duplicar o rótulo de uma etapa visível; útil para
                // estados prolongados (ex.: "Finalizando inicialização...").
                if (message != null && !isError) ...[
                  const SizedBox(height: 12),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                if (isError)
                  _ErrorBlock(
                    message: errorMessage ?? 'Não foi possível iniciar.',
                    onRetry: onRetry,
                  )
                else ...[
                  // ── Barra de progresso ────────────────────────────────
                  _ProgressBar(value: clampedProgress),
                  const SizedBox(height: 28),

                  // ── Etapas visuais ────────────────────────────────────
                  _StepList(
                    steps: _visibleSteps,
                    currentOrder: _stageOrder(stage),
                    isComplete: stage.isComplete,
                    animate: animate,
                  ),
                ],

                const Spacer(flex: 4),

                // ── Footer institucional ────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'K9 OPS • INTELLIGENCE IN MOTION',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.robotoMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.primary.withAlpha(90),
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
                if (version != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    version!,
                    style: GoogleFonts.robotoMono(
                      fontSize: 10,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Área central que hospeda o visual do Malinois.
///
/// Enquanto [visual] for `null` (asset oficial ainda não entregue), exibe um
/// marcador HUD neutro. A moldura circular (anéis + glow) é nativa e não
/// depende de nenhum asset.
class _AssetStage extends StatelessWidget {
  const _AssetStage({required this.visual, required this.animate});

  final Widget? visual;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Animação de carregamento do K9 Ops',
      child: SizedBox(
        width: 176,
        height: 176,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Glow de fundo — nativo.
            Container(
              width: 176,
              height: 176,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withAlpha(15),
              ),
            ),
            // Anel HUD estático — nativo, não compete com o cão.
            Container(
              width: 168,
              height: 168,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.primary.withAlpha(60),
                  width: 1.5,
                ),
              ),
            ),
            // Visual injetável ou fallback estático oficial (K9OpsLoadingVisual).
            visual ?? const K9OpsLoadingVisual(),
          ],
        ),
      ),
    );
  }
}

/// Barra de progresso semideterminada. Aceita [value] `null` para modo
/// indeterminado — nunca exibe percentual sem medição real.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    final percent = value == null ? null : (value! * 100).round();

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 240,
            height: 4,
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: AppTheme.primary.withAlpha(25),
              valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
            ),
          ),
        ),
        if (percent != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 240,
              child: Text(
                '$percent%',
                textAlign: TextAlign.right,
                style: GoogleFonts.robotoMono(
                  fontSize: 10,
                  color: AppTheme.primary.withAlpha(130),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Lista de etapas visuais com indicador de estado (concluída/ativa/pendente).
class _StepList extends StatelessWidget {
  const _StepList({
    required this.steps,
    required this.currentOrder,
    required this.isComplete,
    required this.animate,
  });

  final List<K9OpsLoadingStage> steps;
  final int currentOrder;
  final bool isComplete;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < steps.length; index++) ...[
          if (index > 0) const SizedBox(height: 14),
          _StepRow(
            label: steps[index].stepLabel,
            done: isComplete || index < currentOrder,
            active: !isComplete && index == currentOrder,
            animate: animate,
          ),
        ],
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.done,
    required this.active,
    required this.animate,
  });

  final String label;
  final bool done;
  final bool active;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final Color labelColor = (done || active)
        ? AppTheme.textPrimary
        : AppTheme.textTertiary;

    return Semantics(
      label: done
          ? '$label: concluído'
          : active
          ? '$label: em andamento'
          : '$label: pendente',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Center(
              child: _StepIndicator(done: done, active: active),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.done, required this.active});

  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (done) {
      return const Icon(Icons.check_rounded, size: 14, color: AppTheme.success);
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppTheme.primary : AppTheme.primary.withAlpha(60),
      ),
    );
  }
}

/// Bloco de erro — garante que o loading não fique preso e ofereça retry.
class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.error_outline_rounded, size: 32, color: AppTheme.error),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Tentar novamente'),
          ),
        ],
      ],
    );
  }
}
