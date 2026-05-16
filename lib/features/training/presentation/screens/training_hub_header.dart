part of 'training_hub_screen.dart';

const Color _trainingBackground = Color(0xFF050D10);
const Color _trainingSurface = Color(0xF20B171C);
const Color _trainingSurfaceHigh = Color(0xFF0F2026);
const Color _trainingBorder = Color(0x523E7180);
const Color _trainingBorderStrong = Color(0x804DD0E1);
const Color _trainingTextPrimary = Color(0xFFF4F7F8);
const Color _trainingTextSecondary = Color(0xFFA7B4BA);
const Color _trainingTextMuted = Color(0xFF71828A);
const Color _trainingGreen = Color(0xFF74DB69);
const Color _trainingYellow = Color(0xFFFFC23A);

const LinearGradient _trainingPanelGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xF2112028), Color(0xF207151B), Color(0xF20A1E25)],
);

BoxDecoration _trainingPanelDecoration({Color? borderColor}) {
  return BoxDecoration(
    gradient: _trainingPanelGradient,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: borderColor ?? _trainingBorder, width: 1.1),
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

class _TrainingPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  const _TrainingPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: _trainingPanelDecoration(borderColor: borderColor),
      child: child,
    );
  }
}

class _TrainingPanelTitle extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;

  const _TrainingPanelTitle({
    required this.icon,
    required this.label,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 20),
        const SizedBox(width: 11),
        Expanded(
          child: _TrainingAutoFitText(
            label,
            alignment: Alignment.centerLeft,
            textAlign: TextAlign.left,
            style: GoogleFonts.inter(
              color: _trainingTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: .4,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _TrainingAutoFitText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Alignment alignment;
  final TextAlign textAlign;

  const _TrainingAutoFitText(
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
        if (!constraints.maxWidth.isFinite) return fitted;
        return SizedBox(width: constraints.maxWidth, child: fitted);
      },
    );
  }
}

class _TrainingHeader extends StatelessWidget {
  final Dog dog;
  final String handlerName;
  final String? handlerPhotoUrl;
  final DateTime? shiftStartTime;

  const _TrainingHeader({
    required this.dog,
    required this.handlerName,
    required this.handlerPhotoUrl,
    required this.shiftStartTime,
  });

  @override
  Widget build(BuildContext context) {
    return _TrainingPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      borderColor: AppTheme.primary.withAlpha(48),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 380;
          final conductorName = _shortConductorName(handlerName);
          return Row(
            children: [
              SizedBox(
                width: compact ? 90 : 102,
                height: compact ? 72 : 78,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      right: 0,
                      top: 4,
                      child: _TrainingAvatar(
                        imageUrl: handlerPhotoUrl,
                        fallbackIcon: Icons.person_rounded,
                        borderColor: _trainingTextSecondary,
                        size: compact ? 60 : 68,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      child: _TrainingAvatar(
                        imageUrl: dog.profileImageUrl,
                        fallbackText: dog.name.isNotEmpty ? dog.name[0] : 'K',
                        borderColor: _trainingTextPrimary,
                        size: compact ? 68 : 76,
                      ),
                    ),
                    Positioned(
                      left: compact ? 56 : 64,
                      bottom: 3,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _trainingGreen,
                          border: Border.all(
                            color: _trainingSurfaceHigh,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 11 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'TREINOS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _TrainingAutoFitText(
                      '${dog.name} • $conductorName',
                      alignment: Alignment.centerLeft,
                      textAlign: TextAlign.left,
                      style: GoogleFonts.inter(
                        fontSize: compact ? 21 : 24,
                        fontWeight: FontWeight.w900,
                        color: _trainingTextPrimary,
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
                            color: _statusColor(dog.status),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _statusColor(dog.status).withAlpha(80),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TrainingAutoFitText(
                            _headerStatusLabel(),
                            alignment: Alignment.centerLeft,
                            textAlign: TextAlign.left,
                            style: GoogleFonts.inter(
                              color: _statusColor(dog.status),
                              fontSize: compact ? 13 : 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
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

  String _headerStatusLabel() {
    final status = dog.status.trim().isEmpty ? 'Ativo' : dog.status;
    final start = shiftStartTime;
    if (start == null) return 'K9 $status';
    final hour = start.hour.toString().padLeft(2, '0');
    final minute = start.minute.toString().padLeft(2, '0');
    return 'K9 $status desde $hour:$minute';
  }

  String _shortConductorName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Condutor';
    final cleaned = trimmed.replaceFirst(
      RegExp(r'^GCM\s+', caseSensitive: false),
      '',
    );
    final pieces = cleaned.split(RegExp(r'\s+'));
    return pieces.length <= 1 ? pieces.first : pieces.last;
  }
}

class _TrainingWeekSummary extends StatelessWidget {
  final TrainingHubData data;

  const _TrainingWeekSummary({required this.data});

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _TrainingMetricData(
        icon: Icons.calendar_month_outlined,
        value: '${data.trainingsThisWeek}',
        label: 'Treinos esta semana',
        color: AppTheme.primary,
      ),
      _TrainingMetricData(
        icon: Icons.shield_outlined,
        value: '${data.specialties.where((item) => item.isActive).length}',
        label: 'Especialidades ativas',
        color: AppTheme.primary,
      ),
      _TrainingMetricData(
        icon: Icons.schedule_rounded,
        value: data.lastTrainingLabel,
        label: 'Último treino',
        color: _trainingTextPrimary,
      ),
      _TrainingMetricData(
        icon: Icons.my_location_rounded,
        value: data.suggestedFocus,
        label: 'Próximo foco sugerido',
        color: _trainingTextPrimary,
      ),
    ];

    return _TrainingPanel(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TrainingPanelTitle(
            icon: Icons.insights_rounded,
            label: 'RESUMO DA SEMANA',
          ),
          const SizedBox(height: 17),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 390) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _TrainingMetric(data: metrics[0])),
                        const _TrainingVerticalDivider(),
                        Expanded(child: _TrainingMetric(data: metrics[1])),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _TrainingMetric(data: metrics[2])),
                        const _TrainingVerticalDivider(),
                        Expanded(child: _TrainingMetric(data: metrics[3])),
                      ],
                    ),
                  ],
                );
              }

              return IntrinsicHeight(
                child: Row(
                  children: [
                    for (int i = 0; i < metrics.length; i++) ...[
                      Expanded(child: _TrainingMetric(data: metrics[i])),
                      if (i < metrics.length - 1)
                        const _TrainingVerticalDivider(),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TrainingMetricData {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _TrainingMetricData({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });
}

class _TrainingMetric extends StatelessWidget {
  final _TrainingMetricData data;

  const _TrainingMetric({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(data.icon, color: AppTheme.primary, size: 28),
        const SizedBox(height: 9),
        _TrainingAutoFitText(
          data.value,
          style: GoogleFonts.inter(
            color: data.color,
            fontSize: 23,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          data.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: _trainingTextSecondary,
            fontSize: 12,
            height: 1.08,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _TrainingVerticalDivider extends StatelessWidget {
  const _TrainingVerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      color: _trainingBorderStrong.withAlpha(72),
    );
  }
}

class _TrainingAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? fallbackText;
  final IconData? fallbackIcon;
  final Color borderColor;
  final double size;

  const _TrainingAvatar({
    required this.imageUrl,
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
        color: _trainingSurfaceHigh,
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: ClipOval(
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, _) => _fallback(),
                errorWidget: (_, _, _) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      color: _trainingSurfaceHigh,
      alignment: Alignment.center,
      child: fallbackText != null
          ? Text(
              fallbackText!,
              style: GoogleFonts.inter(
                color: borderColor,
                fontSize: size * .36,
                fontWeight: FontWeight.w900,
              ),
            )
          : Icon(
              fallbackIcon ?? Icons.person_rounded,
              color: borderColor.withAlpha(190),
              size: size * .42,
            ),
    );
  }
}

Color _statusColor(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.contains('ativo') || normalized.contains('operacional')) {
    return _trainingGreen;
  }
  if (normalized.contains('lic') || normalized.contains('form')) {
    return _trainingYellow;
  }
  if (normalized.contains('aposent') || normalized.contains('inativo')) {
    return _trainingTextMuted;
  }
  return _trainingGreen;
}

IconData _trainingIconFor(String value) {
  final key = normalizeTrainingKey(value);
  if (key.contains('detec') || key.contains('faro')) {
    return Icons.search_rounded;
  }
  if (key.contains('guarda') || key.contains('protec')) {
    return Icons.shield_outlined;
  }
  if (key.contains('busca') || key.contains('captura')) {
    return Icons.pets_rounded;
  }
  if (key.contains('obediencia')) {
    return Icons.sign_language_rounded;
  }
  if (key.contains('condicionamento')) {
    return Icons.fitness_center_rounded;
  }
  if (key.contains('socializacao')) {
    return Icons.groups_rounded;
  }
  return Icons.fitness_center_rounded;
}

Color _trainingColorFor(String value, {String? status}) {
  final normalizedStatus = normalizeTrainingKey(status ?? '');
  if (normalizedStatus.contains('not_started') ||
      normalizedStatus.contains('nao_iniciada')) {
    return _trainingYellow;
  }
  if (normalizedStatus.contains('formation') ||
      normalizedStatus.contains('formacao')) {
    return _trainingYellow;
  }

  final key = normalizeTrainingKey(value);
  if (key.contains('guarda') || key.contains('protec')) return _trainingYellow;
  if (key.contains('busca') || key.contains('captura')) return _trainingGreen;
  return AppTheme.primary;
}
