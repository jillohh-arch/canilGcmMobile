part of 'dynamic_activity_sheet.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _OccurrenceSheetWizard on _DynamicActivitySheetState {
  Widget _buildOccurrenceNatureStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OccurrenceNatureSearch(
          controller: _naturezaOcorrenciaController,
          focusNode: _occurrenceNatureFocusNode,
          natures: _occurrenceNatures,
          panelColor: _kHudPanel,
          accent: _kHudCyan,
          onChanged: (_) => setState(_syncSelectedOccurrenceNatureFromText),
          onSelected: _selectOccurrenceNature,
          fieldBuilder: (context, controller, focusNode, onChanged) {
            return TacticalTextField(
              controller: controller,
              focusNode: focusNode,
              labelText: 'Natureza da ocorrência',
              prefixIcon: Icons.category_rounded,
              suffixIcon: IconButton(
                icon: const Icon(
                  Icons.search_rounded,
                  color: _kHudCyan,
                  size: 18,
                ),
                onPressed: () => focusNode.requestFocus(),
              ),
              onChanged: onChanged,
            );
          },
        ),
        const SizedBox(height: 14),
        TacticalTextField(
          controller: _equipeController,
          labelText: 'Equipe envolvida',
          prefixIcon: Icons.group_rounded,
        ),
      ],
    );
  }

  Widget _buildOccurrenceCloseStep(bool canShowFinalResults) {
    return OccurrenceCloseWizard(
      isSaving: _isSaving,
      onCancel: () {
        setState(() {
          _occurrenceFinishSubmitted = false;
          _showOccurrenceFinalization = false;
          _occurrenceStatus = OccurrenceFormController.statusInProgress;
          _occurrenceSuccessful = null;
        });
      },
      onFinish: (wizardData) async {
        if (_occurrenceFinishSubmitted || _isSaving) return;
        setState(() {
          _occurrenceFinishSubmitted = true;
          _applyOccurrenceWizardData(wizardData);
        });

        final saved = await _save();
        if (!saved && mounted) {
          setState(() => _occurrenceFinishSubmitted = false);
        }
      },
    );
  }

  void _selectOccurrenceNature(OccurrenceNature option) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedSubtype = option.name;
      _naturezaOcorrenciaController.text = option.label;
      _occCtrl.selectNatureById(option.name);
      _copyOccurrenceControllerToFields();
    });
  }
}
