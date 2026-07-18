import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_revision.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_action_availability.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_outcome.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_type_picker.dart';
import 'package:canil_gcm/features/health/presentation/shared/forms/health_form_controller.dart';
import 'package:canil_gcm/features/health/presentation/shared/forms/health_form_scaffold.dart';
import 'package:canil_gcm/features/health/presentation/shared/widgets/health_date_time_field.dart';
import 'package:canil_gcm/features/health/presentation/shared/widgets/health_field_label.dart';
import 'package:canil_gcm/features/health/presentation/shared/widgets/health_form_actions.dart';
import 'package:canil_gcm/features/health/presentation/shared/widgets/health_form_section.dart';

/// Modo do formulário de item manual da Agenda.
enum HealthScheduleItemFormMode { create, edit }

/// Resultado de navegação do formulário (para o caller opcionalmente reagir).
enum HealthScheduleItemFormResult { saved, savedRefreshPending, cancelled }

/// Formulário create/edit de item **manual** da Agenda Preventiva.
///
/// Hierarquia Create: Título → Tipo → Agendado → Prazo → Observações.
/// Edit: tipo compacto read-only; primeiro input real = título.
///
/// Não envia campos server-owned. Mutações apenas via
/// [HealthScheduleMutationController] → gateway.
class HealthScheduleItemFormScreen extends StatefulWidget {
  final HealthScheduleItemFormMode mode;
  final String dogId;
  final HealthScheduleMutationController mutationController;

  /// Obrigatório no modo [HealthScheduleItemFormMode.edit].
  final HealthScheduleItemView? item;

  const HealthScheduleItemFormScreen({
    super.key,
    required this.mode,
    required this.dogId,
    required this.mutationController,
    this.item,
  }) : assert(
         mode == HealthScheduleItemFormMode.create || item != null,
         'edit exige item',
       );

  static Future<HealthScheduleItemFormResult?> openCreate(
    BuildContext context, {
    required String dogId,
    required HealthScheduleMutationController mutationController,
  }) {
    return Navigator.of(context).push<HealthScheduleItemFormResult>(
      MaterialPageRoute(
        builder: (_) => HealthScheduleItemFormScreen(
          mode: HealthScheduleItemFormMode.create,
          dogId: dogId,
          mutationController: mutationController,
        ),
      ),
    );
  }

  static Future<HealthScheduleItemFormResult?> openEdit(
    BuildContext context, {
    required HealthScheduleItemView item,
    required HealthScheduleMutationController mutationController,
  }) {
    return Navigator.of(context).push<HealthScheduleItemFormResult>(
      MaterialPageRoute(
        builder: (_) => HealthScheduleItemFormScreen(
          mode: HealthScheduleItemFormMode.edit,
          dogId: item.dogId,
          mutationController: mutationController,
          item: item,
        ),
      ),
    );
  }

  @override
  State<HealthScheduleItemFormScreen> createState() =>
      _HealthScheduleItemFormScreenState();
}

