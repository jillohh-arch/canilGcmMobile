import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/incidents/domain/occurrence_nature.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/routine/presentation/viewmodels/routine_viewmodel.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/core/services/location_resolution_service.dart';
import 'package:canil_gcm/core/services/media_processing_service.dart';
import 'package:canil_gcm/core/services/media_attachment_upload_service.dart';
import 'package:canil_gcm/core/services/occurrence_event_media_service.dart';
import 'package:canil_gcm/core/services/operator_context_service.dart';
import 'package:canil_gcm/core/services/pdf_attachment_service.dart';
import 'package:canil_gcm/core/services/pt_br_date_time_service.dart';
import 'package:canil_gcm/core/services/speech_dictation_service.dart';
import 'package:canil_gcm/core/services/storage_service.dart';
import 'package:canil_gcm/core/services/text_match_service.dart';
import 'package:canil_gcm/core/services/weather_capture_service.dart';
import 'package:canil_gcm/core/utils/firestore_date.dart';
import 'package:canil_gcm/core/widgets/activity_form_body.dart';
import 'package:canil_gcm/core/widgets/activity_card_catalog.dart';
import 'package:canil_gcm/core/widgets/activity_common_fields.dart';
import 'package:canil_gcm/core/widgets/activity_category_menu_sheet.dart';
import 'package:canil_gcm/core/widgets/activity_form_labels.dart';
import 'package:canil_gcm/core/widgets/activity_form_scaffold.dart';
import 'package:canil_gcm/core/widgets/activity_save_controls.dart';
import 'package:canil_gcm/core/widgets/activity_tracking_action.dart';
import 'package:canil_gcm/features/training/presentation/widgets/dynamic_subtype_fields.dart';
import 'package:canil_gcm/features/training/presentation/widgets/training_activity_fields.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_activity_fields.dart';
import 'package:canil_gcm/core/widgets/media_attachment_rows.dart';
import 'package:canil_gcm/core/widgets/media_attachment_gallery.dart';
import 'package:canil_gcm/core/widgets/quick_location_actions.dart';
import 'package:canil_gcm/features/routine/presentation/widgets/routine_activity_fields.dart';
import 'package:canil_gcm/core/widgets/tactical_text_field.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_form_controller.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_display_text.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_dynamic_rows.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_event_draft.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_extra_fields_snapshot.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_payload_builder.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_progress_update_builder.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_save_validator.dart';
import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_wizard_result.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_command_header.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_active_context_summary.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_active_footer.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/event_details_bottom_sheet.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_nature_search.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_close_wizard.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_event_center_sheet.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_event_catalog.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_compact_location_block.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_form_scaffold.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_grouped_sections.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_initial_data_sheet.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_location_map_sheet.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_meta_fields.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_timeline_preview.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_quick_action.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_quick_action_catalog.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_quick_action_grid.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_quick_action_options_sheet.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_quick_update_catalog.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_specific_fields.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_stage_panels.dart';
import 'package:canil_gcm/features/incidents/presentation/widgets/occurrence_start_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/controllers/activity_sheet_occurrence_ctrl.dart';
import 'package:canil_gcm/features/shifts/presentation/controllers/activity_sheet_training_ctrl.dart';
import 'package:canil_gcm/features/shifts/presentation/controllers/activity_sheet_routine_ctrl.dart';
import 'package:canil_gcm/features/shifts/presentation/controllers/activity_sheet_health_ctrl.dart';
import 'live_tracking_screen.dart';

part '_occurrence_sheet_builders.dart';
part '_standard_sheet_builders.dart';

// Constantes HUD (compartilhadas com part files)
const Color _kHudBackground = Color(0xFF070B14);
const Color _kHudPanel = Color(0xFF0B1220);
const Color _kHudCyan = Color(0xFF00E5FF);
const Color _kHudAmber = Color(0xFFFFB84D);
const Color _kHudGreen = Color(0xFF00F5A0);
const Color _kHudRed = Color(0xFFFF3B5C);

