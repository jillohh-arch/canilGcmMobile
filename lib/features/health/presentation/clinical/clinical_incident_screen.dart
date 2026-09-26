import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/data/clinical/firebase_functions_clinical_incident_gateway.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_gateway.dart'
    show ClinicalCaseOption;
import 'package:canil_gcm/features/health/domain/clinical_incident_command.dart';
import 'package:canil_gcm/features/health/domain/clinical_incident_gateway.dart';
import 'package:canil_gcm/features/health/presentation/clinical/clinical_incident_form_state.dart';

class ClinicalIncidentScreen extends StatefulWidget {
  const ClinicalIncidentScreen({
    super.key,
    required this.dogId,
    this.initialCaseId,
    this.gateway,
  });

  final String dogId;
  final String? initialCaseId;
  final ClinicalIncidentGateway? gateway;

  @override
  State<ClinicalIncidentScreen> createState() => _ClinicalIncidentScreenState();
}

class _ClinicalIncidentScreenState extends State<ClinicalIncidentScreen> {
  late final ClinicalIncidentGateway _gateway;
  late final ClinicalIncidentFormState _form;

  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _conductCtrl = TextEditingController();
  final TextEditingController _caseTitleCtrl = TextEditingController();
  final TextEditingController _vetNameCtrl = TextEditingController();
  final TextEditingController _clinicCtrl = TextEditingController();
  final TextEditingController _crmvCtrl = TextEditingController();

  List<ClinicalCaseOption> _usableCases = const [];
  bool _loadingCases = true;
  bool _submitting = false;
  String? _errorMessage;
  IncidentPendingFinalization? _pendingFinalization;

  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  final DateFormat _timeFormat = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? FirebaseFunctionsClinicalIncidentGateway();
    _form = ClinicalIncidentFormState();

    if (widget.initialCaseId != null) {
      _form.selectedCaseId = widget.initialCaseId;
      _form.openNewCase = false;
    }

