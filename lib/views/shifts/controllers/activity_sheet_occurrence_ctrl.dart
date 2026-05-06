import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/incidents/domain/occurrence_nature.dart';
import 'package:canil_gcm/services/firestore_service.dart';
import 'package:canil_gcm/services/media_attachment_upload_service.dart';
import 'package:canil_gcm/services/occurrence_event_media_service.dart';
import 'package:canil_gcm/services/storage_service.dart';
import 'package:canil_gcm/services/text_match_service.dart';
import 'package:canil_gcm/utils/firestore_date.dart';
import 'package:canil_gcm/widgets/media_attachment_rows.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_display_text.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_dynamic_rows.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_extra_fields_snapshot.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_form_controller.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_payload_builder.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_progress_update_builder.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_save_validator.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_wizard_result.dart';

// ---------------------------------------------------------------------------
// Subtype constants (espelhados aqui para evitar dependência circular)
// ---------------------------------------------------------------------------
abstract final class _Sub {
  static const detection = 'Busca de Entorpecentes';
  static const narcoticsSearch = 'Narcoticsearch';
  static const other = 'Outros';
}

/// Controller que encapsula todo o estado e lógica da categoria
/// Ocorrência / Evento dentro do [DynamicActivitySheet].
///
/// Opção B: cada categoria tem seus próprios [locationController] e
/// [descriptionController]; o State lê do controller ativo.
class ActivitySheetOccurrenceCtrl {
  ActivitySheetOccurrenceCtrl({
    required this.dogId,
    required this.dogName,
    required this.onStateChanged,
    this.documentId,
    this.initialData,
  });

  // Deps injetadas pelo State
  final String dogId;
  final String dogName;
  final String? documentId;
  final Map<String, dynamic>? initialData;

  /// Chamado sempre que o controller muta estado que a UI precisa refletir.
  final VoidCallback onStateChanged;

  // -------------------------------------------------------------------------
  // TextEditingControllers
  // -------------------------------------------------------------------------
  final locationController = TextEditingController();
  final descriptionController = TextEditingController();
  final timeController = TextEditingController();
  final naturezaController = TextEditingController();
  final equipeController = TextEditingController();
  final boController = TextEditingController();
  final guarnicaoController = TextEditingController();
  final situacaoController = TextEditingController();
  final desfechoController = TextEditingController();
  final odorObjetoController = TextEditingController();
  final tempoDesaparecimentoController = TextEditingController();
  final condicaoTerrenoController = TextEditingController();
  final numeroOsController = TextEditingController();
  final updateController = TextEditingController();
  final publicoController = TextEditingController();
  final temaController = TextEditingController();
  final orgaoController = TextEditingController();

  // -------------------------------------------------------------------------
  // FocusNodes
  // -------------------------------------------------------------------------
  final naturezaFocusNode = FocusNode();
  final updateFocusNode = FocusNode();

  // -------------------------------------------------------------------------
  // Estado de ocorrência
  // -------------------------------------------------------------------------
  List<OccurrenceNature> natures = OccurrenceNatureSeed.items;
  String status = OccurrenceFormController.statusCompleted;
  bool? successful = true;
  final Set<String> selectedOutcomes = {};
  final List<IncidentProgressUpdate> timeline = [];
  String? selectedUpdateTitle;
  bool showFinalization = false;
  bool finishSubmitted = false;
  String? activeIncidentId;
  DateTime? activeStartedAt;
  LatLng? selectedLocationLatLng;
  bool showStartNatureEditor = false;

  // -------------------------------------------------------------------------
  // Listas dinâmicas de resultado
  // -------------------------------------------------------------------------
  final List<Map<String, dynamic>> detecaoDrogas = [];
  final List<Map<String, dynamic>> detainedIndividuals = [];
  final List<Map<String, dynamic>> seizedObjects = [];
  final List<Map<String, dynamic>> detainedVehicles = [];