class _HealthScheduleItemFormScreenState
    extends State<HealthScheduleItemFormScreen> {
  final _formController = HealthFormController();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();

  ScheduleType _scheduleType = ScheduleType.general;
  DateTime? _scheduledFor;
  DateTime? _dueUntil;
  late final String _timezone;
  HealthScheduleRevision? _expectedRevision;
  String? _scheduleId;

  bool get _isCreate => widget.mode == HealthScheduleItemFormMode.create;

  @override
  void initState() {
    super.initState();
    _timezone = HealthScheduleActionAvailability.defaultTimezone;

    if (_isCreate) {
      widget.mutationController.ensureCreateIdempotencyKey();
      _scheduledFor = DateTime.now();
      _scheduleId = null;
      _expectedRevision = null;
      _formController.markPristine();
    } else {
      final item = widget.item!;
      _scheduleId = item.id;
      _expectedRevision = item.revision;
      _scheduleType = item.scheduleType;
      _titleController.text = item.title;
      _notesController.text = item.notes ?? '';
      _scheduledFor = item.scheduledFor.toLocal();
      _dueUntil = item.dueUntil?.toLocal();
      widget.mutationController.beginUpdateIntent(item.id);
      _formController.markPristine();
    }

    _titleController.addListener(_onFieldChanged);
    _notesController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    if (_isCreate) {
      if (!_formController.isSubmitting) {
        widget.mutationController.endCreateIntent();
      }
    } else {
      final id = _scheduleId;
      if (id != null && !_formController.isSubmitting) {
        widget.mutationController.endUpdateIntent(id);
      }
    }
    _titleController.removeListener(_onFieldChanged);
    _notesController.removeListener(_onFieldChanged);
    _titleController.dispose();
    _notesController.dispose();
    _formController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    _formController.markDirty();
  }

  void _setScheduledFor(DateTime value) {
    setState(() => _scheduledFor = value);
    _formController.markDirty();
  }

  void _setDueUntil(DateTime? value) {
    setState(() => _dueUntil = value);
    _formController.markDirty();
  }

  void _setType(ScheduleType type) {
    setState(() => _scheduleType = type);
    _formController.markDirty();
  }

  String? _validate() {
    if (_titleController.text.trim().isEmpty) {
      return HealthScheduleMutationUserCopy.titleRequired;
    }
    if (_scheduledFor == null) {
      return HealthScheduleMutationUserCopy.scheduledForRequired;
    }
    final due = _dueUntil;
    if (due != null && due.isBefore(_scheduledFor!)) {
      return HealthScheduleMutationUserCopy.dueUntilBeforeScheduled;
    }
    return null;
  }

  Future<void> _submit() async {
    final ok = await _formController.submit(
      validate: _validate,
      action: () async {
        final outcome = _isCreate
            ? await widget.mutationController.createManual(
                dogId: widget.dogId,
                scheduleType: _scheduleType,
                title: _titleController.text,
                scheduledFor: _scheduledFor!.toUtc(),
                timezone: _timezone,
                dueUntil: _dueUntil?.toUtc(),
                notes: _notesController.text.trim().isEmpty
                    ? null
                    : _notesController.text,
              )
            : await widget.mutationController.updateOpen(
                dogId: widget.dogId,
                scheduleId: _scheduleId!,
                expectedRevision: _expectedRevision!,
                title: _titleController.text,
                scheduledFor: _scheduledFor!.toUtc(),
                dueUntil: _dueUntil?.toUtc(),
                clearDueUntil:
                    _dueUntil == null && widget.item?.dueUntil != null,
                timezone: _timezone,
                notes: _notesController.text.trim().isEmpty
                    ? null
                    : _notesController.text,
                clearNotes:
                    _notesController.text.trim().isEmpty &&
                    (widget.item?.notes?.trim().isNotEmpty ?? false),
              );

        switch (outcome) {
          case HealthScheduleMutationUiBlocked():
            throw const HealthFormException(
              'Operação já em andamento. Aguarde.',
            );
          case HealthScheduleMutationUiFailure(
            :final userMessage,
            :final shouldRefresh,
          ):
            if (shouldRefresh) {
              // ignore: discarded_futures
              widget.mutationController.refreshSchedule();
            }
            throw HealthFormException(userMessage);
          case HealthScheduleMutationUiSuccess(
            :final successMessage,
            :final refreshFailed,
            :final refreshWarning,
          ):
            if (!mounted) return;
            if (refreshFailed) {
              AppFeedback.warning(
                context,
                refreshWarning ??
                    HealthScheduleMutationUserCopy.refreshFailedAfterSuccess,
              );
              Navigator.of(
                context,
              ).pop(HealthScheduleItemFormResult.savedRefreshPending);
            } else {
              AppFeedback.success(context, successMessage);
              Navigator.of(context).pop(HealthScheduleItemFormResult.saved);
            }
        }
      },
    );

    if (!ok && mounted) {
      // no-op — erro já no HealthFormActions
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isCreate
        ? HealthScheduleMutationUserCopy.createFormTitle
        : HealthScheduleMutationUserCopy.editFormTitle;

    return ListenableBuilder(
      listenable: _formController,
      builder: (context, _) {
        final submitting = _formController.isSubmitting;
        return HealthFormScaffold(
          title: title,
          controller: _formController,
          accentColor: AppTheme.primary,
          bottomBar: HealthFormActions(
            controller: _formController,
            onSubmit: _submit,
            submitLabel: HealthScheduleMutationUserCopy.saveLabel,
            submittingLabel: HealthScheduleMutationUserCopy.savingLabel,
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HealthFormSection(
                title: 'Agendamento',
                subtitle: _isCreate
                    ? 'Item preventivo manual'
                    : 'Somente campos editáveis',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Edit: tipo compacto read-only no topo (não é input).
                    if (!_isCreate) ...[
                      HealthScheduleTypeReadOnlyHeader(
                        scheduleType: _scheduleType,
                      ),
                      const SizedBox(height: 14),
                    ],

                    // 1. Título
                    HealthFieldLabel(
                      HealthScheduleMutationUserCopy.fieldTitle,
                      required: true,
                    ),
                    TextFormField(
                      key: const ValueKey('schedule-form-title'),
                      controller: _titleController,
                      enabled: !submitting,
                      maxLength: 200,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      decoration: _inputDecoration(hint: 'Ex.: Vacina V10'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 10),

                    // 2. Tipo (somente create — sheet visual)
                    if (_isCreate) ...[
                      HealthScheduleTypePickerField(
                        value: _scheduleType,
                        enabled: !submitting,
                        onChanged: _setType,
                      ),
                      const SizedBox(height: 14),
                    ],

                    // 3. Agendado para
                    HealthDateTimeField(
                      key: const ValueKey('schedule-form-scheduled-for'),
                      label: HealthScheduleMutationUserCopy.fieldScheduledFor,
                      value: _scheduledFor,
                      includeTime: true,
                      required: true,
                      enabled: !submitting,
                      onChanged: _setScheduledFor,
                    ),
                    const SizedBox(height: 14),

                    // 4. Prazo limite
                    HealthDateTimeField(
                      key: const ValueKey('schedule-form-due-until'),
                      label: HealthScheduleMutationUserCopy.fieldDueUntil,
                      value: _dueUntil,
                      includeTime: true,
                      required: false,
                      enabled: !submitting,
                      onChanged: _setDueUntil,
                    ),
                    if (_dueUntil != null) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: submitting
                              ? null
                              : () => _setDueUntil(null),
                          child: Text(
                            'Limpar prazo',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      HealthScheduleMutationUserCopy.fieldTimezoneHint,
                      style: GoogleFonts.inter(
                        color: AppTheme.textTertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // 5. Observações
              HealthFormSection(
                title: 'Observações',
                child: TextFormField(
                  key: const ValueKey('schedule-form-notes'),
                  controller: _notesController,
                  enabled: !submitting,
                  maxLines: 3,
                  maxLength: 1000,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                  decoration: _inputDecoration(
                    hint: 'Opcional — contexto operacional',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        color: AppTheme.textMuted,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.primary, width: 1.2),
      ),
      counterStyle: GoogleFonts.inter(
        color: AppTheme.textTertiary,
        fontSize: 11,
      ),
    );
  }
}
