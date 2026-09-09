import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/health/data/clinical/firebase_functions_clinical_consultation_gateway.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_command.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_errors.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_gateway.dart';
import 'package:canil_gcm/features/health/presentation/clinical/clinical_consultation_form_state.dart';
import 'package:canil_gcm/features/health/presentation/shared/forms/health_form_controller.dart';
import 'package:canil_gcm/features/health/presentation/shared/forms/health_form_scaffold.dart';
import 'package:canil_gcm/features/health/presentation/shared/widgets/health_date_time_field.dart';
import 'package:canil_gcm/features/health/presentation/shared/widgets/health_field_label.dart';
import 'package:canil_gcm/features/health/presentation/shared/widgets/health_form_section.dart';

/// Tela dedicada de Consulta Veterinária.
///
/// Materializa o mockup aprovado `docs/health/mockups/consulta veterinaria.png`.
///
/// Escreve no caminho clínico canônico
/// (`dogs/{dogId}/clinical_cases/{caseId}/clinical_events/{eventId}`) via
/// callables, NUNCA no `HealthLogModel` legado. O formulário genérico
/// `HealthEventFormScreen` continua atendendo os demais tipos sem alteração.
///
/// Uma única ação de salvar; o gateway orquestra internamente
/// `Open`/`Append` → `draft` → `Finalize` → `final`.
class ClinicalConsultationScreen extends StatefulWidget {
  const ClinicalConsultationScreen({
    super.key,
    required this.dogId,
    this.gateway,
    this.onChangeDog,
  });

  final String dogId;

  /// Injetável para teste. Em produção usa o gateway canônico.
  final ClinicalConsultationGateway? gateway;

  /// "Trocar K9". Quando ausente, o botão não é exibido.
  final Future<String?> Function(BuildContext context)? onChangeDog;

  @override
  State<ClinicalConsultationScreen> createState() =>
      _ClinicalConsultationScreenState();
}

