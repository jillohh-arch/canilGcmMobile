import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/core/widgets/hud_status_dot.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/presentation/screens/dog_health_prontuario_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/pending_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/vehicle_crew_profile_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/shift_group_widgets.dart';
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

  /// Callback customizado para abrir a aba/tela de saude do K9.
  final VoidCallback? onDogHealthTap;

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
    this.onDogHealthTap,
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
        _HeaderMenuButton(
          dog: dog,
          showProfile: showProfileButton,
          onProfileTap: onProfileTap,
          onDogHealthTap: onDogHealthTap,
          onSwitchDog: onSwitchDog,
        ),
        const SizedBox(width: 10),

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
                      HudStatusDot(
                        color: statusDotColor ?? AppTheme.success,
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
              const SizedBox(height: 4),
              const ShiftGroupBadge(compact: true),
            ],
          ),
        ),

        // Ações padronizadas do header: sino separado do menu para pendências.
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        if (showNotificationButton && notificationRa != null) ...[
          const SizedBox(width: 8),
          _HeaderNotificationBell(userId: notificationRa),
        ],
        const SizedBox(width: 8),
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
          color: AppTheme.surfacePanel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: dogColor.withAlpha(30)),
        ),
        child: content,
      );
    }

    return content;
  }
}

class _HeaderMenuVisualButton extends StatelessWidget {
  const _HeaderMenuVisualButton();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Menu',
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppTheme.primary.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primary.withAlpha(50)),
        ),
        child: const Center(
          child: Icon(Icons.menu_rounded, color: AppTheme.primary, size: 18),
        ),
      ),
    );
  }
}

class _HeaderNotificationBell extends StatelessWidget {
  final String userId;

  const _HeaderNotificationBell({required this.userId});

  @override
  Widget build(BuildContext context) {
    final notificationService = NotificationService();

    return StreamBuilder<int>(
      stream: notificationService.getOpenActionCount(userId: userId),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final label = count > 99 ? '99+' : '$count';

        return Semantics(
          button: true,
          label: count > 0 ? '$label pendencias requerem acao' : 'Notificacoes',
          child: Tooltip(
            message: count > 0
                ? '$label pendencias requerem acao'
                : 'Notificacoes',
            child: Badge(
              isLabelVisible: count > 0,
              backgroundColor: AppTheme.warning,
              textColor: AppTheme.background,
              label: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                      builder: (_) => PendingScreen(userId: userId),
                    ),
                  );
                },
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.surfacePanelAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primary.withAlpha(45)),
                  ),
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    color: AppTheme.primary,
                    size: 19,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _HeaderMenuAction { profile, team, dog, switchDog, endShift, logout }

class _HeaderMenuButton extends StatelessWidget {
  final Dog dog;
  final bool showProfile;
  final VoidCallback? onProfileTap;
  final VoidCallback? onDogHealthTap;
  final VoidCallback? onSwitchDog;

  const _HeaderMenuButton({
    required this.dog,
    required this.showProfile,
    required this.onProfileTap,
    required this.onDogHealthTap,
    required this.onSwitchDog,
  });

  @override
  Widget build(BuildContext context) {
    return _buildMenu(context);
  }

