import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/occurrences/data/amendment_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/amendment.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';

/// Tela para criar um aditamento/retificação em uma ocorrência selada.
/// Permite ao condutor titular corrigir campos específicos com motivo.
class CreateAmendmentScreen extends StatefulWidget {
  final Occurrence occurrence;

  const CreateAmendmentScreen({super.key, required this.occurrence});

  @override
  State<CreateAmendmentScreen> createState() => _CreateAmendmentScreenState();
}

class _CreateAmendmentScreenState extends State<CreateAmendmentScreen> {
  final _reasonController = TextEditingController();
  final _corrections = <_CorrectionEntry>[];
  final _repository = AmendmentRepository();
  bool _isSaving = false;

  static const _editableFields = [
    _FieldOption('type_name', 'Natureza'),
    _FieldOption('location_address', 'Endereço'),
    _FieldOption('dog_name', 'Cão'),
    _FieldOption('handler_name', 'Condutor'),
    _FieldOption('final_report', 'Relatório final'),
    _FieldOption('initial_observation', 'Observação inicial'),
  ];

  @override
  void dispose() {
    _reasonController.dispose();
    for (final c in _corrections) {
      c.dispose();
    }
    super.dispose();
  }

  void _addCorrection() {
    setState(() {
      _corrections.add(_CorrectionEntry());
    });
  }

  void _removeCorrection(int index) {
    setState(() {
      _corrections[index].dispose();
      _corrections.removeAt(index);
    });
  }

  String? _getOldValue(String fieldKey) {
    final occ = widget.occurrence;
    switch (fieldKey) {
      case 'type_name':
        return occ.typeName;
      case 'location_address':
        return occ.locationAddress;
      case 'dog_name':
        return occ.dogId; // Será exibido como referência
      case 'handler_name':
        return occ.primaryHandlerId;
      case 'final_report':
        return occ.finalReport;
      case 'initial_observation':
        return occ.initialObservation;
      default:
        return null;
    }
  }

  bool get _isValid {
    if (_reasonController.text.trim().isEmpty) return false;
    if (_corrections.isEmpty) return false;
    return _corrections.every(
      (c) =>
          c.selectedField != null &&
          c.newValueController.text.trim().isNotEmpty,
    );
  }

  Future<void> _save() async {
    if (!_isValid || _isSaving) return;

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      final corrections = <String, AmendmentCorrection>{};
      for (final c in _corrections) {
        final fieldKey = c.selectedField!;
        corrections[fieldKey] = AmendmentCorrection(
          oldValue: _getOldValue(fieldKey),
          newValue: c.newValueController.text.trim(),
          description: c.descriptionController.text.trim().isNotEmpty
              ? c.descriptionController.text.trim()
              : null,
        );
      }

      final amendment = await _repository.create(
        occurrenceId: widget.occurrence.id,
        reason: _reasonController.text.trim(),
        corrections: corrections,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Retificação #${amendment.sequenceNumber} criada com sucesso',
            ),
            backgroundColor: AppTheme.successOperational,
          ),
        );
        Navigator.of(context).pop(amendment);
      }
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppTheme.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao criar retificação: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfacePanelStrong,
      appBar: AppBar(
        backgroundColor: AppTheme.surfacePanelSoft,
        title: Text(
          'Nova Retificação',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info da ocorrência
            _buildOccurrenceInfo(),
            const SizedBox(height: 24),

            // Motivo
            _buildSectionLabel('MOTIVO DA RETIFICAÇÃO'),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _reasonController,
              hint: 'Descreva o motivo da correção...',
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // Correções
            _buildSectionLabel('CORREÇÕES'),
            const SizedBox(height: 8),
            ..._corrections.asMap().entries.map(
              (entry) => _buildCorrectionCard(entry.key, entry.value),
            ),
            const SizedBox(height: 12),
            _buildAddCorrectionButton(),
            const SizedBox(height: 32),

            // Botão salvar
            _buildSaveButton(),
            const SizedBox(height: 16),

            // Aviso
            _buildWarningNote(),
          ],
        ),
      ),
    );
  }

  Widget _buildOccurrenceInfo() {
    final occ = widget.occurrence;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.textPrimary.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            occ.typeName,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ID: ${occ.id.substring(0, 8)}... · Selada',
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary.withAlpha(100),
              fontSize: 11,
            ),
          ),
          if (occ.integrityHash != null) ...[
            const SizedBox(height: 4),
            Text(
              'Hash: ${occ.integrityHash!.substring(0, 16)}...',
              style: TextStyle(
                color: AppTheme.primary.withAlpha(150),
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: AppTheme.primary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: (_) => setState(() {}),
      style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(
          color: AppTheme.textPrimary.withAlpha(97),
          fontSize: 14,
        ),
        filled: true,
        fillColor: AppTheme.textPrimary.withAlpha(8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.textPrimary.withAlpha(20)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.textPrimary.withAlpha(20)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildCorrectionCard(int index, _CorrectionEntry correction) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.textPrimary.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Correção ${index + 1}',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _removeCorrection(index),
                child: Icon(
                  Icons.close,
                  color: AppTheme.textPrimary.withAlpha(100),
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Campo a corrigir
          DropdownButtonFormField<String>(
            initialValue: correction.selectedField,
            dropdownColor: AppTheme.surfacePanelSoft,
            style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Campo',
              labelStyle: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(138),
                fontSize: 12,
              ),
              filled: true,
              fillColor: AppTheme.textPrimary.withAlpha(8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppTheme.textPrimary.withAlpha(20),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppTheme.textPrimary.withAlpha(20),
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            items: _editableFields
                .map(
                  (f) => DropdownMenuItem(value: f.key, child: Text(f.label)),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                correction.selectedField = value;
              });
            },
          ),
          const SizedBox(height: 12),

          // Valor anterior (read-only)
          if (correction.selectedField != null) ...[
            Text(
              'Valor anterior:',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(138),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.textPrimary.withAlpha(5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _getOldValue(correction.selectedField!) ?? '(vazio)',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary.withAlpha(120),
                  fontSize: 12,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Novo valor
          _buildTextField(
            controller: correction.newValueController,
            hint: 'Novo valor...',
            maxLines: 2,
          ),
          const SizedBox(height: 8),

          // Descrição opcional
          _buildTextField(
            controller: correction.descriptionController,
            hint: 'Justificativa desta correção (opcional)',
          ),
        ],
      ),
    );
  }

  Widget _buildAddCorrectionButton() {
    return GestureDetector(
      onTap: _addCorrection,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppTheme.primary.withAlpha(60),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: AppTheme.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Adicionar correção',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isValid && !_isSaving ? _save : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isValid
              ? AppTheme.primary
              : AppTheme.primary.withAlpha(40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.textPrimary,
                ),
              )
            : Text(
                'CRIAR RETIFICAÇÃO',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildWarningNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warningAccent.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warningAccent.withAlpha(30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: AppTheme.warningAccent,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'A retificação será registrada com hash próprio e não altera '
              'o selo original da ocorrência. O registro original permanece '
              'intacto e auditável.',
              style: GoogleFonts.inter(
                color: AppTheme.warningAccent.withAlpha(180),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CorrectionEntry {
  String? selectedField;
  final TextEditingController newValueController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();

  void dispose() {
    newValueController.dispose();
    descriptionController.dispose();
  }
}

class _FieldOption {
  final String key;
  final String label;

  const _FieldOption(this.key, this.label);
}