abstract final class _SheetSubtype {
  static const detection = ActivitySubtypeIds.detection;
  static const missingPerson = ActivitySubtypeIds.missingPerson;
  static const event = ActivitySubtypeIds.event;

  // ignore: unused_field
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
  final _formKey = GlobalKey<FormState>();

  bool get _isOccurrenceCategory {
    final category = widget.category.toLowerCase();
    return category == 'ocorrencia' || category == 'ocorrência';
  }

  /// Verdadeiro para Ocorrência e Evento — ambos usam _occCtrl para salvar.
  bool get _isOccurrenceOrEventCategory =>
      _isOccurrenceCategory || widget.category == 'Evento';

  String? _nonEmptyId(String? value) {
    final id = value?.trim();
    return id == null || id.isEmpty ? null : id;
  }

  String? get _initialOccurrenceDocumentId {
    return _nonEmptyId(widget.documentId) ??
        _nonEmptyId(widget.initialData?['id']?.toString());
  }

  String? get _activeIncidentDocumentId {
    return _nonEmptyId(_activeIncidentId) ?? _initialOccurrenceDocumentId;
  }

  bool get _hasActiveIncidentDocument => _activeIncidentDocumentId != null;

  bool get _isExistingOccurrence =>
      _isOccurrenceCategory && _initialOccurrenceDocumentId != null;

  bool get _hasActiveOccurrenceRecord =>
      _isExistingOccurrence || _hasActiveIncidentDocument;

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

  // ---------------------------------------------------------------------------
  // Health controller (Fase 4)
  // ---------------------------------------------------------------------------
  late final ActivitySheetHealthCtrl _healthCtrl;

  // Getters Opção B: o State lê do controller ativo conforme a categoria.
  // Ocorrência + Evento → _occCtrl; Treino → _trainingCtrl;
  // Rotina → _routineCtrl; Saúde → _healthCtrl.
  TextEditingController get _locationController => _isOccurrenceOrEventCategory
      ? _occCtrl.locationController
      : widget.category == 'Treino'
      ? _trainingCtrl.locationController
      : _locationCtrlOther; // Rotina não usa campo location
  TextEditingController get _descriptionController =>
      _isOccurrenceOrEventCategory
      ? _occCtrl.descriptionController
      : widget.category == 'Treino'
      ? _trainingCtrl.descriptionController
      : widget.category == 'Rotina'
      ? _routineCtrl.descriptionController
      : _healthCtrl.descriptionController; // Saúde (categoria padrão)
  TextEditingController get _timeController => _isOccurrenceOrEventCategory
      ? _occCtrl.timeController
      : widget.category == 'Treino'
      ? _trainingCtrl.timeController
      : widget.category == 'Rotina'
      ? _routineCtrl.timeController
      : _healthCtrl.timeController; // Saúde (categoria padrão)
  // durationController: Treino -> _trainingCtrl, Rotina -> _routineCtrl
  TextEditingController get _durationController => widget.category == 'Treino'
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
  // Saúde: campos específicos (Fase 4)
  TextEditingController get _vetNameController => _healthCtrl.vetNameController;
  TextEditingController get _motivoController => _healthCtrl.motivoController;
  TextEditingController get _tipoVacinaController =>
      _healthCtrl.tipoVacinaController;
  TextEditingController get _tipoExameController =>
      _healthCtrl.tipoExameController;
  TextEditingController get _produtosBanhoController =>
      _healthCtrl.produtosBanhoController;
  TextEditingController get _returnDateController =>
      _healthCtrl.returnDateController;
  String? get _selectedVacina => _healthCtrl.selectedVacina;
  File? get _examePdfFile => _healthCtrl.examePdfFile;
  String? get _examePdfName => _healthCtrl.examePdfName;

  TextEditingController get _naturezaOcorrenciaController =>
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
  TextEditingController get _numeroOsController => _occCtrl.numeroOsController;
  TextEditingController get _publicoController => _occCtrl.publicoController;
  TextEditingController get _temaController => _occCtrl.temaController;