  Widget _buildMenu(BuildContext context) {
    return Consumer2<ShiftViewModel, AuthViewModel>(
      builder: (context, shiftVM, authVM, _) {
        final hasActiveShift = shiftVM.hasActiveShift;
        final hasCrew = shiftVM.vehicleCrewId?.trim().isNotEmpty == true;

        return PopupMenuButton<_HeaderMenuAction>(
          tooltip: 'Menu',
          color: AppTheme.surfacePanel,
          elevation: 10,
          offset: const Offset(0, 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppTheme.primary.withAlpha(45)),
          ),
          onSelected: (action) =>
              _handleAction(context, action, shiftVM, authVM),
          itemBuilder: (context) => [
            _menuItem(
              _HeaderMenuAction.profile,
              Icons.person_outline_rounded,
              'Meu perfil',
              enabled: showProfile,
            ),
            _menuItem(
              _HeaderMenuAction.team,
              Icons.groups_2_outlined,
              'Minha equipe',
              enabled: hasCrew,
            ),
            _menuItem(_HeaderMenuAction.dog, Icons.pets_rounded, 'Meu K9'),
            _menuItem(
              _HeaderMenuAction.switchDog,
              Icons.compare_arrows_rounded,
              'Trocar K9',
              enabled: hasActiveShift && onSwitchDog != null,
            ),
            const PopupMenuDivider(height: 10),
            _menuItem(
              _HeaderMenuAction.endShift,
              Icons.power_settings_new_rounded,
              'Encerrar turno',
              enabled: hasActiveShift,
              destructive: true,
            ),
            _menuItem(
              _HeaderMenuAction.logout,
              Icons.logout_rounded,
              'Sair',
              destructive: true,
            ),
          ],
          child: const _HeaderMenuVisualButton(),
        );
      },
    );
  }

  PopupMenuItem<_HeaderMenuAction> _menuItem(
    _HeaderMenuAction action,
    IconData icon,
    String label, {
    bool enabled = true,
    bool destructive = false,
  }) {
    final color = destructive ? AppTheme.error : AppTheme.textPrimary;
    return PopupMenuItem<_HeaderMenuAction>(
      value: action,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 18, color: enabled ? color : AppTheme.textTertiary),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.inter(
              color: enabled ? color : AppTheme.textTertiary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    _HeaderMenuAction action,
    ShiftViewModel shiftVM,
    AuthViewModel authVM,
  ) async {
    HapticFeedback.lightImpact();
    switch (action) {
      case _HeaderMenuAction.profile:
        if (onProfileTap != null) {
          onProfileTap!();
        } else {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
        }
        break;
      case _HeaderMenuAction.team:
        final crewId = shiftVM.vehicleCrewId;
        if (crewId == null || crewId.trim().isEmpty) {
          _showSnack(context, 'Nenhuma equipe ativa no turno.');
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VehicleCrewProfileScreen(crewId: crewId),
          ),
        );
        break;
      case _HeaderMenuAction.dog:
        if (onDogHealthTap != null) {
          onDogHealthTap!();
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DogHealthProntuarioScreen(dogId: dog.id),
            ),
          );
        }
        break;
      case _HeaderMenuAction.switchDog:
        if (onSwitchDog == null) {
          _showSnack(context, 'Troca de K9 indisponível nesta tela.');
          return;
        }
        onSwitchDog!();
        break;
      case _HeaderMenuAction.endShift:
        await _confirmEndShift(context, shiftVM);
        break;
      case _HeaderMenuAction.logout:
        await _confirmLogout(context, authVM);
        break;
    }
  }

  Future<void> _confirmEndShift(
    BuildContext context,
    ShiftViewModel shiftVM,
  ) async {
    final confirmed = await _confirm(
      context,
      title: 'Encerrar turno?',
      message: 'O turno ativo será finalizado para este condutor.',
      confirmLabel: 'Encerrar',
    );
    if (confirmed != true) return;

    await shiftVM.endShift();
    // Sem guard de mounted: ao encerrar o turno o app troca de tela e desmonta
    // este widget. O AppFeedback detecta isso e roteia para o messenger global,
    // que sobrevive à navegação.
    // ignore: use_build_context_synchronously
    AppFeedback.success(context, 'Expediente finalizado. Bom descanso, GCM!', title: 'Até logo');
  }

  Future<void> _confirmLogout(
    BuildContext context,
    AuthViewModel authVM,
  ) async {
    final confirmed = await _confirm(
      context,
      title: 'Sair do app?',
      message: 'Você precisará fazer login novamente.',
      confirmLabel: 'Sair',
    );
    if (confirmed != true) return;

    await authVM.signOut();
    if (!context.mounted) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
  }

  Future<bool?> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfacePanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          title,
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(color: AppTheme.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              confirmLabel,
              style: GoogleFonts.inter(
                color: AppTheme.error,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    AppFeedback.info(context, message);
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
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(size / 2),
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
      color: AppTheme.surfacePanelAlt,
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
