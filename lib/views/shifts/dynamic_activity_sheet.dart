import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../viewmodels/training_viewmodel.dart';
import '../../models/occurrence_nature.dart';
import '../../viewmodels/incident_viewmodel.dart';
import '../../models/incident.dart';
import '../../viewmodels/health_viewmodel.dart';
import '../../viewmodels/routine_viewmodel.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/user_viewmodel.dart';
import '../../viewmodels/dog_viewmodel.dart';
import '../../services/handler_identity_service.dart';
import '../../services/form_metadata_reader.dart';
import '../../services/location_resolution_service.dart';
import '../../services/media_processing_service.dart';
import '../../services/media_attachment_upload_service.dart';
import '../../services/occurrence_event_media_service.dart';
import '../../services/operator_context_service.dart';
import '../../services/pdf_attachment_service.dart';
import '../../services/pt_br_date_time_service.dart';
import '../../services/speech_dictation_service.dart';
import '../../services/storage_service.dart';
import '../../services/text_match_service.dart';
import '../../services/weather_capture_service.dart';
import '../../utils/firestore_date.dart';
import '../../widgets/activity_form_body.dart';
import '../../widgets/activity_card_catalog.dart';
import '../../widgets/activity_common_fields.dart';
import '../../widgets/activity_category_menu_sheet.dart';
import '../../widgets/activity_form_labels.dart';
import '../../widgets/activity_form_scaffold.dart';
import '../../widgets/activity_save_controls.dart';
import '../../widgets/activity_tracking_action.dart';
import '../../widgets/dynamic_subtype_fields.dart';
import '../../widgets/health_activity_fields.dart';
import '../../widgets/media_attachment_rows.dart';
import '../../widgets/media_attachment_gallery.dart';
import '../../widgets/quick_location_actions.dart';
import '../../widgets/routine_activity_fields.dart';
import '../../widgets/tactical_text_field.dart';
import '../incidents/controllers/occurrence_form_controller.dart';
import '../incidents/controllers/occurrence_display_text.dart';
import '../incidents/controllers/occurrence_dynamic_rows.dart';
import '../incidents/controllers/occurrence_event_draft.dart';
import '../incidents/controllers/occurrence_extra_fields_snapshot.dart';
import '../incidents/controllers/occurrence_payload_builder.dart';
import '../incidents/controllers/occurrence_progress_update_builder.dart';
import '../incidents/controllers/occurrence_save_validator.dart';
import '../incidents/controllers/occurrence_wizard_result.dart';
import '../incidents/widgets/occurrence_command_header.dart';
import '../incidents/widgets/occurrence_active_context_summary.dart';
import '../incidents/widgets/occurrence_active_footer.dart';
import '../incidents/widgets/event_details_bottom_sheet.dart';
import '../incidents/widgets/occurrence_nature_search.dart';
import '../incidents/widgets/occurrence_close_wizard.dart';
import '../incidents/widgets/occurrence_event_center_sheet.dart';
import '../incidents/widgets/occurrence_event_catalog.dart';
import '../incidents/widgets/occurrence_compact_location_block.dart';
import '../incidents/widgets/occurrence_form_scaffold.dart';
import '../incidents/widgets/occurrence_grouped_sections.dart';
import '../incidents/widgets/occurrence_initial_data_sheet.dart';
import '../incidents/widgets/occurrence_location_map_sheet.dart';
import '../incidents/widgets/occurrence_meta_fields.dart';
import '../incidents/widgets/occurrence_timeline_preview.dart';
import '../incidents/widgets/occurrence_quick_action.dart';
import '../incidents/widgets/occurrence_quick_action_catalog.dart';
import '../incidents/widgets/occurrence_quick_action_grid.dart';
import '../incidents/widgets/occurrence_quick_action_options_sheet.dart';
import '../incidents/widgets/occurrence_quick_update_catalog.dart';
import '../incidents/widgets/occurrence_specific_fields.dart';
import '../incidents/widgets/occurrence_stage_panels.dart';
import '../incidents/widgets/occurrence_start_screen.dart';
import 'controllers/activity_sheet_occurrence_ctrl.dart';
import 'controllers/activity_sheet_training_ctrl.dart';
import 'controllers/activity_sheet_routine_ctrl.dart';
import 'controllers/activity_record_payload_builder.dart';
import 'live_tracking_screen.dart';

abstract final class _SheetSubtype {
  static const detection = ActivitySubtypeIds.detection;
  static const missingPerson = ActivitySubtypeIds.missingPerson;
  static const event = ActivitySubtypeIds.event;

  static const scentWork = ActivitySubtypeIds.scentWork;
  static const searchCapture = ActivitySubtypeIds.searchCapture;

  static const consultation = ActivitySubtypeIds.consultation;
  static const vaccine = ActivitySubtypeIds.vaccine;
  static const exam = ActivitySubtypeIds.exam;
  static const bath = ActivitySubtypeIds.bath;

  static const feeding = ActivitySubtypeIds.feeding;
  static const walk = ActivitySubtypeIds.walk;
  static const play = ActivitySubtypeIds.play;
  static const other = ActivitySubtypeIds.other;
  static const narcoticsSearch = ActivitySubtypeIds.narcoticsSearch;
}

class DynamicActivitySheet extends StatefulWidget {
  final String category; // 'Ocorrencia', 'Treino', 'Rotina', 'Evento', 'Saude'
  final String dogId;
  final String dogName;
  final Map<String, dynamic>? initialData;
  final String? documentId;
  final bool fullScreen;

  const DynamicActivitySheet({
    super.key,
    required this.category,
    required this.dogId,
    this.dogName = '',
    this.initialData,
    this.documentId,
    this.fullScreen = false,
  });

  @override
  State<DynamicActivitySheet> createState() => _DynamicActivitySheetState();
}

class _DynamicActivitySheetState extends State<DynamicActivitySheet> {
  static const Color _hudBackground = Color(0xFF070B14);
  static const Color _hudPanel = Color(0xFF0B1220);
  static const Color _hudCyan = Color(0xFF00E5FF);
  static const Color _hudAmber = Color(0xFFFFB84D);
  static const Color _hudGreen = Color(0xFF00F5A0);
  static const Color _hudRed = Color(0xFFFF3B5C);

  final _formKey = GlobalKey<FormState>();

  bool get _isOccurrenceCategory {
    final category = widget.category.toLowerCase();
    return category == 'ocorrencia' || category == 'ocorrência';
  }

  bool get _isExistingOccurrence =>
      _isOccurrenceCategory && widget.documentId != null;

  bool get _hasActiveOccurrenceRecord =>
      _isExistingOccurrence || _activeIncidentId != null;

  // ---------------------------------------------------------------------------
  // Occurrence controller (Fase 1)
  // ---------------------------------------------------------------------------
  late final ActivitySheetOccurrenceCtrl _occCtrl;

  // ---------------------------------------------------------------------------
  // Training controller (Fase 2)
  // ---------------------------------------------------------------------------
  late final ActivitySheetTrainingCtrl _trainingCtrl;

  // ---------------------------------------------------------------------------
  // Routine controller (Fase 3)
  // ---------------------------------------------------------------------------
  late final ActivitySheetRoutineCtrl _routineCtrl;

  // Getters Opção B: o State lê do controller ativo
  TextEditingController get _locationController =>
      _isOccurrenceCategory
          ? _occCtrl.locationController
          : widget.category == 'Treino'
              ? _trainingCtrl.locationController
              : _locationCtrlOther; // Rotina/Saúde não usam location no form
  TextEditingController get _descriptionController =>
      _isOccurrenceCategory
          ? _occCtrl.descriptionController
          : widget.category == 'Treino'
              ? _trainingCtrl.descriptionController
              : widget.category == 'Rotina'
                  ? _routineCtrl.descriptionController
                  : _descriptionCtrlOther;
  TextEditingController get _timeController =>
      _isOccurrenceCategory
          ? _occCtrl.timeController
          : widget.category == 'Treino'
              ? _trainingCtrl.timeController
              : widget.category == 'Rotina'
                  ? _routineCtrl.timeController
                  : _timeCtrlOther;
  // durationController: Treino -> _trainingCtrl, Rotina -> _routineCtrl
  TextEditingController get _durationController =>
      widget.category == 'Treino'
          ? _trainingCtrl.durationController
          : widget.category == 'Rotina'
              ? _routineCtrl.durationController
              : _durationCtrlOther;
  TextEditingController get _tempController => _trainingCtrl.tempController;
  TextEditingController get _humidityController =>
      _trainingCtrl.humidityController;
  TextEditingController get _objetivoTreinoController =>
      _trainingCtrl.objetivoController;
  TextEditingController get _dificuldadesController =>
      _trainingCtrl.dificuldadesController;
  // Rotina: campos específicos
  TextEditingController get _racaoMarcaController =>
      _routineCtrl.racaoMarcaController;
  TextEditingController get _racaoQtdController =>
      _routineCtrl.racaoQtdController;
  TextEditingController get _distanciaController =>
      _routineCtrl.distanciaController;

      _occCtrl.naturezaController;
  FocusNode get _occurrenceNatureFocusNode => _occCtrl.naturezaFocusNode;
  FocusNode get _occurrenceUpdateFocusNode => _occCtrl.updateFocusNode;
  TextEditingController get _occurrenceUpdateController =>
      _occCtrl.updateController;
  TextEditingController get _equipeController => _occCtrl.equipeController;
  TextEditingController get _boController => _occCtrl.boController;
  TextEditingController get _guarnicaoController =>
      _occCtrl.guarnicaoController;
  TextEditingController get _situacaoController => _occCtrl.situacaoController;
  TextEditingController get _desfechoController => _occCtrl.desfechoController;
  TextEditingController get _odorObjetoController =>
      _occCtrl.odorObjetoController;
  TextEditingController get _tempoDesaparecimentoController =>
      _occCtrl.tempoDesaparecimentoController;
  TextEditingController get _condicaoTerrenoController =>
      _occCtrl.condicaoTerrenoController;
  TextEditingController get _numeroOsController =>
      _occCtrl.numeroOsController;
  TextEditingController get _orgaoController => _occCtrl.orgaoController;
  TextEditingController get _publicoController => _occCtrl.publicoController;
  TextEditingController get _temaController => _occCtrl.temaController;

  // Getters de listas e estado de ocorrência
  List<Map<String, dynamic>> get _detecaoDrogas => _occCtrl.detecaoDrogas;
  List<Map<String, dynamic>> get _detainedIndividuals =>
      _occCtrl.detainedIndividuals;
  List<Map<String, dynamic>> get _seizedObjects => _occCtrl.seizedObjects;
  List<Map<String, dynamic>> get _detainedVehicles =>
      _occCtrl.detainedVehicles;
  List<IncidentProgressUpdate> get _occurrenceTimeline => _occCtrl.timeline;
  Set<String> get _selectedOccurrenceOutcomes => _occCtrl.selectedOutcomes;
  LatLng? get _selectedLocationLatLng => _occCtrl.selectedLocationLatLng;

