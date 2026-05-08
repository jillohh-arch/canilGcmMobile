part of 'activity_sheet_occurrence_ctrl.dart';

extension ActivitySheetOccurrenceWizardMedia on ActivitySheetOccurrenceCtrl {
  // Wizard de encerramento
  // -------------------------------------------------------------------------

  void applyWizardData(Map<String, dynamic> wizardData) {
    final result = OccurrenceWizardResult.fromMap(wizardData);
    status = OccurrenceFormController.statusCompleted;
    _formCtrl.setStatus(OccurrenceFormController.statusCompleted);

    descriptionController.text = result.report;
    selectedOutcomes
      ..clear()
      ..addAll(result.results);
    _formCtrl.outcomes
      ..clear()
      ..addAll(result.results);
    successful = result.successful;

    _applyWizardDrugResult(result);
    _applyWizardSeizedObjectResult(result);
    _applyWizardDetainedVehicleResult(result);
    _applyWizardDetainedIndividualResult(result);
    _syncFormCtrl();
    onStateChanged();
  }

  void _applyWizardDrugResult(OccurrenceWizardResult r) {
    if (!r.containsResult('Droga apreendida')) return;
    _replaceDynamicRows(detecaoDrogas, ['quantidade', 'especificar'], []);
    final list = r.details['drogas'];
    if (list is List) {
      for (final item in list) {
        if (item is! Map) continue;
        final d = Map<String, dynamic>.from(item);
        _addWizardDrugRow(
          type: (d['tipo'] ?? '').toString().trim(),
          amount: (d['quantidade'] ?? '').toString().trim(),
        );
      }
    }
    if (detecaoDrogas.isEmpty) {
      _addWizardDrugRow(
        type: r.detail('droga_tipo'),
        amount: r.detail('droga_quantidade'),
      );
    }
    if (detecaoDrogas.isEmpty) detecaoDrogas.add(OccurrenceDynamicRows.drug());
  }

  void _addWizardDrugRow({required String type, required String amount}) {
    if (type.isEmpty && amount.isEmpty) return;
    detecaoDrogas.add(
      OccurrenceDynamicRows.drug(
        type: type.isEmpty ? 'Maconha' : type,
        amount: amount,
      ),
    );
  }

  void _applyWizardSeizedObjectResult(OccurrenceWizardResult r) {
    if (!r.containsResult('Objetos apreendidos')) return;
    _replaceDynamicRows(seizedObjects, ['descricao', 'quantidade'], []);
    final desc = r.detail('objetos_descricao');
    final qty = r.detail('objetos_quantidade');
    if (desc.isNotEmpty || qty.isNotEmpty) {
      seizedObjects.add(
        OccurrenceDynamicRows.seizedObject(description: desc, amount: qty),
      );
    }
  }

  void _applyWizardDetainedVehicleResult(OccurrenceWizardResult r) {
    if (!r.containsResult('Veículo detido')) return;
    _replaceDynamicRows(detainedVehicles, ['tipo', 'placa'], []);
    final type = r.detail('veiculo_tipo');
    final plate = r.detail('veiculo_placa');
    if (type.isNotEmpty || plate.isNotEmpty) {
      detainedVehicles.add(
        OccurrenceDynamicRows.detainedVehicle(type: type, plate: plate),
      );
    }
  }

  void _applyWizardDetainedIndividualResult(OccurrenceWizardResult r) {
    if (!r.containsResult('Indivíduo detido')) return;
    _replaceDynamicRows(detainedIndividuals, ['quantidade'], []);
    final qty = r.detail('individuo_quantidade');
    if (qty.isNotEmpty) {
      detainedIndividuals.add(
        OccurrenceDynamicRows.detainedIndividual(amount: qty),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Mídia de eventos da linha do tempo
  // -------------------------------------------------------------------------

  Future<List<File>> pickEventPhotos() async {
    final files = await OccurrenceEventMediaService(
      storageService: StorageService(),
    ).pickCompressedPhotos();
    return files;
  }

  Future<List<Map<String, dynamic>>> uploadEventPhotos(List<File> files) async {
    return OccurrenceEventMediaService(
      storageService: StorageService(),
    ).uploadPhotos(files: files, incidentIdOrDogId: activeIncidentId ?? dogId);
  }

  // -------------------------------------------------------------------------
  // Upload de mídias gerais
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> uploadAllMedia({
    required List<Map<String, dynamic>> attachments,
    required String folder,
    required void Function(Map<String, dynamic>) onUploading,
    required void Function(Map<String, dynamic>, String) onUploaded,
    required void Function(Map<String, dynamic>) onPending,
  }) {
    return ActivityMediaUploader.upload(
      attachments: attachments,
      folder: folder,
      onUploading: onUploading,
      onUploaded: onUploaded,
      onPending: onPending,
    );
  }

  /// Mescla mídias já existentes no documento com as recém-enviadas.
  List<Map<String, dynamic>> mergeExistingMedia(
    List<Map<String, dynamic>> uploaded,
  ) {
    return MediaAttachmentRows.mergeExistingWithUploaded(
      existing: initialData?['mediaAttachments'],
      uploaded: uploaded,
    );
  }

  // -------------------------------------------------------------------------
  // Helpers de data / hora
  // -------------------------------------------------------------------------

  DateTime? get occurrenceStartedAt {
    if (activeStartedAt != null) return activeStartedAt;
    final data = initialData;
    if (data == null) return null;
    final raw = data['startedAt'];
    if (raw != null) return parseFirestoreDate(raw);
    final rawDate = data['_rawDate'];
    if (rawDate is DateTime) return rawDate;
    return null;
  }

  DateTime resolveStartedAt(DateTime fallback) =>
      activeStartedAt ??
      (initialData?['startedAt'] != null
          ? parseFirestoreDate(initialData!['startedAt'])
          : initialData?['_rawDate'] ?? fallback);

  // -------------------------------------------------------------------------
  // Display helpers
  // -------------------------------------------------------------------------

  String headerNatureLabel() => OccurrenceDisplayText.headerNatureLabel(
    selectedSubtype: _selectedNature,
    manualNature: naturezaController.text,
  );

  String effectiveNature() =>
      OccurrenceDisplayText.effectiveNature(_selectedNature);

  String elapsedLabel() =>
      OccurrenceDisplayText.elapsedLabel(occurrenceStartedAt);

  // -------------------------------------------------------------------------
  // Badge check
  // -------------------------------------------------------------------------

  bool shouldGrantFaroAfiadoBadge(Map<String, dynamic> extraFields) {
    final hasDetectedDrugs =
        extraFields.containsKey('drogas') &&
        (extraFields['drogas'] as List).isNotEmpty;
    final isDetection =
        _selectedNature == _Sub.detection ||
        _selectedNature == _Sub.narcoticsSearch;
    return isDetection && hasDetectedDrugs;
  }
}
