import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/screens/profile_screen.dart';

/// Widget universal de cabeçalho binômio (cão + condutor).
/// Mostra fotos sobrepostas, nomes, e status/subtítulo opcional.
///
/// Uso:
/// ```dart
/// BinomioHeader(
///   dog: dog,
///   subtitle: 'Turno ativo · há 5h',
///   subtitleColor: AppTheme.success,
///   trailing: IconButton(...),
/// )
/// ```
class BinomioHeader extends StatelessWidget {
  final Dog dog;

  /// Texto abaixo do binômio (ex: "Turno ativo · há 5h", "MANUTENÇÃO OPERACIONAL")
  final String? subtitle;

  /// Cor do subtítulo (default: textSecondary)
  final Color? subtitleColor;

  /// Cor da borda do avatar do cão (default: primary/cyan)
  final Color? dogBorderColor;

  /// Cor da borda do avatar do condutor (default: success/green)
  final Color? conductorBorderColor;

  /// URL da foto do condutor (se null, usa fallback icon)
  final String? conductorPhotoUrl;

  /// Widget à direita (ex: botão trocar cão, botão perfil)
  final Widget? trailing;

  /// Se true, mostra dot de status antes do subtitle
  final bool showStatusDot;

  /// Cor do dot de status (default: success)
  final Color? statusDotColor;

  /// Tamanho dos avatares (default: 50)
  final double avatarSize;

  /// Se true, envolve em container com fundo e borda
  final bool withBackground;

  /// Callback ao tocar no header (ex: abrir perfil do cão)
  final VoidCallback? onTap;

  /// Se true, mostra botão 👤 que navega para ProfileScreen (default: true)
  final bool showProfileButton;

  const BinomioHeader({
    super.key,
    required this.dog,
    this.subtitle,
    this.subtitleColor,
    this.dogBorderColor,
    this.conductorBorderColor,
    this.conductorPhotoUrl,
    this.trailing,
    this.showStatusDot = false,
    this.statusDotColor,
    this.avatarSize = 50,
    this.withBackground = true,
    this.onTap,
    this.showProfileButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final userVM = Provider.of<UserViewModel>(context);
    final handlerName = userVM.displayNameFor(ra: dog.conductorRa);
    final dogColor = dogBorderColor ?? AppTheme.primary;
    final conductorColor = conductorBorderColor ?? AppTheme.success;

    Widget content = Row(
      children: [
        // Avatares sobrepostos
        SizedBox(
          width: avatarSize * 1.7,
          height: avatarSize + 4,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 2,
                child: _BinomioAvatar(
                  imageUrl: dog.profileImageUrl,
                  fallbackText: dog.name.isNotEmpty ? dog.name[0] : 'K',
                  borderColor: dogColor,
                  size: avatarSize,
                ),
              ),
              Positioned(
                left: avatarSize * 0.65,
                top: 2,
                child: _BinomioAvatar(
                  imageUrl: conductorPhotoUrl,
                  fallbackIcon: Icons.person_rounded,
                  borderColor: conductorColor,
                  size: avatarSize,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),

        // Nomes + subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${dog.name} · $handlerName',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (showStatusDot) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusDotColor ?? AppTheme.success,
                          boxShadow: [
                            BoxShadow(
                              color: (statusDotColor ?? AppTheme.success).withAlpha(80),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        subtitle!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: subtitleColor ?? AppTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // Trailing widget + profile button
        if (trailing != null || showProfileButton) ...[
          const SizedBox(width: 8),
          if (trailing != null) trailing!,
          if (showProfileButton) ...[
            if (trailing != null) const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primary.withAlpha(50)),
                ),
                child: const Center(
                  child: Text('👤', style: TextStyle(fontSize: 13)),
                ),
              ),
            ),
          ],
        ],
      ],
    );

    if (onTap != null) {
      content = GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap!();
        },
        behavior: HitTestBehavior.opaque,
        child: content,
      );
    }

    if (withBackground) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1A1F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: dogColor.withAlpha(30)),
        ),
        child: content,
      );
    }

    return content;
  }
}

/// Avatar circular com foto ou fallback.
class _BinomioAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? fallbackText;
  final IconData? fallbackIcon;
  final Color borderColor;
  final double size;

  const _BinomioAvatar({
    this.imageUrl,
    this.fallbackText,
    this.fallbackIcon,
    required this.borderColor,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.background,
        border: Border.all(color: borderColor, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: borderColor.withAlpha(35),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipOval(
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, __) => _buildFallback(),
                errorWidget: (_, __, ___) => _buildFallback(),
              )
            : _buildFallback(),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      color: const Color(0xFF1A2A30),
      child: Center(
        child: fallbackText != null
            ? Text(
                fallbackText!,
                style: GoogleFonts.inter(
                  color: borderColor,
                  fontSize: size * 0.32,
                  fontWeight: FontWeight.w800,
                ),
              )
            : Icon(
                fallbackIcon ?? Icons.person_rounded,
                color: borderColor.withAlpha(180),
                size: size * 0.4,
              ),
      ),
    );
  }
}