  // Estado de ocorrência (leitura/escrita proxied)
  String get _occurrenceStatus => _occCtrl.status;
  set _occurrenceStatus(String v) => _occCtrl.status = v;
  bool? get _occurrenceSuccessful => _occCtrl.successful;
  set _occurrenceSuccessful(bool? v) => _occCtrl.successful = v;
  bool get _showOccurrenceFinalization => _occCtrl.showFinalization;
  set _showOccurrenceFinalization(bool v) => _occCtrl.showFinalization = v;
  bool get _occurrenceFinishSubmitted => _occCtrl.finishSubmitted;
  set _occurrenceFinishSubmitted(bool v) => _occCtrl.finishSubmitted = v;
  String? get _activeIncidentId => _occCtrl.activeIncidentId;
  set _activeIncidentId(String? v) => _occCtrl.activeIncidentId = v;
  DateTime? get _activeOccurrenceStartedAt => _occCtrl.activeStartedAt;
  set _activeOccurrenceStartedAt(DateTime? v) => _occCtrl.activeStartedAt = v;
  bool get _showStartNatureEditor => _occCtrl.showStartNatureEditor;
  set _showStartNatureEditor(bool v) => _occCtrl.showStartNatureEditor = v;
  String? get _selectedOccurrenceUpdateTitle => _occCtrl.selectedUpdateTitle;
  set _selectedOccurrenceUpdateTitle(String? v) =>
      _occCtrl.selectedUpdateTitle = v;
  List<OccurrenceNature> get _occurrenceNatures => _occCtrl.natures;

  // Rotina/Saúde: controladores fallback (Saúde — Fase 4)
  final _locationCtrlOther = TextEditingController();
  final _descriptionCtrlOther = TextEditingController();
  final _timeCtrlOther = TextEditingController();
  final _durationCtrlOther = TextEditingController(); // nenhuma categoria restante usa


  late PageController _menuPageController;
  int _currentMenuPage = 0;

  List<Map<String, dynamic>> get _currentCategoryCards {
    return ActivityCardCatalog.forCategory(widget.category);
  }

