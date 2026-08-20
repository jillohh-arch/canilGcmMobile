import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../domain/health_evidence_file.dart';
import '../../domain/health_v1_enums_ext.dart';
import '../shared/evidence/health_evidence_picker.dart';
import '../shared/forms/health_form_controller.dart';
import '../shared/forms/health_form_scaffold.dart';
import '../shared/widgets/health_date_time_field.dart';
import '../shared/widgets/health_field_label.dart';
import '../shared/widgets/health_form_actions.dart';
import '../shared/widgets/health_form_section.dart';
import 'health_professional_draft.dart';
import 'health_restriction_issue_controller.dart';
import 'health_restriction_labels.dart';
import 'widgets/health_professional_identity_field.dart';

// `HealthEvidencePicker`, `defaultPickHealthEvidence` e
// `healthEvidenceRejectionMessage` vivem na boundary neutra
// `shared/evidence/health_evidence_picker.dart`. Emissão e encerramento a
// consomem como irmãs; nenhuma das duas telas importa a outra.

/// Registro de restrição operacional (B3).
///
/// Sob o botão único, a tela orquestra PREPARE → upload → FINALIZE → ISSUE via
/// [HealthRestrictionIssueController]. Nenhuma dessas etapas aparece como
/// vocabulário para o operador.
final class HealthRestrictionFormScreen extends StatefulWidget {
  const HealthRestrictionFormScreen({
    super.key,
    required this.dogId,
    required this.controller,
    this.dogName,
    this.evidencePicker,
  });

  final String dogId;
  final String? dogName;
  final HealthRestrictionIssueController controller;
  final HealthEvidencePicker? evidencePicker;

  @override
  State<HealthRestrictionFormScreen> createState() =>
      _HealthRestrictionFormScreenState();
}

