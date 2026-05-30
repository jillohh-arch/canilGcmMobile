import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/pending_screen.dart';
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

  /// Nome do condutor quando a tela já resolveu o display.
  final String? handlerNameOverride;

  /// Widget à direita (ex: botão trocar cão, botão perfil)
  final Widget? trailing;

  /// Callback para trocar o cão do turno. Quando informado, mostra o botão ⇄.
  final VoidCallback? onSwitchDog;

  /// Callback customizado para abrir o perfil do condutor.
  final VoidCallback? onProfileTap;

  /// Se true, mostra o sino de pendências/notificações.
  final bool showNotificationButton;

  /// RA usado para buscar pendências. Se null, usa o usuário autenticado.
  final String? notificationUserId;

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
    this.handlerNameOverride,
    this.trailing,
    this.onSwitchDog,
    this.onProfileTap,
    this.showNotificationButton = true,
    this.notificationUserId,
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
    final authVM = Provider.of<AuthViewModel>(context);
    final currentRa = HandlerIdentityService.raFromUser(authVM.user);
    final handlerRa = currentRa ?? dog.conductorRa;
    final notificationRa = notificationUserId?.trim().isNotEmpty == true
        ? notificationUserId!.trim()
        : currentRa;
    final providedHandlerName = handlerNameOverride?.trim();
    final handlerName =
        providedHandlerName != null && providedHandlerName.isNotEmpty
        ? providedHandlerName
        : userVM.displayNameFor(
            ra: handlerRa,
            firebaseUser: handlerRa == currentRa ? authVM.user : null,
          );
    final propPhoto = conductorPhotoUrl?.trim();
    final userPhoto = userVM.findByRa(handlerRa)?.photoUrl?.trim();
    final firebasePhoto = handlerRa == currentRa
        ? authVM.user?.photoURL?.trim()
        : null;
    final resolvedConductorPhotoUrl = propPhoto != null && propPhoto.isNotEmpty
        ? propPhoto
        : userPhoto != null && userPhoto.isNotEmpty
        ? userPhoto
        : firebasePhoto != null && firebasePhoto.isNotEmpty
        ? firebasePhoto
        : null;
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
                  imageUrl: resolvedConductorPhotoUrl,
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
                              color: (statusDotColor ?? AppTheme.success)
                                  .withAlpha(80),
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

        // Ações padronizadas do header
        if (onSwitchDog != null ||
            trailing != null ||
            (showNotificationButton && notificationRa != null) ||
            showProfileButton) ...[
          const SizedBox(width: 8),
          if (onSwitchDog != null) ...[
            _HeaderIconButton(
              icon: Icons.compare_arrows_rounded,
              tooltip: 'Trocar K9',
              onTap: onSwitchDog!,
            ),
            if (trailing != null ||
                (showNotificationButton && notificationRa != null) ||
                showProfileButton)
              const SizedBox(width: 6),
          ],
          ?trailing,
          if (trailing != null &&
              ((showNotificationButton && notificationRa != null) ||
                  showProfileButton))
            const SizedBox(width: 6),
          if (showNotificationButton && notificationRa != null) ...[
            _HeaderNotificationButton(userId: notificationRa),
            if (showProfileButton) const SizedBox(width: 6),
          ],
          if (showProfileButton) ...[
            _HeaderIconButton(
              icon: Icons.person_outline_rounded,
              tooltip: 'Perfil',
              onTap:
                  onProfileTap ??
                  () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
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

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.primary.withAlpha(50)),
          ),
          child: Center(child: Icon(icon, color: AppTheme.primary, size: 16)),
        ),
      ),
    );
  }
}

class _HeaderNotificationButton extends StatelessWidget {
  final String userId;

  const _HeaderNotificationButton({required this.userId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: NotificationService().getUnreadCount(userId: userId),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Badge(
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          backgroundColor: AppTheme.warning,
          textColor: AppTheme.background,
          child: _HeaderIconButton(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Pendências',
            onTap: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => PendingScreen(userId: userId),
                ),
              );
            },
          ),
        );
      },
    );
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
                placeholder: (_, _) => _buildFallback(),
                errorWidget: (_, _, _) => _buildFallback(),
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