  @override
  void initState() {
    super.initState();
    _occCtrl = ActivitySheetOccurrenceCtrl(
      dogId: widget.dogId,
      dogName: widget.dogName,
      documentId: widget.documentId,
      initialData: widget.initialData,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
    );
    _trainingCtrl = ActivitySheetTrainingCtrl(
      dogId: widget.dogId,
      dogName: widget.dogName,
      documentId: widget.documentId,
      initialData: widget.initialData,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
    );
    _routineCtrl = ActivitySheetRoutineCtrl(
      dogId: widget.dogId,
      dogName: widget.dogName,
      documentId: widget.documentId,
      initialData: widget.initialData,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
    );
    _speechDictation = SpeechDictationService();
    if (_isOccurrenceCategory) {
      _occCtrl.init();
    } else if (widget.category == 'Treino') {
      _trainingCtrl.init();
    } else if (widget.category == 'Rotina') {
      _routineCtrl.init();
    }
    _menuPageController = PageController(viewportFraction: 0.80);
    _menuPageController.addListener(() {
      final page = _menuPageController.page?.round();
      if (page != null && page != _currentMenuPage) {
        setState(() => _currentMenuPage = page);
      }
    });
    _occCtrl.descriptionController.addListener(_onOccurrenceDescriptionChanged);
    if (_isOccurrenceCategory && widget.initialData == null) {
      _showMenu = false;
      _selectedSubtype = null;
      _selectedSubtypeImagePath = 'assets/images/k9_tactical_background.png';
    }
    if (widget.initialData != null) {
      _showMenu = false;
      _populateEditData();
    }
    // Set default time to now when creating a new record
    if (widget.initialData == null) {
      _timeCtrlOther.text = _formatTimeOfDay(DateTime.now());
      _occCtrl.timeController.text = _formatTimeOfDay(DateTime.now());
      _trainingCtrl.timeController.text = _formatTimeOfDay(DateTime.now());
      _routineCtrl.timeController.text = _formatTimeOfDay(DateTime.now());
    }
    if (_isOccurrenceCategory) {
      _occCtrl.loadNatures();
      if (widget.initialData == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _didAutoPrimeOccurrenceStart) return;
          _didAutoPrimeOccurrenceStart = true;
          _setTimeToNow();
          _fetchCurrentAddress();
        });
      }
    }
  }

  void _onOccurrenceDescriptionChanged() {
    if (_isOccurrenceCategory && mounted) {
      setState(() {});
    }
  }

  // _loadOccurrenceNatures foi migrado para _occCtrl.loadNatures()

  void _populateEditData() {
    final d = widget.initialData!;
    _selectedSubtypeImagePath = 'assets/images/k9_tactical_background.png';
    _populateEditTimestamp(d);

    if (widget.category == 'Treino') {
      _populateTrainingEditData(d);
    } else if (widget.category == 'Rotina') {
      _populateRoutineEditData(d);
    } else if (_isOccurrenceCategory || widget.category == 'Evento') {
      _populateOccurrenceEditData(d);
    } else if (widget.category == 'Saude') {
      _populateHealthEditData(d);
    }

    _applySelectedSubtypeImage();
  }

  void _populateEditTimestamp(Map<String, dynamic> data) {
    final rawDate = data['_rawDate'];
    if (rawDate is DateTime) {
      _timeController.text = _formatTimeOfDay(rawDate);
    }
  }

  void _populateTrainingEditData(Map<String, dynamic> data) {
    _selectedSubtype = data['trainingType'];
    _locationController.text = data['location'] ?? '';
    _descriptionController.text = data['handlerNotes'] ?? '';
    if (data['searchDuration'] != null) {
      _durationController.text = ((data['searchDuration'] as num) ~/ 60)
          .toString();
    }
    if (data['metadata'] != null) {
      _formData.addAll(Map<String, dynamic>.from(data['metadata']));
      final storedTemperature = _metadataValue('Temperatura (°C)');
      if (storedTemperature != null) {
        _tempController.text = storedTemperature.toString();
      }
      final storedHumidity = _metadataValue('Umidade (%)');
      if (storedHumidity != null) {
        _humidityController.text = storedHumidity.toString();
      }
    }
  }

  void _populateRoutineEditData(Map<String, dynamic> data) {
    _selectedSubtype = data['activityType'];
    _descriptionController.text = data['notes'] ?? '';
    if (data['metadata'] == null) return;

    _formData.addAll(Map<String, dynamic>.from(data['metadata']));
    final rationBrand = _metadataValue('Marca da Ração');
    if (rationBrand != null) {
      _racaoMarcaController.text = rationBrand.toString();
    }
    final rationAmount = _metadataValue('Quantidade (g)');
    if (rationAmount != null) {
      _racaoQtdController.text = rationAmount.toString();
    }
    final duration = _metadataValue('Duração (min)');
    if (duration != null) {
      _durationController.text = duration.toString();
    }
    final distance = _metadataValue('Distância (km)');
    if (distance != null) {
      _distanciaController.text = distance.toString();
    }
  }

  void _populateOccurrenceEditData(Map<String, dynamic> data) {
    _selectedSubtype = OccurrenceFormController.normalizeNature(
      data['type'] ??
          (_isOccurrenceCategory
              ? _SheetSubtype.detection
              : _SheetSubtype.event),
    );
    _setOccurrenceNatureTextFromSelected();
    _locationController.text = data['location'] ?? '';
    _descriptionController.text = data['description'] ?? '';
    _formData['Resultado da Busca'] = data['result'];
    _occurrenceStatus = OccurrenceFormController.normalizeStatus(
      data['status'],
    );
    _occurrenceSuccessful = data['operationalSuccess'] as bool?;
    _showOccurrenceFinalization =
        _occurrenceStatus != OccurrenceFormController.statusInProgress;

    if (data['extraFields'] is Map) {
      _populateOccurrenceExtraFields(
        Map<String, dynamic>.from(data['extraFields'] as Map),
      );
    }
    _populateOccurrenceOutcomes(data['outcomes']);
    _populateOccurrenceTimeline(data);
    _syncOccurrenceController();
  }

  void _populateOccurrenceOutcomes(dynamic rawOutcomes) {
    if (rawOutcomes is! List) return;

    _selectedOccurrenceOutcomes
      ..clear()
      ..addAll(
        List<String>.from(
          rawOutcomes,
        ).map(OccurrenceFormController.normalizeOutcome),
      );
  }

  void _populateOccurrenceTimeline(Map<String, dynamic> data) {
    if (data['progressUpdates'] is List) {
      _occurrenceTimeline
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

    if (_descriptionController.text.isEmpty) return;
    _occurrenceTimeline
      ..clear()
      ..add(
        IncidentProgressUpdate(
          title: 'Registro inicial',
          description: _descriptionController.text,
          timestamp: data['_rawDate'] is DateTime
              ? data['_rawDate'] as DateTime
              : DateTime.now(),
          location: _locationController.text,
        ),
      );
  }

  void _populateHealthEditData(Map<String, dynamic> data) {
    _selectedSubtype = data['logType'];
    final obs = data['healthObservations'] as String? ?? '';
    _descriptionController.text = obs;
    if (obs.contains('Retorno agendado: ')) {
      final split = obs.split('Retorno agendado: ');
      if (split.length > 1) {
        _returnDateController.text = split[1].trim();
        _descriptionController.text = split[0].trim();
      }
    }
    _vetNameController.text = data['vetName'] ?? '';
  }

  void _applySelectedSubtypeImage() {
    final cardImage = ActivityCardCatalog.imageFor(
      category: widget.category,
      id: _selectedSubtype,
    );
    if (cardImage != null) {
      _selectedSubtypeImagePath = cardImage;
    }
  }

  dynamic _metadataValue(String key) {
    return FormMetadataReader(_formData).value(key);
  }

  void _populateOccurrenceExtraFields(Map<String, dynamic> extraFields) {
    final snapshot = OccurrenceExtraFieldsSnapshot(extraFields);

    _equipeController.text = snapshot.team;
    _boController.text = snapshot.reportNumber;
    _guarnicaoController.text = snapshot.supportedGarrison;
    _situacaoController.text = snapshot.situation;
    _desfechoController.text = snapshot.interventionOutcome;
    _odorObjetoController.text = snapshot.odorSource;
    _tempoDesaparecimentoController.text = snapshot.missingTime;
    _durationController.text = snapshot.searchDuration;
    _condicaoTerrenoController.text = snapshot.terrainCondition;
    _numeroOsController.text = snapshot.serviceOrderNumber;
    _publicoController.text = snapshot.publicEstimate;
    _temaController.text = snapshot.eventTheme;

    if (_selectedSubtype == _SheetSubtype.other) {
      _naturezaOcorrenciaController.text = snapshot.manualNatureOrNature();
    }

    if (snapshot.searchType != null) {
      _formData['Tipo de Busca'] = snapshot.searchType;
    }

    final lat = snapshot.locationLat;
    final lng = snapshot.locationLng;
    if (lat != null && lng != null) {
      _occCtrl.selectedLocationLatLng = LatLng(lat, lng);
    }

    final details = snapshot.detailedResults;
    if (details != null) {
      _hydrateDetainedIndividuals(details['individuosDetidos']);
      _hydrateSeizedObjects(details['objetosApreendidos']);
      _hydrateDrugRows(details['drogasApreendidas']);
      _hydrateDetainedVehicles(details['veiculosDetidos']);
    }

    if (_detecaoDrogas.isEmpty) {
      _hydrateDrugRows(snapshot.legacyDrugRows);
    }
  }

  void _setOccurrenceNatureTextFromSelected() {
    if (!_isOccurrenceCategory || _selectedSubtype == null) return;
    final selected = _selectedOccurrenceNature();
    _naturezaOcorrenciaController.text = selected?.label ?? _selectedSubtype!;
  }

  void _syncSelectedOccurrenceNatureFromText() {
    if (!_isOccurrenceCategory) return;
    final text = _naturezaOcorrenciaController.text.trim();
    if (text.isEmpty) {
      _selectedSubtype = null;
      return;
    }

    final normalized = OccurrenceNature.normalizeForSearch(text);
    final selected = _occurrenceNatures.cast<OccurrenceNature?>().firstWhere((
      nature,
    ) {
      if (nature == null) return false;
      return OccurrenceNature.normalizeForSearch(nature.label) == normalized ||
          OccurrenceNature.normalizeForSearch(nature.name) == normalized ||
          OccurrenceNature.normalizeForSearch(nature.code) == normalized;
    }, orElse: () => null);

    _selectedSubtype = selected?.name ?? text;
  }

  OccurrenceNature? _selectedOccurrenceNature() {
    final selectedSubtype = _selectedSubtype;
    if (selectedSubtype == null || selectedSubtype.trim().isEmpty) {
      return null;
    }
    final normalized = OccurrenceNature.normalizeForSearch(selectedSubtype);
    return _occurrenceNatures.cast<OccurrenceNature?>().firstWhere((nature) {
      if (nature == null) return false;
      return OccurrenceNature.normalizeForSearch(nature.name) == normalized ||
          OccurrenceNature.normalizeForSearch(nature.label) == normalized;
    }, orElse: () => null);
  }

  void _hydrateDetainedIndividuals(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(
      _detainedIndividuals,
      ['quantidade'],
      OccurrenceDynamicRows.hydrateDetainedIndividuals(rows),
    );
  }

  void _hydrateSeizedObjects(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(_seizedObjects, [
      'descricao',
      'quantidade',
    ], OccurrenceDynamicRows.hydrateSeizedObjects(rows));
  }

  void _hydrateDrugRows(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(
      _detecaoDrogas,
      ['quantidade', 'especificar'],
      OccurrenceDynamicRows.hydrateDrugs(
        rows,
        knownOptions: _detectionDrugOptions,
      ),
    );
  }

  void _hydrateDetainedVehicles(dynamic rows) {
    if (rows is! List) return;
    _replaceDynamicRows(_detainedVehicles, [
      'tipo',
      'placa',
    ], OccurrenceDynamicRows.hydrateDetainedVehicles(rows));
  }

  bool _showMenu = true;
  String? _selectedSubtype;
  String? _selectedSubtypeImagePath;
  final Map<String, dynamic> _formData = {};
  // _occurrenceNatures agora via getter => _occCtrl.natures
  String? _selectedVacina; // para dropdown de vacina (Saúde)

  bool _isCompressing = false;
  bool _isSaving = false;
  // _occurrenceFinishSubmitted agora via getter => _occCtrl.finishSubmitted
  String _saveStatus = '';
  bool _saveFailed = false;
  late SpeechDictationService _speechDictation;
  bool _isListening = false;
  int _activePhotoIndex = -1;
  bool _didAutoPrimeOccurrenceStart = false;

  // _timeController, _locationController, _descriptionController agora são getters
  // _occurrenceNatureFocusNode, _occurrenceUpdateController, _occurrenceUpdateFocusNode
  // agora são getters delegando para _occCtrl
  // _durationController agora é um getter delegando para _trainingCtrl ou _durationCtrlOther
  final _returnDateController = TextEditingController(); // Saúde

  void _setSaveStatus(String status, {bool failed = false}) {
    if (!mounted) return;
    setState(() {
      _saveStatus = status;
      _saveFailed = failed;
    });
  }

  void _closeForm([bool result = false]) {
    if (_isSaving) {
      HapticFeedback.lightImpact();
      _showOperationalSnack(
        'Aguarde a sincronização terminar antes de sair.',
        backgroundColor: const Color(0xFFFBBF24),
        foregroundColor: Colors.black,
      );
      return;
    }

    Navigator.pop(context, result || _activeIncidentId != null);
  }

  void _showOperationalSnack(
    String message, {
    Color backgroundColor = const Color(0xFF121826),
    Color foregroundColor = Colors.white,
    IconData? icon,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: backgroundColor,
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: foregroundColor),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(
                  color: foregroundColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _cleanSaveError(Object error) {
    final raw = error.toString();
    return raw
        .replaceFirst('Exception: ', '')
        .replaceFirst('FirebaseException: ', '')
        .trim();
  }

  String _formatTimeOfDay(DateTime value) {
    return const PtBrDateTimeService().time(value);
  }

  String _formatDatePtBr(DateTime value) {
    return const PtBrDateTimeService().date(value);
  }

  String _successSaveMessage() {
    return ActivityFormLabels.successSaveMessage(
      category: widget.category,
      isOccurrenceCategory: _isOccurrenceCategory,
      occurrenceStatus: _occurrenceStatus,
    );
  }

  // Saúde - campos adicionais (a migrar na Fase 4)
  final _vetNameController = TextEditingController();
  final _clinicaController = TextEditingController();
  final _motivoController = TextEditingController();
  final _tipoVacinaController = TextEditingController();
  final _tipoExameController = TextEditingController();
  final _produtosBanhoController = TextEditingController();
  // Faro / clima e campos de treino: migrados para _trainingCtrl (Fase 2)
  // _tempController, _humidityController, _objetivoTreinoController,
  // _dificuldadesController agora são getters delegando para _trainingCtrl

  // Rotina campos adicionais
  final _racaoMarcaController = TextEditingController();
  final _racaoQtdController = TextEditingController();
  final _distanciaController = TextEditingController();

  // PDF/arquivo para Exames (Saúde)
  File? _examePdfFile;
  String? _examePdfName;

  // Fotos / mídias globais
  final List<Map<String, dynamic>> _mediaAttachments = [];

  // Restantes ainda no State (Fases 2-4)
  final _materiaisController = TextEditingController();
  // _occurrenceController agora encapsulado no _occCtrl
  // Estado de ocorrência: todos os campos abaixo são getters => _occCtrl

  @override
  void dispose() {
    _occCtrl.descriptionController
        .removeListener(_onOccurrenceDescriptionChanged);
    _occCtrl.dispose();
    _trainingCtrl.dispose();
    _routineCtrl.dispose();
    _locationCtrlOther.dispose();
    _descriptionCtrlOther.dispose();
    _timeCtrlOther.dispose();
    _durationCtrlOther.dispose();
    _returnDateController.dispose();
    _materiaisController.dispose();
    _vetNameController.dispose();
    _clinicaController.dispose();
    _motivoController.dispose();
    _tipoVacinaController.dispose();
    _tipoExameController.dispose();
    // _produtosBanhoController (Saúde) — ainda aqui até Fase 4
    _produtosBanhoController.dispose();
    // _racaoMarcaController, _racaoQtdController, _distanciaController: migrados para _routineCtrl

    MediaAttachmentRows.disposeAll(_mediaAttachments);
    _menuPageController.dispose();
    super.dispose();
  }

  void _disposeDynamicResultRows(
    List<Map<String, dynamic>> rows,
    List<String> controllerKeys,
  ) {
    OccurrenceDynamicRows.disposeRows(rows, controllerKeys);
  }

  void _replaceDynamicRows(
    List<Map<String, dynamic>> target,
    List<String> controllerKeys,
    List<Map<String, dynamic>> nextRows,
  ) {
    _disposeDynamicResultRows(target, controllerKeys);
    target
      ..clear()
      ..addAll(nextRows);
  }

  // _disposeDrugRows foi migrado para _occCtrl.dispose()

  void _selectSubtype(String type, {String? imagePath}) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedSubtype = type;
      if (_isOccurrenceCategory) {
        _setOccurrenceNatureTextFromSelected();
      }
      _selectedSubtypeImagePath =
          imagePath ?? 'assets/images/k9_tactical_background.png';
      _formData.clear();
      if (_isOccurrenceCategory) {
        _occCtrl.status = OccurrenceFormController.statusCompleted;
        _occCtrl.successful = true;
        _occCtrl.selectNatureById(type);
        _copyOccurrenceControllerToFields();
        _occurrenceTimeline.clear();
        _selectedOccurrenceUpdateTitle = null;
        _occurrenceUpdateController.clear();
      }
      _showMenu = false;
    });
  }

  Future<void> _fetchCurrentAddress() async {
    try {
      HapticFeedback.lightImpact();
      final location = await const LocationResolutionService()
          .currentHighAccuracy();
      setState(() {
        _locationController.text = location.address;
        _occCtrl.selectedLocationLatLng = location.point;
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao obter endereço: $e')));
      }
    }
  }

  Future<void> _selectOccurrenceLocation(LatLng point) async {
    setState(() => _occCtrl.selectedLocationLatLng = point);
    final address = await const LocationResolutionService().addressForPoint(
      point,
    );
    if (address.isNotEmpty) {
      setState(() => _locationController.text = address);
    }
  }

  void _setTimeToNow() {
    setState(() {
      _timeController.text = _formatTimeOfDay(DateTime.now());
    });
    HapticFeedback.selectionClick();
  }

  void _addDrug() {
    setState(() {
      _detecaoDrogas.add(OccurrenceDynamicRows.drug());
    });
    HapticFeedback.selectionClick();
  }

  void _removeDrug(int index) {
    setState(() {
      _detecaoDrogas[index]['quantidade'].dispose();
      _detecaoDrogas[index]['especificar']?.dispose();
      _detecaoDrogas.removeAt(index);
    });
    HapticFeedback.selectionClick();
  }

  void _addDetainedIndividual() {
    setState(() {
      _detainedIndividuals.add(OccurrenceDynamicRows.detainedIndividual());
    });
    HapticFeedback.selectionClick();
  }

  void _addSeizedObject() {
    setState(() {
      _seizedObjects.add(OccurrenceDynamicRows.seizedObject());
    });
    HapticFeedback.selectionClick();
  }

  void _addDetainedVehicle() {
    setState(() {
      _detainedVehicles.add(OccurrenceDynamicRows.detainedVehicle());
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _pullCurrentWeather() async {
    try {
      HapticFeedback.lightImpact();
      final weather = await const WeatherCaptureService().currentWeather();
      if (weather != null) {
        setState(() {
          _tempController.text = weather.temperature.toString();
          _humidityController.text = weather.humidity.toString();
          if (_condicaoTerrenoController.text.isEmpty) {
            _condicaoTerrenoController.text = weather.terrainSummary;
          }
        });
        HapticFeedback.mediumImpact();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Clima atualizado com sucesso!'),
              backgroundColor: Color(0xFF1B8A4C),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao coletar clima: $e')));
      }
    }
  }

  Future<void> _pickImage() async {
    if (mounted) {
      setState(() => _isCompressing = true);
    }

    final compressedImages = await const MediaProcessingService()
        .pickAndCompressImages();
    if (compressedImages.isNotEmpty) {
      setState(() {
        for (var file in compressedImages) {
          _mediaAttachments.add(MediaAttachmentRows.pendingPhoto(file));
        }
        _isCompressing = false;
      });
      HapticFeedback.lightImpact();
    } else if (mounted) {
      setState(() => _isCompressing = false);
    }
  }

  Future<void> _listen() async {
    if (_isListening) {
      _stopListening();
      return;
    }

    final started = await _speechDictation.start(
      controller: _descriptionController,
      onListeningStarted: () {
        if (mounted) setState(() => _isListening = true);
      },
      onListeningStopped: () {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (started) {
      HapticFeedback.lightImpact();
    }
  }

  void _stopListening() {
    if (_isListening) {
      if (mounted) setState(() => _isListening = false);
      _speechDictation.stop();
      HapticFeedback.selectionClick();
    }
  }

  Future<List<Map<String, dynamic>>> _uploadAllMedia(String folder) async {
    if (_mediaAttachments.isEmpty) return const [];

    if (mounted) {
      setState(() {
        _saveStatus = 'Fazendo upload de mídias...';
      });
    }

    return MediaAttachmentUploadService(
      storageService: StorageService(),
    ).uploadAll(
      attachments: _mediaAttachments,
      folder: folder,
      onUploading: (attachment) {
        if (mounted) {
          setState(() => MediaAttachmentRows.markUploading(attachment));
        }
      },
      onUploaded: (attachment, url) {
        if (mounted) {
          setState(() => MediaAttachmentRows.markDone(attachment, url));
        }
      },
      onPending: (attachment) {
        if (mounted) {
          setState(() => MediaAttachmentRows.markPending(attachment));
        }
      },
    );
  }

  List<Map<String, dynamic>> _mergeExistingIncidentMedia(
    List<Map<String, dynamic>> uploadedMedia,
  ) {
    return MediaAttachmentRows.mergeExistingWithUploaded(
      existing: widget.initialData?['mediaAttachments'],
      uploaded: uploadedMedia,
    );
  }

  Future<String?> _uploadExamePdf() async {
    if (_examePdfFile == null) return null;
    if (mounted) setState(() => _saveStatus = 'Enviando PDF do Exame...');
    return const PdfAttachmentService().uploadExamPdf(_examePdfFile!);
  }

  DateTime _resolveFormTimestamp() {
    final baseTimestamp = widget.initialData?['_rawDate'] ?? DateTime.now();
    return const PtBrDateTimeService().withTimeText(
      base: baseTimestamp,
      timeText: _timeController.text,
    );
  }

  void _prepareRoutineMetadata() {
    if (_selectedSubtype == _SheetSubtype.feeding) {
      _formData['Marca da Ração'] = _racaoMarcaController.text;
      _formData['Quantidade (g)'] = _racaoQtdController.text;
    }
    if (_durationController.text.isNotEmpty) {
      _formData['Duração (min)'] = _durationController.text;
    }
    if (_distanciaController.text.isNotEmpty) {
      _formData['Distância (km)'] = _distanciaController.text;
    }
  }

  void _prepareHealthMetadata() {
    if (_returnDateController.text.isNotEmpty) {
      _formData['Data de Retorno'] = _returnDateController.text;
    }
  }

  void _prepareTrainingMetadata() {
    // Migrado para _trainingCtrl.buildMetadata(subtype: _selectedSubtype)
    // Chamado em _saveTraining via o próprio controller.
  }

  Future<void> _saveRoutine({
    required AuthViewModel authVM,
    required RoutineViewModel routineVM,
  }) async {
    final currentRa = HandlerIdentityService.raFromUser(authVM.user) ?? '';
    final List<Map<String, dynamic>> finalMedia = await _uploadAllMedia(
      'routines',
    );

    final routine = ActivityRecordPayloadBuilder.routine(
      documentId: widget.documentId,
      dogId: widget.dogId,
      dogName: widget.dogName,
      currentRa: currentRa,
      initialHandlerId: widget.initialData?['_rawHandlerId']?.toString(),
      activityType: _selectedSubtype!,
      timestamp: _resolveFormTimestamp(),
      notes: _descriptionController.text,
      mediaAttachments: finalMedia,
      metadata: _formData,
    );

    if (widget.documentId != null) {
      await routineVM.updateRoutine(routine);
    } else {
      await routineVM.addRoutine(routine);
    }
  }

  Future<void> _saveHealth({required HealthViewModel healthVM}) async {
    final List<Map<String, dynamic>> finalMedia = await _uploadAllMedia(
      'health',
    );
    final String? pdfUrl = await _uploadExamePdf();

    if (pdfUrl != null) {
      finalMedia.add({
        'url': pdfUrl,
        'caption': 'PDF do Exame: ${_examePdfName ?? "documento.pdf"}',
        'type': 'pdf',
      });
    }

    _prepareHealthMetadata();

    final hLog = ActivityRecordPayloadBuilder.healthLog(
      documentId: widget.documentId,
      dogId: widget.dogId,
      dogName: widget.dogName,
      date: widget.initialData?['_rawDate'] ?? DateTime.now(),
      logType: _selectedSubtype!,
      observations: _descriptionController.text,
      returnDate: _returnDateController.text,
      vetName: _vetNameController.text,
      mediaAttachments: finalMedia,
    );

    if (widget.documentId != null) {
      await healthVM.updateHealthLog(hLog);
    } else {
      await healthVM.addHealthLog(hLog);
    }
  }

  Future<void> _saveTraining({
    required TrainingViewModel trainingVM,
    required AuthViewModel authVM,
  }) async {
    await _trainingCtrl.save(
      trainingVM: trainingVM,
      authVM: authVM,
      selectedSubtype: _selectedSubtype,
      formData: _formData,
      mediaAttachments: _mediaAttachments,
      onStatus: (msg) {
        if (mounted) setState(() => _saveStatus = msg);
      },
      isMounted: () => mounted,
      onUploading: (a) {
        if (mounted) setState(() => MediaAttachmentRows.markUploading(a));
      },
      onUploaded: (a, url) {
        if (mounted) setState(() => MediaAttachmentRows.markDone(a, url));
      },
      onPending: (a) {
        if (mounted) setState(() => MediaAttachmentRows.markPending(a));
      },
    );
  }

  Future<List<Map<String, dynamic>>>
  _prepareOccurrenceMediaAttachments() async {
    _setSaveStatus('Preparando anexos da ocorrência...');
    final List<Map<String, dynamic>> uploadedMedia = await _uploadAllMedia(
      'incidents',
    );
    return _mergeExistingIncidentMedia(uploadedMedia);
  }

  Map<String, dynamic>? _existingOccurrenceExtraFields() {
    if (widget.initialData?['extraFields'] is! Map) {
      return null;
    }

    return Map<String, dynamic>.from(widget.initialData!['extraFields'] as Map);
  }

  DateTime _occurrenceSaveDate() {
    return _activeIncidentId == null ? _resolveFormTimestamp() : DateTime.now();
  }

  DateTime _occurrenceStartedAtOr(DateTime fallbackDate) {
    return _activeOccurrenceStartedAt ??
        (widget.initialData?['startedAt'] != null
            ? parseFirestoreDate(widget.initialData!['startedAt'])
            : widget.initialData?['_rawDate'] ?? fallbackDate);
  }

  Future<void> _grantOccurrenceBadgesIfNeeded({
    required UserViewModel userVM,
    required String currentRa,
    required Map<String, dynamic> extraFields,
  }) async {
    final hasDetectedDrugs =
        extraFields.containsKey('drogas') &&
        (extraFields['drogas'] as List).isNotEmpty;
    final isDetection =
        _selectedSubtype == _SheetSubtype.detection ||
        _selectedSubtype == _SheetSubtype.narcoticsSearch;

    if (isDetection && hasDetectedDrugs) {
      await userVM.grantBadge(currentRa, 'faro_afiado');
    }
  }

  OperatorContext _operatorContext({
    required AuthViewModel authVM,
    required UserViewModel userVM,
  }) {
    return const OperatorContextService().fromViewModels(
      authVM: authVM,
      userVM: userVM,
    );
  }

  Future<void> _saveOccurrenceOrEvent({
    required AuthViewModel authVM,
    required IncidentViewModel incidentVM,
    required UserViewModel userVM,
  }) async {
    _setSaveStatus('Validando ocorrência...');
    final operatorContext = _operatorContext(authVM: authVM, userVM: userVM);

    if (_activeIncidentId == null) {
      _setSaveStatus('Verificando ocorrência aberta...');
      final openIncident = await incidentVM.findOpenIncident(
        dogId: widget.dogId,
      );
      if (openIncident != null) {
        throw Exception(
          'Já existe uma ocorrência em andamento para este K9. Continue ou encerre o registro aberto antes de iniciar outro.',
        );
      }
    }

    _validateOccurrenceBeforeSave();

    final finalMedia = await _prepareOccurrenceMediaAttachments();
    final extraFields = _buildOccurrenceExtraFields(
      existingExtraFields: _existingOccurrenceExtraFields(),
    );

    final finalDate = _occurrenceSaveDate();
    final incidentUpdates = _buildIncidentProgressUpdates(
      finalDate,
      authorId: operatorContext.ra,
      authorName: operatorContext.name,
    );
    final startedAt = _occurrenceStartedAtOr(finalDate);

    final inc = _buildOccurrenceIncident(
      currentRa: operatorContext.ra,
      finalDate: finalDate,
      startedAt: startedAt,
      extraFields: extraFields,
      mediaAttachments: finalMedia,
      progressUpdates: incidentUpdates,
    );

    if (_activeIncidentId != null) {
      _setSaveStatus('Atualizando ocorrência no Firebase...');
      await incidentVM.updateIncident(inc);
      return;
    }

    _setSaveStatus('Criando ocorrência no Firebase...');
    await incidentVM.saveIncident(inc);
    _activeIncidentId = inc.id;
    _activeOccurrenceStartedAt = inc.startedAt;

    await _grantOccurrenceBadgesIfNeeded(
      userVM: userVM,
      currentRa: operatorContext.ra,
      extraFields: extraFields,
    );
  }

  Future<bool> _save({bool closeAfterSave = true}) async {
    if (_isOccurrenceCategory) {
      _syncSelectedOccurrenceNatureFromText();
    }
    if (_selectedSubtype == null || _selectedSubtype!.trim().isEmpty) {
      if (_isOccurrenceCategory) {
        _selectedSubtype = _naturezaOcorrenciaController.text.trim().isEmpty
            ? 'Averiguação'
            : _naturezaOcorrenciaController.text.trim();
        if (_naturezaOcorrenciaController.text.trim().isEmpty) {
          _naturezaOcorrenciaController.text = _selectedSubtype!;
        }
      } else {
        return false;
      }
    }
    if (_isSaving) return false;
    HapticFeedback.lightImpact();

    if (_formKey.currentState!.validate()) {
      final authVM = Provider.of<AuthViewModel>(context, listen: false);
      final routineVM = Provider.of<RoutineViewModel>(context, listen: false);
      final trainingVM = Provider.of<TrainingViewModel>(context, listen: false);
      final incidentVM = Provider.of<IncidentViewModel>(context, listen: false);
      final healthVM = Provider.of<HealthViewModel>(context, listen: false);
      final userVM = Provider.of<UserViewModel>(context, listen: false);

      _formKey.currentState!.save();
      setState(() {
        _isSaving = true;
        _saveStatus = 'Preparando dados...';
        _saveFailed = false;
      });

      try {
        if (widget.category == 'Rotina') {
          _setSaveStatus('Validando rotina...');
          _prepareRoutineMetadata();
          _setSaveStatus('Salvando rotina no Firebase...');
          await _saveRoutine(authVM: authVM, routineVM: routineVM);
        } else if (widget.category == 'Treino') {
          _setSaveStatus('Validando treino...');
          _prepareTrainingMetadata();
          _setSaveStatus('Salvando treino no Firebase...');
          await _saveTraining(trainingVM: trainingVM, authVM: authVM);
        } else if (_isOccurrenceCategory || widget.category == 'Evento') {
          await _saveOccurrenceOrEvent(
            authVM: authVM,
            incidentVM: incidentVM,
            userVM: userVM,
          );
        } else if (widget.category == 'Saude') {
          _setSaveStatus('Salvando prontuário no Firebase...');
          await _saveHealth(healthVM: healthVM);
        }

        if (mounted) {
          _setSaveStatus('Sincronizado com Firebase.');
          HapticFeedback.mediumImpact();
          _showOperationalSnack(
            _successSaveMessage(),
            backgroundColor: const Color(0xFF1B8A4C),
            icon: Icons.cloud_done_rounded,
          );
          if (closeAfterSave) {
            Navigator.pop(context, true);
          }
        }
        return true;
      } catch (e) {
        if (mounted) {
          final message = _cleanSaveError(e);
          _setSaveStatus(
            'Falha ao salvar. Verifique conexão/permissão.',
            failed: true,
          );
          _showOperationalSnack(
            message.isEmpty ? 'Não foi possível salvar o registro.' : message,
            backgroundColor: const Color(0xFFE53935),
            icon: Icons.error_outline_rounded,
          );
        }
        return false;
      } finally {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
      }
    }

    return false;
  }

  void _saveOccurrenceInProgress() {
    setState(() {
      _occurrenceStatus = OccurrenceFormController.statusInProgress;
      _occurrenceSuccessful = null;
      _showOccurrenceFinalization = false;
    });
    _save(closeAfterSave: false);
  }

  void _validateOccurrenceBeforeSave() {
    OccurrenceSaveValidator.validate(
      status: _occurrenceStatus,
      description: _descriptionController.text,
      outcomes: _selectedOccurrenceOutcomes,
      subtype: _selectedSubtype,
      natureText: _naturezaOcorrenciaController.text,
    );
  }

  Map<String, dynamic> _buildOccurrenceExtraFields({
    required Map<String, dynamic>? existingExtraFields,
  }) {
    final extraFields = OccurrencePayloadBuilder.buildExtraFields(
      nature: _selectedSubtype,
      manualNature: _naturezaOcorrenciaController.text,
      formData: _formData,
      team: _equipeController.text,
      bo: _boController.text,
      supportedTeam: _guarnicaoController.text,
      situation: _situacaoController.text,
      interventionOutcome: _desfechoController.text,
      odorSource: _odorObjetoController.text,
      missingTime: _tempoDesaparecimentoController.text,
      searchDuration: _durationController.text,
      terrainCondition: _condicaoTerrenoController.text,
      serviceOrderNumber: _numeroOsController.text,
      drugRows: _detecaoDrogas,
      detainedIndividuals: _detainedIndividuals,
      seizedObjects: _seizedObjects,
      detainedVehicles: _detainedVehicles,
      existingExtraFields: existingExtraFields,
      publicEstimate: _publicoController.text,
      eventTheme: _temaController.text,
      locationLat: _selectedLocationLatLng?.latitude,
      locationLng: _selectedLocationLatLng?.longitude,
    );
    final selectedNature = _selectedOccurrenceNature();
    if (selectedNature != null) {
      extraFields['natureza_codigo'] = selectedNature.code;
      extraFields['natureza_nome'] = selectedNature.name;
      extraFields['natureza_grupo'] = selectedNature.group;
    }
    return extraFields;
  }

  Incident _buildOccurrenceIncident({
    required String currentRa,
    required DateTime finalDate,
    required DateTime startedAt,
    required Map<String, dynamic> extraFields,
    required List<Map<String, dynamic>> mediaAttachments,
    required List<IncidentProgressUpdate> progressUpdates,
  }) {
    return OccurrencePayloadBuilder.buildIncident(
      documentId: _activeIncidentId,
      dogId: widget.dogId,
      dogName: widget.dogName,
      handlerId: widget.initialData?['_rawHandlerId'] ?? currentRa,
      location: _locationController.text.isNotEmpty
          ? _locationController.text
          : 'GCM',
      description: _descriptionController.text,
      result: _resolveIncidentResultSummary(),
      type: _selectedSubtype,
      extraFields: extraFields,
      mediaAttachments: mediaAttachments,
      status: _occurrenceStatus,
      operationalSuccess: _occurrenceSuccessful,
      outcomes: _selectedOccurrenceOutcomes.toList(),
      startedAt: startedAt,
      updatedAt: finalDate,
      progressUpdates: progressUpdates,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fullScreen) {
      return _buildFormScaffold();
    }

    if (widget.initialData != null) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        child: _buildFormScaffold(),
      );
    }
    final size = MediaQuery.of(context).size;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
      child: SizedBox(
        height: size.height * 0.9,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          child: _showMenu ? _buildMenuSheet(context) : _buildFormScaffold(),
        ),
      ),
    );
  }

  Widget _buildFormScaffold() {
    if (_isOccurrenceCategory) {
      return _buildOccurrenceFormScaffold();
    }

    return ActivityFormScaffold(
      title: _selectedSubtype?.toUpperCase() ?? '',
      imagePath: _selectedSubtypeImagePath,
      heroTag: _selectedSubtype == null
          ? null
          : 'hero_category_$_selectedSubtype',
      isSaving: _isSaving,
      onBack: _handleStandardFormBack,
      child: _buildFormContent(),
    );
  }

  void _handleStandardFormBack() {
    if (widget.fullScreen || widget.initialData != null) {
      _closeForm(false);
      return;
    }

    final savedPage = _currentMenuPage;
    setState(() {
      _showMenu = true;
      _selectedSubtype = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_menuPageController.hasClients) {
        _menuPageController.jumpToPage(savedPage);
      }
    });
  }

  Widget _buildOccurrenceFormScaffold() {
    final tColor = _getCategoryColor();
    final isNewRecord = widget.documentId == null;

    return OccurrenceFormScaffold(
      backgroundColor: _hudBackground,
      panelColor: _hudPanel,
      accentColor: _hudCyan,
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

  Widget _buildMenuSheet(BuildContext context) {
    if (_currentMenuPage >= _currentCategoryCards.length) {
      _currentMenuPage = 0;
    }

    return ActivityCategoryMenuSheet(
      cards: _currentCategoryCards,
      currentPage: _currentMenuPage,
      pageController: _menuPageController,
      onPageChanged: (index) {
        HapticFeedback.selectionClick();
        setState(() => _currentMenuPage = index);
      },
      onCardConfirmed: (card) =>
          _selectSubtype(card['id'], imagePath: card['image']),
    );
  }

  Color _getCategoryColor() {
    if (_isOccurrenceCategory) {
      if (_occurrenceStatus == OccurrenceFormController.statusCanceled) {
        return _hudRed;
      }
      if (_occurrenceStatus == OccurrenceFormController.statusCompleted) {
        return _hudGreen;
      }
      return _hudCyan;
    }
    return ActivityCardCatalog.glowFor(
      category: widget.category,
      id: _selectedSubtype,
      fallback: const Color(0xFF1B8A4C),
    );
  }

  Widget _buildFormContent() {
    final tColor = _getCategoryColor();
    if (_isOccurrenceCategory) {
      return _buildOccurrenceStepperContent(tColor);
    }
    if (_selectedSubtype == _SheetSubtype.detection ||
        _selectedSubtype == _SheetSubtype.missingPerson) {
      return _buildGroupedFormContent(tColor);
    }
    return _buildStandardFormContent(tColor);
  }

  Widget _buildGroupedFormContent(Color tColor) {
    return ActivityFormBody(
      formKey: _formKey,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_selectedSubtype == _SheetSubtype.detection)
          ..._buildDetecaoGrouped(),
        if (_selectedSubtype == _SheetSubtype.missingPerson)
          ..._buildBuscaPessoaGrouped(),
        ..._buildOccurrenceMetaFields(),
        const SizedBox(height: 32),
        _buildSaveButton(tColor),
      ],
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

  Widget _buildOccurrenceStartScreenV2(Color tColor) {
    final dogVM = Provider.of<DogViewModel>(context);
    dynamic activeDog;
    for (final dog in dogVM.dogs) {
      if (dog.id == widget.dogId) {
        activeDog = dog;
        break;
      }
    }

    final dogName = widget.dogName.isNotEmpty
        ? widget.dogName
        : (activeDog?.name?.toString() ?? 'K9');
    final imageUrl = activeDog?.profileImageUrl?.toString();
    final locationLabel = _locationController.text.trim().isEmpty
        ? 'Capturando localização...'
        : _locationController.text.trim();
    final timeLabel = _timeController.text.trim().isEmpty
        ? '--:--'
        : _timeController.text.trim();
    final dateLabel = _formatDatePtBr(DateTime.now());
    final natureText = _naturezaOcorrenciaController.text.trim();

    return OccurrenceStartScreen(
      accentColor: tColor,
      panelColor: _hudPanel,
      dogName: dogName,
      dogImageUrl: imageUrl,
      locationLabel: locationLabel,
      timeLabel: timeLabel,
      dateLabel: dateLabel,
      natureText: natureText,
      showNatureEditor: _showStartNatureEditor,
      natureEditor: _buildOccurrenceNatureOnlyEditor(),
      onRefreshLocation: () {
        HapticFeedback.mediumImpact();
        _fetchCurrentAddress();
      },
      onRefreshTime: () {
        HapticFeedback.mediumImpact();
        _setTimeToNow();
      },
      onToggleNatureEditor: () =>
          setState(() => _showStartNatureEditor = !_showStartNatureEditor),
    );
  }

  Widget _buildOccurrenceNatureOnlyEditor() {
    return OccurrenceNatureSearch(
      controller: _naturezaOcorrenciaController,
      focusNode: _occurrenceNatureFocusNode,
      natures: _occurrenceNatures,
      panelColor: _hudPanel,
      accent: _hudCyan,
      onChanged: (_) => setState(_syncSelectedOccurrenceNatureFromText),
      onSelected: _selectOccurrenceNature,
      fieldBuilder: (context, controller, focusNode, onChanged) {
        return TacticalTextField(
          controller: controller,
          focusNode: focusNode,
          labelText: 'Natureza da ocorrência',
          prefixIcon: Icons.category_rounded,
          suffixIcon: IconButton(
            icon: const Icon(Icons.search_rounded, color: _hudCyan, size: 18),
            onPressed: () => focusNode.requestFocus(),
          ),
          onChanged: onChanged,
        );
      },
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

  Widget _buildOccurrenceInitialDataPanel(Color tColor) {
    return OccurrenceInitialDataPanel(
      accentColor: tColor,
      panelColor: _hudPanel,
      natureStep: _buildOccurrenceNatureStep(),
      locationBlock: _buildOccurrenceCompactLocationBlock(tColor),
    );
  }

  Widget _buildOccurrenceActiveContextSummary(Color tColor) {
    final startedAt = _occurrenceStartedAt() ?? _resolveFormTimestamp();
    final startedLabel = _formatTimeOfDay(startedAt);
    final location = _locationController.text.trim().isEmpty
        ? 'Local pendente'
        : _locationController.text.trim();
    final team = _equipeController.text.trim().isEmpty
        ? 'Equipe pendente'
        : _equipeController.text.trim();

    return OccurrenceActiveContextSummary(
      accentColor: tColor,
      panelColor: _hudPanel,
      backgroundColor: _hudBackground,
      location: location,
      team: team,
      startedLabel: startedLabel,
      onEdit: () => _showOccurrenceInitialDataSheet(tColor),
    );
  }

  Future<void> _showOccurrenceInitialDataSheet(Color tColor) async {
    HapticFeedback.selectionClick();
    await _showTacticalBottomSheet<void>(
      builder: (context) {
        return OccurrenceInitialDataSheet(
          accentColor: tColor,
          backgroundColor: _hudBackground,
          child: _buildOccurrenceInitialDataPanel(tColor),
          onDone: () {
            setState(() {});
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  Widget _buildOccurrenceCompactLocationBlock(Color tColor) {
    return OccurrenceCompactLocationBlock(
      hasLocation: _locationController.text.trim().isNotEmpty,
      showMapAdjust: _selectedLocationLatLng != null,
      gpsColor: _hudAmber,
      timeColor: _hudGreen,
      accentColor: tColor,
      locationField: TacticalTextField(
        controller: _locationController,
        labelText: 'Endereço / Local',
        prefixIcon: Icons.location_on_rounded,
      ),
      timeField: TacticalTextField(
        controller: _timeController,
        labelText: 'Hora de início',
        prefixIcon: Icons.schedule_rounded,
        readOnly: true,
      ),
      onCaptureGps: () {
        HapticFeedback.mediumImpact();
        _fetchCurrentAddress();
      },
      onSetCurrentTime: () {
        HapticFeedback.mediumImpact();
        _setTimeToNow();
      },
      onAdjustMap: _showOccurrenceLocationMapSheet,
    );
  }

  Future<void> _showOccurrenceLocationMapSheet() async {
    final location = _selectedLocationLatLng;
    if (location == null) return;

    HapticFeedback.selectionClick();
    await _showTacticalBottomSheet<void>(
      builder: (context) {
        return OccurrenceLocationMapSheet(
          location: location,
          accentColor: _hudCyan,
          backgroundColor: _hudBackground,
          onLocationChanged: _selectOccurrenceLocation,
        );
      },
    );
  }

  Widget _buildOccurrenceQuickActionGrid(Color tColor) {
    final actions = OccurrenceQuickActionCatalog.primaryActions(
      amber: _hudAmber,
      green: _hudGreen,
      cyan: _hudCyan,
    );

    return OccurrenceQuickActionGrid(
      accentColor: tColor,
      actions: actions,
      enabled: !_isSaving,
      onActionSelected: _handleOccurrenceQuickAction,
      onOpenEventCenter: () => _showOccurrenceEventCenter(tColor),
    );
  }

  Future<void> _handleOccurrenceQuickAction(
    OccurrenceQuickAction action,
  ) async {
    if (action.options.isEmpty) {
      await _registerOccurrenceEvent(action);
      return;
    }

    final selected = await _showOccurrenceActionOptions(action);
    if (selected == null) return;
    await _registerOccurrenceEvent(selected);
  }

  Future<OccurrenceQuickAction?> _showOccurrenceActionOptions(
    OccurrenceQuickAction action,
  ) {
    HapticFeedback.selectionClick();
    return _showTacticalBottomSheet<OccurrenceQuickAction>(
      builder: (context) => OccurrenceQuickActionOptionsSheet(
        action: action,
        backgroundColor: _hudBackground,
        panelColor: _hudPanel,
      ),
    );
  }

  Future<void> _showOccurrenceEventCenter(Color tColor) async {
    HapticFeedback.selectionClick();
    final categories = OccurrenceEventCatalog.categories(tColor);
    _occurrenceUpdateController.clear();

    await _showTacticalBottomSheet<void>(
      builder: (context) => OccurrenceEventCenterSheet(
        accentColor: tColor,
        backgroundColor: _hudBackground,
        panelColor: _hudPanel,
        categories: categories,
        controller: _occurrenceUpdateController,
        focusNode: _occurrenceUpdateFocusNode,
        onActionSelected: _registerOccurrenceEvent,
      ),
    );
  }

  IncidentProgressUpdate _buildOccurrenceEventUpdate(
    OccurrenceQuickAction action, {
    required DateTime timestamp,
    required OperatorContext operatorContext,
  }) {
    return IncidentProgressUpdate(
      title: action.title,
      description: action.description,
      timestamp: timestamp,
      location: _locationController.text.trim(),
      latitude: _selectedLocationLatLng?.latitude,
      longitude: _selectedLocationLatLng?.longitude,
      authorId: operatorContext.ra,
      authorName: operatorContext.name,
    );
  }

  Widget _buildOccurrenceActiveFooter(Color tColor) {
    return OccurrenceActiveFooter(
      showFinalization: _showOccurrenceFinalization,
      hasActiveOccurrenceRecord: _hasActiveOccurrenceRecord,
      isSaving: _isSaving,
      accentColor: tColor,
      backgroundColor: _hudBackground,
      dangerColor: _hudRed,
      saveStatusPanel: _buildSaveStatusPanel(tColor),
      finalSaveButton: _buildPrimarySaveButton(_hudRed),
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
          _occCtrl.setStatus(
            OccurrenceFormController.statusCompleted,
          );
          _copyOccurrenceControllerToFields(includeOutcomes: false);
        });
      },
    );
  }

  Future<void> _registerOccurrenceEvent(OccurrenceQuickAction action) async {
    if (_isSaving) return;
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final incidentVM = Provider.of<IncidentViewModel>(context, listen: false);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final operatorContext = _operatorContext(authVM: authVM, userVM: userVM);

    final update = _buildOccurrenceEventUpdate(
      action,
      timestamp: now,
      operatorContext: operatorContext,
    );

    setState(() {
      _isSaving = true;
      _saveStatus = 'Registrando evento...';
      _saveFailed = false;
      _occurrenceStatus = OccurrenceFormController.statusInProgress;
      _occurrenceSuccessful = null;
      _selectedOccurrenceUpdateTitle = null;
      _occurrenceTimeline.add(update);
      _occurrenceUpdateController.clear();
    });

    try {
      await _saveActiveOccurrenceSnapshot(
        incidentVM: incidentVM,
        currentRa: operatorContext.ra,
        currentOperatorName: operatorContext.name,
        updatedAt: now,
      );
      if (!mounted) return;
      _setSaveStatus('Evento sincronizado.');
      _showOperationalSnack(
        '${action.title} registrado na linha do tempo.',
        backgroundColor: const Color(0xFF123044),
        icon: action.icon,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saveFailed = true;
        _saveStatus = 'Falha ao sincronizar evento.';
      });
      _showOperationalSnack(
        _cleanSaveError(e).isEmpty
            ? 'Não foi possível sincronizar o evento.'
            : _cleanSaveError(e),
        backgroundColor: const Color(0xFFE53935),
        icon: Icons.error_outline_rounded,
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveActiveOccurrenceSnapshot({
    required IncidentViewModel incidentVM,
    required String currentRa,
    required String currentOperatorName,
    required DateTime updatedAt,
  }) async {
    if (_activeIncidentId == null) {
      final openIncident = await incidentVM.findOpenIncident(
        dogId: widget.dogId,
      );
      if (openIncident != null) {
        throw Exception(
          'Já existe uma ocorrência em andamento para este K9. Continue ou encerre o registro aberto antes de iniciar outro.',
        );
      }
    }

    _activeOccurrenceStartedAt ??= _resolveFormTimestamp();
    final inc = _buildActiveOccurrenceSnapshot(
      currentRa: currentRa,
      currentOperatorName: currentOperatorName,
      updatedAt: updatedAt,
    );

    if (_activeIncidentId == null) {
      await incidentVM.saveIncident(inc);
      _activeIncidentId = inc.id;
      _activeOccurrenceStartedAt = inc.startedAt;
    } else {
      await incidentVM.updateIncident(inc);
    }
  }

  Incident _buildActiveOccurrenceSnapshot({
    required String currentRa,
    required String currentOperatorName,
    required DateTime updatedAt,
  }) {
    final effectiveNature = OccurrenceDisplayText.effectiveNature(
      _selectedSubtype,
    );
    final effectiveManualNature = OccurrenceDisplayText.manualNatureOr(
      manualNature: _naturezaOcorrenciaController.text,
      fallback: effectiveNature,
    );

    final extraFields = OccurrencePayloadBuilder.buildExtraFields(
      nature: effectiveNature,
      manualNature: effectiveManualNature,
      formData: _formData,
      team: _equipeController.text,
      bo: _boController.text,
      supportedTeam: _guarnicaoController.text,
      situation: _situacaoController.text,
      interventionOutcome: _desfechoController.text,
      odorSource: _odorObjetoController.text,
      missingTime: _tempoDesaparecimentoController.text,
      searchDuration: _durationController.text,
      terrainCondition: _condicaoTerrenoController.text,
      serviceOrderNumber: _numeroOsController.text,
      drugRows: _detecaoDrogas,
      detainedIndividuals: _detainedIndividuals,
      seizedObjects: _seizedObjects,
      detainedVehicles: _detainedVehicles,
      existingExtraFields: _existingOccurrenceExtraFields(),
      publicEstimate: _publicoController.text,
      eventTheme: _temaController.text,
      locationLat: _selectedLocationLatLng?.latitude,
      locationLng: _selectedLocationLatLng?.longitude,
    );
    final selectedNature = _selectedOccurrenceNature();
    if (selectedNature != null) {
      extraFields['natureza_codigo'] = selectedNature.code;
      extraFields['natureza_nome'] = selectedNature.name;
      extraFields['natureza_grupo'] = selectedNature.group;
    }

    return OccurrencePayloadBuilder.buildIncident(
      documentId: _activeIncidentId,
      dogId: widget.dogId,
      dogName: widget.dogName,
      handlerId: widget.initialData?['_rawHandlerId'] ?? currentRa,
      startedAt: _activeOccurrenceStartedAt ?? updatedAt,
      updatedAt: updatedAt,
      location: _locationController.text.trim().isNotEmpty
          ? _locationController.text.trim()
          : 'GCM',
      description: _descriptionController.text,
      result: OccurrenceFormController.statusInProgress,
      type: effectiveNature,
      extraFields: extraFields,
      mediaAttachments: _mergeExistingIncidentMedia(const []),
      status: OccurrenceFormController.statusInProgress,
      operationalSuccess: null,
      outcomes: _selectedOccurrenceOutcomes.toList(),
      progressUpdates: List<IncidentProgressUpdate>.from(_occurrenceTimeline),
    );
  }

  dynamic _activeDogFrom(DogViewModel dogVM) {
    for (final dog in dogVM.dogs) {
      if (dog.id == widget.dogId) {
        return dog;
      }
    }
    return null;
  }

  dynamic _operatorUserFrom({
    required UserViewModel userVM,
    required String currentRa,
  }) {
    for (final user in userVM.users) {
      if (user.ra == currentRa) {
        return user;
      }
    }
    return null;
  }

  Widget _buildOccurrenceCommandHeader(
    Color tColor, {
    bool showOperationalMetrics = false,
  }) {
    final status = _occurrenceStatus;
    final startedAt = _occurrenceStartedAt();
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final operatorContext = _operatorContext(authVM: authVM, userVM: userVM);
    final activeDog = _activeDogFrom(dogVM);
    final currentUser = _operatorUserFrom(
      userVM: userVM,
      currentRa: operatorContext.ra,
    );

    return OccurrenceCommandHeader(
      nature: OccurrenceDisplayText.headerNatureLabel(
        selectedSubtype: _selectedSubtype,
        manualNature: _naturezaOcorrenciaController.text,
      ),
      status: status,
      dogName: widget.dogName,
      operatorName: operatorContext.name,
      elapsedLabel: OccurrenceDisplayText.elapsedLabel(startedAt),
      eventCount: showOperationalMetrics ? _occurrenceTimeline.length : null,
      showOperationalMetrics: showOperationalMetrics,
      dogImageUrl: activeDog?.profileImageUrl?.toString(),
      operatorImageUrl: currentUser?.photoUrl?.toString(),
      accent: tColor,
      statusColor: status == OccurrenceFormController.statusCanceled
          ? _hudRed
          : _hudGreen,
      onBack: _isSaving ? null : () => _closeForm(false),
    );
  }

  DateTime? _occurrenceStartedAt() {
    if (_activeOccurrenceStartedAt != null) return _activeOccurrenceStartedAt;
    final data = widget.initialData;
    if (data == null) return null;
    final startedAt = data['startedAt'];
    if (startedAt != null) {
      return parseFirestoreDate(startedAt);
    }
    final rawDate = data['_rawDate'];
    if (rawDate is DateTime) return rawDate;
    return null;
  }

  Widget _buildOccurrenceNatureStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OccurrenceNatureSearch(
          controller: _naturezaOcorrenciaController,
          focusNode: _occurrenceNatureFocusNode,
          natures: _occurrenceNatures,
          panelColor: _hudPanel,
          accent: _hudCyan,
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
                  color: _hudCyan,
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
    _occCtrl.selectedOutcomes
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

  Widget _buildStandardFormContent(Color tColor) {
    return ActivityFormBody(
      formKey: _formKey,
      children: [
        _buildTopActionRow(),
        const SizedBox(height: 16),
        _buildLocationTimeRow(),
        const SizedBox(height: 32),
        ..._buildDynamicFields(),
        ..._buildCategorySpecificFields(),
        ..._buildStandardContextFields(),
        ..._buildTrainingMetaFields(),
        ..._buildHealthMetaFields(),
        ..._buildRoutineMetaFields(),
        const SizedBox(height: 24),
        _buildDescriptionField(),
        const SizedBox(height: 24),
        _buildImageGallery(),
        const SizedBox(height: 48),
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

  void _applyOccurrenceQuickUpdateShortcut(
    OccurrenceQuickUpdateShortcut shortcut,
  ) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedOccurrenceUpdateTitle == shortcut.title) {
        _selectedOccurrenceUpdateTitle = null;
        return;
      }

      _selectedOccurrenceUpdateTitle = shortcut.title;
      _occurrenceStatus = OccurrenceFormController.statusInProgress;
      _occurrenceSuccessful = null;
      _occurrenceUpdateController.text = shortcut.template;
      _occurrenceUpdateController.selection = TextSelection.fromPosition(
        TextPosition(offset: _occurrenceUpdateController.text.length),
      );
    });
  }

  Future<List<File>> _pickOccurrenceEventPhotos() async {
    final files = await OccurrenceEventMediaService(
      storageService: StorageService(),
    ).pickCompressedPhotos();
    if (files.isEmpty) return const [];

    HapticFeedback.lightImpact();
    return files;
  }

  Future<List<Map<String, dynamic>>> _uploadOccurrenceEventPhotos(
    List<File> files,
  ) async {
    return OccurrenceEventMediaService(
      storageService: StorageService(),
    ).uploadPhotos(
      files: files,
      incidentIdOrDogId: _activeIncidentId ?? widget.dogId,
    );
  }

  Future<ResolvedLocation> _captureOccurrenceEventLocation() async {
    final location = await const LocationResolutionService()
        .currentHighAccuracy();
    HapticFeedback.lightImpact();
    return location;
  }

  Future<void> _openOccurrenceEventDetails(int index) async {
    if (index < 0 || index >= _occurrenceTimeline.length || _isSaving) return;

    final update = _occurrenceTimeline[index];
    final draft = OccurrenceEventDraft(update);
    final result = await _showOccurrenceEventDetailsSheet(update, draft);
    draft.dispose();
    if (result == null || !mounted) return;

    await _applyOccurrenceEventChange(index, result);
  }

  Future<OccurrenceEventChange?> _showOccurrenceEventDetailsSheet(
    IncidentProgressUpdate update,
    OccurrenceEventDraft draft,
  ) {
    return _showTacticalBottomSheet<OccurrenceEventChange>(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) => OccurrenceEventDetailsSheet(
            update: update,
            titleController: draft.titleController,
            descriptionController: draft.descriptionController,
            timestampLabel: _formatOccurrenceEventTimestamp(update.timestamp),
            eventLocation: draft.location,
            eventAttachments: draft.attachments,
            pendingPhotoCount: draft.pendingPhotoCount,
            backgroundColor: _hudBackground,
            panelColor: _hudPanel,
            accentColor: _hudCyan,
            successColor: _hudGreen,
            warningColor: _hudAmber,
            dangerColor: _hudRed,
            onAddPhotos: () async {
              final files = await _pickOccurrenceEventPhotos();
              if (files.isEmpty) return;
              setSheetState(() => draft.addPendingPhotos(files));
            },
            onCaptureLocation: () async {
              try {
                final eventPoint = await _captureOccurrenceEventLocation();
                setSheetState(() => draft.applyLocation(eventPoint));
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Não foi possível capturar o local: $e'),
                  ),
                );
              }
            },
            onDelete: () =>
                Navigator.of(context).pop(const OccurrenceEventChange.delete()),
            onSave: () async {
              try {
                final uploaded = await _uploadOccurrenceEventPhotos(
                  draft.pendingPhotos,
                );
                draft.addAttachments(uploaded);
                if (!context.mounted) return;
                Navigator.of(
                  context,
                ).pop(OccurrenceEventChange.update(draft.toProgressUpdate()));
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _cleanSaveError(e).isEmpty
                          ? 'Não foi possível salvar as evidências.'
                          : _cleanSaveError(e),
                    ),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }

  Future<T?> _showTacticalBottomSheet<T>({required WidgetBuilder builder}) {
    return showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: builder,
    );
  }

  String _formatOccurrenceEventTimestamp(DateTime timestamp) {
    return '${_formatDatePtBr(timestamp)} às ${_formatTimeOfDay(timestamp)}';
  }

  Future<void> _syncActiveOccurrenceSnapshot(DateTime updatedAt) async {
    if (_activeIncidentId == null) return;

    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final incidentVM = Provider.of<IncidentViewModel>(context, listen: false);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final operatorContext = _operatorContext(authVM: authVM, userVM: userVM);

    await _saveActiveOccurrenceSnapshot(
      incidentVM: incidentVM,
      currentRa: operatorContext.ra,
      currentOperatorName: operatorContext.name,
      updatedAt: updatedAt,
    );
  }

  Future<void> _applyOccurrenceEventChange(
    int index,
    OccurrenceEventChange change,
  ) async {
    if (index < 0 || index >= _occurrenceTimeline.length || _isSaving) return;
    final previousTimeline = List<IncidentProgressUpdate>.from(
      _occurrenceTimeline,
    );

    setState(() {
      _isSaving = true;
      _saveStatus = change.delete
          ? 'Excluindo evento...'
          : 'Atualizando evento...';
      _saveFailed = false;
      if (change.delete) {
        _occurrenceTimeline.removeAt(index);
      } else if (change.update != null) {
        _occurrenceTimeline[index] = change.update!;
      }
    });

    try {
      await _syncActiveOccurrenceSnapshot(DateTime.now());
      if (!mounted) return;
      _setSaveStatus('Linha do tempo sincronizada.');
      _showOperationalSnack(
        change.delete ? 'Evento excluído.' : 'Evento atualizado.',
        backgroundColor: const Color(0xFF123044),
        icon: change.delete
            ? Icons.delete_outline_rounded
            : Icons.cloud_done_rounded,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _occurrenceTimeline
          ..clear()
          ..addAll(previousTimeline);
        _saveFailed = true;
        _saveStatus = 'Falha ao sincronizar evento.';
      });
      _showOperationalSnack(
        _cleanSaveError(e).isEmpty
            ? 'Não foi possível sincronizar o evento.'
            : _cleanSaveError(e),
        backgroundColor: const Color(0xFFE53935),
        icon: Icons.error_outline_rounded,
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String _resolveIncidentResultSummary() {
    return _occCtrl.resultSummary(
      fallback: (_formData['Resultado da Busca'] ?? 'Averiguação').toString(),
    );
  }

  void _syncOccurrenceController() {
    _occCtrl.status = _occurrenceStatus;
    _occCtrl.successful = _occurrenceSuccessful;
    _occCtrl.selectedOutcomes
      ..clear()
      ..addAll(_selectedOccurrenceOutcomes);
  }

  void _copyOccurrenceControllerToFields({bool includeOutcomes = true}) {
    // Status e successful são lidos diretamente via getters proxied para _occCtrl
    if (!includeOutcomes) return;
    // selectedOutcomes já é um getter para _occCtrl.selectedOutcomes
  }

  List<String> _outcomeOptionsForOccurrenceSubtype(String? subtype) {
    return _occCtrl.outcomeOptionsForNature(subtype);
  }

  void _ensureOutcomeDetailRow(String option) {
    final normalized = const TextMatchService().normalizePtBr(option);
    if (normalized.contains('veiculo') && _detainedVehicles.isEmpty) {
      _addDetainedVehicle();
    } else if (normalized.contains('detido') && _detainedIndividuals.isEmpty) {
      _addDetainedIndividual();
    } else if (normalized.contains('objeto') && _seizedObjects.isEmpty) {
      _addSeizedObject();
    } else if (normalized.contains('droga') && _detecaoDrogas.isEmpty) {
      _addDrug();
    }
  }

  List<IncidentProgressUpdate> _buildIncidentProgressUpdates(
    DateTime finalDate, {
    required String authorId,
    required String authorName,
  }) {
    return OccurrenceProgressUpdateBuilder.build(
      timeline: _occurrenceTimeline,
      isNewRecord: widget.initialData == null,
      isEditingExistingRecord: widget.documentId != null,
      timestamp: finalDate,
      description: _descriptionController.text,
      location: _locationController.text,
      status: _occurrenceStatus,
      selectedUpdateTitle: _selectedOccurrenceUpdateTitle,
      updateNote: _occurrenceUpdateController.text,
      authorId: authorId,
      authorName: authorName,
    );
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

  List<Widget> _buildRoutineMetaFields() {
    if (widget.category != 'Rotina') {
      return const [];
    }

    return [
      RoutineActivityFields(
        visible: true,
        isFeeding: _selectedSubtype == _SheetSubtype.feeding,
        isPlayOrWalk:
            _selectedSubtype == _SheetSubtype.play ||
            _selectedSubtype == _SheetSubtype.walk,
        isWalk: _selectedSubtype == _SheetSubtype.walk,
        rationBrandController: _racaoMarcaController,
        rationAmountController: _racaoQtdController,
        durationController: _durationController,
        distanceController: _distanciaController,
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
        consultationSubtype: _SheetSubtype.consultation,
        vaccineSubtype: _SheetSubtype.vaccine,
        examSubtype: _SheetSubtype.exam,
        bathSubtype: _SheetSubtype.bath,
        accentColor: _hudCyan,
        responsibleController: _vetNameController,
        reasonController: _motivoController,
        vaccineTypeController: _tipoVacinaController,
        examTypeController: _tipoExameController,
        bathProductsController: _produtosBanhoController,
        returnDateController: _returnDateController,
        selectedVaccine: _selectedVacina,
        onVaccineChanged: (val) => setState(() {
          _selectedVacina = val;
          _tipoVacinaController.text = val ?? '';
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

  Widget _buildTopActionRow() {
    return QuickLocationActions(
      backgroundColor: _hudBackground,
      gpsColor: _hudAmber,
      timeColor: _hudGreen,
      onCaptureGps: () {
        HapticFeedback.mediumImpact();
        _fetchCurrentAddress();
      },
      onSetCurrentTime: () {
        HapticFeedback.mediumImpact();
        _setTimeToNow();
      },
    );
  }

  Widget _buildLocationTimeRow() {
    return ActivityLocationTimeFields(
      locationController: _locationController,
      timeController: _timeController,
      isHealth: widget.category == 'Saude',
    );
  }

  Widget _buildDescriptionField() {
    return ActivityDescriptionField(
      controller: _descriptionController,
      labelText: _descriptionLabel(),
      isListening: _isListening,
      onStartListening: _listen,
      onStopListening: _stopListening,
      onToggleListening: () {
        if (_isListening) {
          _stopListening();
        } else {
          _listen();
        }
      },
    );
  }

  String _descriptionLabel() {
    return ActivityFormLabels.descriptionLabel(
      category: widget.category,
      subtype: _selectedSubtype,
      feedingSubtype: _SheetSubtype.feeding,
    );
  }

  Widget _buildSaveButton(Color tColor) {
    return ActivitySaveButton(
      accentColor: tColor,
      foregroundColor: _hudBackground,
      isSaving: _isSaving,
      isCompressing: _isCompressing,
      saveFailed: _saveFailed,
      saveStatus: _saveStatus,
      idleLabel: _saveButtonLabel(),
      onSave: _handlePrimarySave,
    );
  }

  Widget _buildPrimarySaveButton(Color tColor) {
    return ActivityPrimarySaveButton(
      accentColor: tColor,
      foregroundColor: _hudBackground,
      isSaving: _isSaving,
      isCompressing: _isCompressing,
      saveStatus: _saveStatus,
      idleLabel: _saveButtonLabel(),
      onSave: _handlePrimarySave,
    );
  }

  Widget _buildSaveStatusPanel(Color accent) {
    return ActivitySaveStatusPanel(
      accentColor: accent,
      isSaving: _isSaving,
      saveFailed: _saveFailed,
      saveStatus: _saveStatus,
    );
  }

  String _saveButtonLabel() {
    return ActivityFormLabels.saveButtonLabel(
      category: widget.category,
      occurrenceStatus: _occurrenceStatus,
    );
  }

  void _handlePrimarySave() {
    HapticFeedback.heavyImpact();
    _save();
  }

  Widget _buildTrackingAction({
    required String startLabel,
    required IconData startIcon,
    required Color backgroundColor,
    required Color foregroundColor,
    bool isLightMode = false,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    EdgeInsetsGeometry capturedMargin = EdgeInsets.zero,
  }) {
    final distance = _formData['_trackingDistance'];
    return ActivityTrackingAction(
      hasRoute: _formData.containsKey('_trackingRoute'),
      distanceMeters: distance is num ? distance : null,
      startLabel: startLabel,
      startIcon: startIcon,
      startBackgroundColor: backgroundColor,
      startForegroundColor: foregroundColor,
      padding: padding,
      capturedMargin: capturedMargin,
      onStart: () => _openLiveTracking(isLightMode: isLightMode),
    );
  }

  Future<void> _openLiveTracking({bool isLightMode = false}) async {
    HapticFeedback.lightImpact();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveTrackingScreen(isLightMode: isLightMode),
      ),
    );

    if (result == null || result is! Map || !mounted) {
      return;
    }

    final distanceMeters = result['distanceMeters'];
    final durationSeconds = result['durationSeconds'];

    setState(() {
      _formData['_trackingRoute'] = result['route'];
      _formData['_trackingDistance'] = distanceMeters;
      if (durationSeconds is num) {
        _durationController.text = (durationSeconds / 60).floor().toString();
      }
      if (distanceMeters is num) {
        _distanciaController.text = (distanceMeters / 1000).toStringAsFixed(2);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rastreamento finalizado. Distância e tempo calculados.'),
        backgroundColor: Color(0xFF1B8A4C),
      ),
    );
  }

  void _setFormDataValue(String label, String? value) {
    setState(() {
      if (value == null) {
        _formData.remove(label);
      } else {
        _formData[label] = value;
      }
    });
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
        odorAccentColor: _hudAmber,
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
        searchCaptureSubtype: _SheetSubtype.searchCapture,
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

  List<String> get _detectionDrugOptions => [
    'Maconha',
    'Cocaína',
    'Crack',
    'Sintéticos',
    'Nose MP',
    'Outros',
  ];

  List<Widget> _buildCategorySpecificFields() {
    if (!_isOccurrenceCategory ||
        !OccurrenceSpecificFields.handles(_selectedSubtype)) {
      return const [];
    }

    return [
      OccurrenceSpecificFields(
        subtype: _selectedSubtype,
        formData: _formData,
        drugs: _detecaoDrogas,
        drugOptions: _detectionDrugOptions,
        accentColor: _getCategoryColor(),
        detectionAccentColor: _hudCyan,
        supportTeamController: _equipeController,
        reportNumberController: _boController,
        garrisonController: _guarnicaoController,
        situationController: _situacaoController,
        outcomeController: _desfechoController,
        odorObjectController: _odorObjetoController,
        missingTimeController: _tempoDesaparecimentoController,
        durationController: _durationController,
        terrainConditionController: _condicaoTerrenoController,
        orderNumberController: _numeroOsController,
        audienceController: _publicoController,
        themeController: _temaController,
        onAddDrug: _addDrug,
        onRemoveDrug: _removeDrug,
        onDrugTypeChanged: (drug, type) {
          setState(() => drug['tipo'] = type);
        },
        onSearchTypeChanged: (value) {
          setState(() {
            if (value == null) {
              _formData.remove('Tipo de Busca');
            } else {
              _formData['Tipo de Busca'] = value;
            }
          });
        },
        onPullWeather: _pullCurrentWeather,
      ),
    ];
  }

  Widget _buildImageGallery() {
    return MediaAttachmentGallery(
      isCompressing: _isCompressing,
      showPdfAttachment: _selectedSubtype == _SheetSubtype.exam,
      pdfName: _examePdfFile != null ? (_examePdfName ?? 'arquivo.pdf') : null,
      mediaAttachments: _mediaAttachments,
      activePhotoIndex: _activePhotoIndex,
      onPickImage: _pickImage,
      onPickPdf: _pickPdf,
      onRemovePdf: () => setState(() {
        _examePdfFile = null;
        _examePdfName = null;
      }),
      onSelectPhoto: (index) {
        setState(() => _activePhotoIndex = index);
        HapticFeedback.lightImpact();
      },
      onRemovePhoto: (index) {
        setState(() {
          MediaAttachmentRows.disposeCaption(_mediaAttachments[index]);
          _mediaAttachments.removeAt(index);
          if (_activePhotoIndex >= _mediaAttachments.length) {
            _activePhotoIndex = _mediaAttachments.length - 1;
          }
        });
        HapticFeedback.selectionClick();
      },
    );
  }

  Future<void> _pickPdf() async {
    final result = await const PdfAttachmentService().pickPdf();
    if (result != null) {
      setState(() {
        _examePdfFile = result.file;
        _examePdfName = result.name;
      });
      HapticFeedback.lightImpact();
    }
  }
}

