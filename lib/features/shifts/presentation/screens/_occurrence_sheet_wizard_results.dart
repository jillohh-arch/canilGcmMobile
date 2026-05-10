part of 'dynamic_activity_sheet.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _OccurrenceSheetWizardResults on _DynamicActivitySheetState {
  void _addWizardDrugRow({required String type, required String amount}) {
    if (type.isEmpty && amount.isEmpty) return;
    _detecaoDrogas.add(
      OccurrenceDynamicRows.drug(
        type: type.isEmpty ? 'Maconha' : type,
        amount: amount,
      ),
    );
  }

  void _applyWizardDrugResult(OccurrenceWizardResult wizardResult) {
    if (!wizardResult.containsResult('Droga apreendida')) return;

    _replaceDynamicRows(_detecaoDrogas, ['quantidade', 'especificar'], []);
    final drugDetails = wizardResult.details['drogas'];
    if (drugDetails is List) {
      for (final item in drugDetails) {
        if (item is! Map) continue;
        final data = Map<String, dynamic>.from(item);
        _addWizardDrugRow(
          type: (data['tipo'] ?? '').toString().trim(),
          amount: (data['quantidade'] ?? '').toString().trim(),
        );
      }
    }

    if (_detecaoDrogas.isEmpty) {
      _addWizardDrugRow(
        type: wizardResult.detail('droga_tipo'),
        amount: wizardResult.detail('droga_quantidade'),
      );
    }

    if (_detecaoDrogas.isEmpty) {
      _detecaoDrogas.add(OccurrenceDynamicRows.drug());
    }
  }

  void _applyWizardSeizedObjectResult(OccurrenceWizardResult wizardResult) {
    if (!wizardResult.containsResult('Objetos apreendidos')) return;

    _replaceDynamicRows(_seizedObjects, ['descricao', 'quantidade'], []);
    final descricao = wizardResult.detail('objetos_descricao');
    final quantidade = wizardResult.detail('objetos_quantidade');
    if (descricao.isNotEmpty || quantidade.isNotEmpty) {
      _seizedObjects.add(
        OccurrenceDynamicRows.seizedObject(
          description: descricao,
          amount: quantidade,
        ),
      );
    }
  }

  void _applyWizardDetainedVehicleResult(OccurrenceWizardResult wizardResult) {
    if (!wizardResult.containsResult('Veículo detido')) return;

    _replaceDynamicRows(_detainedVehicles, ['tipo', 'placa'], []);
    final tipo = wizardResult.detail('veiculo_tipo');
    final placa = wizardResult.detail('veiculo_placa');
    if (tipo.isNotEmpty || placa.isNotEmpty) {
      _detainedVehicles.add(
        OccurrenceDynamicRows.detainedVehicle(type: tipo, plate: placa),
      );
    }
  }

  void _applyWizardDetainedIndividualResult(
    OccurrenceWizardResult wizardResult,
  ) {
    if (!wizardResult.containsResult('Indivíduo detido')) return;

    _replaceDynamicRows(_detainedIndividuals, ['quantidade'], []);
    final quantidade = wizardResult.detail('individuo_quantidade');
    if (quantidade.isNotEmpty) {
      _detainedIndividuals.add(
        OccurrenceDynamicRows.detainedIndividual(amount: quantidade),
      );
    }

    final destino = wizardResult.detail('individuo_destino');
    if (destino.isNotEmpty) {
      _formData['Destino do indivíduo'] = destino;
    }
  }

  void _applyWizardAdministrativeDetails(OccurrenceWizardResult wizardResult) {
    final bo = wizardResult.detail('bo_numero');
    if (bo.isNotEmpty) {
      _boController.text = bo;
    }

    final apoio = wizardResult.detail('apoio_observacao');
    if (apoio.isNotEmpty) {
      _formData['Apoio prestado'] = apoio;
    }

    final encaminhamento = wizardResult.detail('encaminhamento_observacao');
    if (encaminhamento.isNotEmpty) {
      _formData['Encaminhamento médico'] = encaminhamento;
    }
  }

  void _applyOccurrenceWizardData(Map<String, dynamic> wizardData) {
    final wizardResult = OccurrenceWizardResult.fromMap(wizardData);
    _occurrenceStatus = OccurrenceFormController.statusCompleted;
    _occCtrl.setStatus(OccurrenceFormController.statusCompleted);

    _descriptionController.text = wizardResult.report;

    _selectedOccurrenceOutcomes
      ..clear()
      ..addAll(wizardResult.results);

    _occurrenceSuccessful = wizardResult.successful;

    _formData['wizard_results'] = wizardResult.results;
    _formData['wizard_details'] = wizardResult.details;

    _applyWizardDrugResult(wizardResult);
    _applyWizardSeizedObjectResult(wizardResult);
    _applyWizardDetainedVehicleResult(wizardResult);
    _applyWizardDetainedIndividualResult(wizardResult);
    _applyWizardAdministrativeDetails(wizardResult);

    _syncOccurrenceController();
  }
}