class _ClinicalConsultationScreenState
    extends State<ClinicalConsultationScreen> {
  static const _accent = AppTheme.info;

  final _formController = HealthFormController();
  final _state = ConsultationFormState();

  late String _dogId;
  late final ClinicalConsultationGateway _gateway;

  List<ClinicalCaseOption> _cases = const [];
  bool _loadingCases = true;
  String? _caseLoadError;

  /// Consultas concluídas do caso selecionado (escopo por CASO, não global).
  List<ClinicalConsultationRecordView> _caseRecords = const [];
  bool _loadingRecords = false;

  /// Sinaliza que um caso foi pré-selecionado durante `_loadCases` e seus
  /// registros ainda precisam ser buscados (não dá para `await` dentro do
  /// `setState`).
  bool _shouldLoadRecords = false;

  /// Pendência de finalização preservada entre tentativas.
  ///
  /// Enquanto não for `null`, Salvar retenta SOMENTE a finalização.
  ConsultationPendingFinalization? _pending;

  @override
  void initState() {
    super.initState();
    _dogId = widget.dogId;
    _gateway =
        widget.gateway ?? FirebaseFunctionsClinicalConsultationGateway();
    _loadCases();
  }

  @override
  void dispose() {
    _formController.dispose();
    super.dispose();
  }

  Future<void> _loadCases() async {
    setState(() {
      _loadingCases = true;
      _caseLoadError = null;
    });
    try {
      final cases = await _gateway.loadUsableCases(_dogId);
      if (!mounted) return;
      setState(() {
        _cases = cases;
        _loadingCases = false;
        // Um único caso utilizável vem pré-selecionado, mas permanece VISÍVEL
        // como destino e alterável (decisão de produto).
        if (cases.length == 1) {
          _state.selectedCaseId = cases.first.caseId;
          _state.openNewCase = false;
          _shouldLoadRecords = true;
        } else if (cases.isEmpty) {
          _state.selectedCaseId = null;
          _state.openNewCase = true;
        } else {
          _state.selectedCaseId = null;
          _state.openNewCase = false;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingCases = false;
        _cases = const [];
        _caseLoadError = _message(error);
        // Sem leitura de casos não presumimos abertura silenciosa.
        _state.selectedCaseId = null;
        _state.openNewCase = false;
      });
      return;
    }

    // Fora do `setState`: um caso pré-selecionado já mostra seus registros.
    if (_shouldLoadRecords) {
      _shouldLoadRecords = false;
      await _loadCaseRecords();
    }
  }

  /// Sucesso confirmado: o evento está `final`.
  ///
  /// Recarrega os registros canônicos do caso para que a consulta recém-salva
  /// fique observável na própria tela, e só então informa sucesso.
  Future<void> _onSaved({required String caseId}) async {
    _state.completeAttempt();
    if (!mounted) return;
    setState(() {
      _pending = null;
      _state.selectedCaseId = caseId;
      _state.openNewCase = false;
    });
    await _loadCaseRecords();
    if (!mounted) return;
    AppFeedback.success(context, 'Consulta registrada.');
  }

  String _message(Object error) {
    if (error is ClinicalConsultationFailure) {
      return error.message ?? 'Não foi possível carregar os casos clínicos.';
    }
    return 'Não foi possível carregar os casos clínicos.';
  }

  /// Carrega as consultas CONCLUÍDAS do caso selecionado.
  ///
  /// Escopo por CASO: `clinical_events` é subcoleção de `clinical_cases`, e a
  /// leitura cross-case exigiria `collectionGroup`, não autorizado pelas Rules
  /// vigentes. Ver `GLOBAL CLINICAL TIMELINE = DEFERRED`.
  Future<void> _loadCaseRecords() async {
    final caseId = _state.selectedCaseId;
    if (caseId == null) {
      if (mounted) {
        setState(() {
          _caseRecords = const [];
          _loadingRecords = false;
        });
      }
      return;
    }
    setState(() => _loadingRecords = true);
    try {
      final records = await _gateway.loadCaseConsultations(
        dogId: _dogId,
        caseId: caseId,
      );
      if (!mounted) return;
      setState(() {
        _caseRecords = records;
        _loadingRecords = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Falha de leitura não invalida o formulário: a seção apenas não lista.
      setState(() {
        _caseRecords = const [];
        _loadingRecords = false;
      });
    }
  }

  Dog? get _dog {
    final dogs = context.read<DogViewModel>().dogs;
    for (final dog in dogs) {
      if (dog.id == _dogId) return dog;
    }
    return null;
  }

  Future<void> _submit() async {
    final pending = _pending;
    await _formController.submit(
      validate: pending != null ? null : _state.validate,
      action: () async {
        final result = pending == null
            ? await _gateway.saveConsultation(
                _state.toCommand(dogId: _dogId),
              )
            : await _gateway.retryFinalization(pending);
        await _handleResult(result);
      },
    );
  }

  Future<void> _handleResult(ConsultationSaveResult result) async {
    switch (result) {
      case final ConsultationOpenedCase ok:
        await _onSaved(caseId: ok.caseId);

      case final ConsultationAppendedToCase ok:
        await _onSaved(caseId: ok.caseId);

      case final ConsultationPendingFinalization pendingResult:
        // NÃO é sucesso: o fato existe em draft. Preserva a identidade para
        // retentar somente a finalização.
        if (mounted) {
          setState(() => _pending = pendingResult);
        }
        throw ClinicalConsultationPendingError(
          pendingResult.failure.message ??
              'Registro criado, mas a finalização está pendente. '
                  'Toque em Finalizar consulta para tentar novamente.',
        );

      case ConsultationSaveFailure(:final failure):
        throw ClinicalConsultationPendingError(_failureText(failure));
    }
  }

  String _failureText(ClinicalConsultationFailure failure) {
    return switch (failure) {
      ClinicalConsultationNotAuthorized() =>
        'Seu perfil não tem autorização para registrar consultas clínicas.',
      ClinicalConsultationDogAccessDenied() =>
        'Seu perfil permite registrar dados apenas para o K9 vinculado ou em '
            'turno ativo.',
      ClinicalConsultationUnauthenticated() =>
        'Sessão expirada. Entre novamente para registrar a consulta.',
      ClinicalConsultationCaseNotFound() =>
        'O caso clínico selecionado não foi encontrado. Recarregue a lista.',
      ClinicalConsultationCaseNotWritable() =>
        failure.message ?? 'O caso clínico não aceita novos registros.',
      ClinicalConsultationIdempotencyConflict() =>
        'Esta consulta já foi registrada com outra intenção. Recarregue a tela.',
      ClinicalConsultationValidationFailure() =>
        failure.message ?? 'Dados da consulta recusados pelo servidor.',
      ClinicalConsultationUnavailable() =>
        'Registro clínico indisponível neste ambiente.',
      ClinicalConsultationUnexpected() =>
        failure.message ?? 'Não foi possível registrar a consulta.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final dog = _dog;
    return HealthFormScaffold(
      title: 'CONSULTA VETERINÁRIA',
      accentColor: _accent,
      controller: _formController,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _K9Card(
            dog: dog,
            accent: _accent,
            onChangeDog: widget.onChangeDog == null
                ? null
                : () async {
                    final next = await widget.onChangeDog!(context);
                    if (next == null || !mounted || next == _dogId) return;
                    setState(() => _dogId = next);
                    await _loadCases();
                  },
          ),
          _CaseSelector(
            accent: _accent,
            cases: _cases,
            loading: _loadingCases,
            error: _caseLoadError,
            selectedCaseId: _state.selectedCaseId,
            openNewCase: _state.openNewCase,
            onRetry: _loadCases,
            onSelect: (caseId) {
              setState(() {
                _state.selectedCaseId = caseId;
                _state.openNewCase = false;
                _formController.markDirty();
              });
              _loadCaseRecords();
            },
            onOpenNew: () => setState(() {
              _state.openNewCase = true;
              _state.selectedCaseId = null;
              _caseRecords = const [];
              _formController.markDirty();
            }),
          ),
          _ConsultationSection(state: _state, accent: _accent, onChanged: _touch),
          _AssessmentSection(state: _state, accent: _accent, onChanged: _touch),
          _TextSection(state: _state, accent: _accent, onChanged: _touch),
          _ConductSection(state: _state, accent: _accent, onChanged: _touch),
          _OperationalSection(state: _state, accent: _accent, onChanged: _touch),
          const _AttachmentsDeferredSection(accent: _accent),
          _ProfessionalSection(state: _state, accent: _accent, onChanged: _touch),
          if (_pending != null) _PendingBanner(pending: _pending!),
          if (_state.selectedCaseId != null)
            _CaseRecordsSection(
              accent: _accent,
              loading: _loadingRecords,
              records: _caseRecords,
            ),
        ],
      ),
      bottomBar: _SaveBar(
        controller: _formController,
        accent: _accent,
        pending: _pending != null,
        onSubmit: _submit,
      ),
    );
  }

  void _touch() {
    _formController.markDirty();
    setState(() {});
  }
}

/// Erro de apresentação: leva a mensagem factual ao [HealthFormController].
class ClinicalConsultationPendingError implements Exception {
  ClinicalConsultationPendingError(this.message);

  final String message;

  @override
  String toString() => message;
}

// ─────────────────────────────────────────────────────────────────────────────
// Seções
// ─────────────────────────────────────────────────────────────────────────────

class _K9Card extends StatelessWidget {
  const _K9Card({required this.dog, required this.accent, this.onChangeDog});

  final Dog? dog;
  final Color accent;
  final VoidCallback? onChangeDog;

  @override
  Widget build(BuildContext context) {
    final d = dog;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.profileCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryChipBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppTheme.surfacePanelAlt,
            backgroundImage:
                (d?.profileImageUrl != null && d!.profileImageUrl!.isNotEmpty)
                ? NetworkImage(d.profileImageUrl!)
                : null,
            child: (d?.profileImageUrl == null || d!.profileImageUrl!.isEmpty)
                ? const Icon(Icons.pets, color: AppTheme.textSecondary)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d?.name ?? 'K9',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (d != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        d.breed,
                        if (d.weight != null)
                          '${d.weight!.toStringAsFixed(1)} kg',
                      ].join(' · '),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (onChangeDog != null)
            TextButton.icon(
              onPressed: onChangeDog,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Trocar K9'),
              style: TextButton.styleFrom(foregroundColor: accent),
            ),
        ],
      ),
    );
  }
}

