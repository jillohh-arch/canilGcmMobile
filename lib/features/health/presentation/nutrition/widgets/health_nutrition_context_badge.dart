import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';

/// PASS 03D: badge de CLASSIFICAÇÃO DO REGISTRO no card de contexto.
///
/// Vive no canto superior direito, na mesma linha do nome do K9, para ler como
/// classificação do registro em vez de mais uma linha de conteúdo.
///
/// Responsividade: o chamador envolve este widget em `Flexible`/`Row` e o texto
/// usa `ellipsis`, então em 320px ou text scale alto o badge encurta em vez de
/// empurrar o nome para fora do card.
class HealthNutritionContextBadge extends StatelessWidget {
  const HealthNutritionContextBadge({
    super.key,
    required this.label,
    this.accent = AppTheme.primary,
    this.backgroundAlpha = 0.15,
  });

  final String label;
  final Color accent;

  /// Preserva o tom de fundo que cada card já usava antes da 03D.
  final double backgroundAlpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: backgroundAlpha),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          color: accent,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