  // -------------------------------------------------------------------------
  // Controlador de lógica de negócio (puro Dart)
  // -------------------------------------------------------------------------
  final _formCtrl = OccurrenceFormController();
  String? _selectedNature; // ex: 'Busca de Entorpecentes'

  String? get selectedNature => _selectedNature;

  static const List<String> drugOptions = [
    'Maconha',
    'Cocaína',
    'Crack',
    'Sintéticos',
    'Nose MP',
    'Outros',
  ];

  // -------------------------------------------------------------------------
  // Inicialização
  // -------------------------------------------------------------------------

  /// Deve ser chamado durante [initState] do State.
  void init() {
    if (initialData != null) {
      _populate(initialData!);
    } else {
      // Nova ocorrência
      _formCtrl.startNewOccurrence();
      _copyFormCtrlToFields();
    }

    if (initialData?['startedAt'] != null) {
      activeStartedAt = parseFirestoreDate(initialData!['startedAt']);
    } else if (initialData?['_rawDate'] is DateTime) {
      activeStartedAt = initialData!['_rawDate'] as DateTime;
    }
    activeIncidentId = documentId;
  }

  // -------------------------------------------------------------------------
  // Populate (edição de registro existente)
  // -------------------------------------------------------------------------

  void _populate(Map<String, dynamic> data) {
    _populateTimestamp(data);
    _populateEditData(data);
  }

  void _populateTimestamp(Map<String, dynamic> data) {
    final rawDate = data['_rawDate'];
    if (rawDate is DateTime) {
      final h = rawDate.hour.toString().padLeft(2, '0');
      final m = rawDate.minute.toString().padLeft(2, '0');
      timeController.text = '$h:$m';
    }
  }

  void _populateEditData(Map<String, dynamic> data) {
    _selectedNature = OccurrenceFormController.normalizeNature(
      data['type'] ?? _Sub.detection,
    );
    _setNatureTextFromSelected();
    locationController.text = data['location'] ?? '';
    descriptionController.text = data['description'] ?? '';
    status = OccurrenceFormController.normalizeStatus(data['status']);
    successful = data['operationalSuccess'] as bool?;
    showFinalization = status != OccurrenceFormController.statusInProgress;

    if (data['extraFields'] is Map) {
      _populateExtraFields(
        Map<String, dynamic>.from(data['extraFields'] as Map),
      );
    }
    _populateOutcomes(data['outcomes']);
    _populateTimeline(data);
    _syncFormCtrl();
  }

  void _populateOutcomes(dynamic rawOutcomes) {
    if (rawOutcomes is! List) return;
    selectedOutcomes
      ..clear()
      ..addAll(
        List<String>.from(
          rawOutcomes,
        ).map(OccurrenceFormController.normalizeOutcome),
      );
  }

  void _populateTimeline(Map<String, dynamic> data) {
    if (data['progressUpdates'] is List) {
      timeline
        ..clear()
        ..addAll(
          (data['progressUpdates'] as List).map(
            (e) => IncidentProgressUpdate.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          ),
        );
      return;
    }
    if (descriptionController.text.isEmpty) return;
    timeline
      ..clear()
      ..add(
        IncidentProgressUpdate(
          title: 'Registro inicial',
          description: descriptionController.text,
          timestamp: data['_rawDate'] is DateTime
              ? data['_rawDate'] as DateTime
              : DateTime.now(),
          location: locationController.text,
        ),
      );
  }