/// Seletor inline de ClinicalCase, imediatamente abaixo do card do K9.
///
/// Nunca escolhe silenciosamente: o destino da consulta fica sempre visível.
class _CaseSelector extends StatelessWidget {
  const _CaseSelector({
    required this.accent,
    required this.cases,
    required this.loading,
    required this.error,
    required this.selectedCaseId,
    required this.openNewCase,
    required this.onSelect,
    required this.onOpenNew,
    required this.onRetry,
  });

  final Color accent;
  final List<ClinicalCaseOption> cases;
  final bool loading;
  final String? error;
  final String? selectedCaseId;
  final bool openNewCase;
  final ValueChanged<String> onSelect;
  final VoidCallback onOpenNew;
  final VoidCallback onRetry;

  static const _statusLabels = <String, String>{
    'open': 'Aberto',
    'under_investigation': 'Em investigação',
    'under_treatment': 'Em tratamento',
    'monitoring': 'Em monitoramento',
  };

  @override
  Widget build(BuildContext context) {
    return HealthFormSection(
      title: 'CASO CLÍNICO',
      accentColor: accent,
      subtitle: 'Onde esta consulta será registrada',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (error != null) ...[
            Text(
              error!,
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.error),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('consultation_cases_retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar novamente'),
            ),
          ] else ...[
            if (cases.isEmpty)
              Text(
                'Nenhum caso clínico aberto para este K9.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            for (final option in cases)
              _SelectableRow(
                rowKey: Key('consultation_case_${option.caseId}'),
                selected: !openNewCase && selectedCaseId == option.caseId,
                accent: accent,
                title: option.title,
                subtitle: [
                  _statusLabels[option.statusWireName] ??
                      option.statusWireName,
                  if (option.openedAt != null)
                    'aberto em ${DateFormat('dd/MM/yyyy').format(option.openedAt!)}',
                ].join(' · '),
                onTap: () => onSelect(option.caseId),
              ),
            const SizedBox(height: 4),
            InkWell(
              key: const Key('consultation_open_new_case'),
              onTap: onOpenNew,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: openNewCase
                      ? accent.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: openNewCase ? accent : AppTheme.primaryChipBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      openNewCase
                          ? Icons.check_circle_rounded
                          : Icons.add_circle_outline_rounded,
                      size: 18,
                      color: openNewCase ? accent : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Abrir novo caso',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: openNewCase ? accent : AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConsultationSection extends StatelessWidget {
  const _ConsultationSection({
    required this.state,
    required this.accent,
    required this.onChanged,
  });

  final ConsultationFormState state;
  final Color accent;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return HealthFormSection(
      title: 'CONSULTA',
      accentColor: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HealthDateTimeField(
            label: 'Data e hora',
            value: state.occurredAt,
            includeTime: true,
            required: true,
            accentColor: accent,
            lastDate: DateTime.now().add(const Duration(days: 1)),
            onChanged: (value) {
              state.occurredAt = value;
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          _TextField(
            fieldKey: const Key('consultation_veterinarian'),
            label: 'Veterinário',
            value: state.veterinarianName,
            accent: accent,
            onChanged: (value) {
              state.veterinarianName = value;
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          _TextField(
            fieldKey: const Key('consultation_clinic'),
            label: 'Clínica ou local',
            value: state.clinicOrLocation,
            accent: accent,
            onChanged: (value) {
              state.clinicOrLocation = value;
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          const HealthFieldLabel('Motivo', required: true),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final reason in ConsultationReason.values)
                ChoiceChip(
                  key: Key('consultation_reason_${reason.wireValue}'),
                  label: Text(reason.label),
                  selected: state.reason == reason,
                  selectedColor: accent.withValues(alpha: 0.22),
                  onSelected: (_) {
                    state.reason = reason;
                    onChanged();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssessmentSection extends StatelessWidget {
  const _AssessmentSection({
    required this.state,
    required this.accent,
    required this.onChanged,
  });

  final ConsultationFormState state;
  final Color accent;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return HealthFormSection(
      title: 'AVALIAÇÃO CLÍNICA',
      accentColor: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HealthFieldLabel('Escore corporal'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in ConsultationBodyCondition.values)
                ChoiceChip(
                  key: Key('consultation_body_${value.wireValue}'),
                  label: Text(value.label),
                  selected: state.bodyCondition == value,
                  selectedColor: accent.withValues(alpha: 0.22),
                  onSelected: (_) {
                    state.bodyCondition = value;
                    onChanged();
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          const HealthFieldLabel('Hidratação'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in ConsultationHydration.values)
                ChoiceChip(
                  key: Key('consultation_hydration_${value.wireValue}'),
                  label: Text(value.label),
                  selected: state.hydration == value,
                  selectedColor: accent.withValues(alpha: 0.22),
                  onSelected: (_) {
                    state.hydration = value;
                    onChanged();
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TextField(
                  fieldKey: const Key('consultation_temperature'),
                  label: 'Temperatura (°C)',
                  value: state.temperatureCelsius,
                  accent: accent,
                  numeric: true,
                  onChanged: (value) {
                    state.temperatureCelsius = value;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TextField(
                  fieldKey: const Key('consultation_weight'),
                  label: 'Peso (kg)',
                  value: state.weightKg,
                  accent: accent,
                  numeric: true,
                  onChanged: (value) {
                    state.weightKg = value;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TextField(
                  fieldKey: const Key('consultation_heart_rate'),
                  label: 'F. cardíaca (bpm)',
                  value: state.heartRateBpm,
                  accent: accent,
                  numeric: true,
                  onChanged: (value) {
                    state.heartRateBpm = value;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TextField(
                  fieldKey: const Key('consultation_respiratory_rate'),
                  label: 'F. respiratória (irpm)',
                  value: state.respiratoryRateIrpm,
                  accent: accent,
                  numeric: true,
                  onChanged: (value) {
                    state.respiratoryRateIrpm = value;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TextSection extends StatelessWidget {
  const _TextSection({
    required this.state,
    required this.accent,
    required this.onChanged,
  });

  final ConsultationFormState state;
  final Color accent;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HealthFormSection(
          title: 'ACHADOS',
          accentColor: accent,
          child: _TextField(
            fieldKey: const Key('consultation_findings'),
            label: '',
            value: state.findings,
            accent: accent,
            maxLines: 4,
            maxLength: 1000,
            onChanged: (value) {
              state.findings = value;
              onChanged();
            },
          ),
        ),
        HealthFormSection(
          title: 'DIAGNÓSTICO',
          accentColor: accent,
          child: _TextField(
            fieldKey: const Key('consultation_diagnosis'),
            label: '',
            value: state.diagnosis,
            accent: accent,
            maxLines: 4,
            maxLength: 1000,
            onChanged: (value) {
              state.diagnosis = value;
              onChanged();
            },
          ),
        ),
      ],
    );
  }
}

class _ConductSection extends StatelessWidget {
  const _ConductSection({
    required this.state,
    required this.accent,
    required this.onChanged,
  });

  final ConsultationFormState state;
  final Color accent;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return HealthFormSection(
      title: 'CONDUTA',
      accentColor: accent,
      subtitle: 'Registrado como recomendação da consulta',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final conduct in ConsultationConduct.values)
            CheckboxListTile(
              key: Key('consultation_conduct_${conduct.wireValue}'),
              value: state.conducts.contains(conduct),
              onChanged: (checked) {
                if (checked == true) {
                  state.conducts.add(conduct);
                } else {
                  state.conducts.remove(conduct);
                }
                onChanged();
              },
              activeColor: accent,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                conduct.label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          const SizedBox(height: 8),
          _TextField(
            fieldKey: const Key('consultation_conduct_notes'),
            label: 'Observações da conduta',
            value: state.conductNotes,
            accent: accent,
            maxLines: 3,
            maxLength: 1000,
            onChanged: (value) {
              state.conductNotes = value;
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}

class _OperationalSection extends StatelessWidget {
  const _OperationalSection({
    required this.state,
    required this.accent,
    required this.onChanged,
  });

  final ConsultationFormState state;
  final Color accent;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return HealthFormSection(
      title: 'STATUS OPERACIONAL',
      accentColor: accent,
      subtitle: 'O K9 pode continuar em atividade operacional?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final status in ConsultationOperationalStatus.values)
            _SelectableRow(
              rowKey: Key('consultation_operational_${status.wireValue}'),
              selected: state.operationalStatus == status,
              accent: _operationalColor(status),
              title: status.label,
              icon: _operationalIcon(status),
              onTap: () {
                state.operationalStatus = status;
                onChanged();
              },
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Registrado como evidência clínica. Não altera automaticamente '
              'a prontidão nem emite restrição.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Anexos deferidos: a UI não pode sugerir que um anexo será salvo.
class _AttachmentsDeferredSection extends StatelessWidget {
  const _AttachmentsDeferredSection({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return HealthFormSection(
      title: 'ANEXOS',
      accentColor: accent,
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Anexos ainda não disponíveis para a consulta clínica canônica. '
              'Nenhum arquivo será salvo nesta versão.',
              key: const Key('consultation_attachments_deferred'),
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloco factual do profissional. NÃO afirma assinatura digital.
class _ProfessionalSection extends StatelessWidget {
  const _ProfessionalSection({
    required this.state,
    required this.accent,
    required this.onChanged,
  });

  final ConsultationFormState state;
  final Color accent;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return HealthFormSection(
      title: 'PROFISSIONAL RESPONSÁVEL',
      accentColor: accent,
      subtitle: 'Quem respondeu clinicamente pelo atendimento',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _TextField(
                  fieldKey: const Key('consultation_registration_type'),
                  label: 'Conselho',
                  value: state.professionalRegistrationType,
                  accent: accent,
                  onChanged: (value) {
                    state.professionalRegistrationType = value;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _TextField(
                  fieldKey: const Key('consultation_registration_number'),
                  label: 'Registro',
                  value: state.professionalRegistrationNumber,
                  accent: accent,
                  onChanged: (value) {
                    state.professionalRegistrationNumber = value;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'O registro é atribuído ao usuário autenticado que preencheu a '
              'consulta; os dados do profissional são registrados como '
              'informados.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cores do mockup para a conclusão operacional.
Color _operationalColor(ConsultationOperationalStatus status) {
  return switch (status) {
    ConsultationOperationalStatus.totalmenteApto => AppTheme.success,
    ConsultationOperationalStatus.restrito => AppTheme.warning,
    ConsultationOperationalStatus.temporariamenteInapto => AppTheme.error,
  };
}

IconData _operationalIcon(ConsultationOperationalStatus status) {
  return switch (status) {
    ConsultationOperationalStatus.totalmenteApto => Icons.verified_user_rounded,
    ConsultationOperationalStatus.restrito => Icons.warning_amber_rounded,
    ConsultationOperationalStatus.temporariamenteInapto =>
      Icons.block_rounded,
  };
}

/// Linha selecionável reutilizada pelo seletor de caso e pela conclusão
/// operacional.
///
/// Substitui `RadioListTile`, cuja API de grupo está deprecada nesta versão do
/// Flutter e não é usada em nenhum outro ponto de `lib/`.
class _SelectableRow extends StatelessWidget {
  const _SelectableRow({
    required this.rowKey,
    required this.selected,
    required this.accent,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon,
  });

  final Key rowKey;
  final bool selected;
  final Color accent;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: rowKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? accent : AppTheme.primaryChipBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon ??
                    (selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded),
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
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
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
              if (selected && icon != null)
                Icon(Icons.check_circle_rounded, size: 16, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Consultas concluídas DESTE caso, lidas do caminho canônico.
///
/// Escopo deliberadamente por caso: a agregação global no Histórico Clínico
/// exigiria `collectionGroup`, que as Rules vigentes não autorizam
/// (`GLOBAL CLINICAL TIMELINE = DEFERRED`).
class _CaseRecordsSection extends StatelessWidget {
  const _CaseRecordsSection({
    required this.accent,
    required this.loading,
    required this.records,
  });

  final Color accent;
  final bool loading;
  final List<ClinicalConsultationRecordView> records;

  @override
  Widget build(BuildContext context) {
    return HealthFormSection(
      title: 'REGISTROS DESTE CASO',
      accentColor: accent,
      subtitle: 'Consultas já concluídas neste caso clínico',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (records.isEmpty)
            Text(
              'Nenhuma consulta concluída neste caso ainda.',
              key: const Key('consultation_case_records_empty'),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            )
          else
            for (final record in records)
              Container(
                key: Key('consultation_record_${record.eventId}'),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppTheme.surfacePanelSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primaryChipBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.medical_services_rounded,
                          size: 15,
                          color: accent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            record.title,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          DateFormat(
                            'dd/MM/yyyy HH:mm',
                          ).format(record.occurredAt),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        record.reasonLabel,
                        if (record.veterinarianName != null)
                          record.veterinarianName!,
                      ].join(' · '),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    if (record.diagnosis != null || record.findings != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          record.diagnosis ?? record.findings!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    if (record.operationalStatusLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          record.operationalStatusLabel!,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.pending});

  final ConsultationPendingFinalization pending;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('consultation_pending_banner'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.pending_actions_rounded,
            size: 18,
            color: AppTheme.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'O registro clínico foi criado, mas a finalização está pendente. '
              'Toque em Finalizar consulta para concluir. Nenhuma nova '
              'consulta será criada.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.controller,
    required this.accent,
    required this.pending,
    required this.onSubmit,
  });

  final HealthFormController controller;
  final Color accent;
  final bool pending;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final submitting = controller.isSubmitting;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.hasError && controller.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  controller.errorMessage!,
                  key: const Key('consultation_error_text'),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.error,
                  ),
                ),
              ),
            FilledButton.icon(
              key: const Key('consultation_save_button'),
              // Desabilitado durante o envio: protege contra duplo toque.
              onPressed: submitting ? null : onSubmit,
              icon: Icon(
                submitting
                    ? Icons.hourglass_top_rounded
                    : (pending ? Icons.task_alt_rounded : Icons.save_rounded),
                size: 18,
              ),
              label: Text(
                submitting
                    ? 'SALVANDO...'
                    : (pending ? 'FINALIZAR CONSULTA' : 'SALVAR CONSULTA'),
              ),
              style: FilledButton.styleFrom(backgroundColor: accent),
            ),
          ],
        );
      },
    );
  }
}

class _TextField extends StatefulWidget {
  const _TextField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
    this.maxLines = 1,
    this.maxLength,
    this.numeric = false,
  });

  final Key fieldKey;
  final String label;
  final String value;
  final Color accent;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final int? maxLength;
  final bool numeric;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label.isNotEmpty) HealthFieldLabel(widget.label),
        TextField(
          key: widget.fieldKey,
          controller: _controller,
          onChanged: widget.onChanged,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          keyboardType: widget.numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: widget.numeric
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
              : null,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppTheme.surfacePanelSoft,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primaryChipBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primaryChipBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: widget.accent),
            ),
          ),
        ),
      ],
    );
  }
}
