import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/hud_controls.dart';
import 'package:canil_gcm/features/health/domain/meal_occurrence.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan_regimen.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_outcome.dart';

/// Sheet operacional Health v1 para criação de SupplementLog.
///
/// Suporta dois modos:
/// - **Prescrito**: vinculado a um `NutritionPlanSupplementRegimen` (plano ativo).
///   Nome/dose/unit pré-preenchidos a partir do regimen, bloqueados.
/// - **Avulso**: administração livre, todos campos editáveis.
///
/// NÃO cria semântica pending/completed.
/// NÃO marca regimen como concluído.
/// NÃO inferir que uma administração completou uma frequência prescrita.
class HealthSupplementFormSheet extends StatefulWidget {
  const HealthSupplementFormSheet({
    super.key,
    required this.dogId,
    required this.dogDisplayName,
    required this.controller,
    required this.onRefreshRequested,
    this.timezone,
    this.clock,
    this.activePlan,
    this.defaultRegimen,
  });

  final String dogId;
  final String dogDisplayName;
  final HealthNutritionMutationController controller;
  final Future<void> Function() onRefreshRequested;
  final String? timezone;
  final DateTime Function()? clock;

  /// Plano ativo com regimens disponíveis (pode ser null).
  final NutritionActiveCanonicalPlan? activePlan;

  /// Regimen pré-selecionado (opcional).
  final NutritionPlanSupplementRegimen? defaultRegimen;

  @override
  State<HealthSupplementFormSheet> createState() =>
      _HealthSupplementFormSheetState();
}

class _HealthSupplementFormSheetState extends State<HealthSupplementFormSheet> {
  final _formKey = GlobalKey<FormState>();

  // Modo: true = prescrito (vinculado a regimen), false = avulso.
  bool _isPrescribed = false;

  // Regimen selecionado (modo prescrito).
  NutritionPlanSupplementRegimen? _selectedRegimen;

  // Campos do formulário.
  late final TextEditingController _nameController;
  late final TextEditingController _doseController;
  late final TextEditingController _notesController;
  late final TextEditingController _batchController;

  SupplementDoseUnit _unit = SupplementDoseUnit.tablet;
  late TimeOfDay _adminTime;

  bool _submitting = false;
  bool _savedButRefreshFailed = false;
  String? _message;

  String get _tz => widget.timezone ?? NutritionPlan.defaultTimezone;
  DateTime get _now => (widget.clock?.call() ?? DateTime.now()).toUtc();

  List<NutritionPlanSupplementRegimen> get _availableRegimens =>
      widget.activePlan?.plan.supplements ?? [];

  bool get _hasPrescribedMode => _availableRegimens.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _selectedRegimen = widget.defaultRegimen;
    _isPrescribed = _selectedRegimen != null;

    _nameController = TextEditingController();
    _doseController = TextEditingController();
    _notesController = TextEditingController();
    _batchController = TextEditingController();

    final local = LocalServiceDate.instantInTimezone(_now, timezone: _tz);
    _adminTime = TimeOfDay(hour: local.hour, minute: local.minute);

