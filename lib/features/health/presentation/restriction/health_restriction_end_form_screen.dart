import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../domain/health_evidence_file.dart';
import '../shared/evidence/health_evidence_picker.dart';
import '../shared/forms/health_form_controller.dart';
import '../shared/forms/health_form_scaffold.dart';
import '../shared/widgets/health_field_label.dart';
import '../shared/widgets/health_form_actions.dart';
import '../shared/widgets/health_form_section.dart';
import 'health_professional_draft.dart';
import 'health_restriction_end_controller.dart';
// `HealthEvidenceIntent` é a intenção documental compartilhada pelas duas
// verticais. Reusá-la evita um segundo pipeline documental. O seam do picker e o
// mapeamento de rejeição vêm da boundary neutra `shared/evidence`, não da tela
// de emissão.
import 'health_restriction_issue_controller.dart' show HealthEvidenceIntent;
import 'widgets/health_professional_identity_field.dart';

/// Encerramento clínico de uma restrição operacional (B4-C.3).
///
/// END é **liberação clínica documentada**: exige motivo, profissional externo
/// responsável e evidência documental. Não confundir com CANCEL, que é
/// invalidação administrativa e não passa por aqui.
///
/// ## Fases distintas
///
/// Sob o botão único, o [HealthRestrictionEndController] orquestra
/// PREPARE → upload → FINALIZE → END e, depois do commit, a barreira causal de
/// prontidão. Nenhuma dessas etapas aparece como vocabulário para o operador.
///
/// A distinção que esta tela existe para preservar:
///
/// ```text
/// END não commitou        → restrição continua ATIVA        → erro
/// END commitou + convergiu → restrição ENCERRADA            → confirmado
/// END commitou + falhou    → restrição ENCERRADA            → sincronização
///                            convergência não confirmada      pendente
/// ```
///
/// O terceiro caso **nunca** pode ser apresentado como "falha ao encerrar": o
/// comando é fato canônico no backend, e apenas a projeção observável não pôde
/// ser provada.
///
/// Resultado da navegação do encerramento.
///
/// Um `bool` não bastaria: `true`/`null` colapsa "mutation commitada mas
/// convergência não provada" em "encerrado com sucesso" ou, pior, um resultado
/// perdido colapsaria uma mutation commitada em "nada aconteceu". O host precisa
/// dos dois eixos separados para decidir reload e linguagem.
///
/// Ainda assim, a autoridade final sobre `mutationCommitted` é o
/// [HealthRestrictionEndController], que sobrevive ao fechamento desta tela — este
/// resultado é conveniência de navegação, não fonte de verdade.
final class HealthRestrictionEndOutcome {
  const HealthRestrictionEndOutcome({
    required this.mutationCommitted,
    required this.convergenceConfirmed,
  });

  /// O END foi aceito pelo backend. Nunca volta a falso por falha de projeção.
  final bool mutationCommitted;

  /// A projeção de prontidão foi provada causalmente posterior ao END.
  final bool convergenceConfirmed;
}

class HealthRestrictionEndFormScreen extends StatefulWidget {
  const HealthRestrictionEndFormScreen({
    required this.controller,
    required this.dogId,
    required this.dogName,
    required this.restrictionId,
    this.evidencePicker,
    super.key,
  });

  final HealthRestrictionEndController controller;
  final String dogId;
  final String dogName;

  /// Restrição-alvo exata. Nunca derivada de descrição ou posição em lista.
  final String restrictionId;

  /// Seam de teste; em produção usa o picker real.
  final HealthEvidencePicker? evidencePicker;

  @override
  State<HealthRestrictionEndFormScreen> createState() =>
      _HealthRestrictionEndFormScreenState();
}