    _loadCases();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _conductCtrl.dispose();
    _caseTitleCtrl.dispose();
    _vetNameCtrl.dispose();
    _clinicCtrl.dispose();
    _crmvCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCases() async {
    try {
      final cases = await _gateway.loadUsableCases(widget.dogId);
      if (mounted) {
        setState(() {
          _usableCases = cases;
          _loadingCases = false;
          if (widget.initialCaseId == null) {
            if (cases.isEmpty) {
              _form.openNewCase = true;
            } else {
              _form.openNewCase = false;
              _form.selectedCaseId = cases.first.caseId;
            }
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingCases = false;
          _form.openNewCase = true;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _form.occurredAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(minutes: 5)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              surface: AppTheme.surfacePanel,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _form.occurredAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _form.occurredAt.hour,
          _form.occurredAt.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_form.occurredAt),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              surface: AppTheme.surfacePanel,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _form.occurredAt = DateTime(
          _form.occurredAt.year,
          _form.occurredAt.month,
          _form.occurredAt.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  Future<void> _submit() async {
    _form.description = _descCtrl.text;
    _form.initialConductNotes = _conductCtrl.text;
    _form.caseTitle = _caseTitleCtrl.text;
    _form.veterinarianName = _vetNameCtrl.text;
    _form.clinicOrLocation = _clinicCtrl.text;
    _form.professionalRegistrationNumber = _crmvCtrl.text;

    final validationError = _form.validate();
    if (validationError != null) {
      setState(() => _errorMessage = validationError);
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final cmd = _form.toCommand(dogId: widget.dogId);
    final result = await _gateway.saveIncident(cmd);

    if (!mounted) return;

    switch (result) {
      case IncidentOpenedCase():
      case IncidentAppendedToCase():
        _form.completeAttempt();
        setState(() => _submitting = false);
        _showSuccessAndExit();
        break;
      case IncidentPendingFinalization(:final failure):
        setState(() {
          _submitting = false;
          _pendingFinalization = result;
          _errorMessage =
              'Registro criado, mas a finalização falhou: ${failure.message}';
        });
        break;
      case IncidentSaveFailure(:final failure):
        setState(() {
          _submitting = false;
          _errorMessage = failure.message;
        });
        break;
    }
  }

  Future<void> _retryFinalize() async {
    final pending = _pendingFinalization;
    if (pending == null) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final result = await _gateway.retryFinalization(pending);

    if (!mounted) return;

    switch (result) {
      case IncidentOpenedCase():
      case IncidentAppendedToCase():
        _form.completeAttempt();
        setState(() {
          _submitting = false;
          _pendingFinalization = null;
        });
        _showSuccessAndExit();
        break;
      case IncidentPendingFinalization(:final failure):
        setState(() {
          _submitting = false;
          _pendingFinalization = result;
          _errorMessage = 'Nova tentativa falhou: ${failure.message}';
        });
        break;
      case IncidentSaveFailure(:final failure):
        setState(() {
          _submitting = false;
          _errorMessage = failure.message;
        });
        break;
    }
  }

  void _showSuccessAndExit() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Intercorrência registrada com sucesso no prontuário!'),
        backgroundColor: AppTheme.success,
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          'Registrar Intercorrência',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.primary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null) _buildErrorBanner(),
              _buildSectionHeader('1. DATA E HORA DO OCORRIDO'),
              _buildDateTimeCard(),
              const SizedBox(height: 20),
              _buildSectionHeader('2. CATEGORIA / NATUREZA *'),
              _buildCategorySelector(),
              const SizedBox(height: 20),
              _buildSectionHeader('3. GRAVIDADE CLÍNICA *'),
              _buildSeveritySelector(),
              const SizedBox(height: 20),
              _buildSectionHeader('4. DESCRIÇÃO DO INCIDENTE *'),
              _buildDescriptionField(),
              const SizedBox(height: 20),
              _buildSectionHeader('5. CONDUTA INICIAL ADOTADA'),
              _buildConductSection(),
              const SizedBox(height: 20),
              _buildSectionHeader('6. IMPACTO OPERACIONAL'),
              _buildOperationalImpactCard(),
              const SizedBox(height: 20),
              _buildSectionHeader('7. DESTINO NO PRONTUÁRIO CLÍNICO'),
              _buildCaseDestinationSection(),
              const SizedBox(height: 20),
              _buildSectionHeader('8. ATENDIMENTO EXTERNO (OPCIONAL)'),
              _buildProfessionalCard(),
              const SizedBox(height: 28),
              _buildSubmitButton(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.inter(
          color: AppTheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.error),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.inter(color: AppTheme.error, fontSize: 13),
            ),
          ),
          if (_pendingFinalization != null)
            TextButton(
              onPressed: _submitting ? null : _retryFinalize,
              child: const Text('Re-tentar'),
            ),
        ],
      ),
    );
  }

  Widget _buildDateTimeCard() {
    return Card(
      color: AppTheme.surfacePanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _pickDate,
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        color: AppTheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _dateFormat.format(_form.occurredAt),
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(height: 24, width: 1, color: AppTheme.outline),
            const SizedBox(width: 16),
            Expanded(
              child: InkWell(
                onTap: _pickTime,
                child: Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        color: AppTheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _timeFormat.format(_form.occurredAt),
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: IncidentCategory.values.map((cat) {
        final selected = _form.category == cat;
        return ChoiceChip(
          label: Text(cat.label),
          selected: selected,
          onSelected: (val) {
            if (val) setState(() => _form.category = cat);
          },
          labelStyle: GoogleFonts.inter(
            color: selected ? Colors.white : AppTheme.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
          selectedColor: AppTheme.primary,
          backgroundColor: AppTheme.surfacePanel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: selected ? AppTheme.primary : AppTheme.outline,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSeveritySelector() {
    return Column(
      children: IncidentSeverity.values.map((sev) {
        final selected = _form.severity == sev;
        final color = switch (sev) {
          IncidentSeverity.mild => AppTheme.success,
          IncidentSeverity.moderate => AppTheme.warning,
          IncidentSeverity.severe => AppTheme.attention,
          IncidentSeverity.critical => AppTheme.error,
        };

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => setState(() => _form.severity = sev),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? color.withValues(alpha: 0.15) : AppTheme.surfacePanel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? color : AppTheme.outline,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    sev.label,
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  if (selected)
                    Icon(Icons.check_circle_rounded, color: color, size: 20),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDescriptionField() {
    return TextField(
      controller: _descCtrl,
      maxLines: 4,
      maxLength: 2000,
      style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Descreva detalhadamente o que aconteceu com o K9...',
        hintStyle: GoogleFonts.inter(color: AppTheme.textSoft),
        filled: true,
        fillColor: AppTheme.surfacePanel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.primary, width: 2),
        ),
      ),
    );
  }

  Widget _buildConductSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: IncidentConductAction.values.map((action) {
            final active = _form.conductActions.contains(action);
            return FilterChip(
              label: Text(action.label),
              selected: active,
              onSelected: (val) {
                setState(() {
                  if (val) {
                    _form.conductActions.add(action);
                  } else {
                    _form.conductActions.remove(action);
                  }
                });
              },
              labelStyle: GoogleFonts.inter(
                color: active ? Colors.white : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
              selectedColor: AppTheme.info,
              backgroundColor: AppTheme.surfacePanel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: active ? AppTheme.info : AppTheme.outline,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _conductCtrl,
          maxLines: 2,
          maxLength: 2000,
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Detalhes da conduta inicial, medicações dadas...',
            hintStyle: GoogleFonts.inter(color: AppTheme.textSoft),
            filled: true,
            fillColor: AppTheme.surfacePanel,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.outline),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOperationalImpactCard() {
    return Card(
      color: AppTheme.surfacePanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        title: Text(
          'Requer suspensão de atividades operacionais?',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'Sinaliza necessidade de avaliação clínica para restrição.',
          style: GoogleFonts.inter(
            color: AppTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        value: _form.hasOperationalImpact,
        activeThumbColor: AppTheme.attention,
        onChanged: (val) {
          setState(() => _form.hasOperationalImpact = val);
        },
      ),
    );
  }

  Widget _buildCaseDestinationSection() {
    if (_loadingCases) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        _IncidentSelectableRow(
          selected: _form.openNewCase,
          accent: AppTheme.primary,
          title: 'Abrir novo caso clínico',
          subtitle: 'Cria um novo caso investigativo/assistencial para esta intercorrência.',
          onTap: () => setState(() => _form.openNewCase = true),
        ),
        if (_form.openNewCase)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: TextField(
              controller: _caseTitleCtrl,
              maxLength: 200,
              style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Título do novo caso (ex: Lesão Pata Dianteira)',
                hintStyle: GoogleFonts.inter(color: AppTheme.textSoft),
                filled: true,
                fillColor: AppTheme.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        _IncidentSelectableRow(
          selected: !_form.openNewCase,
          accent: AppTheme.primary,
          title: 'Vincular a caso clínico ativo existente',
          subtitle: _usableCases.isEmpty
              ? 'Nenhum caso clínico ativo encontrado.'
              : 'Anexa este evento a um caso já em andamento.',
          onTap: _usableCases.isEmpty
              ? () {}
              : () => setState(() => _form.openNewCase = false),
        ),
        if (!_form.openNewCase && _usableCases.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DropdownButtonFormField<String>(
              initialValue: _form.selectedCaseId ?? _usableCases.first.caseId,
              dropdownColor: AppTheme.surfacePanel,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              items: _usableCases.map((c) {
                return DropdownMenuItem<String>(
                  value: c.caseId,
                  child: Text(
                    '${c.title} (${c.statusWireName})',
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _form.selectedCaseId = val);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildProfessionalCard() {
    return Card(
      color: AppTheme.surfacePanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: _vetNameCtrl,
              style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Nome do Veterinário / Responsável',
                labelStyle: GoogleFonts.inter(color: AppTheme.textSecondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _crmvCtrl,
                    style:
                        GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'CRMV / Registro',
                      labelStyle: GoogleFonts.inter(color: AppTheme.textSecondary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _clinicCtrl,
                    style:
                        GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Clínica / Local',
                      labelStyle: GoogleFonts.inter(color: AppTheme.textSecondary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: _submitting ? null : _submit,
        child: _submitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                'Registrar Intercorrência',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
      ),
    );
  }
}

class _IncidentSelectableRow extends StatelessWidget {
  const _IncidentSelectableRow({
    required this.selected,
    required this.accent,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final bool selected;
  final Color accent;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? accent : AppTheme.outline,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: selected ? accent : AppTheme.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? accent : AppTheme.textPrimary,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