  void _populateExtraFields(Map<String, dynamic> extra) {
    final snapshot = OccurrenceExtraFieldsSnapshot(extra);
    equipeController.text = snapshot.team;
    boController.text = snapshot.reportNumber;
    guarnicaoController.text = snapshot.supportedGarrison;
    situacaoController.text = snapshot.situation;
    desfechoController.text = snapshot.interventionOutcome;
    odorObjetoController.text = snapshot.odorSource;
    tempoDesaparecimentoController.text = snapshot.missingTime;
    condicaoTerrenoController.text = snapshot.terrainCondition;
    numeroOsController.text = snapshot.serviceOrderNumber;
    publicoController.text = snapshot.publicEstimate;
    temaController.text = snapshot.eventTheme;

    if (_selectedNature == _Sub.other) {
      naturezaController.text = snapshot.manualNatureOrNature();
    }

    if (snapshot.searchType != null) {
      // Armazenado via formData no State — será repassado via formData
    }

    final lat = snapshot.locationLat;
    final lng = snapshot.locationLng;
    if (lat != null && lng != null) {
      selectedLocationLatLng = LatLng(lat, lng);
    }

    final details = snapshot.detailedResults;
    if (details != null) {
      _hydrateDetainedIndividuals(details['individuosDetidos']);
      _hydrateSeizedObjects(details['objetosApreendidos']);
      _hydrateDrugRows(details['drogasApreendidas']);
      _hydrateDetainedVehicles(details['veiculosDetidos']);
    }
    if (detecaoDrogas.isEmpty) {
      _hydrateDrugRows(snapshot.legacyDrugRows);
    }
  }

  // -------------------------------------------------------------------------
  // Natureza da ocorrência
  // -------------------------------------------------------------------------

  void _setNatureTextFromSelected() {
    if (_selectedNature == null) return;
    final n = _selectedOccurrenceNature();
    naturezaController.text = n?.label ?? _selectedNature!;
  }

  void syncNatureFromText() {
    final text = naturezaController.text.trim();
    if (text.isEmpty) {
      _selectedNature = null;
      return;
    }
    final normalized = OccurrenceNature.normalizeForSearch(text);
    final found = natures.cast<OccurrenceNature?>().firstWhere(
      (n) =>
          n != null &&
          (OccurrenceNature.normalizeForSearch(n.label) == normalized ||
              OccurrenceNature.normalizeForSearch(n.name) == normalized ||
              OccurrenceNature.normalizeForSearch(n.code) == normalized),
      orElse: () => null,
    );
    _selectedNature = found?.name ?? text;
  }

  OccurrenceNature? _selectedOccurrenceNature() {
    if (_selectedNature == null || _selectedNature!.trim().isEmpty) return null;
    final normalized = OccurrenceNature.normalizeForSearch(_selectedNature!);
    return natures.cast<OccurrenceNature?>().firstWhere(
      (n) =>
          n != null &&
          (OccurrenceNature.normalizeForSearch(n.name) == normalized ||
              OccurrenceNature.normalizeForSearch(n.label) == normalized),
      orElse: () => null,
    );
  }

  OccurrenceNature? get currentNature => _selectedOccurrenceNature();

  void selectNature(OccurrenceNature option) {
    _selectedNature = option.name;
    naturezaController.text = option.label;
    _formCtrl.selectNature(option.name);
    _copyFormCtrlToFields();
    onStateChanged();
  }

  void selectNatureById(String id) {
    _selectedNature = id;
    _setNatureTextFromSelected();
    _formCtrl.selectNature(id);
    _copyFormCtrlToFields();
    timeline.clear();
    selectedUpdateTitle = null;
    updateController.clear();
    onStateChanged();
  }

