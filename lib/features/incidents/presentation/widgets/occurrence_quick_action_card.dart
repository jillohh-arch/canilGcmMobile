import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Card de ação rápida da ocorrência.
///
/// Quando há [assetPath], usa a própria arte como conteúdo do card
/// (a imagem já é um card completo: título, subtítulo, ícone e
/// ilustração). Quando não há arte (ex.: subopções de "Material
/// localizado"), exibe um fallback compacto com ícone + título.
class OccurrenceQuickActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final String? assetPath;
  final double width;
  final bool enabled;
  final VoidCallback onTap;

  const OccurrenceQuickActionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.width,
    required this.enabled,
    required this.onTap,
    this.assetPath,
  });

  @override
  Widget build(BuildContext context) {
    final hasAsset = (assetPath ?? '').isNotEmpty;
    return SizedBox(
      width: width,
      height: width, // 1:1 — respeita o aspect das artes
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1220),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: color.withAlpha(enabled ? 110 : 50),
                width: 1.2,
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: color.withAlpha(22),
                        blurRadius: 14,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: hasAsset
                  ? _ArtworkCard(
                      assetPath: assetPath!,
                      title: title,
                      icon: icon,
                      color: color,
                      enabled: enabled,
                    )
                  : _FallbackCard(
                      title: title,
                      icon: icon,
                      color: color,
                      enabled: enabled,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mostra a arte ocupando o card inteiro. A arte já contém todos os
/// elementos visuais (título, ícone, ilustração) — então não há
/// sobreposição de gradiente nem ícone fallback.
class _ArtworkCard extends StatelessWidget {
  final String assetPath;
  final String title;
  final IconData icon;
  final Color color;
  final bool enabled;

  const _ArtworkCard({
    required this.assetPath,
    required this.title,
    required this.icon,
    required this.color,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Image.asset(
        assetPath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _FallbackCard(
          title: title,
          icon: icon,
          color: color,
          enabled: enabled,
        ),
      ),
    );
  }
}

/// Card fallback usado quando a ação não tem [assetPath] (subopções)
/// ou se a arte falhar ao carregar.
class _FallbackCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool enabled;

  const _FallbackCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withAlpha(enabled ? 28 : 14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withAlpha(enabled ? 150 : 70)),
            ),
            child: Icon(
              icon,
              color: enabled ? color : color.withAlpha(120),
              size: 26,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.robotoMono(
              color: enabled ? Colors.white : Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.55,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}
