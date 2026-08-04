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
      text: widget.dog.weight?.toStringAsFixed(1) ?? '',
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
    _weightController.text = next.toStringAsFixed(1);
    setState(() => _validationMessage = null);
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
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Material(
          color: AppTheme.surfaceSheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Registrar pesagem',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            widget.dog.name,
                            key: const Key('health-weight-dog-name'),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const Key('health-weight-cancel'),
                      onPressed: _controller.isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    IconButton.filledTonal(
                      key: const Key('health-weight-decrement'),
                      onPressed: _controller.isSubmitting
                          ? null
                          : () => _step(-1),
                      icon: const Icon(Icons.remove),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        key: const Key('health-weight-input'),
                        controller: _weightController,
                        enabled: !_controller.isSubmitting,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d{0,3}([\.,]\d*)?$'),
                          ),
                        ],
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          labelText: 'Peso em kg',
                          suffixText: 'kg',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      key: const Key('health-weight-increment'),
                      onPressed: _controller.isSubmitting
                          ? null
                          : () => _step(1),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<HealthWeightContext?>(
                  key: const Key('health-weight-context'),
                  initialValue: _context,
                  decoration: const InputDecoration(
                    labelText: 'Contexto opcional',
                  ),
                  items: [
                    const DropdownMenuItem<HealthWeightContext?>(
                      value: null,
                      child: Text('Não informado'),
                    ),
                    ...HealthWeightContext.values.map(
                      (value) => DropdownMenuItem<HealthWeightContext?>(
                        value: value,
                        child: Text(value.label),
                      ),
                    ),
                  ],
                  onChanged: _controller.isSubmitting
                      ? null
                      : (value) => setState(() => _context = value),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('health-weight-notes'),
                  controller: _notesController,
                  enabled: !_controller.isSubmitting,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Observações opcionais',
                  ),
                ),
                if (_validationMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _validationMessage!,
                    key: const Key('health-weight-error'),
                    style: const TextStyle(color: AppTheme.error),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    key: const Key('health-weight-save'),
                    onPressed: _controller.isSubmitting ? null : _submit,
                    child: _controller.isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('SALVAR PESAGEM'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