  Future<void> loadNatures() async {
    try {
      final remote = await FirestoreService().getOccurrenceNatures();
      if (remote.isEmpty) return;
      natures = remote;
      _setNatureTextFromSelected();
      onStateChanged();
    } catch (e) {
      debugPrint('[OccurrenceCtrl] Erro ao carregar naturezas: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Listas dinâmicas
  // -------------------------------------------------------------------------

  void _replaceDynamicRows(
    List<Map<String, dynamic>> target,
    List<String> keys,
    List<Map<String, dynamic>> next,
  ) {
    OccurrenceDynamicRows.disposeRows(target, keys);
    target
      ..clear()
      ..addAll(next);
  }

  void _hydrateDetainedIndividuals(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(detainedIndividuals, [
      'quantidade',
    ], OccurrenceDynamicRows.hydrateDetainedIndividuals(rows));
  }

  void _hydrateSeizedObjects(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(seizedObjects, [
      'descricao',
      'quantidade',
    ], OccurrenceDynamicRows.hydrateSeizedObjects(rows));
  }

  void _hydrateDrugRows(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(
      detecaoDrogas,
      ['quantidade', 'especificar'],
      OccurrenceDynamicRows.hydrateDrugs(rows, knownOptions: drugOptions),
    );
  }

  void _hydrateDetainedVehicles(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(detainedVehicles, [
      'tipo',
      'placa',
    ], OccurrenceDynamicRows.hydrateDetainedVehicles(rows));
  }

  void addDrug() {
    detecaoDrogas.add(OccurrenceDynamicRows.drug());
    onStateChanged();
  }

  void removeDrug(int index) {
    detecaoDrogas[index]['quantidade'].dispose();
    detecaoDrogas[index]['especificar']?.dispose();
    detecaoDrogas.removeAt(index);
    onStateChanged();
  }

  void addDetainedIndividual() {
    detainedIndividuals.add(OccurrenceDynamicRows.detainedIndividual());
    onStateChanged();
  }

  void addSeizedObject() {
    seizedObjects.add(OccurrenceDynamicRows.seizedObject());
    onStateChanged();
  }

  void addDetainedVehicle() {
    detainedVehicles.add(OccurrenceDynamicRows.detainedVehicle());
    onStateChanged();
  }

  void ensureOutcomeDetailRow(String option) {
    final normalized = const TextMatchService().normalizePtBr(option);
    if (normalized.contains('veiculo') && detainedVehicles.isEmpty) {
      addDetainedVehicle();
    } else if (normalized.contains('detido') && detainedIndividuals.isEmpty) {
      addDetainedIndividual();
    } else if (normalized.contains('objeto') && seizedObjects.isEmpty) {
      addSeizedObject();
    } else if (normalized.contains('droga') && detecaoDrogas.isEmpty) {
      addDrug();
    }
  }

  // -------------------------------------------------------------------------
  // Sincronização com OccurrenceFormController
  // -------------------------------------------------------------------------

  void _syncFormCtrl() {
    _formCtrl.status = status;
    _formCtrl.successful = successful;
    _formCtrl.outcomes
      ..clear()
      ..addAll(selectedOutcomes);
  }

  void _copyFormCtrlToFields({bool includeOutcomes = true}) {
    status = _formCtrl.status;
    successful = _formCtrl.successful;
    if (!includeOutcomes) return;
    selectedOutcomes
      ..clear()
      ..addAll(_formCtrl.outcomes);
  }

  void setStatus(String s) {
    _formCtrl.setStatus(s);
    _copyFormCtrlToFields(includeOutcomes: false);
    onStateChanged();
  }

  List<String> outcomeOptionsForNature(String? subtype) =>
      _formCtrl.outcomeOptionsForNature(subtype);

  String resultSummary({String? fallback}) => _formCtrl.resultSummary(
    nature: _selectedNature,
    fallback: fallback ?? 'Averiguação',
  );

  // -------------------------------------------------------------------------
  // Build de payload (extraFields + Incident)
  // -------------------------------------------------------------------------

  Map<String, dynamic> buildExtraFields({
    required Map<String, dynamic> formData,
    required Map<String, dynamic>? existingExtraFields,
  }) {
    final extra = OccurrencePayloadBuilder.buildExtraFields(
      nature: _selectedNature,
      manualNature: naturezaController.text,
      formData: formData,
      team: equipeController.text,
      bo: boController.text,
      supportedTeam: guarnicaoController.text,
      situation: situacaoController.text,
      interventionOutcome: desfechoController.text,
      odorSource: odorObjetoController.text,
      missingTime: tempoDesaparecimentoController.text,
      searchDuration: '', // Preenchido pelo State via _durationController
      terrainCondition: condicaoTerrenoController.text,
      serviceOrderNumber: numeroOsController.text,
      drugRows: detecaoDrogas,
      detainedIndividuals: detainedIndividuals,
      seizedObjects: seizedObjects,
      detainedVehicles: detainedVehicles,
      existingExtraFields: existingExtraFields,
      publicEstimate: publicoController.text,
      eventTheme: temaController.text,
      locationLat: selectedLocationLatLng?.latitude,
      locationLng: selectedLocationLatLng?.longitude,
    );
    final n = _selectedOccurrenceNature();
    if (n != null) {
      extra['natureza_codigo'] = n.code;
      extra['natureza_nome'] = n.name;
      extra['natureza_grupo'] = n.group;
    }
    return extra;
  }

  Incident buildIncident({
    required String? currentRa,
    required DateTime finalDate,
    required DateTime startedAt,
    required Map<String, dynamic> extraFields,
    required List<Map<String, dynamic>> mediaAttachments,
    required List<IncidentProgressUpdate> progressUpdates,
    required String handlerIdOverride,
  }) {
    _syncFormCtrl();
    return OccurrencePayloadBuilder.buildIncident(
      documentId: activeIncidentId,
      dogId: dogId,
      dogName: dogName,
      handlerId: handlerIdOverride.isNotEmpty
          ? handlerIdOverride
          : (currentRa ?? 'GCM'),
      location: locationController.text.isNotEmpty
          ? locationController.text
          : 'GCM',
      description: descriptionController.text,
      result: resultSummary(
        fallback: (extraFields['Resultado da Busca'] ?? 'Averiguação')
            .toString(),
      ),
      type: _selectedNature,
      extraFields: extraFields,
      mediaAttachments: mediaAttachments,
      status: status,
      operationalSuccess: successful,
      outcomes: selectedOutcomes.toList(),
      startedAt: startedAt,
      updatedAt: finalDate,
      progressUpdates: progressUpdates,
    );
  }

  List<IncidentProgressUpdate> buildProgressUpdates({
    required DateTime finalDate,
    required String authorId,
    required String authorName,
    required bool isNewRecord,
    required bool isEditingExistingRecord,
  }) {
    return OccurrenceProgressUpdateBuilder.build(
      timeline: timeline,
      isNewRecord: isNewRecord,
      isEditingExistingRecord: isEditingExistingRecord,
      timestamp: finalDate,
      description: descriptionController.text,
      location: locationController.text,
      status: status,
      selectedUpdateTitle: selectedUpdateTitle,
      updateNote: updateController.text,
      authorId: authorId,
      authorName: authorName,
    );
  }

  // -------------------------------------------------------------------------
  // Validação
  // -------------------------------------------------------------------------

  void validate() {
    OccurrenceSaveValidator.validate(
      status: status,
      description: descriptionController.text,
      outcomes: selectedOutcomes,
      subtype: _selectedNature,
      natureText: naturezaController.text,
    );
  }

  // -------------------------------------------------------------------------
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
    return MediaAttachmentUploadService(
      storageService: StorageService(),
    ).uploadAll(
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

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

  void dispose() {
    locationController.dispose();
    descriptionController.dispose();
    timeController.dispose();
    naturezaController.dispose();
    equipeController.dispose();
    boController.dispose();
    guarnicaoController.dispose();
    situacaoController.dispose();
    desfechoController.dispose();
    odorObjetoController.dispose();
    tempoDesaparecimentoController.dispose();
    condicaoTerrenoController.dispose();
    numeroOsController.dispose();
    updateController.dispose();
    publicoController.dispose();
    temaController.dispose();
    orgaoController.dispose();
    naturezaFocusNode.dispose();
    updateFocusNode.dispose();
    OccurrenceDynamicRows.disposeDrugs(detecaoDrogas);
    OccurrenceDynamicRows.disposeRows(detainedIndividuals, ['quantidade']);
    OccurrenceDynamicRows.disposeRows(seizedObjects, [
      'descricao',
      'quantidade',
    ]);
    OccurrenceDynamicRows.disposeRows(detainedVehicles, ['tipo', 'placa']);
  }
}
