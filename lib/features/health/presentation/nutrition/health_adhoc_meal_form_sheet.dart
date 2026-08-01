import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/hud_controls.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/meal_occurrence.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_outcome.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_pending_intent.dart';

/// Sheet operacional Health v1 para criação exclusiva de MealLog adhoc (avulso).
class HealthAdhocMealFormSheet extends StatefulWidget {
  const HealthAdhocMealFormSheet({
    super.key,
    required this.dogId,
    required this.dogDisplayName,
    required this.controller,
    required this.onRefreshRequested,
    this.timezone,
    this.clock,
  });

  final String dogId;
  final String dogDisplayName;
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
  MealAcceptance _acceptance = MealAcceptance.unknown;
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
    _consumed = TextEditingController();
    _observations = TextEditingController();

    // Período inicial baseado no horário local se não recuperado de pending intent
    final local = LocalServiceDate.instantInTimezone(_now, timezone: _tz);
    _fedTime = TimeOfDay(hour: local.hour, minute: local.minute);
    if (!same) {
      _period = _suggestPeriod(local.hour);
    }
  }

  MealPeriod _suggestPeriod(int hour) {
    if (hour >= 5 && hour < 12) return MealPeriod.morning;
    if (hour >= 12 && hour < 18) return MealPeriod.afternoon;
    if (hour >= 18 && hour < 22) return MealPeriod.evening;
    if (hour >= 22 || hour < 5) return MealPeriod.night;
    return MealPeriod.extra;
  }

  @override
  void dispose() {
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
                    const Icon(
                      Icons.restaurant_rounded,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'REGISTRAR REFEIÇÃO',
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
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
                HudSelectField<MealPeriod>(
                  label: 'Período',
                  icon: Icons.schedule_rounded,
                  value: _period,
                  items: MealPeriod.values,
                  labelBuilder: (p) => _periodLabel(p),
                  accent: AppTheme.primary,
                  placeholder: 'Selecione',
                  onChanged: _onPeriodChanged,
                ),
                const SizedBox(height: 14),
                _numberField(
                  controller: _offered,
                  label: 'Quantidade oferecida (g)',
                  validator: (raw) {
                    final value = _number(raw);
                    return value == null || value <= 0
                        ? 'Informe uma quantidade maior que zero.'
                        : null;
                  },
                ),
                const SizedBox(height: 14),
                HudSelectField<MealAcceptance>(
                  label: 'Aceitação',
                  icon: Icons.restaurant_rounded,
                  value: _acceptance,
                  items: MealAcceptance.values,
                  labelBuilder: (a) => _acceptanceLabel(a),
                  accent: AppTheme.primary,
                  placeholder: 'Selecione',
                  onChanged: _onAcceptanceChanged,
                ),
                const SizedBox(height: 14),
                _numberField(
                  controller: _consumed,
                  label: 'Quantidade consumida (g) — opcional',
                  enabled: _acceptance != MealAcceptance.refused,
                  validator: _validateConsumed,
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: _submitting ? null : _pickTime,
                  borderRadius: BorderRadius.circular(10),
                  child: InputDecorator(
                    decoration: _inputDecoration('Oferecido às'),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          color: AppTheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
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
                  decoration: _inputDecoration('Observações — opcional'),
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
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.primaryOverlay,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.primaryDivider),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.dogDisplayName,
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.attention.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Registro avulso',
                style: GoogleFonts.inter(
                  color: AppTheme.attention,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Refeição independente de plano nutricional',
          style: GoogleFonts.inter(
            color: AppTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    bool enabled = true,
  }) => TextFormField(
    controller: controller,
    enabled: enabled && !_submitting && !_savedButRefreshFailed,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
    style: GoogleFonts.inter(color: AppTheme.textPrimary),
    decoration: _inputDecoration(label),
    validator: validator,
  );

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: GoogleFonts.inter(color: AppTheme.textSecondary),
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

  String? _validateConsumed(String? raw) {
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
    final consumedGrams = _number(_consumed.text)?.toDouble();

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
    MealPeriod.evening => 'Noite',
    MealPeriod.night => 'Madrugada',
    MealPeriod.extra => 'Extra / Intermediária',
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
      } else if (value == MealAcceptance.unknown) {
        _consumed.clear();
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
