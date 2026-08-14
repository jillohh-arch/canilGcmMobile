import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';

/// PASS 03C: avatar do K9 para o card de contexto dos modais de Nutrição.
///
/// Não busca dado algum: recebe uma URL que já existe no contexto atual do app
/// (`Dog.profileImageUrl`, exposta como `HealthSummaryDogContextView.photoUrl`).
/// Quando a URL está ausente, vazia ou a imagem falha ao carregar, o fallback é
/// o mesmo `Icons.pets_rounded` usado antes desta pass — nunca uma área vazia.
class HealthNutritionDogAvatar extends StatelessWidget {
  const HealthNutritionDogAvatar({
    super.key,
    required this.dogDisplayName,
    this.photoUrl,
    this.size = 56,
    this.accent = AppTheme.primary,
  });

  /// Usado apenas para rótulo de acessibilidade.
  final String dogDisplayName;

  /// URL já disponível no contexto. `null`/vazia → fallback.
  final String? photoUrl;

  final double size;

  /// Cor da borda/fallback, para o card herdar o tom do seu contexto.
  final Color accent;

  bool get _hasPhoto => photoUrl != null && photoUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // A foto é decorativa; o nome do K9 já é texto no card. O label evita
      // que o leitor de tela anuncie um elemento sem significado.
      label: 'Foto de $dogDisplayName',
      image: true,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: _hasPhoto
            ? CachedNetworkImage(
                imageUrl: photoUrl!.trim(),
                fit: BoxFit.cover,
                width: size,
                height: size,
                placeholder: (_, _) => _fallback(),
                errorWidget: (_, _, _) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Icon(
    Icons.pets_rounded,
    key: const ValueKey('nutrition-dog-avatar-fallback'),
    color: accent,
    size: size * 0.5,
  );
}