class _HealthRestrictionFormScreenState
    extends State<HealthRestrictionFormScreen> {
  final _formController = HealthFormController();
  final _descriptionController = TextEditingController();
  final _titleController = TextEditingController();
  final _activityController = TextEditingController();

  // Nível e categoria começam sem seleção: ambos são afirmação clínica do
  // operador, não default do sistema.
  RestrictionLevel? _level;
  RestrictionCategory? _category;
  final List<String> _activities = <String>[];
  DateTime? _expectedEnd;
  HealthProfessionalDraft _professional = const HealthProfessionalDraft();

  SelectedHealthEvidenceFile? _file;
  HealthEvidenceNature? _nature;
  String? _fileRejection;
  bool _titleTouched = false;

  Color get _accent => AppTheme.error;

  @override
  void dispose() {
    _formController.dispose();
    _descriptionController.dispose();
    _titleController.dispose();
    _activityController.dispose();
    super.dispose();
  }

  void _touch() => _formController.markDirty();

  String get _dogLabel {
    final name = widget.dogName?.trim();
    return (name == null || name.isEmpty) ? 'K9' : name;
  }

  /// Prefill editável do título, derivado da natureza escolhida.
  void _refreshTitlePrefill() {
    if (_titleTouched) return;
    final nature = _nature;
    if (nature == null) return;
    final prefix = switch (nature) {
      HealthEvidenceNature.certificate => 'Atestado veterinário',
      HealthEvidenceNature.report => 'Laudo veterinário',
      HealthEvidenceNature.other => 'Documento de restrição',
    };
    _titleController.text = '$prefix — $_dogLabel';
  }

  Future<void> _pickFile() async {
    final picker = widget.evidencePicker ?? defaultPickHealthEvidence;
    final result = await picker();
    if (!mounted) return;
    if (result == null) return; // cancelado: nenhuma mutação, nenhum erro

    switch (result) {
      case HealthEvidenceFileAccepted(:final file):
        setState(() {
          _file = file;
          _fileRejection = null;
          _refreshTitlePrefill();
        });
        _touch();
      case HealthEvidenceFileRejected(:final reason):
        setState(() {
          _file = null;
          _fileRejection = _rejectionMessage(reason);
        });
    }
  }

  String _rejectionMessage(HealthEvidenceFileRejection reason) =>
      healthEvidenceRejectionMessage(reason);

  void _addActivity() {
    final value = _activityController.text.trim();
    if (value.isEmpty) return;
    final exists = _activities.any(
      (a) => a.toLowerCase() == value.toLowerCase(),
    );
    if (exists) {
      _activityController.clear();
      return;
    }
    setState(() {
      _activities.add(value);
      _activityController.clear();
    });
    _touch();
  }

  void _removeActivity(String value) {
    setState(() => _activities.remove(value));
    _touch();
  }

  /// Validação na ordem visual: leva o operador ao primeiro problema de cima
  /// para baixo.
  String? _validate() {
    if (_level == null) return 'Selecione o nível da restrição.';
    if (_category == null) return 'Selecione a categoria da restrição.';
    if (_descriptionController.text.trim().isEmpty) {
      return 'Descreva a restrição informada pelo profissional.';
    }
    if (_level == RestrictionLevel.partial && _activities.isEmpty) {
      return 'Restrição parcial exige ao menos uma atividade restrita.';
    }
    final professionalError = _professional.validationError();
    if (professionalError != null) return professionalError;
    if (_file == null) {
      return _fileRejection ??
          'Anexe o atestado ou laudo que fundamenta a restrição.';
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
        final restriction = HealthRestrictionIntent(
          dogId: widget.dogId,
          level: _level!,
          category: _category!,
          description: _descriptionController.text.trim(),
          professional: _professional.toProfessionalIdentity(),
          activitiesRestricted: List<String>.unmodifiable(_activities),
          expectedEnd: _expectedEnd,
        );

        final success = await widget.controller.submit(
          evidence: evidence,
          restriction: restriction,
        );
        if (!success) {
          final failure = widget.controller.failure;
          // Mensagem já vem em linguagem operacional, com a etapa embutida.
          throw HealthFormException(
            failure?.message ??
                'Não foi possível registrar a restrição. Tente novamente.',
          );
        }
      },
    );

    if (!ok || !mounted) return;
    AppFeedback.success(context, 'Restrição operacional registrada.');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return HealthFormScaffold(
      title: 'Restrição Operacional',
      controller: _formController,
      accentColor: _accent,
      bottomBar: HealthFormActions(
        controller: _formController,
        onSubmit: _submit,
        submitLabel: 'REGISTRAR RESTRIÇÃO',
        submittingLabel: 'REGISTRANDO...',
        accentColor: _accent,
      ),
      body: ListenableBuilder(
        listenable: _formController,
        builder: (context, _) {
          final busy = _formController.isSubmitting;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dogHeader(),
              _levelSection(busy),
              _categorySection(busy),
              _descriptionSection(busy),
              if (_level == RestrictionLevel.partial) _activitiesSection(busy),
              _expectedEndSection(busy),
              _professionalSection(busy),
              _evidenceSection(busy),
            ],
          );
        },
      ),
    );
  }

  Widget _dogHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanel,
        borderRadius: BorderRadius.circular(10),
        // Borda uniforme: `borderRadius` com lados de cores diferentes é
        // rejeitado pelo framework. O acento vira barra própria abaixo.
        border: Border.all(color: AppTheme.outline.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.gpp_maybe_outlined, color: _accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dogLabel.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'A restrição afeta a prontidão e a autorização de serviço.',
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelSection(bool busy) {
    return HealthFormSection(
      title: 'Nível e impacto',
      accentColor: _accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HealthFieldLabel('Nível da restrição', required: true),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final level in kHealthRestrictionLevelOrder)
                ChoiceChip(
                  key: Key('restriction_level_${level.wireName}'),
                  label: Text(healthRestrictionLevelLabel(level)),
                  selected: _level == level,
                  showCheckmark: false,
                  onSelected: busy
                      ? null
                      : (_) {
                          setState(() => _level = level);
                          _touch();
                        },
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _level == level ? Colors.white : AppTheme.textSoft,
                  ),
                  selectedColor: _accent,
                  backgroundColor: AppTheme.surfacePanelStrong,
                  side: BorderSide(
                    color: _level == level
                        ? _accent
                        : AppTheme.outline.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
          if (_level != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                healthRestrictionLevelSupport(_level!),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _categorySection(bool busy) {
    return HealthFormSection(
      title: 'Categoria',
      accentColor: _accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HealthFieldLabel('Natureza da condição', required: true),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in kHealthRestrictionCategoryOrder)
                ChoiceChip(
                  key: Key('restriction_category_${category.wireName}'),
                  label: Text(healthRestrictionCategoryLabel(category)),
                  selected: _category == category,
                  showCheckmark: false,
                  onSelected: busy
                      ? null
                      : (_) {
                          setState(() => _category = category);
                          _touch();
                        },
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _category == category
                        ? Colors.white
                        : AppTheme.textSoft,
                  ),
                  selectedColor: _accent,
                  backgroundColor: AppTheme.surfacePanelStrong,
                  side: BorderSide(
                    color: _category == category
                        ? _accent
                        : AppTheme.outline.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _descriptionSection(bool busy) {
    return HealthFormSection(
      title: 'Descrição',
      accentColor: _accent,
      subtitle:
          'Registre de forma objetiva a limitação ou condição informada '
          'pelo profissional.',
      child: TextFormField(
        key: const Key('restriction_description'),
        controller: _descriptionController,
        enabled: !busy,
        minLines: 3,
        maxLines: 6,
        maxLength: 2000,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Ex.: Lesão em membro anterior direito, sem apoio de carga.',
          hintStyle: const TextStyle(color: AppTheme.textSoft, fontSize: 13),
          filled: true,
          fillColor: AppTheme.surfacePanelStrong,
          counterText: '',
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: AppTheme.outline.withValues(alpha: 0.6),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: _accent, width: 1.4),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: AppTheme.outline.withValues(alpha: 0.3),
            ),
          ),
        ),
        onChanged: (_) => _touch(),
      ),
    );
  }

  Widget _activitiesSection(bool busy) {
    return HealthFormSection(
      title: 'Atividades restritas',
      accentColor: _accent,
      subtitle:
          'Informe quais atividades ficam limitadas. '
          'Obrigatório para restrição parcial.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('restriction_activity_input'),
                  controller: _activityController,
                  enabled: !busy,
                  maxLength: 120,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _addActivity(),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ex.: busca em área',
                    hintStyle: const TextStyle(
                      color: AppTheme.textSoft,
                      fontSize: 13,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: AppTheme.surfacePanelStrong,
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppTheme.outline.withValues(alpha: 0.6),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _accent, width: 1.4),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppTheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  key: const Key('restriction_activity_add'),
                  onPressed: busy ? null : _addActivity,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Adicionar',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          if (_activities.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final activity in _activities)
                  InputChip(
                    key: Key('restriction_activity_chip_$activity'),
                    label: Text(activity),
                    onDeleted: busy ? null : () => _removeActivity(activity),
                    deleteIconColor: AppTheme.textSoft,
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textPrimary,
                    ),
                    backgroundColor: AppTheme.surfacePanelStrong,
                    side: BorderSide(
                      color: AppTheme.outline.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _expectedEndSection(bool busy) {
    return HealthFormSection(
      title: 'Previsão de término',
      accentColor: _accent,
      subtitle:
          'Apenas uma previsão. A restrição permanece ativa até liberação '
          'ou cancelamento explícito.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HealthDateTimeField(
            label: 'Data prevista',
            value: _expectedEnd,
            enabled: !busy,
            accentColor: _accent,
            hintText: 'Opcional',
            onChanged: (value) {
              setState(() => _expectedEnd = value);
              _touch();
            },
          ),
          if (_expectedEnd != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('restriction_expected_end_clear'),
                onPressed: busy
                    ? null
                    : () {
                        setState(() => _expectedEnd = null);
                        _touch();
                      },
                child: const Text(
                  'Limpar previsão',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSoft),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _professionalSection(bool busy) {
    return HealthFormSection(
      title: 'Profissional responsável',
      accentColor: _accent,
      subtitle: 'Profissional externo que decidiu a restrição.',
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
      subtitle: 'Atestado ou laudo que fundamenta a restrição. Até 20 MB.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (file == null)
            OutlinedButton.icon(
              key: const Key('restriction_pick_file'),
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
              key: const Key('restriction_selected_file'),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _fileSizeLabel(file.sizeBytes),
                          style: const TextStyle(
                            color: AppTheme.textSoft,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('restriction_change_file'),
                    onPressed: busy ? null : _pickFile,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                    color: AppTheme.textSoft,
                    tooltip: 'Trocar arquivo',
                  ),
                ],
              ),
            ),
          if (_fileRejection != null) ...[
            const SizedBox(height: 8),
            Text(
              _fileRejection!,
              key: const Key('restriction_file_rejection'),
              style: TextStyle(color: _accent, fontSize: 12, height: 1.3),
            ),
          ],
          const SizedBox(height: 14),

          const HealthFieldLabel('Natureza do documento', required: true),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final nature in HealthEvidenceNature.values)
                ChoiceChip(
                  key: Key('restriction_nature_${nature.wireName}'),
                  label: Text(nature.label),
                  selected: _nature == nature,
                  showCheckmark: false,
                  onSelected: busy
                      ? null
                      : (_) {
                          setState(() {
                            _nature = nature;
                            _refreshTitlePrefill();
                          });
                          _touch();
                        },
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
          TextFormField(
            key: const Key('restriction_document_title'),
            controller: _titleController,
            enabled: !busy,
            maxLength: 200,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Ex.: Atestado veterinário — Bono',
              hintStyle: const TextStyle(
                color: AppTheme.textSoft,
                fontSize: 13,
              ),
              isDense: true,
              filled: true,
              fillColor: AppTheme.surfacePanelStrong,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppTheme.outline.withValues(alpha: 0.6),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: _accent, width: 1.4),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppTheme.outline.withValues(alpha: 0.3),
                ),
              ),
            ),
            onChanged: (_) {
              _titleTouched = true;
              _touch();
            },
          ),
        ],
      ),
    );
  }

  String _fileSizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
