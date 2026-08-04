import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_provider.dart';
import 'package:canil_gcm/core/services/authoritative_time/firebase_functions_authoritative_time_gateway.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/data/weight/firebase_functions_health_weight_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_weight_mutation_gateway.dart';
import 'package:canil_gcm/features/health/presentation/weight/health_weight_controller.dart';

Future<bool?> showHealthWeightFormSheet({
  required BuildContext context,
  required Dog dog,
  HealthWeightController? controller,
  Future<void> Function()? onRefreshAfterSuccess,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    backgroundColor: AppTheme.transparent,
    builder: (_) => HealthWeightFormSheet(
      dog: dog,
      controller: controller,
      onRefreshAfterSuccess: onRefreshAfterSuccess,
    ),
  );
}

class HealthWeightFormSheet extends StatefulWidget {
  const HealthWeightFormSheet({
    super.key,
    required this.dog,
    this.controller,
    this.onRefreshAfterSuccess,
  });

  final Dog dog;
  final HealthWeightController? controller;
  final Future<void> Function()? onRefreshAfterSuccess;

  @override
  State<HealthWeightFormSheet> createState() => _HealthWeightFormSheetState();
}

class _HealthWeightFormSheetState extends State<HealthWeightFormSheet> {
  final _notesController = TextEditingController();
  late final TextEditingController _weightController;
  late final HealthWeightController _controller;
  late final bool _ownsController;
  HealthWeightContext? _context;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController(
      text: widget.dog.weight?.toStringAsFixed(1).replaceAll('.', ',') ?? '',
    );
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        HealthWeightController(
          gateway: FirebaseFunctionsHealthWeightMutationGateway(),
          authoritativeTimeProvider: AuthoritativeTimeProvider(
            gateway: FirebaseFunctionsAuthoritativeTimeGateway(),
          ),
          onRefreshAfterSuccess: widget.onRefreshAfterSuccess,
        );
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.discardOperation();
      _controller.dispose();
    }
    _weightController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double? _parsedWeight() {
    return double.tryParse(_weightController.text.trim().replaceAll(',', '.'));
  }

  void _step(int deltaTenths) {
    final current = _parsedWeight() ?? 0;
    final tenths = (current * 10).round() + deltaTenths;
    final next = tenths.clamp(1, 1000) / 10;
    _weightController.text = next.toStringAsFixed(1).replaceAll('.', ',');
    setState(() => _validationMessage = null);
  }

  bool get _canDecrement {
    final weight = _parsedWeight();
    return !_controller.isSubmitting && weight != null && weight > 0.1;
  }

  bool get _canIncrement {
    final weight = _parsedWeight();
    return !_controller.isSubmitting && (weight == null || weight < 100);
  }

  String get _summaryWeight {
    final raw = _weightController.text.trim();
    final weight = _parsedWeight();
    if (raw.isEmpty || weight == null || !weight.isFinite) return '—';
    return raw.replaceAll('.', ',');
  }

  void _cancel() {
    if (_controller.isSubmitting) return;
    _controller.discardOperation();
    Navigator.of(context).pop(false);
  }

  Future<void> _submit() async {
    if (_controller.isSubmitting) return;
    final weight = _parsedWeight();
    if (weight == null || !weight.isFinite || weight <= 0 || weight > 100) {
      setState(() {
        _validationMessage =
            'Informe um peso maior que 0 e menor ou igual a 100 kg.';
      });
      return;
    }
    setState(() => _validationMessage = null);
    final outcome = await _controller.submit(
      dogId: widget.dog.id,
      weightKg: weight,
      context: _context,
      notes: _notesController.text,
    );
    if (!mounted) return;
    switch (outcome) {
      case HealthWeightSubmissionSuccess():
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(true);
      case HealthWeightSubmissionFailure(:final failure):
        setState(() => _validationMessage = failure.message);
      case HealthWeightSubmissionBlocked():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope<bool>(
      canPop: !_controller.isSubmitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _controller.discardOperation();
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: 0.94,
              child: Material(
                key: const Key('health-weight-sheet'),
                clipBehavior: Clip.antiAlias,
                color: AppTheme.surfaceSheet,
                shape: const RoundedRectangleBorder(
                  side: BorderSide(color: AppTheme.primaryChipBorder),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(),
                          const SizedBox(height: 14),
                          _dogIdentity(),
                          const SizedBox(height: 14),
                          _section(
                            index: '1',
                            title: 'NOVA PESAGEM',
                            child: _weightEditor(),
                          ),
                          const SizedBox(height: 12),
                          _section(
                            index: '2',
                            title: 'CONTEXTO — OPCIONAL',
                            child: _contextSelector(),
                          ),
                          const SizedBox(height: 12),
                          _section(
                            index: '3',
                            title: 'OBSERVAÇÕES — OPCIONAL',
                            child: _notesField(),
                          ),
                          if (_validationMessage != null) ...[
                            const SizedBox(height: 12),
                            _errorPanel(),
                          ],
                          const SizedBox(height: 14),
                          _actionSummary(),
                          const SizedBox(height: 12),
                          _primaryAction(context),
                          const SizedBox(height: 4),
                          Semantics(
                            button: true,
                            label: 'Cancelar registro de pesagem',
                            child: TextButton(
                              key: const Key('health-weight-cancel'),
                              onPressed: _controller.isSubmitting
                                  ? null
                                  : _cancel,
                              child: const Text('Cancelar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primaryChipBackground,
            border: Border.all(color: AppTheme.primaryChipBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.monitor_weight_outlined,
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'REGISTRAR PESAGEM',
                key: Key('health-weight-title'),
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Avaliação física do K9',
                key: Key('health-weight-subtitle'),
                style: TextStyle(
                  color: AppTheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Semantics(
          button: true,
          label: 'Fechar registro de pesagem',
          child: IconButton(
            key: const Key('health-weight-close'),
            tooltip: 'Fechar',
            onPressed: _controller.isSubmitting ? null : _cancel,
            icon: const Icon(Icons.close_rounded),
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _dogIdentity() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSelectionLabel =
            constraints.maxWidth >= 360 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.2;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surfacePanelStrong,
            border: Border.all(color: AppTheme.outlineVariant),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.profileChip,
                  border: Border.all(color: AppTheme.primaryChipBorder),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.pets_rounded,
                  color: AppTheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.dog.name,
                      key: const Key('health-weight-dog-name'),
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (widget.dog.breed.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.dog.breed.trim(),
                        key: const Key('health-weight-dog-breed'),
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showSelectionLabel)
                const Text(
                  'K9 SELECIONADO',
                  style: TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _section({
    required String index,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanelSoft,
        border: Border.all(color: AppTheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$index. $title',
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _weightEditor() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final field = TextField(
          key: const Key('health-weight-input'),
          controller: _weightController,
          enabled: !_controller.isSubmitting,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              RegExp(r'^-?\d{0,3}([\.,]\d*)?$'),
            ),
          ],
          onChanged: (_) => setState(() => _validationMessage = null),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 38,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
          decoration: const InputDecoration(
            labelText: 'Peso',
            hintText: '0,0',
            suffixText: 'kg',
            suffixStyle: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _stepButton(decrement: true),
            const SizedBox(width: 10),
            _stepButton(decrement: false),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact) ...[
              field,
              const SizedBox(height: 12),
              Align(alignment: Alignment.center, child: controls),
            ] else
              Row(
                children: [
                  Expanded(child: field),
                  const SizedBox(width: 14),
                  controls,
                ],
              ),
            const SizedBox(height: 8),
            const Text(
              'Ajuste em passos de 0,1 kg ou digite o valor aferido.',
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
            ),
          ],
        );
      },
    );
  }

  Widget _stepButton({required bool decrement}) {
    final enabled = decrement ? _canDecrement : _canIncrement;
    final label = decrement
        ? 'Diminuir peso em 0,1 kg'
        : 'Aumentar peso em 0,1 kg';
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Tooltip(
        message: label,
        child: SizedBox.square(
          dimension: 56,
          child: OutlinedButton(
            key: Key(
              decrement ? 'health-weight-decrement' : 'health-weight-increment',
            ),
            onPressed: enabled ? () => _step(decrement ? -1 : 1) : null,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: AppTheme.primary,
              side: BorderSide(
                color: enabled ? AppTheme.primary : AppTheme.outline,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Icon(decrement ? Icons.remove_rounded : Icons.add_rounded),
          ),
        ),
      ),
    );
  }

  Widget _contextSelector() {
    final values = <HealthWeightContext?>[null, ...HealthWeightContext.values];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values
          .map((value) {
            final label = value?.label ?? 'Não informado';
            return ChoiceChip(
              key: Key('health-weight-context-${value?.wireValue ?? 'none'}'),
              label: Text(label),
              selected: _context == value,
              onSelected: _controller.isSubmitting
                  ? null
                  : (_) => setState(() {
                      _context = value;
                      _validationMessage = null;
                    }),
              selectedColor: AppTheme.primaryChipBackground,
              side: BorderSide(
                color: _context == value
                    ? AppTheme.primary
                    : AppTheme.outlineVariant,
              ),
              labelStyle: TextStyle(
                color: _context == value
                    ? AppTheme.primary
                    : AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _notesField() {
    return TextField(
      key: const Key('health-weight-notes'),
      controller: _notesController,
      enabled: !_controller.isSubmitting,
      minLines: 3,
      maxLines: 5,
      maxLength: 500,
      textInputAction: TextInputAction.newline,
      keyboardType: TextInputType.multiline,
      onChanged: (_) => setState(() => _validationMessage = null),
      decoration: const InputDecoration(
        labelText: 'Observações — opcional',
        hintText: 'Inclua somente informações relevantes da aferição.',
        alignLabelWithHint: true,
      ),
    );
  }

  Widget _errorPanel() {
    final retryable = _controller.lastError?.isTransient ?? false;
    return Semantics(
      liveRegion: true,
      label: 'Erro ao registrar pesagem: $_validationMessage',
      child: Container(
        key: const Key('health-weight-error'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.1),
          border: Border.all(color: AppTheme.error.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppTheme.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _validationMessage!,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                ),
              ),
            ),
            if (retryable)
              TextButton(
                key: const Key('health-weight-retry'),
                onPressed: _controller.isSubmitting ? null : _submit,
                child: const Text('Tentar novamente'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _actionSummary() {
    final contextLabel = _context?.label;
    return Container(
      key: const Key('health-weight-summary'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanelStrong,
        border: Border.all(color: AppTheme.primaryDivider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.monitor_weight_outlined,
            size: 20,
            color: AppTheme.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Pesagem · $_summaryWeight kg'
              '${contextLabel == null ? '' : ' · $contextLabel'}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryAction(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      enabled: !_controller.isSubmitting,
      label: _controller.isSubmitting ? 'Salvando pesagem' : 'Salvar pesagem',
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton.icon(
          key: const Key('health-weight-save'),
          onPressed: _controller.isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: AppTheme.background,
            disabledBackgroundColor: AppTheme.surfacePanelAlt,
            disabledForegroundColor: AppTheme.textTertiary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: _controller.isSubmitting
              ? reduceMotion
                    ? const Icon(Icons.hourglass_top_rounded, size: 20)
                    : const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.textTertiary,
                        ),
                      )
              : const Icon(Icons.save_outlined),
          label: Text(
            _controller.isSubmitting ? 'SALVANDO...' : 'Salvar pesagem',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
      ),
    );
  }
}
