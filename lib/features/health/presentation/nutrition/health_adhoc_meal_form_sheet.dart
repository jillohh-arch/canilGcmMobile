import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/meal_occurrence.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_outcome.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_pending_intent.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/widgets/health_nutrition_context_badge.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/widgets/health_nutrition_dog_avatar.dart';

/// PASS 02B: modo de preenchimento da quantidade consumida na refeição avulsa.
enum _ConsumedMode { all, partial, unmeasured }

/// Sheet operacional Health v1 para criação exclusiva de MealLog adhoc (avulso).
class HealthAdhocMealFormSheet extends StatefulWidget {
  const HealthAdhocMealFormSheet({
    super.key,
    required this.dogId,
    required this.dogDisplayName,
    this.dogPhotoUrl,
    required this.controller,
    required this.onRefreshRequested,
    this.timezone,
    this.clock,
  });

  final String dogId;
  final String dogDisplayName;

  /// PASS 03C: URL de foto já disponível no contexto do app. Ausente → patinha.
  final String? dogPhotoUrl;
  final HealthNutritionMutationController controller;
  final Future<void> Function() onRefreshRequested;
  final String? timezone;
  final DateTime Function()? clock;

  @override
  State<HealthAdhocMealFormSheet> createState() =>
      _HealthAdhocMealFormSheetState();
}

