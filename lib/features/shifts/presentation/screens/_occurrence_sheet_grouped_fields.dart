part of 'dynamic_activity_sheet.dart';

// ignore_for_file: unused_element, invalid_use_of_protected_member

extension _OccurrenceSheetGroupedFields on _DynamicActivitySheetState {
  Widget _buildGroupedFormContent(Color tColor) {
    return ActivityFormBody(
      formKey: _formKey,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_selectedSubtype == ActivitySubtypeIds.detection)
          ..._buildDetecaoGrouped(),
        if (_selectedSubtype == ActivitySubtypeIds.missingPerson)
          ..._buildBuscaPessoaGrouped(),
        ..._buildOccurrenceMetaFields(),
        const SizedBox(height: 32),
        _buildSaveButton(tColor),
      ],
    );
  }

  List<Widget> _buildStandardContextFields() {
    if (!_isOccurrenceCategory) {
      return const [];
    }
    return [
      const SizedBox(height: 16),
      TacticalTextField(
        controller: _naturezaOcorrenciaController,
        labelText: 'Natureza da ocorrência',
        prefixIcon: Icons.category_rounded,
      ),
      ..._buildOccurrenceMetaFields(),
    ];
  }

  List<Widget> _buildOccurrenceMetaFields() {
    if (!_isOccurrenceCategory) {
      return const [];
    }

    final shortcuts = OccurrenceQuickUpdateCatalog.forSubtype(_selectedSubtype);
    return [
      OccurrenceMetaFields(
        status: _occurrenceStatus,
        successful: _occurrenceSuccessful,
        outcomeOptions: _outcomeOptionsForOccurrenceSubtype(_selectedSubtype),
        selectedOutcomes: _selectedOccurrenceOutcomes,
        shortcuts: shortcuts,
        selectedShortcutTitle: _selectedOccurrenceUpdateTitle,
        showUpdateSpacing: _selectedSubtype != null,
        updateController: _occurrenceUpdateController,
        timelineUpdates: _occurrenceTimeline,
        accent: _getCategoryColor(),
        onStatusSelected: (value) {
          setState(() {
            _occCtrl.setStatus(value);
            _copyOccurrenceControllerToFields(includeOutcomes: false);
          });
        },
        onSuccessChanged: (value) {
          setState(() => _occurrenceSuccessful = value);
        },
        onOutcomeToggle: (option) {
          setState(() {
            if (_selectedOccurrenceOutcomes.contains(option)) {
              _selectedOccurrenceOutcomes.remove(option);
            } else {
              _selectedOccurrenceOutcomes.add(option);
              _ensureOutcomeDetailRow(option);
            }
          });
        },
        onShortcutSelected: (title) {
          final shortcut = shortcuts.firstWhere(
            (shortcut) => shortcut.title == title,
          );
          _applyOccurrenceQuickUpdateShortcut(shortcut);
        },
        onEventTap: _openOccurrenceEventDetails,
      ),
    ];
  }

  List<Widget> _buildDetecaoGrouped() {
    return [
      OccurrenceDetectionGroupedSections(
        natureController: _naturezaOcorrenciaController,
        specificFields: _buildCategorySpecificFields(),
        topActionRow: _buildTopActionRow(),
        locationTimeRow: _buildLocationTimeRow(),
        descriptionField: _buildDescriptionField(),
        imageGallery: _buildImageGallery(),
      ),
    ];
  }

  List<Widget> _buildBuscaPessoaGrouped() {
    return [
      OccurrencePersonSearchGroupedSections(
        natureController: _naturezaOcorrenciaController,
        searchCaptureSubtype: ActivitySubtypeIds.searchCapture,
        selectedSearchType: _formData['Tipo de Busca'] as String?,
        accentColor: _getCategoryColor(),
        odorObjectController: _odorObjetoController,
        missingTimeController: _tempoDesaparecimentoController,
        durationController: _durationController,
        terrainConditionController: _condicaoTerrenoController,
        onPullWeather: _pullCurrentWeather,
        onSearchTypeChanged: (value) {
          setState(() {
            if (value == null) {
              _formData.remove('Tipo de Busca');
            } else {
              _formData['Tipo de Busca'] = value;
            }
          });
        },
        topActionRow: _buildTopActionRow(),
        locationTimeRow: _buildLocationTimeRow(),
        trackingAction: _buildTrackingAction(
          startLabel: 'INICIAR RASTREIO TÁTICO',
          startIcon: Icons.satellite_alt_rounded,
          backgroundColor: const Color(0xFFFBBF24),
          foregroundColor: Colors.black,
        ),
        descriptionField: _buildDescriptionField(),
        imageGallery: _buildImageGallery(),
      ),
    ];
  }
}