  // Getters de listas e estado de ocorrência
  List<Map<String, dynamic>> get _detecaoDrogas => _occCtrl.detecaoDrogas;
  List<Map<String, dynamic>> get _detainedIndividuals =>
      _occCtrl.detainedIndividuals;
  List<Map<String, dynamic>> get _seizedObjects => _occCtrl.seizedObjects;
  List<Map<String, dynamic>> get _detainedVehicles => _occCtrl.detainedVehicles;
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

  // Fallback para categorias sem controller dedicado para o campo.
  // _locationCtrlOther: Rotina não tem campo de localização.
  // _durationCtrlOther: duração de busca em Ocorrência/Evento.
  final _locationCtrlOther = TextEditingController();
  final _durationCtrlOther = TextEditingController();

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
    _healthCtrl = ActivitySheetHealthCtrl(
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
    } else if (widget.category == 'Saude') {
      _healthCtrl.init();
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
    // Inicializa hora atual para todos os controllers (novo registro)
    if (widget.initialData == null) {
      final nowTime = _formatTimeOfDay(DateTime.now());
      _occCtrl.timeController.text = nowTime;
      _trainingCtrl.timeController.text = nowTime;
      _routineCtrl.timeController.text = nowTime;
      _healthCtrl.timeController.text = nowTime;
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
    // Campos de texto populados por _trainingCtrl.init()
    _selectedSubtype = data['trainingType'];
  }

  void _populateRoutineEditData(Map<String, dynamic> data) {
    // Campos de texto populados por _routineCtrl.init()
    _selectedSubtype = data['activityType'];
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
    _occurrenceTimeline.clear();

    if (data['progressUpdates'] is List) {
      _occurrenceTimeline.addAll(
        (data['progressUpdates'] as List).map(
          (e) => IncidentProgressUpdate.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        ),
      );
    }

    _ensureInitialOccurrenceTimelineEntry(
      timestamp: _timelineStartFromOccurrenceData(data),
      authorId: data['_rawHandlerId']?.toString(),
    );
  }

  DateTime _timelineStartFromOccurrenceData(Map<String, dynamic> data) {
    if (data['startedAt'] != null) {
      return parseFirestoreDate(data['startedAt']);
    }
    if (data['_rawDate'] is DateTime) {
      return data['_rawDate'] as DateTime;
    }
    if (data['date'] != null) {
      return parseFirestoreDate(data['date']);
    }
    return _activeOccurrenceStartedAt ?? _resolveFormTimestamp();
  }

  IncidentProgressUpdate _initialOccurrenceTimelineEntry({
    DateTime? timestamp,
    String? authorId,
    String? authorName,
  }) {
    final description = _descriptionController.text.trim();

    return IncidentProgressUpdate(
      title: 'Início da ocorrência',
      description: description.isNotEmpty
          ? description
          : 'Ocorrência iniciada pela equipe.',
      timestamp:
          timestamp ?? _activeOccurrenceStartedAt ?? _resolveFormTimestamp(),
      location: _locationController.text.trim(),
      authorId: authorId,
      authorName: authorName,
    );
  }

  bool _isInitialOccurrenceTimelineEntry(IncidentProgressUpdate update) {
    final normalized = const TextMatchService().normalizePtBr(update.title);
    return normalized.contains('inicio') ||
        normalized.contains('registro inicial');
  }

  void _ensureInitialOccurrenceTimelineEntry({
    DateTime? timestamp,
    String? authorId,
    String? authorName,
  }) {
    if (_occurrenceTimeline.any(_isInitialOccurrenceTimelineEntry)) {
      return;
    }

    _occurrenceTimeline.insert(
      0,
      _initialOccurrenceTimelineEntry(
        timestamp: timestamp,
        authorId: authorId,
        authorName: authorName,
      ),
    );
  }

  void _populateHealthEditData(Map<String, dynamic> data) {
    // Campos de texto populados por _healthCtrl.init()
    _selectedSubtype = data['logType'];
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
  // _selectedVacina, _examePdfFile, _examePdfName: agora getters => _healthCtrl (Fase 4)

  bool _isCompressing = false;
  bool _isSaving = false;
  // _occurrenceFinishSubmitted agora via getter => _occCtrl.finishSubmitted
  String _saveStatus = '';
  bool _saveFailed = false;
  late SpeechDictationService _speechDictation;
  bool _isListening = false;
  int _activePhotoIndex = -1;
  bool _didAutoPrimeOccurrenceStart = false;
  // _timeController, _locationController, _descriptionController: getters por categoria
  // _returnDateController: getter => _healthCtrl.returnDateController (Fase 4)

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

    Navigator.pop(context, result || _hasActiveIncidentDocument);
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

  // Saúde: todos os campos agora são getters delegando para _healthCtrl (Fase 4)
  // _vetNameController, _clinicaController, _motivoController, _tipoVacinaController,
  // _tipoExameController, _produtosBanhoController, _returnDateController,
  // _materiaisController, _selectedVacina, _examePdfFile, _examePdfName

  // Faro / clima e campos de treino: migrados para _trainingCtrl (Fase 2)
  // _tempController, _humidityController, _objetivoTreinoController,
  // _dificuldadesController agora são getters delegando para _trainingCtrl

  // Rotina campos adicionais: migrados para _routineCtrl (Fase 3)
  // _racaoMarcaController, _racaoQtdController, _distanciaController

  // Fotos / mídias globais
  final List<Map<String, dynamic>> _mediaAttachments = [];

  // _occurrenceController agora encapsulado no _occCtrl
  // Estado de ocorrência: todos os campos abaixo são getters => _occCtrl

  @override
  void dispose() {
    _occCtrl.descriptionController.removeListener(
      _onOccurrenceDescriptionChanged,
    );
    _occCtrl.dispose();
    _trainingCtrl.dispose();
    _routineCtrl.dispose();
    _healthCtrl.dispose();
    _locationCtrlOther.dispose();
    _durationCtrlOther.dispose();
    // _returnDateController, _vetNameController, etc. agora em _healthCtrl (Fase 4)
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

  DateTime _resolveFormTimestamp() {
    final baseTimestamp = widget.initialData?['_rawDate'] ?? DateTime.now();
    return const PtBrDateTimeService().withTimeText(
      base: baseTimestamp,
      timeText: _timeController.text,
    );
  }

  // _uploadExamePdf, _prepareHealthMetadata, _saveHealth:
  // migrados para ActivitySheetHealthCtrl (Fase 4)

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
    return !_hasActiveIncidentDocument
        ? _resolveFormTimestamp()
        : DateTime.now();
  }

  DateTime _occurrenceStartedAtOr(DateTime fallbackDate) {
    return _activeOccurrenceStartedAt ??
        (widget.initialData?['startedAt'] != null
            ? parseFirestoreDate(widget.initialData!['startedAt'])
            : widget.initialData?['_rawDate'] ?? fallbackDate);
  }

  bool _isFinalizingOccurrence() {
    return _occurrenceStatus != OccurrenceFormController.statusInProgress;
  }

  bool _sameOccurrenceProgressUpdate(
    IncidentProgressUpdate left,
    IncidentProgressUpdate right,
  ) {
    return left.title == right.title &&
        left.description == right.description &&
        left.timestamp.isAtSameMomentAs(right.timestamp);
  }

  void _mergeOpenIncidentTimeline(Incident openIncident) {
    if (openIncident.progressUpdates.isEmpty) return;

    final current = List<IncidentProgressUpdate>.from(_occurrenceTimeline);
    _occurrenceTimeline.clear();

    for (final update in openIncident.progressUpdates) {
      if (!_occurrenceTimeline.any(
        (existing) => _sameOccurrenceProgressUpdate(existing, update),
      )) {
        _occurrenceTimeline.add(update);
      }
    }

    for (final update in current) {
      if (!_occurrenceTimeline.any(
        (existing) => _sameOccurrenceProgressUpdate(existing, update),
      )) {
        _occurrenceTimeline.add(update);
      }
    }
  }

  void _adoptOpenIncidentForCurrentOccurrence(Incident openIncident) {
    final id = _nonEmptyId(openIncident.id);
    if (id == null) return;

    _activeIncidentId = id;
    _activeOccurrenceStartedAt = openIncident.startedAt;
    _mergeOpenIncidentTimeline(openIncident);

    if (_locationController.text.trim().isEmpty) {
      _locationController.text = openIncident.location;
    }
    if (_selectedSubtype == null || _selectedSubtype!.trim().isEmpty) {
      _selectedSubtype = openIncident.type;
      _setOccurrenceNatureTextFromSelected();
    }
  }

  Future<void> _attachOpenIncidentIfAllowed({
    required IncidentViewModel incidentVM,
    required bool allowAttach,
  }) async {
    if (_hasActiveIncidentDocument) return;

    _setSaveStatus('Verificando ocorrência aberta...');
    final openIncident = await incidentVM.findOpenIncident(dogId: widget.dogId);
    if (openIncident == null) return;

    if (!allowAttach) {
      throw Exception(
        'Já existe uma ocorrência em andamento para este K9. Continue ou encerre o registro aberto antes de iniciar outro.',
      );
    }

    _adoptOpenIncidentForCurrentOccurrence(openIncident);
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

    await _attachOpenIncidentIfAllowed(
      incidentVM: incidentVM,
      allowAttach: _isFinalizingOccurrence() || _occurrenceTimeline.isNotEmpty,
    );

    _validateOccurrenceBeforeSave();

    final finalMedia = await _prepareOccurrenceMediaAttachments();
    final extraFields = _buildOccurrenceExtraFields(
      existingExtraFields: _existingOccurrenceExtraFields(),
    );

    final finalDate = _occurrenceSaveDate();
    final startedAt = _occurrenceStartedAtOr(finalDate);
    _activeOccurrenceStartedAt ??= startedAt;
    _ensureInitialOccurrenceTimelineEntry(
      timestamp: startedAt,
      authorId: operatorContext.ra,
      authorName: operatorContext.name,
    );
    final incidentUpdates = _buildIncidentProgressUpdates(
      finalDate,
      authorId: operatorContext.ra,
      authorName: operatorContext.name,
    );

    final inc = _buildOccurrenceIncident(
      currentRa: operatorContext.ra,
      finalDate: finalDate,
      startedAt: startedAt,
      extraFields: extraFields,
      mediaAttachments: finalMedia,
      progressUpdates: incidentUpdates,
    );

    if (_hasActiveIncidentDocument) {
      _setSaveStatus('Atualizando ocorrência no Firebase...');
      await incidentVM.updateIncident(inc);
      _occurrenceTimeline
        ..clear()
        ..addAll(incidentUpdates);
      return;
    }

    _setSaveStatus('Criando ocorrência no Firebase...');
    await incidentVM.saveIncident(inc);
    _activeIncidentId = inc.id;
    _activeOccurrenceStartedAt = inc.startedAt;
    _occurrenceTimeline
      ..clear()
      ..addAll(incidentUpdates);

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
          _setSaveStatus('Salvando rotina no Firebase...');
          await _routineCtrl.save(
            routineVM: routineVM,
            authVM: authVM,
            selectedSubtype: _selectedSubtype,
            formData: _formData,
            mediaAttachments: _mediaAttachments,
            resolvedTimestamp: _resolveFormTimestamp(),
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
        } else if (widget.category == 'Treino') {
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
          await _healthCtrl.save(
            healthVM: healthVM,
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
      documentId: _activeIncidentDocumentId,
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
        return _kHudRed;
      }
      if (_occurrenceStatus == OccurrenceFormController.statusCompleted) {
        return _kHudGreen;
      }
      return _kHudCyan;
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
}
