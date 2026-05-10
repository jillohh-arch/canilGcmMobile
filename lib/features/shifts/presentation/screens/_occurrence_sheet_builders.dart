part of 'dynamic_activity_sheet.dart';

// ignore_for_file: unused_element, invalid_use_of_protected_member

extension _OccurrenceSheetBuilders on _DynamicActivitySheetState {
  Widget _buildOccurrenceFormScaffold() {
    final tColor = _getCategoryColor();
    final isNewRecord = widget.documentId == null;

    return OccurrenceFormScaffold(
      backgroundColor: _kHudBackground,
      panelColor: _kHudPanel,
      accentColor: _kHudCyan,
      showTopBar: !_hasActiveOccurrenceRecord,
      isSaving: _isSaving,
      modeLabel: ActivityFormLabels.occurrenceModeLabel(
        isNewRecord: isNewRecord,
      ),
      statusLabel: ActivityFormLabels.occurrenceStatusLabel(
        occurrenceStatus: _occurrenceStatus,
        isNewRecord: isNewRecord,
      ),
      content: _buildOccurrenceStepperContent(tColor, includeControls: false),
      footer: _showOccurrenceFinalization
          ? null
          : _buildOccurrenceActiveFooter(tColor),
      onBack: () => _closeForm(false),
    );
  }

  Widget _buildOccurrenceStepperContent(
    Color tColor, {
    bool includeControls = true,
  }) {
    final canShowFinalResults = _descriptionController.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, includeControls ? 28 : 18),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showOccurrenceFinalization)
              _buildOccurrenceFinalizationPanel(tColor, canShowFinalResults)
            else
              _buildOccurrenceActivePanel(tColor),
            if (includeControls) ...[
              const SizedBox(height: 16),
              _buildOccurrenceActiveFooter(tColor),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOccurrenceActivePanel(Color tColor) {
    if (!_hasActiveOccurrenceRecord) {
      return _buildOccurrenceStartScreenV2(tColor);
    }

    return OccurrenceActivePanel(
      commandHeader: _buildOccurrenceCommandHeader(tColor),
      contextSummary: _buildOccurrenceActiveContextSummary(tColor),
      quickActions: _buildOccurrenceQuickActionGrid(tColor),
      timelinePreview: _occurrenceTimeline.isEmpty
          ? const []
          : [
              OccurrenceTimelinePreview(
                updates: _occurrenceTimeline,
                accent: _getCategoryColor(),
                onEventTap: _openOccurrenceEventDetails,
              ),
            ],
    );
  }

  Widget _buildOccurrenceFinalizationPanel(
    Color tColor,
    bool canShowFinalResults,
  ) {
    return OccurrenceFinalizationPanel(
      commandHeader: _buildOccurrenceCommandHeader(
        tColor,
        showOperationalMetrics: true,
      ),
      closeStep: _buildOccurrenceCloseStep(canShowFinalResults),
    );
  }

  Widget _buildOccurrenceActiveFooter(Color tColor) {
    return OccurrenceActiveFooter(
      showFinalization: _showOccurrenceFinalization,
      hasActiveOccurrenceRecord: _hasActiveOccurrenceRecord,
      isSaving: _isSaving,
      accentColor: tColor,
      backgroundColor: _kHudBackground,
      dangerColor: _kHudRed,
      saveStatusPanel: _buildSaveStatusPanel(tColor),
      finalSaveButton: _buildPrimarySaveButton(_kHudRed),
      onCancelFinalization: () => setState(() {
        _showOccurrenceFinalization = false;
        _occurrenceStatus = OccurrenceFormController.statusInProgress;
        _occurrenceSuccessful = null;
      }),
      onStartOccurrence: _saveOccurrenceInProgress,
      onRequestFinalization: () {
        setState(() {
          _occurrenceFinishSubmitted = false;
          _showOccurrenceFinalization = true;
          _occurrenceStatus = OccurrenceFormController.statusCompleted;
          _occCtrl.setStatus(OccurrenceFormController.statusCompleted);
          _copyOccurrenceControllerToFields(includeOutcomes: false);
        });
      },
    );
  }
}
