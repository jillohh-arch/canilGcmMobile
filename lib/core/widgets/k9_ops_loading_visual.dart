import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/animation_constants.dart';

/// Elemento visual do carregamento oficial do K9 Ops (Mobile).
///
/// Encapsula a renderização do elemento central do Malinois.
///
/// - **Animações habilitadas:** Tenta renderizar o Animated WebP oficial
///   (`assets/images/k9_ops_loading_dog_animated.webp`).
/// - **Reduced Motion:** Renderiza diretamente o fallback estático PNG
///   (`assets/images/k9_ops_loading_dog_static_v1.png`) sem tentar carregar a mídia animada.
/// - **Erro no WebP:** Se o asset animado falhar ao carregar ou decodificar, cai
///   suavemente para o fallback estático PNG.
class K9OpsLoadingVisual extends StatefulWidget {
  const K9OpsLoadingVisual({
    super.key,
    this.assetPath = _defaultStaticAsset,
    this.size = 156,
  });

  /// Path oficial do fallback estático no Mobile.
  static const String _defaultStaticAsset =
      'assets/images/k9_ops_loading_dog_static_v1.png';

  /// Path oficial do asset animado no Mobile.
  static const String _defaultAnimatedAsset =
      'assets/images/k9_ops_loading_dog_animated.webp';

  /// Path do asset de imagem.
  final String assetPath;

  /// Dimensão (largura/altura) do visual.
  final double size;

  @override
  State<K9OpsLoadingVisual> createState() => _K9OpsLoadingVisualState();
}

class _K9OpsLoadingVisualState extends State<K9OpsLoadingVisual> {
  bool _hasAnimatedWebpError = false;

  Widget _buildFallbackIcon() {
    return Icon(
      Icons.pets_rounded,
      size: widget.size * 0.45,
      color: const Color(0xFF00E5FF).withAlpha(110),
    );
  }

  Widget _buildStaticImage(String path) {
    return Image.asset(
      path,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => _buildFallbackIcon(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Se o invocador forneceu um assetPath customizado (diferente do padrão),
    // respeita explicitamente esse caminho.
    if (widget.assetPath != K9OpsLoadingVisual._defaultStaticAsset) {
      return _buildStaticImage(widget.assetPath);
    }

    final bool animate = shouldAnimate(context);

    // Quando movimento reduzido estiver ativo ou se o Animated WebP sofreu erro
    // prévio, renderiza diretamente o PNG estático oficial sem tentar o WebP.
    if (!animate || _hasAnimatedWebpError) {
      return _buildStaticImage(K9OpsLoadingVisual._defaultStaticAsset);
    }

    // Tenta renderizar o Animated WebP oficial.
    return Image.asset(
      K9OpsLoadingVisual._defaultAnimatedAsset,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        // Marca o erro para que reconstruções subsequentes usem o PNG estático.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_hasAnimatedWebpError) {
            setState(() {
              _hasAnimatedWebpError = true;
            });
          }
        });
        // Renderiza o PNG estático imediatamente como fallback visual.
        return _buildStaticImage(K9OpsLoadingVisual._defaultStaticAsset);
      },
    );
  }
}
