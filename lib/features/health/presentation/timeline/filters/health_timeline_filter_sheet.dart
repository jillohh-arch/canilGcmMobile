import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_labels.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_filter_session.dart';
import 'package:canil_gcm/features/health/presentation/timeline/filters/health_timeline_period_preset.dart';

/// Abre o modal de filtros (draft). Retorna true se aplicou.
Future<bool> showHealthTimelineFilterSheet({
  required BuildContext context,
  required HealthTimelineFilterSession session,
}) async {
  session.openDraft();
  final applied = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surfacePanel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: HealthTimelineFilterSheet(session: session),
      );
    },
  );
  if (applied != true) {
    session.cancelDraft();
    return false;
  }
  return true;
}

/// Conteúdo do modal de filtros (draft).
class HealthTimelineFilterSheet extends StatefulWidget {
  const HealthTimelineFilterSheet({super.key, required this.session});

  final HealthTimelineFilterSession session;

  @override
  State<HealthTimelineFilterSheet> createState() =>
      _HealthTimelineFilterSheetState();
}

class _HealthTimelineFilterSheetState extends State<HealthTimelineFilterSheet> {
  HealthTimelinePeriodPreset _preset = HealthTimelinePeriodPreset.allHistory;
  DateTime? _customStart;
  DateTime? _customEnd;
  String? _periodError;
  bool _applying = false;

  HealthTimelineFilterSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    _inferPresetFromDraft();
  }

  void _inferPresetFromDraft() {
    final draft = session.draft;
    _preset = draft.periodOrigin;
    if (_preset == HealthTimelinePeriodPreset.custom &&
        !draft.period.isUnbounded) {
      _customStart = draft.period.start;
      _customEnd = draft.period.end;
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceWhiteBorder,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Filtros',
                          style: GoogleFonts.inter(
                            color: AppTheme.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: 'Limpar filtros do rascunho',
                        child: TextButton(
                          onPressed: () {
                            session.clearDraft();
                            setState(() {
                              _preset = HealthTimelinePeriodPreset.allHistory;
                              _customStart = null;
                              _customEnd = null;
                              _periodError = null;
                            });
                          },
                          child: Text(
                            'LIMPAR',
                            style: GoogleFonts.inter(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Tipos',
                          style: GoogleFonts.inter(
                            color: AppTheme.textSoft,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final type
                                in HealthTimelineFilterLabels.selectableTypes)
                              _TypeChip(
                                label: HealthTimelineFilterLabels.typeLabel(
                                  type,
                                ),
                                selected: session.draft.types.contains(type),
                                onTap: () => session.toggleDraftType(type),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Período',
                          style: GoogleFonts.inter(
                            color: AppTheme.textSoft,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final preset
                                in HealthTimelinePeriodPreset.values)
                              _TypeChip(
                                label: HealthTimelineFilterLabels.presetLabel(
                                  preset,
                                ),
                                selected: _preset == preset,
                                onTap: () => _selectPreset(preset),
                              ),
                          ],
                        ),
                        if (_preset == HealthTimelinePeriodPreset.custom) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _DateField(
                                  label: 'Início',
                                  value: _customStart,
                                  onPick: () => _pickDate(isStart: true),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _DateField(
                                  label: 'Fim',
                                  value: _customEnd,
                                  onPick: () => _pickDate(isStart: false),
                                ),
                              ),
                            ],
                          ),
                          if (_periodError != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _periodError!,
                              style: GoogleFonts.inter(
                                color: AppTheme.error,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                        if (session.draft.hasCaseId) ...[
                          const SizedBox(height: 16),
                          _ContextualRow(
                            label: 'Caso clínico',
                            onClear: () => session.setDraftCaseId(null),
                          ),
                        ],
                        if (session.draft.hasProfessional) ...[
                          const SizedBox(height: 10),
                          _ContextualRow(
                            label:
                                HealthTimelineFilterLabels.professionalChipLabel(
                                  session.draft.professional!,
                                ),
                            onClear: () => session.setDraftProfessional(null),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _applying
                              ? null
                              : () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textSecondary,
                            side: const BorderSide(
                              color: AppTheme.surfaceWhiteBorder,
                            ),
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: Text(
                            'CANCELAR',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _applying ? null : _onApply,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: AppTheme.textPrimary,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: _applying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.textPrimary,
                                  ),
                                )
                              : Text(
                                  'APLICAR FILTROS',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _selectPreset(HealthTimelinePeriodPreset preset) {
    setState(() {
      _preset = preset;
      _periodError = null;
      if (preset != HealthTimelinePeriodPreset.custom) {
        final period = HealthTimelinePeriodPresets.resolve(
          preset,
          now: session.now(),
        );
        session.setDraftPeriod(period, origin: preset);
      }
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_customStart ?? session.now())
        : (_customEnd ?? session.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _customStart = picked;
      } else {
        _customEnd = picked;
      }
      _periodError = null;
    });
  }

  Future<void> _onApply() async {
    if (_preset == HealthTimelinePeriodPreset.custom) {
      final err = HealthTimelinePeriodPresets.validateCustom(
        start: _customStart,
        end: _customEnd,
      );
      if (err != null) {
        setState(() => _periodError = err);
        return;
      }
      final period = HealthTimelinePeriodPresets.customInclusive(
        start: _customStart!,
        end: _customEnd!,
      );
      session.setDraftPeriod(period, origin: HealthTimelinePeriodPreset.custom);
    }

    setState(() => _applying = true);
    try {
      await session.apply();
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: AppTheme.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.14)
                  : AppTheme.surfacePanelSoft,
              border: Border.all(
                color: selected
                    ? AppTheme.primary.withValues(alpha: 0.55)
                    : AppTheme.surfaceWhiteBorder,
              ),
            ),
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? 'Selecionar'
        : '${value!.day.toString().padLeft(2, '0')}/'
              '${value!.month.toString().padLeft(2, '0')}/'
              '${value!.year}';
    return Semantics(
      button: true,
      label: '$label: $text',
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextualRow extends StatelessWidget {
  const _ContextualRow({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppTheme.surfacePanelSoft,
        border: Border.all(color: AppTheme.surfaceWhiteBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Remover $label',
            child: IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded, size: 18),
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