    if (_selectedRegimen != null) {
      _applyRegimen(_selectedRegimen!);
    }
  }

  void _applyRegimen(NutritionPlanSupplementRegimen regimen) {
    _nameController.text = regimen.name;
    _doseController.text = regimen.dose.toString();
    _unit = regimen.unit;
  }

  void _onUnitChanged(SupplementDoseUnit? value) {
    if (value == null || _submitting || _isPrescribed) return;
    setState(() => _unit = value);
  }

  void _onRegimenChanged(NutritionPlanSupplementRegimen? value) {
    if (value == null || _submitting) return;
    setState(() {
      _selectedRegimen = value;
      _applyRegimen(value);
    });
  }

  String _regimenLabel(NutritionPlanSupplementRegimen r) =>
      '${r.name} · ${r.dose} ${r.unit.displayLabel}';

  @override
  void dispose() {
    _nameController.dispose();
    _doseController.dispose();
    _notesController.dispose();
    _batchController.dispose();
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
                      Icons.medication_rounded,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'REGISTRAR SUPLEMENTO',
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
                      onPressed:
                          _submitting ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: AppTheme.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _contextCard(),
                const SizedBox(height: 16),

                // Seletor de modo (apenas se há regimens disponíveis).
                if (_hasPrescribedMode) ...[
                  _modeSelector(),
                  const SizedBox(height: 16),
                ],

                // Seleção de regimen (modo prescrito).
                if (_isPrescribed) ...[
                  _regimenDropdown(),
                  const SizedBox(height: 14),
                ],

                // Nome do suplemento.
                _textField(
                  controller: _nameController,
                  label: 'Nome do suplemento',
                  enabled: !_isPrescribed,
                  validator: (raw) {
                    if ((raw?.trim().length ?? 0) == 0) {
                      return 'Informe o nome do suplemento.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Dose.
                _numberField(
                  controller: _doseController,
                  label: 'Dose',
                  enabled: !_isPrescribed,
                  validator: (raw) {
                    final value = _parseNumber(raw);
                    if (value == null || value <= 0) {
                      return 'Informe uma dose maior que zero.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Unidade.
                HudSelectField<SupplementDoseUnit>(
                  label: 'Unidade',
                  icon: Icons.medical_services_rounded,
                  value: _unit,
                  items: SupplementDoseUnit.values,
                  labelBuilder: _unitLabel,
                  accent: AppTheme.primary,
                  placeholder: 'Selecione',
                  onChanged: _onUnitChanged,
                ),
                const SizedBox(height: 14),

                // Horário de administração.
                InkWell(
                  onTap: _submitting ? null : _pickTime,
                  borderRadius: BorderRadius.circular(10),
                  child: InputDecorator(
                    decoration: _inputDecoration('Horário da administração'),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          color: AppTheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _adminTime.format(context),
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

                // Batch number (opcional).
                _textField(
                  controller: _batchController,
                  label: 'Número do lote — opcional',
                  enabled: !_submitting && !_savedButRefreshFailed,
                ),
                const SizedBox(height: 14),

                // Notes (opcional).
                TextFormField(
                  controller: _notesController,
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
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.background,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _isPrescribed
                                          ? 'Registrando administração do plano…'
                                          : 'Registrando suplemento…',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _isPrescribed
                                      ? 'REGISTRAR ADMINISTRAÇÃO DO PLANO'
                                      : 'REGISTRAR SUPLEMENTO AVULSO',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
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

  Widget _contextCard() {
    final regimen = _selectedRegimen;
    return Container(
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
                  color: _isPrescribed
                      ? AppTheme.success.withValues(alpha: 0.2)
                      : AppTheme.attention.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _isPrescribed ? 'Do plano' : 'Avulso',
                  style: GoogleFonts.inter(
                    color: _isPrescribed ? AppTheme.success : AppTheme.attention,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _isPrescribed
                ? 'Administração vinculada ao plano nutricional'
                : 'Administração independente de plano nutricional',
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          if (regimen != null) ...[
            const SizedBox(height: 4),
            Text(
              'Regime: ${regimen.name} · ${regimen.dose} ${regimen.unit.displayLabel}',
              style: GoogleFonts.inter(
                color: AppTheme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _modeSelector() {
    return Row(
      children: [
        Expanded(
          child: _ModeButton(
            label: 'Do plano',
            selected: _isPrescribed,
            enabled: !_submitting,
            onPressed: () => setState(() => _isPrescribed = true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ModeButton(
            label: 'Avulso',
            selected: !_isPrescribed,
            enabled: !_submitting,
            onPressed: () {
              setState(() {
                _isPrescribed = false;
                _selectedRegimen = null;
                _nameController.clear();
                _doseController.clear();
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _regimenDropdown() {
    return HudSelectField<NutritionPlanSupplementRegimen>(
      label: 'Suplemento do plano',
      icon: Icons.list_alt_rounded,
      value: _selectedRegimen,
      items: _availableRegimens,
      labelBuilder: _regimenLabel,
      accent: AppTheme.primary,
      placeholder: 'Selecione',
      onChanged: _onRegimenChanged,
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    bool enabled = true,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        enabled: enabled && !_submitting && !_savedButRefreshFailed,
        style: GoogleFonts.inter(color: AppTheme.textPrimary),
        decoration: _inputDecoration(label),
        validator: validator,
      );

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    bool enabled = true,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        enabled: enabled && !_submitting && !_savedButRefreshFailed,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))
        ],
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

  String _unitLabel(SupplementDoseUnit unit) => switch (unit) {
        SupplementDoseUnit.mg => 'mg (miligrama)',
        SupplementDoseUnit.g => 'g ( grama)',
        SupplementDoseUnit.ml => 'ml (mililitro)',
        SupplementDoseUnit.scoop => 'Scoop / medida do dosador',
        SupplementDoseUnit.tablet => 'comprimido',
        SupplementDoseUnit.drop => 'gota',
        SupplementDoseUnit.other => 'outra',
      };

  num? _parseNumber(String? raw) {
    if (raw == null) return null;
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _adminTime,
    );
    if (selected != null && mounted) setState(() => _adminTime = selected);
  }

  DateTime _adminAtUtc() {
    final localNow = LocalServiceDate.instantInTimezone(_now, timezone: _tz);
    return LocalServiceDate.instantFromLocal(
      year: localNow.year,
      month: localNow.month,
      day: localNow.day,
      hour: _adminTime.hour,
      minute: _adminTime.minute,
      timezone: _tz,
    );
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;

    final adminAt = _adminAtUtc();
    if (adminAt.isAfter(_now)) {
      setState(
        () => _message =
            'O horário da administração não pode estar no futuro.',
      );
      return;
    }

    final dose = _parseNumber(_doseController.text)?.toDouble();
    if (dose == null || dose <= 0) {
      setState(() => _message = 'Dose inválida.');
      return;
    }

    setState(() {
      _submitting = true;
      _message = null;
    });

    // Preparar vínculos.
    String? nutritionPlanId;
    String? supplementRegimenId;

    if (_isPrescribed && _selectedRegimen != null) {
      nutritionPlanId = widget.activePlan!.plan.id;
      supplementRegimenId = _selectedRegimen!.id;
    }

    final outcome = await widget.controller.createSupplement(
      dogId: widget.dogId,
      supplementName: _nameController.text.trim(),
      dose: dose,
      unit: SupplementDoseUnit.parse(_unit.wireName),
      administeredAt: adminAt,
      nutritionPlanId: nutritionPlanId,
      supplementRegimenId: supplementRegimenId,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      batchNumber: _batchController.text.trim().isEmpty
          ? null
          : _batchController.text.trim(),
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
              'Suplemento registrado, mas não foi possível atualizar a tela.';
        });

      case HealthNutritionMutationUiFailure(:final failure):
        if (!mounted) return;
        setState(() => _message = failure.message);

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
          entityKind: HealthNutritionMutationEntityKind.supplementLog,
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
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  const _ModeButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primary.withValues(alpha: 0.15)
                    : AppTheme.surfacePanel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? AppTheme.primary : AppTheme.outline,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: enabled
                      ? (selected ? AppTheme.primary : AppTheme.textSecondary)
                      : AppTheme.textMuted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}