class _HealthRestrictionEndFormScreenState
    extends State<HealthRestrictionEndFormScreen> {
  final _formController = HealthFormController();
  final _reasonController = TextEditingController();
  final _titleController = TextEditingController();

  HealthProfessionalDraft _professional = const HealthProfessionalDraft();
  SelectedHealthEvidenceFile? _file;
  HealthEvidenceNature? _nature;

  /// Vermelho institucional do fluxo de restrição.
  Color get _accent => AppTheme.error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _formController.dispose();
    _reasonController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _touch() => _formController.markDirty();

  Future<void> _pickFile() async {
    final picker = widget.evidencePicker ?? defaultPickHealthEvidence;
    final result = await picker();
    if (result == null || !mounted) return;

    switch (result) {
      case HealthEvidenceFileAccepted(:final file):
        setState(() => _file = file);
        _touch();
      case HealthEvidenceFileRejected(:final reason):
        // Mesmo mapeamento do fluxo de emissão: um único texto por motivo.
        AppFeedback.warning(context, healthEvidenceRejectionMessage(reason));
    }
  }

  String? _validate() {
    if (_reasonController.text.trim().isEmpty) {
      return 'Informe o motivo do encerramento.';
    }
    final professionalError = _professional.validationError();
    if (professionalError != null) return professionalError;
    if (_file == null) {
      return 'Anexe o documento que fundamenta a liberação clínica.';
    }
    if (_nature == null) return 'Informe a natureza do documento anexado.';
    if (_titleController.text.trim().isEmpty) {
      return 'Informe um título para o documento.';
    }
    return null;
  }

  Future<void> _submit() async {
    final ok = await _formController.submit(
      validate: _validate,
      action: () async {
        final evidence = HealthEvidenceIntent(
          file: _file!,
          nature: _nature!,
          title: _titleController.text.trim(),
        );
        final end = HealthRestrictionEndIntent(
          dogId: widget.dogId,
          restrictionId: widget.restrictionId,
          endReason: _reasonController.text.trim(),
          endProfessional: _professional.toProfessionalIdentity(),
        );

        final success = await widget.controller.submit(
          evidence: evidence,
          end: end,
        );
        if (!success) {
          final failure = widget.controller.failure;
          throw HealthFormException(
            failure?.message ??
                'Não foi possível encerrar a restrição. Tente novamente.',
          );
        }
      },
    );

    if (!ok || !mounted) return;

    // Daqui em diante o END é fato canônico. A convergência pode ter falhado, e
    // isso NÃO é falha de encerramento — o retorno leva os dois eixos separados
    // para que o detalhe recarregue e apresente a pendência de sincronização.
    final convergence = widget.controller.convergence;
    final converged = convergence.isConverged;
    if (converged) {
      AppFeedback.success(context, 'Restrição encerrada.');
    } else {
      AppFeedback.warning(
        context,
        'Restrição encerrada. Prontidão ainda não sincronizada.',
      );
    }
    Navigator.pop(
      context,
      HealthRestrictionEndOutcome(
        // `mutationCommitted` vem do coordenador, não de `ok`: é o fato durável
        // da sessão, e nunca é derivado do resultado da barreira causal.
        mutationCommitted: convergence.mutationCommitted,
        convergenceConfirmed: converged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HealthFormScaffold(
      title: 'Encerrar restrição',
      controller: _formController,
      accentColor: _accent,
      bottomBar: HealthFormActions(
        controller: _formController,
        onSubmit: _submit,
        submitLabel: 'ENCERRAR RESTRIÇÃO',
        submittingLabel: 'ENCERRANDO...',
        accentColor: _accent,
      ),
      body: ListenableBuilder(
        listenable: _formController,
        builder: (context, _) {
          final busy = _formController.isSubmitting;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              _reasonSection(busy),
              _professionalSection(busy),
              _evidenceSection(busy),
            ],
          );
        },
      ),
    );
  }

  Widget _header() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_outlined, color: _accent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.dogName,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Liberação clínica documentada. Não é cancelamento de '
                  'registro.',
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reasonSection(bool busy) {
    return HealthFormSection(
      title: 'Motivo do encerramento',
      accentColor: _accent,
      subtitle: 'Fundamento clínico da liberação.',
      child: TextField(
        key: const Key('restriction_end_reason'),
        controller: _reasonController,
        enabled: !busy,
        maxLines: 3,
        maxLength: 500,
        onChanged: (_) => _touch(),
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
        decoration: const InputDecoration(
          hintText: 'Ex.: Alta clínica confirmada após reavaliação.',
        ),
      ),
    );
  }

  Widget _professionalSection(bool busy) {
    return HealthFormSection(
      title: 'Profissional responsável',
      accentColor: _accent,
      subtitle: 'Profissional externo que decidiu a liberação.',
      child: HealthProfessionalIdentityField(
        draft: _professional,
        enabled: !busy,
        accentColor: _accent,
        onChanged: (draft) {
          setState(() => _professional = draft);
          _touch();
        },
      ),
    );
  }

  Widget _evidenceSection(bool busy) {
    final file = _file;
    return HealthFormSection(
      title: 'Evidência documental',
      accentColor: _accent,
      subtitle: 'Atestado ou laudo que fundamenta a liberação. Até 20 MB.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (file == null)
            OutlinedButton.icon(
              key: const Key('restriction_end_pick_file'),
              onPressed: busy ? null : _pickFile,
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: const Text('Selecionar arquivo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: BorderSide(color: _accent.withValues(alpha: 0.7)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            )
          else
            Container(
              key: const Key('restriction_end_selected_file'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.surfacePanelStrong,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.outline.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    size: 20,
                    color: AppTheme.textSoft,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      file.name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  if (!busy)
                    IconButton(
                      key: const Key('restriction_end_clear_file'),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: AppTheme.textSoft,
                      onPressed: () {
                        setState(() => _file = null);
                        _touch();
                      },
                    ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          const HealthFieldLabel('Natureza do documento', required: true),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final nature in HealthEvidenceNature.values)
                ChoiceChip(
                  label: Text(_natureLabel(nature)),
                  selected: _nature == nature,
                  onSelected: busy
                      ? null
                      : (_) {
                          setState(() => _nature = nature);
                          _touch();
                        },
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: _nature == nature
                        ? Colors.white
                        : AppTheme.textSoft,
                  ),
                  selectedColor: _accent,
                  backgroundColor: AppTheme.surfacePanelStrong,
                  side: BorderSide(
                    color: _nature == nature
                        ? _accent
                        : AppTheme.outline.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const HealthFieldLabel('Título do documento', required: true),
          const SizedBox(height: 6),
          TextField(
            key: const Key('restriction_end_document_title'),
            controller: _titleController,
            enabled: !busy,
            maxLength: 120,
            onChanged: (_) => _touch(),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Ex.: Atestado de alta clínica',
            ),
          ),
        ],
      ),
    );
  }

  String _natureLabel(HealthEvidenceNature nature) => switch (nature) {
    HealthEvidenceNature.certificate => 'Atestado veterinário',
    HealthEvidenceNature.report => 'Laudo veterinário',
    HealthEvidenceNature.other => 'Documento de liberação',
  };
}
