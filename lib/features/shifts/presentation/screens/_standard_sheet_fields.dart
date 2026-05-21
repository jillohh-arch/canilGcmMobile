part of 'dynamic_activity_sheet.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _StandardSheetFields on _DynamicActivitySheetState {
  List<Widget> _buildStandardContextFields() {
    return const [];
  }

  List<Widget> _buildTrainingMetaFields() {
    if (widget.category != 'Treino') {
      return const [];
    }

    return [
      TrainingActivityFields(
        visible: true,
        durationController: _durationController,
      ),
    ];
  }

  List<Widget> _buildHealthMetaFields() {
    if (widget.category != 'Saude') {
      return const [];
    }

    return [
      HealthActivityFields(
        subtype: _selectedSubtype,
        consultationSubtype: ActivitySubtypeIds.consultation,
        vaccineSubtype: ActivitySubtypeIds.vaccine,
        examSubtype: ActivitySubtypeIds.exam,
        bathSubtype: ActivitySubtypeIds.bath,
        accentColor: _kHudCyan,
        responsibleController: _vetNameController,
        reasonController: _motivoController,
        vaccineTypeController: _tipoVacinaController,
        examTypeController: _tipoExameController,
        bathProductsController: _produtosBanhoController,
        returnDateController: _returnDateController,
        selectedVaccine: _selectedVacina,
        onVaccineChanged: (val) => setState(() {
          _healthCtrl.selectedVacina = val;
          _healthCtrl.tipoVacinaController.text = val ?? '';
        }),
        onPickReturnDate: _pickReturnDate,
      ),
    ];
  }

  Future<void> _pickReturnDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF1B8A4C),
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date == null) {
      return;
    }

    _returnDateController.text = _formatDatePtBr(date);
  }

  List<Widget> _buildDynamicFields() {
    if (!DynamicSubtypeFields.handles(_selectedSubtype)) {
      return const [];
    }

    return [
      DynamicSubtypeFields(
        subtype: _selectedSubtype,
        formData: _formData,
        accentColor: _getCategoryColor(),
        odorAccentColor: _kHudAmber,
        objectiveController: _objetivoTreinoController,
        difficultiesController: _dificuldadesController,
        temperatureController: _tempController,
        humidityController: _humidityController,
        onChanged: _setFormDataValue,
        onOdorChanged: (value) {
          setState(() => _formData['Tipo de Odor'] = value);
        },
        onPullWeather: _pullCurrentWeather,
        trackingActionBuilder: _buildTrackingAction,
      ),
    ];
  }

  List<Widget> _buildCategorySpecificFields() {
    return const [];
  }
}