class _HealthAdhocMealFormSheetState extends State<HealthAdhocMealFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _offered;
  late final TextEditingController _consumed;
  late final TextEditingController _observations;
  MealPeriod _period = MealPeriod.morning;
  MealAcceptance _acceptance = MealAcceptance.full;
  _ConsumedMode _consumedMode = _ConsumedMode.all;
  late TimeOfDay _fedTime;
  bool _submitting = false;
  bool _savedButRefreshFailed = false;
  String? _message;

  String get _tz => widget.timezone ?? NutritionPlan.defaultTimezone;
  DateTime get _now => (widget.clock?.call() ?? DateTime.now()).toUtc();

  @override
  void initState() {
    super.initState();
    final pending = widget.controller.pendingIntent;
    final same =
        pending != null &&
        pending.kind == HealthNutritionMutationKind.adhocMeal;
    _offered = TextEditingController();
    _offered.addListener(_onOfferedChanged);
    _consumed = TextEditingController();
    _observations = TextEditingController();

    // Período inicial baseado no horário local se não recuperado de pending intent
    final local = LocalServiceDate.instantInTimezone(_now, timezone: _tz);
    _fedTime = TimeOfDay(hour: local.hour, minute: local.minute);
    if (!same) {
      _period = _suggestPeriod(local.hour);
    }
  }

  void _onOfferedChanged() {
    if (_consumedMode == _ConsumedMode.all && _acceptance != MealAcceptance.refused) {
      _consumed.text = _offered.text;
    }
  }

  MealPeriod _suggestPeriod(int hour) {
    if (hour >= 5 && hour < 12) return MealPeriod.morning;
    if (hour >= 12 && hour < 18) return MealPeriod.afternoon;
    if (hour >= 18 || hour < 5) return MealPeriod.night;
    return MealPeriod.extra;
  }

  @override
  void dispose() {
    _offered.removeListener(_onOfferedChanged);
    _offered.dispose();
    _consumed.dispose();
    _observations.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + keyboard),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.restaurant_rounded,
                        color: AppTheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'REGISTRAR REFEIÇÃO',
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Registro independente do plano alimentar',
                            style: GoogleFonts.inter(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: AppTheme.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _contextCard(),
                const SizedBox(height: 16),
                _periodChips(),
                const SizedBox(height: 14),
                _numberField(
                  controller: _offered,
                  label: 'Quantidade oferecida (g)',
                  prefixIcon: Icons.scale_rounded,
                  validator: (raw) {
                    final value = _number(raw);
                    return value == null || value <= 0
                        ? 'Informe uma quantidade maior que zero.'
                        : null;
                  },
                ),
                const SizedBox(height: 14),
                _acceptanceChips(),
                const SizedBox(height: 14),
                _consumedChips(),
                const SizedBox(height: 14),
                InkWell(
                  onTap: _submitting ? null : _pickTime,
                  borderRadius: BorderRadius.circular(10),
                  child: InputDecorator(
                    decoration: _inputDecoration('Oferecido às', prefixIcon: Icons.schedule_rounded),
                    child: Row(
                      children: [
                        Text(
                          _fedTime.format(context),
                          style: GoogleFonts.inter(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            _tz,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: GoogleFonts.inter(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _observations,
                  enabled: !_submitting && !_savedButRefreshFailed,
                  maxLines: 3,
                  maxLength: 500,
                  style: GoogleFonts.inter(color: AppTheme.textPrimary),
                  decoration: _inputDecoration(
                    'Observações — opcional',
                    prefixIcon: Icons.chat_bubble_outline_rounded,
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  _messagePanel(),
                ],
                const SizedBox(height: 18),
                if (_savedButRefreshFailed)
                  OutlinedButton.icon(
                    onPressed: _refreshAgain,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Atualizar novamente'),
                  )
                else
                  SizedBox(
                    height: 50,
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: AppTheme.background,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: _submitting
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.background,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text('Registrando refeição…'),
                                  ),
                                ),
                              ],
                            )
                          : const Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('REGISTRAR REFEIÇÃO AVULSA'),
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _contextCard() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.surfacePanel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.outline),
    ),
    child: Row(
      children: [
        HealthNutritionDogAvatar(
          key: const ValueKey('adhoc-meal-dog-avatar'),
          dogDisplayName: widget.dogDisplayName,
          photoUrl: widget.dogPhotoUrl,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // PASS 03D: nome à esquerda, badge de classificação à direita, na
              // MESMA linha. `Flexible` + ellipsis nos dois lados garante que
              // nome longo e badge nunca colidam nem estourem em 320px.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      widget.dogDisplayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: HealthNutritionContextBadge(
                      key: ValueKey('adhoc-meal-context-badge'),
                      label: 'Registro avulso',
                      accent: AppTheme.attention,
                      backgroundAlpha: 0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Refeição independente de plano nutricional',
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  IconData _periodIcon(MealPeriod p) => switch (p) {
    MealPeriod.morning => Icons.wb_twilight_rounded,
    MealPeriod.afternoon => Icons.wb_sunny_rounded,
    MealPeriod.evening || MealPeriod.night => Icons.nightlight_round,
    MealPeriod.extra => Icons.add_circle_outline_rounded,
  };

  Color _periodColor(MealPeriod p) => switch (p) {
    MealPeriod.morning => const Color(0xFFFFB74D),
    MealPeriod.afternoon => const Color(0xFFFFA726),
    MealPeriod.evening || MealPeriod.night => const Color(0xFFBA68C8),
    MealPeriod.extra => AppTheme.primary,
  };

  Widget _periodCard(MealPeriod option) {
    final isSelected = _isPeriodSelected(option);
    final color = _periodColor(option);
    return InkWell(
      key: Key('adhoc-meal-period-${option.wireName}'),
      onTap: _submitting ? null : () => _onPeriodChanged(option),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.14) : AppTheme.surfacePanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : AppTheme.outline,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _periodIcon(option),
              size: 24,
              color: isSelected ? color : AppTheme.textMuted,
            ),
            const SizedBox(height: 6),
            Text(
              _periodLabel(option),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PERÍODO DA REFEIÇÃO',
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _periodCard(MealPeriod.morning)),
            const SizedBox(width: 10),
            Expanded(child: _periodCard(MealPeriod.afternoon)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _periodCard(MealPeriod.night)),
            const SizedBox(width: 10),
            Expanded(child: _periodCard(MealPeriod.extra)),
          ],
        ),
      ],
    );
  }

  bool _isPeriodSelected(MealPeriod option) {
    if (_period == option) return true;
    if (option == MealPeriod.night && _period == MealPeriod.evening) return true;
    return false;
  }

  /// PASS 03C: label do chip com o indicador de seleção como SUFIXO.
  ///
  /// Regra visual da pass: o ícone semântico vive no slot `avatar` (à esquerda)
  /// e o check vive depois da label (à direita). Nunca no mesmo slot, nunca em
  /// `Stack`. Só o chip selecionado renderiza o check.
  Widget _chipLabel(
    String text, {
    required bool selected,
    required Color accent,
  }) {
    if (!selected) return Text(text);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(text)),
        const SizedBox(width: 6),
        Icon(Icons.check_rounded, size: 15, color: accent),
      ],
    );
  }

  IconData _acceptanceIcon(MealAcceptance a) => switch (a) {
    MealAcceptance.full => Icons.sentiment_satisfied_alt_rounded,
    MealAcceptance.partial => Icons.sentiment_neutral_rounded,
    MealAcceptance.refused => Icons.sentiment_dissatisfied_rounded,
    MealAcceptance.unknown => Icons.help_outline_rounded,
  };

  Color _acceptanceColor(MealAcceptance a) => switch (a) {
    MealAcceptance.full => AppTheme.success,
    MealAcceptance.partial => AppTheme.warningAccent,
    MealAcceptance.refused => AppTheme.error,
    MealAcceptance.unknown => AppTheme.textMuted,
  };

  Widget _acceptanceChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ACEITAÇÃO',
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in MealAcceptance.values)
              ChoiceChip(
                key: Key('adhoc-meal-acceptance-${option.wireName}'),
                // PASS 03C: o checkmark padrão do ChoiceChip é desenhado no
                // MESMO slot do `avatar`, sobrepondo o ícone semântico. Ele é
                // desligado aqui e reposicionado como sufixo depois da label.
                showCheckmark: false,
                avatar: Icon(
                  _acceptanceIcon(option),
                  size: 18,
                  color: _acceptance == option
                      ? _acceptanceColor(option)
                      : AppTheme.textMuted,
                ),
                label: _chipLabel(
                  _acceptanceLabel(option),
                  selected: _acceptance == option,
                  accent: _acceptanceColor(option),
                ),
                selected: _acceptance == option,
                onSelected: _submitting
                    ? null
                    : (_) => _onAcceptanceChanged(option),
                selectedColor: _acceptanceColor(option).withValues(alpha: 0.16),
                backgroundColor: AppTheme.surfacePanel,
                side: BorderSide(
                  color: _acceptance == option
                      ? _acceptanceColor(option)
                      : AppTheme.outline,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                labelStyle: GoogleFonts.inter(
                  color: _acceptance == option
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _consumedChips() {
    final refused = _acceptance == MealAcceptance.refused;

    Widget chip(
      String label,
      IconData icon,
      Color accent,
      bool selected,
      VoidCallback onTap,
    ) {
      return ChoiceChip(
        key: Key('adhoc-meal-consumed-$label'),
        // PASS 03C: ver nota em `_acceptanceChips` — checkmark vai para sufixo.
        showCheckmark: false,
        avatar: Icon(
          icon,
          size: 18,
          // PASS 03D: cor semântica só no estado selecionado; não selecionado
          // permanece discreto como antes.
          color: selected ? accent : AppTheme.textMuted,
        ),
        label: _chipLabel(label, selected: selected, accent: accent),
        selected: selected,
        onSelected: _submitting || refused ? null : (_) => onTap(),
        selectedColor: accent.withValues(alpha: 0.16),
        backgroundColor: AppTheme.surfacePanel,
        side: BorderSide(
          color: selected ? accent : AppTheme.outline,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        labelStyle: GoogleFonts.inter(
          color: selected ? accent : AppTheme.textSecondary,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'QUANTIDADE CONSUMIDA',
          style: GoogleFonts.inter(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            chip(
              'Tudo',
              Icons.restaurant_rounded,
              // PASS 03D: mesma família de Aceitação — verde = completo.
              AppTheme.success,
              _consumedMode == _ConsumedMode.all,
              () {
                setState(() {
                  _consumedMode = _ConsumedMode.all;
                  if (_offered.text.isNotEmpty) {
                    _consumed.text = _offered.text;
                  }
                });
              },
            ),
            chip(
              'Parcial',
              // PASS 03C: `pie_chart_outline` lia como gráfico/estatística.
              // `rice_bowl` = tigela/porção, alinhado a "comeu parte do que
              // foi oferecido" e distinto do rosto neutro de Aceitação parcial.
              Icons.rice_bowl_rounded,
              // PASS 03D: âmbar = parcial, igual a "Aceitação parcial".
              AppTheme.warningAccent,
              _consumedMode == _ConsumedMode.partial,
              () {
                setState(() {
                  final prevMode = _consumedMode;
                  _consumedMode = _ConsumedMode.partial;
                  final off = _number(_offered.text);
                  final con = _number(_consumed.text);
                  if (prevMode == _ConsumedMode.all || (off != null && con != null && off == con)) {
                    _consumed.clear();
                  }
                });
              },
            ),
            chip(
              'Não medido',
              Icons.remove_circle_outline_rounded,
              // PASS 03D: NEUTRO, nunca vermelho. Ausência de mensuração não é
              // recusa, erro nem problema clínico.
              AppTheme.textMuted,
              _consumedMode == _ConsumedMode.unmeasured,
              () {
                setState(() {
                  _consumedMode = _ConsumedMode.unmeasured;
                  _consumed.clear();
                });
              },
            ),
          ],
        ),
        if (_consumedMode == _ConsumedMode.partial && !refused) ...[
          const SizedBox(height: 10),
          _numberField(
            key: const ValueKey('consumed-field'),
            controller: _consumed,
            label: 'Quantidade consumida (g) — opcional',
            prefixIcon: Icons.scale_rounded,
            enabled: !refused,
            validator: _validateConsumed,
          ),
        ],
      ],
    );
  }

  Widget _numberField({
    Key? key,
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    IconData? prefixIcon,
    bool enabled = true,
  }) => TextFormField(
    key: key,
    controller: controller,
    enabled: enabled && !_submitting && !_savedButRefreshFailed,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
    style: GoogleFonts.inter(color: AppTheme.textPrimary),
    decoration: _inputDecoration(label, prefixIcon: prefixIcon),
    validator: validator,
  );

  InputDecoration _inputDecoration(String label, {IconData? prefixIcon}) => InputDecoration(
    labelText: label,
    labelStyle: GoogleFonts.inter(color: AppTheme.textSecondary),
    prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: AppTheme.primary, size: 20) : null,
    filled: true,
    fillColor: AppTheme.surfacePanel,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppTheme.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppTheme.error),
    ),
  );

  Widget _messagePanel() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: (_savedButRefreshFailed ? AppTheme.warning : AppTheme.error)
          .withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      _message!,
      style: GoogleFonts.inter(
        color: _savedButRefreshFailed ? AppTheme.warning : AppTheme.error,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  double? get _calculatedConsumedGrams {
    if (_acceptance == MealAcceptance.refused) return 0.0;
    return switch (_consumedMode) {
      _ConsumedMode.all => _number(_offered.text)?.toDouble(),
      _ConsumedMode.unmeasured => null,
      _ConsumedMode.partial => _number(_consumed.text)?.toDouble(),
    };
  }

  String? _validateConsumed(String? raw) {
    if (_consumedMode != _ConsumedMode.partial) return null;
    final offered = _number(_offered.text);
    final consumed = _number(raw);
    if (raw != null && raw.trim().isNotEmpty && consumed == null) {
      return 'Quantidade consumida inválida.';
    }
    if (consumed != null &&
        (consumed < 0 || offered == null || consumed > offered)) {
      return 'O consumo deve ficar entre 0 e a quantidade oferecida.';
    }
    if (_acceptance == MealAcceptance.refused && consumed != 0) {
      return 'Recusa deve registrar 0 g consumidos.';
    }
    if (_acceptance == MealAcceptance.full &&
        consumed != null &&
        offered != null &&
        consumed != offered) {
      return 'Quando medido, o consumo total deve ser igual ao oferecido.';
    }
    if (_acceptance == MealAcceptance.partial &&
        consumed != null &&
        offered != null &&
        (consumed <= 0 || consumed >= offered)) {
      return 'Consumo parcial medido deve ser maior que 0 e menor que o oferecido.';
    }
    return null;
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _fedTime,
    );
    if (selected != null && mounted) setState(() => _fedTime = selected);
  }

  num? _number(String? raw) {
    if (raw == null) return null;
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }

  DateTime _fedAtUtc() {
    final localNow = LocalServiceDate.instantInTimezone(_now, timezone: _tz);
    return LocalServiceDate.instantFromLocal(
      year: localNow.year,
      month: localNow.month,
      day: localNow.day,
      hour: _fedTime.hour,
      minute: _fedTime.minute,
      timezone: _tz,
    );
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final fedAt = _fedAtUtc();
    if (fedAt.isAfter(_now)) {
      setState(
        () => _message = 'O horário da refeição não pode estar no futuro.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _message = null;
    });

    final offeredGrams = _number(_offered.text)!.toDouble();
    final consumedGrams = _calculatedConsumedGrams;

    final outcome = await widget.controller.createAdhocMeal(
      dogId: widget.dogId,
      period: MealPeriodWire.parseCanonical(_period.wireName),
      offeredGrams: offeredGrams,
      acceptance: MealAcceptanceWire.parse(_acceptance.wireName),
      fedAt: fedAt,
      consumedGrams: consumedGrams,
      observations: _observations.text.trim().isEmpty
          ? null
          : _observations.text.trim(),
      attachmentRefs: const [],
    );

    if (!mounted) return;
    setState(() => _submitting = false);
    switch (outcome) {
      case HealthNutritionMutationUiSuccess(:final refreshFailed):
        if (!refreshFailed) {
          Navigator.pop(context, outcome);
          return;
        }
        setState(() {
          _savedButRefreshFailed = true;
          _message =
              'Refeição registrada, mas não foi possível atualizar a tela.';
        });
      case HealthNutritionMutationUiFailure(:final failure):
        if (!mounted) return;
        setState(() => _message = _failureMessage(failure));
      case HealthNutritionMutationUiBlocked():
        break;
    }
  }

  Future<void> _refreshAgain() async {
    setState(() => _submitting = true);
    try {
      await widget.onRefreshRequested();
      if (!mounted) return;
      Navigator.pop(
        context,
        const HealthNutritionMutationUiSuccess(
          successMessage: 'Registro salvo com sucesso',
          refreshFailed: false,
          dogId: '',
          entityId: '',
          revision: 1,
          wasNoOp: false,
          entityKind: HealthNutritionMutationEntityKind.mealLog,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _message = 'Falha ao atualizar a tela. Tente novamente.';
      });
    }
  }

  String _failureMessage(HealthNutritionMutationFailure failure) {
    return failure.message;
  }

  String _periodLabel(MealPeriod p) => switch (p) {
    MealPeriod.morning => 'Manhã',
    MealPeriod.afternoon => 'Tarde',
    MealPeriod.evening || MealPeriod.night => 'Noite',
    MealPeriod.extra => 'Extra',
  };

  void _onPeriodChanged(MealPeriod? value) {
    if (value == null || _submitting) return;
    setState(() => _period = value);
  }

  void _onAcceptanceChanged(MealAcceptance? value) {
    if (value == null || _submitting) return;
    setState(() {
      _acceptance = value;
      if (value == MealAcceptance.refused) {
        _consumed.text = '0';
        _consumedMode = _ConsumedMode.all;
      } else if (value == MealAcceptance.unknown) {
        _consumed.clear();
        _consumedMode = _ConsumedMode.unmeasured;
      } else if (value == MealAcceptance.full) {
        if (_consumedMode == _ConsumedMode.all) {
          _consumed.text = _offered.text;
        }
      }
    });
  }

  String _acceptanceLabel(MealAcceptance a) => switch (a) {
    MealAcceptance.full => 'Aceitou tudo',
    MealAcceptance.partial => 'Aceitação parcial',
    MealAcceptance.refused => 'Recusou',
    MealAcceptance.unknown => 'Não informado',
  };
}
