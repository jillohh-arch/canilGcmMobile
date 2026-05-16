part of 'active_shift_dashboard_screen.dart';

const Color _kDashboardBackground = Color(0xFF050D10);
const Color _kSurface = Color(0xF20B171C);
const Color _kSurfaceElevated = Color(0xFF0F2026);
const Color _kBorder = Color(0x523E7180);
const Color _kBorderStrong = Color(0x804DD0E1);
const Color _kTextPrimary = Color(0xFFF4F7F8);
const Color _kTextSecondary = Color(0xFFA7B4BA);
const Color _kTextMuted = Color(0xFF71828A);

const LinearGradient _kPanelGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xF2112028), Color(0xF207151B), Color(0xF20A1E25)],
);

BoxDecoration _panelDecoration({Color? borderColor}) {
  return BoxDecoration(
    gradient: _kPanelGradient,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: borderColor ?? _kBorder, width: 1.1),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withAlpha(68),
        blurRadius: 18,
        offset: const Offset(0, 10),
      ),
      BoxShadow(
        color: AppTheme.primary.withAlpha(12),
        blurRadius: 20,
        offset: const Offset(0, -2),
      ),
    ],
  );
}

class _DashboardPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  const _DashboardPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: _panelDecoration(borderColor: borderColor),
      child: child,
    );
  }
}

class _PanelTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;

  const _PanelTitle({required this.icon, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 20),
        const SizedBox(width: 11),
        Expanded(
          child: _AutoFitText(
            label,
            alignment: Alignment.centerLeft,
            textAlign: TextAlign.left,
            style: GoogleFonts.inter(
              color: _kTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _AutoFitText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Alignment alignment;
  final TextAlign textAlign;

  const _AutoFitText(
    this.text, {
    required this.style,
    this.alignment = Alignment.center,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitted = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: textAlign,
            style: style,
          ),
        );

        if (!constraints.maxWidth.isFinite) {
          return fitted;
        }

        return SizedBox(width: constraints.maxWidth, child: fitted);
      },
    );
  }
}

class _AutoFitBox extends StatelessWidget {
  final Widget child;
  final Alignment alignment;

  const _AutoFitBox({required this.child, this.alignment = Alignment.center});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitted = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: child,
        );

        if (!constraints.maxWidth.isFinite) {
          return fitted;
        }

        return SizedBox(width: constraints.maxWidth, child: fitted);
      },
    );
  }
}

/// Label de seção mantido para componentes antigos que ainda dependem dele.
class _SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const _SectionLabel({required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    return _PanelTitle(
      icon: Icons.label_important_outline_rounded,
      label: text,
      trailing: trailing,
    );
  }
}

/// Header operacional: avatares sobrepostos, nome do binômio, status e atalhos.
class _ShiftHeader extends StatelessWidget {
  final Dog dog;
  final String callsign;
  final String? conductorPhotoUrl;
  final VoidCallback onSwitchDog;

  const _ShiftHeader({
    required this.dog,
    required this.callsign,
    this.conductorPhotoUrl,
    required this.onSwitchDog,
  });

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final startTime = _formatStartTime(shiftVM.shiftStartTime);
    final conductorName = _shortConductorName(callsign);

    return _DashboardPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      borderColor: AppTheme.primary.withAlpha(48),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 380;
          final identity = _HeaderIdentity(
            dog: dog,
            conductorPhotoUrl: conductorPhotoUrl,
            conductorName: conductorName,
            startTime: startTime,
            compact: compact,
          );

          if (compact) {
            return Column(
              children: [
                identity,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _HeaderCommandButton(
                        icon: Icons.compare_arrows_rounded,
                        label: 'Trocar binômio',
                        onTap: () {
                          HapticFeedback.lightImpact();
                          onSwitchDog();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeaderCommandButton(
                        icon: Icons.person_rounded,
                        label: 'Meu perfil',
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ProfileScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: identity),
              const SizedBox(width: 10),
              SizedBox(
                width: 122,
                child: Column(
                  children: [
                    _HeaderCommandButton(
                      icon: Icons.compare_arrows_rounded,
                      label: 'Trocar binômio',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onSwitchDog();
                      },
                    ),
                    const SizedBox(height: 8),
                    _HeaderCommandButton(
                      icon: Icons.person_rounded,
                      label: 'Meu perfil',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ProfileScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _shortConductorName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Condutor';
    final pieces = trimmed.split(RegExp(r'\s+'));
    return pieces.length <= 1 ? pieces.first : pieces.last;
  }

  String _formatStartTime(DateTime? start) {
    if (start == null) return '--:--';
    return '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
  }
}

class _HeaderIdentity extends StatelessWidget {
  final Dog dog;
  final String? conductorPhotoUrl;
  final String conductorName;
  final String startTime;
  final bool compact;

  const _HeaderIdentity({
    required this.dog,
    required this.conductorPhotoUrl,
    required this.conductorName,
    required this.startTime,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final avatarWidth = compact ? 86.0 : 98.0;
    final avatarHeight = compact ? 66.0 : 74.0;
    final dogAvatarSize = compact ? 66.0 : 74.0;
    final conductorAvatarSize = compact ? 58.0 : 66.0;

    return Row(
      children: [
        SizedBox(
          width: avatarWidth,
          height: avatarHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: 0,
                top: 4,
                child: _HeaderAvatar(
                  imageUrl: conductorPhotoUrl,
                  fallbackIcon: Icons.person_rounded,
                  borderColor: _kTextSecondary,
                  size: conductorAvatarSize,
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: _HeaderAvatar(
                  imageUrl: dog.profileImageUrl,
                  fallbackText: dog.name.isNotEmpty ? dog.name[0] : 'K',
                  borderColor: _kTextPrimary,
                  size: dogAvatarSize,
                ),
              ),
              Positioned(
                left: compact ? 54 : 62,
                bottom: 3,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.success,
                    border: Border.all(color: _kSurfaceElevated, width: 3),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: compact ? 10 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AutoFitText(
                '${dog.name} • $conductorName',
                alignment: Alignment.centerLeft,
                textAlign: TextAlign.left,
                style: GoogleFonts.inter(
                  fontSize: compact ? 20 : 21,
                  fontWeight: FontWeight.w900,
                  color: _kTextPrimary,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.success,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.success.withAlpha(90),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AutoFitText(
                      'Turno ativo desde $startTime',
                      alignment: Alignment.centerLeft,
                      textAlign: TextAlign.left,
                      style: GoogleFonts.inter(
                        fontSize: compact ? 13 : 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.success,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'K9 Operacional',
                style: GoogleFonts.inter(
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w500,
                  color: _kTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderCommandButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderCommandButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(8),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              Icon(icon, color: _kTextPrimary, size: 25),
              const SizedBox(width: 10),
              Expanded(
                child: _AutoFitText(
                  label,
                  alignment: Alignment.centerLeft,
                  textAlign: TextAlign.left,
                  style: GoogleFonts.inter(
                    color: _kTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? fallbackText;
  final IconData? fallbackIcon;
  final Color borderColor;
  final double size;

  const _HeaderAvatar({
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
        color: _kSurfaceElevated,
        border: Border.all(color: borderColor, width: 1.5),
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
      color: _kSurfaceElevated,
      child: Center(
        child: fallbackText != null
            ? Text(
                fallbackText!,
                style: GoogleFonts.inter(
                  color: borderColor,
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w900,
                ),
              )
            : Icon(
                fallbackIcon ?? Icons.person_rounded,
                color: borderColor.withAlpha(190),
                size: size * 0.42,
              ),
      ),
    );
  }
}
