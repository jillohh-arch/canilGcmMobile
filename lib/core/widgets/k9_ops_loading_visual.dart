import 'package:flutter/material.dart';

/// Elemento visual do carregamento oficial do K9 Ops (Mobile).
///
/// Encapsula a renderização do elemento central do Malinois. Na Fase 2A,
/// renderiza o fallback estático oficial (`assets/images/k9_ops_loading_dog_static_v1.png`).
///
/// Na Fase 5, esta abstração responderá pelo Lottie oficial com fallback
/// automático para a imagem estática se o asset animado falhar ou estiver
/// indisponível, sem necessidade de refatorar o [K9OpsLoadingScreen].
class K9OpsLoadingVisual extends StatelessWidget {
  const K9OpsLoadingVisual({
    super.key,
    this.assetPath = _defaultStaticAsset,
    this.size = 140,
  });

  /// Path oficial do fallback estático no Mobile.
  static const String _defaultStaticAsset =
      'assets/images/k9_ops_loading_dog_static_v1.png';

  /// Path do asset de imagem.
  final String assetPath;

  /// Dimensão (largura/altura) do visual.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        return Icon(
          Icons.pets_rounded,
          size: size * 0.45,
          color: const Color(0xFF00E5FF).withAlpha(110),
        );
      },
    );
  }
}
