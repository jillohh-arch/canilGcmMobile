import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../viewmodels/training_viewmodel.dart';
import '../../models/training_session_model.dart';
import '../../models/occurrence_nature.dart';
import '../../models/routine_model.dart';
import '../../viewmodels/incident_viewmodel.dart';
import '../../models/incident.dart';
import '../../viewmodels/health_viewmodel.dart';
import '../../models/health_log_model.dart';
import '../../viewmodels/routine_viewmodel.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/user_viewmodel.dart';
import '../../viewmodels/dog_viewmodel.dart';
import '../../services/handler_identity_service.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../services/weather_service.dart';
import '../../utils/firestore_date.dart';
import '../../widgets/activity_common_fields.dart';
import '../../widgets/activity_category_menu_sheet.dart';
import '../../widgets/activity_save_controls.dart';
import '../../widgets/activity_tracking_action.dart';
import '../../widgets/health_activity_fields.dart';
import '../../widgets/hud_chip_group.dart';
import '../../widgets/hud_controls.dart';
import '../../widgets/hud_expansion_section.dart';
import '../../widgets/media_attachment_gallery.dart';
import '../../widgets/quick_location_actions.dart';
import '../../widgets/routine_activity_fields.dart';
import '../../widgets/tactical_text_field.dart';
import '../incidents/controllers/occurrence_form_controller.dart';
import '../incidents/controllers/occurrence_payload_builder.dart';
import '../incidents/widgets/occurrence_command_header.dart';
import '../incidents/widgets/occurrence_active_context_summary.dart';
import '../incidents/widgets/occurrence_active_footer.dart';
import '../incidents/widgets/event_details_bottom_sheet.dart';
import '../incidents/widgets/occurrence_detection_fields.dart';
import '../incidents/widgets/occurrence_nature_search.dart';
import '../incidents/widgets/occurrence_close_wizard.dart';
import '../incidents/widgets/occurrence_event_center_sheet.dart';
import '../incidents/widgets/occurrence_event_catalog.dart';
import '../incidents/widgets/occurrence_compact_location_block.dart';
import '../incidents/widgets/occurrence_form_scaffold.dart';
import '../incidents/widgets/occurrence_initial_data_sheet.dart';
import '../incidents/widgets/occurrence_location_map_sheet.dart';
import '../incidents/widgets/occurrence_timeline_preview.dart';
import '../incidents/widgets/occurrence_quick_action.dart';
import '../incidents/widgets/occurrence_quick_action_catalog.dart';
import '../incidents/widgets/occurrence_quick_action_grid.dart';
import '../incidents/widgets/occurrence_quick_action_options_sheet.dart';
import '../incidents/widgets/occurrence_quick_update_catalog.dart';
import '../incidents/widgets/occurrence_quick_update_shortcuts.dart';
import '../incidents/widgets/occurrence_stage_panels.dart';
import '../incidents/widgets/occurrence_start_screen.dart';
import 'live_tracking_screen.dart';

abstract final class _SheetSubtype {
  static const detection = 'Detecção';
  static const supportVehicle = 'Apoio à Viatura/Guarnição';
  static const missingPerson = 'Busca de Pessoa';
  static const serviceOrder = 'Ordem de Serviço (O.S.)';
  static const event = 'Palestra/Evento (RP)';

  static const obedience = 'Obediência';
  static const scentWork = 'Faro';
  static const guardProtection = 'Guarda e Proteção';
  static const searchCapture = 'Busca & Captura';
  static const physicalConditioning = 'Condicionamento Físico';
  static const leisureConditioning = 'Lazer/Condicionamento';

  static const consultation = 'Consulta';
  static const vaccine = 'Vacina';
  static const exam = 'Exame';
  static const bath = 'Banho';

  static const feeding = 'Alimentação';
  static const cleaning = 'Limpeza';
  static const walk = 'Passeio';
  static const rest = 'Descanso';
  static const play = 'Brincadeira';
  static const brushing = 'Escovação';
  static const other = 'Outros';
  static const narcoticsSearch = 'Busca de Entorpecentes';
}

class _OccurrenceEventChange {
  final bool delete;
  final IncidentProgressUpdate? update;

  const _OccurrenceEventChange.delete() : delete = true, update = null;
  const _OccurrenceEventChange.update(this.update) : delete = false;
}

class _OccurrenceEventLocation {
  final String address;
  final LatLng point;

  const _OccurrenceEventLocation({required this.address, required this.point});
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

  bool _showStartNatureEditor = false;
  bool _didAutoPrimeOccurrenceStart = false;

  late PageController _menuPageController;
  int _currentMenuPage = 0;

  final List<Map<String, dynamic>> ocorrenciasCards = [
    {
      'id': _SheetSubtype.detection,
      'image': 'assets/images/card_deteccao.png',
      'glow': Colors.orangeAccent,
    },
    {
      'id': _SheetSubtype.supportVehicle,
      'image': 'assets/images/card_apoio.png',
      'glow': Colors.orangeAccent,
    },
    {
      'id': _SheetSubtype.missingPerson,
      'image': 'assets/images/card_busca_captura.png',
      'glow': Colors.redAccent,
    },
    {
      'id': _SheetSubtype.serviceOrder,
      'image': 'assets/images/card_ordem_servico.png',
      'glow': Colors.blueGrey,
    },
    {
      'id': _SheetSubtype.event,
      'image': 'assets/images/card_palestras.png',
      'glow': Colors.greenAccent,
    },
    {
      'id': _SheetSubtype.other,
      'image': 'assets/images/card_outros.png',
      'glow': Colors.white54,
    },
  ];

  final List<Map<String, dynamic>> treinosCards = [
    {
      'id': _SheetSubtype.obedience,
      'image': 'assets/images/card_obediencia.png',
      'glow': Colors.blueAccent,
    },
    {
      'id': _SheetSubtype.scentWork,
      'image': 'assets/images/card_faro.png',
      'glow': Colors.orangeAccent,
    },
    {
      'id': _SheetSubtype.guardProtection,
      'image': 'assets/images/card_protecao.png',
      'glow': Colors.redAccent,
    },
    {
      'id': _SheetSubtype.searchCapture,
      'image': 'assets/images/card_treino_busca.png',
      'glow': Colors.greenAccent,
    },
    {
      'id': _SheetSubtype.physicalConditioning,
      'image': 'assets/images/card_condicionamento.png',
      'glow': Colors.cyanAccent,
    },
  ];

  final List<Map<String, dynamic>> saudeCards = [
    {
      'id': _SheetSubtype.consultation,
      'image': 'assets/images/card_consulta.png',
      'glow': Colors.tealAccent,
    },
    {
      'id': _SheetSubtype.vaccine,
      'image': 'assets/images/card_vacina.png',
      'glow': Colors.lightBlueAccent,
    },
    {
      'id': _SheetSubtype.exam,
      'image': 'assets/images/card_exame.png',
      'glow': Colors.indigoAccent,
    },
    {
      'id': _SheetSubtype.bath,
      'image': 'assets/images/card_banho.png',
      'glow': Colors.cyanAccent,
    },
  ];

  final List<Map<String, dynamic>> rotinaCards = [
    {
      'id': _SheetSubtype.feeding,
      'image': 'assets/images/card_alimentacao.png',
      'glow': Colors.amber,
    },
    {
      'id': _SheetSubtype.cleaning,
      'image': 'assets/images/card_limpeza.png',
      'glow': Colors.orange,
    },
    {
      'id': _SheetSubtype.walk,
      'image': 'assets/images/card_passeio.png',
      'glow': Colors.lightGreen,
    },
    {
      'id': _SheetSubtype.rest,
      'image': 'assets/images/card_descanso.png',
      'glow': Colors.deepOrangeAccent,
    },
    {
      'id': _SheetSubtype.play,
      'image': 'assets/images/card_brincadeira.png',
      'glow': Colors.yellowAccent,
    },
    {
      'id': _SheetSubtype.brushing,
      'image': 'assets/images/card_escovacao.png',
      'glow': Colors.orangeAccent,
    },
    {
      'id': _SheetSubtype.other,
      'image': 'assets/images/card_outros.png',
      'glow': Colors.white54,
    },
  ];

  List<Map<String, dynamic>> get _currentCategoryCards {
    if (widget.category == 'Treino') return treinosCards;
    if (widget.category == 'Saude') return saudeCards;
    if (widget.category == 'Rotina') return rotinaCards;
    return ocorrenciasCards;
  }

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _activeIncidentId = widget.documentId;
    if (widget.initialData?['startedAt'] != null) {
      _activeOccurrenceStartedAt = parseFirestoreDate(
        widget.initialData!['startedAt'],
      );
    } else if (widget.initialData?['_rawDate'] is DateTime) {
      _activeOccurrenceStartedAt = widget.initialData!['_rawDate'] as DateTime;
    }
    _menuPageController = PageController(viewportFraction: 0.80);
    _menuPageController.addListener(() {
      final page = _menuPageController.page?.round();
      if (page != null && page != _currentMenuPage) {
        setState(() => _currentMenuPage = page);
      }
    });
    _descriptionController.addListener(_onOccurrenceDescriptionChanged);
    if (_isOccurrenceCategory && widget.initialData == null) {
      _showMenu = false;
      _selectedSubtype = null;
      _selectedSubtypeImagePath = 'assets/images/k9_tactical_background.png';
      _occurrenceController.startNewOccurrence();
      _copyOccurrenceControllerToFields();
    }
    if (widget.initialData != null) {
      _showMenu = false;
      _populateEditData();
    }
    // Set default time to now when creating a new record
    if (widget.initialData == null) {
      final now = DateTime.now();
      _timeController.text =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    }
    if (_isOccurrenceCategory) {
      _loadOccurrenceNatures();
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

  Future<void> _loadOccurrenceNatures() async {
    try {
      final remoteNatures = await FirestoreService().getOccurrenceNatures();
      if (!mounted || remoteNatures.isEmpty) return;
      setState(() {
        _occurrenceNatures = remoteNatures;
        _setOccurrenceNatureTextFromSelected();
      });
    } catch (e) {
      debugPrint('Erro ao carregar naturezas de ocorrência: $e');
    }
  }

  void _populateEditData() {
    final d = widget.initialData!;
    _selectedSubtypeImagePath = 'assets/images/k9_tactical_background.png';

    // Populate time field from the raw date
    if (d['_rawDate'] is DateTime) {
      final dt = d['_rawDate'] as DateTime;
      _timeController.text =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    if (widget.category == 'Treino') {
      // Carrega campos da coleção trainings
      _selectedSubtype = d['trainingType'];
      _locationController.text = d['location'] ?? '';
      _descriptionController.text = d['handlerNotes'] ?? '';
      if (d['searchDuration'] != null) {
        _durationController.text = ((d['searchDuration'] as num) ~/ 60)
            .toString();
      }
      if (d['metadata'] != null) {
        _formData.addAll(Map<String, dynamic>.from(d['metadata']));
        final storedTemperature = _metadataValue('Temperatura (°C)');
        if (storedTemperature != null) {
          _tempController.text = storedTemperature.toString();
        }
        final storedHumidity = _metadataValue('Umidade (%)');
        if (storedHumidity != null) {
          _humidityController.text = storedHumidity.toString();
        }
      }
    } else if (widget.category == 'Rotina') {
      // Carrega campos da coleção routines (schema próprio)
      _selectedSubtype = d['activityType'];
      _descriptionController.text = d['notes'] ?? '';
      if (d['metadata'] != null) {
        _formData.addAll(Map<String, dynamic>.from(d['metadata']));
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
    } else if (_isOccurrenceCategory || widget.category == 'Evento') {
      _selectedSubtype = OccurrenceFormController.normalizeNature(
        d['type'] ??
            (_isOccurrenceCategory
                ? _SheetSubtype.detection
                : _SheetSubtype.event),
      );
      _setOccurrenceNatureTextFromSelected();
      _locationController.text = d['location'] ?? '';
      _descriptionController.text = d['description'] ?? '';
      _formData['Resultado da Busca'] = d['result'];
      _occurrenceStatus = OccurrenceFormController.normalizeStatus(d['status']);
      _occurrenceSuccessful = d['operationalSuccess'] as bool?;
      if (_occurrenceStatus == OccurrenceFormController.statusInProgress) {
        _showOccurrenceFinalization = false;
      } else {
        _showOccurrenceFinalization = true;
      }
      if (d['extraFields'] is Map) {
        _populateOccurrenceExtraFields(
          Map<String, dynamic>.from(d['extraFields'] as Map),
        );
      }
      if (d['outcomes'] is List) {
        _selectedOccurrenceOutcomes
          ..clear()
          ..addAll(
            List<String>.from(
              d['outcomes'] as List,
            ).map(OccurrenceFormController.normalizeOutcome),
          );
      }
      if (d['progressUpdates'] is List) {
        _occurrenceTimeline
          ..clear()
          ..addAll(
            (d['progressUpdates'] as List).map(
              (e) => IncidentProgressUpdate.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            ),
          );
      } else if (_descriptionController.text.isNotEmpty) {
        _occurrenceTimeline
          ..clear()
          ..add(
            IncidentProgressUpdate(
              title: 'Registro inicial',
              description: _descriptionController.text,
              timestamp: d['_rawDate'] is DateTime
                  ? d['_rawDate'] as DateTime
                  : DateTime.now(),
              location: _locationController.text,
            ),
          );
      }
      _syncOccurrenceController();
    } else if (widget.category == 'Saude') {
      _selectedSubtype = d['logType'];
      final obs = d['healthObservations'] as String? ?? '';
      _descriptionController.text = obs;
      if (obs.contains('Retorno agendado: ')) {
        final split = obs.split('Retorno agendado: ');
        if (split.length > 1) {
          _returnDateController.text = split[1].trim();
          _descriptionController.text = split[0].trim();
        }
      }
      // Pre-fill vet name
      _vetNameController.text = d['vetName'] ?? '';
    }

    final match = _currentCategoryCards
        .where((c) => c['id'] == _selectedSubtype)
        .toList();
    if (match.isNotEmpty) {
      _selectedSubtypeImagePath = match.first['image'];
    }
  }

  dynamic _metadataValue(String key) {
    return _formData[key] ?? _formData[_legacyMojibakeKey(key)];
  }

  String _legacyMojibakeKey(String value) {
    return latin1.decode(utf8.encode(value));
  }

  void _populateOccurrenceExtraFields(Map<String, dynamic> extraFields) {
    String textValue(String key) => extraFields[key]?.toString() ?? '';

    _equipeController.text = textValue('equipe');
    _boController.text = textValue('bo');
    _guarnicaoController.text = textValue('guarnicao');
    _situacaoController.text = textValue('situacao');
    _desfechoController.text = textValue('desfecho');
    _odorObjetoController.text = textValue('odor_inicial');
    _tempoDesaparecimentoController.text = textValue('tempo_desaparecimento');
    _durationController.text = textValue('duracao_busca');
    _condicaoTerrenoController.text = textValue('condicao_terreno');
    _numeroOsController.text = textValue('numero_os');
    _publicoController.text = textValue('publico_estimado');
    _temaController.text = textValue('tema');

    if (_selectedSubtype == _SheetSubtype.other) {
      _naturezaOcorrenciaController.text =
          textValue('natureza_manual').isNotEmpty
          ? textValue('natureza_manual')
          : textValue('natureza');
    }

    if (extraFields['tipo_busca'] != null) {
      _formData['Tipo de Busca'] = extraFields['tipo_busca'];
    }

    final lat = extraFields['locationLat'];
    final lng = extraFields['locationLng'];
    if (lat is num && lng is num) {
      _selectedLocationLatLng = LatLng(lat.toDouble(), lng.toDouble());
    }

    final detailedResults = extraFields['resultadosDetalhados'];
    if (detailedResults is Map) {
      final details = Map<String, dynamic>.from(detailedResults);
      _hydrateDetainedIndividuals(details['individuosDetidos']);
      _hydrateSeizedObjects(details['objetosApreendidos']);
      _hydrateDrugRows(details['drogasApreendidas']);
      _hydrateDetainedVehicles(details['veiculosDetidos']);
    }

    if (_detecaoDrogas.isEmpty) {
      _hydrateDrugRows(extraFields['drogas']);
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
    _disposeDynamicResultRows(_detainedIndividuals, ['quantidade']);
    _detainedIndividuals
      ..clear()
      ..addAll(
        rows.map((row) {
          final data = row is Map ? Map<String, dynamic>.from(row) : {};
          return {
            'quantidade': TextEditingController(
              text: data['quantidade']?.toString() ?? '',
            ),
          };
        }),
      );
  }

  void _hydrateSeizedObjects(dynamic rows) {
    if (rows is! List) return;
    _disposeDynamicResultRows(_seizedObjects, ['descricao', 'quantidade']);
    _seizedObjects
      ..clear()
      ..addAll(
        rows.map((row) {
          final data = row is Map ? Map<String, dynamic>.from(row) : {};
          return {
            'descricao': TextEditingController(
              text: data['descricao']?.toString() ?? '',
            ),
            'quantidade': TextEditingController(
              text: data['quantidade']?.toString() ?? '',
            ),
          };
        }),
      );
  }

  void _hydrateDrugRows(dynamic rows) {
    if (rows is! List) return;
    _disposeDrugRows();
    _detecaoDrogas
      ..clear()
      ..addAll(
        rows.map((row) {
          final data = row is Map ? Map<String, dynamic>.from(row) : {};
          final rawType = data['tipo']?.toString() ?? '';
          final knownType = _detectionDrugOptions.contains(rawType);
          return {
            'tipo': knownType ? rawType : 'Outros',
            'quantidade': TextEditingController(
              text: data['quantidade']?.toString() ?? '',
            ),
            'especificar': TextEditingController(
              text: knownType ? '' : rawType,
            ),
          };
        }),
      );
  }

  void _hydrateDetainedVehicles(dynamic rows) {
    if (rows is! List) return;
    _disposeDynamicResultRows(_detainedVehicles, ['tipo', 'placa']);
    _detainedVehicles
      ..clear()
      ..addAll(
        rows.map((row) {
          final data = row is Map ? Map<String, dynamic>.from(row) : {};
          return {
            'tipo': TextEditingController(text: data['tipo']?.toString() ?? ''),
            'placa': TextEditingController(
              text: data['placa']?.toString() ?? '',
            ),
          };
        }),
      );
  }

  bool _showMenu = true;
  String? _selectedSubtype;
  String? _selectedSubtypeImagePath;
  final Map<String, dynamic> _formData = {};
  List<OccurrenceNature> _occurrenceNatures = OccurrenceNatureSeed.items;
  String? _selectedVacina; // for vaccine dropdown

  bool _isCompressing = false;
  bool _isSaving = false;
  bool _occurrenceFinishSubmitted = false;
  String _saveStatus = '';
  bool _saveFailed = false;
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _previousText = '';
  int _activePhotoIndex = -1;

  final _timeController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _occurrenceNatureFocusNode = FocusNode();
  final _occurrenceUpdateController = TextEditingController();
  final _occurrenceUpdateFocusNode = FocusNode();
  final _durationController = TextEditingController();
  final _returnDateController = TextEditingController();

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

  String _successSaveMessage() {
    if (_isOccurrenceCategory || widget.category == 'Evento') {
      return _occurrenceStatus == OccurrenceFormController.statusInProgress
          ? 'Ocorrência salva em andamento no Firebase.'
          : 'Ocorrência concluída e sincronizada.';
    }

    if (widget.category == 'Treino') {
      return 'Treino salvo no Firebase.';
    }
    if (widget.category == 'Rotina') {
      return 'Rotina salva no Firebase.';
    }
    if (widget.category == 'Saude') {
      return 'Prontuário salvo no Firebase.';
    }

    return 'Registro salvo no Firebase.';
  }

  // Faro / clima fields
  final _tempController = TextEditingController();
  final _humidityController = TextEditingController();

  // Ocorrência - módulo: detecção
  final List<Map<String, dynamic>> _detecaoDrogas =
      []; // { 'tipo': String, 'quantidade': TextEditingController, 'especificar': TextEditingController }
  final _equipeController = TextEditingController();
  final _boController = TextEditingController();
  final _naturezaOcorrenciaController =
      TextEditingController(); // Natureza da ocorrência

  // Ocorrência - módulo: apoio
  final _guarnicaoController = TextEditingController();
  final _situacaoController = TextEditingController();
  final _desfechoController = TextEditingController();

  // Saúde - campos adicionais
  final _vetNameController = TextEditingController();
  final _clinicaController = TextEditingController();
  final _motivoController = TextEditingController();
  final _tipoVacinaController = TextEditingController();
  final _tipoExameController = TextEditingController();
  final _produtosBanhoController = TextEditingController();

  // Treino campos adicionais
  final _objetivoTreinoController = TextEditingController();
  final _dificuldadesController = TextEditingController();

  // Rotina campos adicionais
  final _racaoMarcaController = TextEditingController();
  final _racaoQtdController = TextEditingController();
  final _distanciaController = TextEditingController();

  // PDF/arquivo para Exames
  File? _examePdfFile;
  String? _examePdfName;

  // Ocorrência - módulo: busca e captura
  final _odorObjetoController = TextEditingController();
  final _tempoDesaparecimentoController = TextEditingController();
  final _condicaoTerrenoController = TextEditingController();

  // Ocorrência - módulo: O.S.
  final _numeroOsController = TextEditingController();

  // Fotos / mídias globais
  final List<Map<String, dynamic>> _mediaAttachments =
      []; // { 'file': File, 'caption': TextEditingController }

  // Restantes
  final _orgaoController = TextEditingController();
  final _materiaisController = TextEditingController();
  final _publicoController = TextEditingController();
  final _temaController = TextEditingController();
  final OccurrenceFormController _occurrenceController =
      OccurrenceFormController();
  String _occurrenceStatus = OccurrenceFormController.statusCompleted;
  bool? _occurrenceSuccessful = true;
  final Set<String> _selectedOccurrenceOutcomes = {};
  final List<IncidentProgressUpdate> _occurrenceTimeline = [];
  String? _selectedOccurrenceUpdateTitle;
  bool _showOccurrenceFinalization = false;
  String? _activeIncidentId;
  DateTime? _activeOccurrenceStartedAt;
  LatLng? _selectedLocationLatLng;

  final List<Map<String, dynamic>> _detainedIndividuals = [];
  final List<Map<String, dynamic>> _seizedObjects = [];
  final List<Map<String, dynamic>> _detainedVehicles = [];

  @override
  void dispose() {
    _descriptionController.removeListener(_onOccurrenceDescriptionChanged);
    _timeController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _occurrenceNatureFocusNode.dispose();
    _occurrenceUpdateController.dispose();
    _occurrenceUpdateFocusNode.dispose();
    _durationController.dispose();
    _returnDateController.dispose();
    _tempController.dispose();
    _humidityController.dispose();
    _orgaoController.dispose();
    _materiaisController.dispose();
    _publicoController.dispose();
    _temaController.dispose();
    _equipeController.dispose();
    _boController.dispose();
    _naturezaOcorrenciaController.dispose();
    _guarnicaoController.dispose();
    _situacaoController.dispose();
    _desfechoController.dispose();
    _odorObjetoController.dispose();
    _tempoDesaparecimentoController.dispose();
    _condicaoTerrenoController.dispose();
    _numeroOsController.dispose();
    _vetNameController.dispose();
    _clinicaController.dispose();
    _motivoController.dispose();
    _tipoVacinaController.dispose();
    _tipoExameController.dispose();
    _produtosBanhoController.dispose();
    _objetivoTreinoController.dispose();
    _dificuldadesController.dispose();
    _racaoMarcaController.dispose();
    _racaoQtdController.dispose();
    _distanciaController.dispose();
    _disposeDrugRows();
    for (var m in _mediaAttachments) {
      m['caption'].dispose();
    }
    _disposeDynamicResultRows(_detainedIndividuals, ['quantidade']);
    _disposeDynamicResultRows(_seizedObjects, ['descricao', 'quantidade']);
    _disposeDynamicResultRows(_detainedVehicles, ['tipo', 'placa']);
    _menuPageController.dispose();
    super.dispose();
  }

  void _disposeDynamicResultRows(
    List<Map<String, dynamic>> rows,
    List<String> controllerKeys,
  ) {
    for (final row in rows) {
      for (final key in controllerKeys) {
        row[key]?.dispose();
      }
    }
  }

  void _disposeDrugRows() {
    for (final droga in _detecaoDrogas) {
      droga['quantidade']?.dispose();
      droga['especificar']?.dispose();
    }
  }

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
        _occurrenceController.status = OccurrenceFormController.statusCompleted;
        _occurrenceController.successful = true;
        _occurrenceController.selectNature(type);
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
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        // Formato: Rua [Nome], [Bairro], [Cidade]
        final address =
            "${p.thoroughfare}, ${p.subLocality ?? p.subAdministrativeArea}, ${p.locality}";
        setState(() {
          _locationController.text = address;
          _selectedLocationLatLng = LatLng(
            position.latitude,
            position.longitude,
          );
        });
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao obter endereço: $e')));
      }
    }
  }

  Future<void> _selectOccurrenceLocation(LatLng point) async {
    setState(() => _selectedLocationLatLng = point);
    try {
      final placemarks = await placemarkFromCoordinates(
        point.latitude,
        point.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final address = [
          p.thoroughfare,
          p.subLocality ?? p.subAdministrativeArea,
          p.locality,
        ].where((part) => part != null && part.trim().isNotEmpty).join(', ');
        if (address.isNotEmpty) {
          setState(() => _locationController.text = address);
        }
      }
    } catch (_) {
      // Mantém o ponto manual no mapa mesmo que a conversão de endereço falhe.
    }
  }

  void _setTimeToNow() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    setState(() {
      _timeController.text = "$h:$m";
    });
    HapticFeedback.selectionClick();
  }

  void _addDrug() {
    setState(() {
      _detecaoDrogas.add({
        'tipo': 'Maconha',
        'quantidade': TextEditingController(),
        'especificar': TextEditingController(),
      });
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
      _detainedIndividuals.add({'quantidade': TextEditingController()});
    });
    HapticFeedback.selectionClick();
  }

  void _addSeizedObject() {
    setState(() {
      _seizedObjects.add({
        'descricao': TextEditingController(),
        'quantidade': TextEditingController(),
      });
    });
    HapticFeedback.selectionClick();
  }

  void _addDetainedVehicle() {
    setState(() {
      _detainedVehicles.add({
        'tipo': TextEditingController(),
        'placa': TextEditingController(),
      });
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _pullCurrentWeather() async {
    try {
      HapticFeedback.lightImpact();
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final weatherService = WeatherService();
      final weather = await weatherService.getCurrentWeather(
        position.latitude,
        position.longitude,
      );
      if (weather != null) {
        setState(() {
          _tempController.text = weather['temperature'].toString();
          _humidityController.text = weather['humidity'].toString();
          if (_condicaoTerrenoController.text.isEmpty) {
            _condicaoTerrenoController.text =
                "Temp média: ${weather['temperature']}°C / Umidade: ${weather['humidity']}%";
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

  Future<File?> _compressImage(File file) async {
    try {
      final dir = await getTemporaryDirectory();
      final targetPath =
          '${dir.absolute.path}/temp_${DateTime.now().millisecondsSinceEpoch}.jpg';

      var result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 70,
        format: CompressFormat.jpeg,
      );

      return result != null ? File(result.path) : null;
    } catch (e) {
      debugPrint("Erro ao comprimir imagem: $e");
      return null; // fallback: return null se falhar
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage(
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 60,
    );
    if (images.isNotEmpty) {
      if (mounted) {
        setState(() => _isCompressing = true);
      }

      final compressedImages = <File>[];
      for (var img in images) {
        final File originalFile = File(img.path);
        final File? compressed = await _compressImage(originalFile);
        if (compressed != null) {
          compressedImages.add(compressed);
        } else {
          // Se a compressão falhar, usa a imagem original.
          compressedImages.add(originalFile);
        }
      }

      setState(() {
        for (var file in compressedImages) {
          _mediaAttachments.add({
            'file': file,
            'caption': TextEditingController(),
            'status': 'pending',
          });
        }
        _isCompressing = false;
      });
      HapticFeedback.lightImpact();
    }
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (val) {
          if (mounted) setState(() => _isListening = false);
        },
      );
      if (available) {
        if (mounted) setState(() => _isListening = true);
        HapticFeedback.lightImpact();
        _previousText = _descriptionController.text;
        if (_previousText.isNotEmpty && !_previousText.endsWith(' ')) {
          _previousText += ' ';
        }
        _speech.listen(
          localeId: 'pt_BR',
          onResult: (val) {
            if (mounted) {
              setState(() {
                _descriptionController.text =
                    _previousText + val.recognizedWords;
              });
            }
          },
        );
      }
    } else {
      _stopListening();
    }
  }

  void _stopListening() {
    if (_isListening) {
      if (mounted) setState(() => _isListening = false);
      _speech.stop();
      HapticFeedback.selectionClick();
    }
  }

  Future<List<Map<String, dynamic>>> _uploadAllMedia(String folder) async {
    final StorageService storageService = StorageService();
    List<Map<String, dynamic>> finalMedia = [];

    if (_mediaAttachments.isEmpty) return finalMedia;

    if (mounted) {
      setState(() {
        _saveStatus = 'Fazendo upload de mídia(s)...';
      });
    }

    for (int i = 0; i < _mediaAttachments.length; i++) {
      if (_mediaAttachments[i]['status'] == 'done') {
        final existingUrl = _mediaAttachments[i]['url']?.toString();
        if (existingUrl != null && existingUrl.isNotEmpty) {
          finalMedia.add({
            'url': existingUrl,
            'caption': _mediaAttachments[i]['caption']?.text ?? '',
          });
        }
        continue;
      }

      if (mounted) setState(() => _mediaAttachments[i]['status'] = 'uploading');

      final String? url = await storageService.uploadProfileImage(
        _mediaAttachments[i]['file'],
        folder,
      );

      if (url != null) {
        if (mounted) {
          setState(() {
            _mediaAttachments[i]['status'] = 'done';
            _mediaAttachments[i]['url'] = url;
          });
        }
        finalMedia.add({
          'url': url,
          'caption': _mediaAttachments[i]['caption'].text,
        });
      } else {
        if (mounted) setState(() => _mediaAttachments[i]['status'] = 'pending');
        throw Exception("Falha ao subir a foto ${i + 1}.");
      }
    }
    return finalMedia;
  }

  List<Map<String, dynamic>> _mergeExistingIncidentMedia(
    List<Map<String, dynamic>> uploadedMedia,
  ) {
    final existing = widget.initialData?['mediaAttachments'];
    final merged = <Map<String, dynamic>>[];

    if (existing is List) {
      merged.addAll(
        existing.whereType<Map>().map(
          (item) => Map<String, dynamic>.from(item),
        ),
      );
    }

    merged.addAll(uploadedMedia);
    return merged;
  }

  Future<String?> _uploadExamePdf() async {
    if (_examePdfFile == null) return null;
    final StorageService storageService = StorageService();
    if (mounted) setState(() => _saveStatus = 'Enviando PDF do Exame...');
    return await storageService.uploadFile(
      _examePdfFile!,
      'health/exams',
      mimeType: 'application/pdf',
      extension: 'pdf',
    );
  }

  DateTime _resolveFormTimestamp() {
    DateTime finalTimestamp = widget.initialData?['_rawDate'] ?? DateTime.now();

    if (_timeController.text.isEmpty) {
      return finalTimestamp;
    }

    final parts = _timeController.text.split(':');
    if (parts.length != 2) {
      return finalTimestamp;
    }

    return DateTime(
      finalTimestamp.year,
      finalTimestamp.month,
      finalTimestamp.day,
      int.tryParse(parts[0]) ?? finalTimestamp.hour,
      int.tryParse(parts[1]) ?? finalTimestamp.minute,
    );
  }

  Future<void> _saveRoutine({
    required AuthViewModel authVM,
    required RoutineViewModel routineVM,
  }) async {
    final currentRa = HandlerIdentityService.raFromUser(authVM.user) ?? '';
    final List<Map<String, dynamic>> finalMedia = await _uploadAllMedia(
      'routines',
    );

    final routine = RoutineModel(
      id: widget.documentId,
      dogId: widget.dogId,
      dogName: widget.dogName,
      handlerId: widget.initialData?['_rawHandlerId'] ?? currentRa,
      activityType: _selectedSubtype!,
      status: 'Concluído',
      timestamp: _resolveFormTimestamp(),
      notes: _descriptionController.text.isNotEmpty
          ? _descriptionController.text
          : null,
      mediaAttachments: finalMedia.isNotEmpty ? finalMedia : null,
      metadata: _formData.isNotEmpty
          ? Map<String, dynamic>.from(_formData)
          : null,
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

    if (_returnDateController.text.isNotEmpty) {
      _formData['Data de Retorno'] = _returnDateController.text;
    }

    final hLog = HealthLogModel(
      id: widget.documentId,
      dogId: widget.dogId,
      dogName: widget.dogName,
      date: widget.initialData?['_rawDate'] ?? DateTime.now(),
      logType: _selectedSubtype!,
      healthObservations:
          _descriptionController.text +
          (_returnDateController.text.isNotEmpty
              ? "\nRetorno agendado: ${_returnDateController.text}"
              : ''),
      vetName: _vetNameController.text.isNotEmpty
          ? _vetNameController.text
          : null,
      mediaAttachments: finalMedia.isNotEmpty ? finalMedia : null,
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
    final List<Map<String, dynamic>> finalMedia = await _uploadAllMedia(
      'trainings',
    );
    final currentRa =
        widget.initialData?['_rawHandlerId'] as String? ??
        HandlerIdentityService.raFromUser(authVM.user) ??
        '';

    if (_selectedSubtype == _SheetSubtype.scentWork) {
      if (_tempController.text.isNotEmpty) {
        _formData['Temperatura (°C)'] = _tempController.text;
      }
      if (_humidityController.text.isNotEmpty) {
        _formData['Umidade (%)'] = _humidityController.text;
      }
    }

    int? durationSecs;
    if (_durationController.text.isNotEmpty) {
      final mins = int.tryParse(_durationController.text) ?? 0;
      durationSecs = mins * 60;
    }

    final session = TrainingSessionModel(
      id: widget.documentId,
      dogId: widget.dogId,
      dogName: widget.dogName,
      handlerId: currentRa,
      date: widget.initialData?['_rawDate'] ?? DateTime.now(),
      trainingType: _selectedSubtype!,
      location: _locationController.text.isNotEmpty
          ? _locationController.text
          : 'Base GCM',
      weather: 'Limpo',
      handlerNotes: _descriptionController.text,
      searchDuration: durationSecs,
      mediaAttachments: finalMedia.isNotEmpty ? finalMedia : null,
      metadata: _formData,
    );

    if (widget.documentId != null) {
      await trainingVM.updateTrainingSession(session);
    } else {
      await trainingVM.addTrainingSession(session);
    }
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
          _setSaveStatus('Salvando rotina no Firebase...');
          await _saveRoutine(authVM: authVM, routineVM: routineVM);
        } else if (widget.category == 'Treino') {
          _setSaveStatus('Validando treino...');
          if (_durationController.text.isNotEmpty) {
            _formData['Duração (min)'] = _durationController.text;
          }
          _setSaveStatus('Salvando treino no Firebase...');
          await _saveTraining(trainingVM: trainingVM, authVM: authVM);
        } else if (_isOccurrenceCategory || widget.category == 'Evento') {
          _setSaveStatus('Validando ocorrência...');
          final currentRa =
              HandlerIdentityService.raFromUser(authVM.user) ?? '';
          final currentOperatorName = _currentOperatorName(
            authVM: authVM,
            userVM: userVM,
            currentRa: currentRa,
          );

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

          final finalizing =
              _occurrenceStatus != OccurrenceFormController.statusInProgress;
          if (finalizing && _descriptionController.text.trim().isEmpty) {
            throw Exception(
              'Preencha a descrição final antes de encerrar a ocorrência.',
            );
          }
          if (finalizing && _selectedOccurrenceOutcomes.isEmpty) {
            throw Exception(
              'Selecione ao menos um resultado final antes de encerrar.',
            );
          }
          if (_selectedSubtype!.trim().isEmpty ||
              _naturezaOcorrenciaController.text.trim().isEmpty) {
            throw Exception('Informe a natureza da ocorrência.');
          }

          _setSaveStatus('Preparando anexos da ocorrência...');
          final List<Map<String, dynamic>> uploadedMedia =
              await _uploadAllMedia('incidents');
          final List<Map<String, dynamic>> finalMedia =
              _mergeExistingIncidentMedia(uploadedMedia);
          final existingExtraFields = widget.initialData?['extraFields'] is Map
              ? Map<String, dynamic>.from(
                  widget.initialData!['extraFields'] as Map,
                )
              : null;

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

          final finalDate = _activeIncidentId == null
              ? _resolveFormTimestamp()
              : DateTime.now();
          final incidentUpdates = _buildIncidentProgressUpdates(
            finalDate,
            authorId: currentRa,
            authorName: currentOperatorName,
          );
          final startedAt =
              _activeOccurrenceStartedAt ??
              (widget.initialData?['startedAt'] != null
                  ? parseFirestoreDate(widget.initialData!['startedAt'])
                  : widget.initialData?['_rawDate'] ?? finalDate);

          final inc = OccurrencePayloadBuilder.buildIncident(
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
            mediaAttachments: finalMedia,
            status: _occurrenceStatus,
            operationalSuccess: _occurrenceSuccessful,
            outcomes: _selectedOccurrenceOutcomes.toList(),
            startedAt: startedAt,
            updatedAt: finalDate,
            progressUpdates: incidentUpdates,
          );

          if (_activeIncidentId != null) {
            _setSaveStatus('Atualizando ocorrência no Firebase...');
            await incidentVM.updateIncident(inc);
          } else {
            _setSaveStatus('Criando ocorrência no Firebase...');
            await incidentVM.saveIncident(inc);
            _activeIncidentId = inc.id;
            _activeOccurrenceStartedAt = inc.startedAt;
            if ((_selectedSubtype == _SheetSubtype.detection ||
                    _selectedSubtype == _SheetSubtype.narcoticsSearch) &&
                extraFields.containsKey('drogas') &&
                (extraFields['drogas'] as List).isNotEmpty) {
              await userVM.grantBadge(currentRa, 'faro_afiado');
            }
          }
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

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      resizeToAvoidBottomInset: true,
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverAppBar(
            expandedHeight: _isOccurrenceCategory ? 96 : 250,
            pinned: true,
            stretch: true,
            backgroundColor: const Color(0xFF1E1E1E),
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_rounded,
                color: Colors.white,
                size: 20,
              ),
              onPressed: _isSaving
                  ? null
                  : () {
                      if (widget.fullScreen ||
                          widget.initialData != null ||
                          _isOccurrenceCategory) {
                        _closeForm(false);
                      } else {
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
                    },
            ),
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [StretchMode.zoomBackground],
              title: Text(
                _isOccurrenceCategory
                    ? 'OCORRÊNCIA'
                    : _selectedSubtype?.toUpperCase() ?? '',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (_selectedSubtypeImagePath != null &&
                      !_isOccurrenceCategory)
                    Hero(
                      tag: 'hero_category_$_selectedSubtype',
                      child: Image.asset(
                        _selectedSubtypeImagePath!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
                    )
                  else
                    Container(color: const Color(0xFF1E1E1E)),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xFF121212)],
                        stops: [0.3, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              color: const Color(0xFF121212),
              child: _buildFormContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOccurrenceFormScaffold() {
    final tColor = _getCategoryColor();
    final statusLabel =
        _occurrenceStatus == OccurrenceFormController.statusCompleted
        ? 'FECHADA'
        : widget.documentId == null
        ? 'NOVA'
        : 'ABERTA';

    return OccurrenceFormScaffold(
      backgroundColor: _hudBackground,
      panelColor: _hudPanel,
      accentColor: _hudCyan,
      showTopBar: !_hasActiveOccurrenceRecord,
      isSaving: _isSaving,
      modeLabel: widget.documentId == null
          ? 'NOVA OCORRÊNCIA'
          : 'OCORRÊNCIA OPERACIONAL',
      statusLabel: statusLabel,
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
    final match = _currentCategoryCards
        .where((c) => c['id'] == _selectedSubtype)
        .toList();
    if (match.isNotEmpty) return match.first['glow'];
    return const Color(0xFF1B8A4C);
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            if (_selectedSubtype == _SheetSubtype.detection)
              ..._buildDetecaoGrouped(),
            if (_selectedSubtype == _SheetSubtype.missingPerson)
              ..._buildBuscaPessoaGrouped(),
            ..._buildOccurrenceMetaFields(),
            const SizedBox(height: 32),
            _buildSaveButton(tColor),
          ],
        ),
      ),
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
      timelinePreview: _buildOccurrenceTimelinePreview(),
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
    final today = DateTime.now();
    final dateLabel =
        '${today.day.toString().padLeft(2, '0')}/${today.month.toString().padLeft(2, '0')}/${today.year}';
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
      onSelected: (option) {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedSubtype = option.name;
          _naturezaOcorrenciaController.text = option.label;
          _occurrenceController.selectNature(option.name);
          _copyOccurrenceControllerToFields();
        });
      },
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
    return _buildOccurrenceFinalizationPanelV2(tColor, canShowFinalResults);
  }

  Widget _buildOccurrenceFinalizationPanelV2(
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
    final startedLabel =
        '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}';
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
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
    return showModalBottomSheet<OccurrenceQuickAction>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
          _occurrenceController.setStatus(
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
    final currentRa = HandlerIdentityService.raFromUser(authVM.user) ?? '';
    final currentOperatorName = _currentOperatorName(
      authVM: authVM,
      userVM: userVM,
      currentRa: currentRa,
    );

    final update = IncidentProgressUpdate(
      title: action.title,
      description: action.description,
      timestamp: now,
      location: _locationController.text.trim(),
      latitude: _selectedLocationLatLng?.latitude,
      longitude: _selectedLocationLatLng?.longitude,
      authorId: currentRa,
      authorName: currentOperatorName,
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
        currentRa: currentRa,
        currentOperatorName: currentOperatorName,
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
    final existingExtraFields = widget.initialData?['extraFields'] is Map
        ? Map<String, dynamic>.from(widget.initialData!['extraFields'] as Map)
        : null;
    final effectiveNature = (_selectedSubtype?.trim().isNotEmpty ?? false)
        ? _selectedSubtype!
        : 'Averiguação';
    final effectiveManualNature =
        _naturezaOcorrenciaController.text.trim().isNotEmpty
        ? _naturezaOcorrenciaController.text.trim()
        : effectiveNature;

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

  Widget _buildOccurrenceCommandHeader(
    Color tColor, {
    bool showOperationalMetrics = false,
  }) {
    final status = _occurrenceStatus;
    final startedAt = _occurrenceStartedAt();
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final currentRa = HandlerIdentityService.raFromUser(authVM.user) ?? '';
    final operatorName = _currentOperatorName(
      authVM: authVM,
      userVM: userVM,
      currentRa: currentRa,
    );
    dynamic activeDog;
    for (final dog in dogVM.dogs) {
      if (dog.id == widget.dogId) {
        activeDog = dog;
        break;
      }
    }
    dynamic currentUser;
    for (final user in userVM.users) {
      if (user.ra == currentRa) {
        currentUser = user;
        break;
      }
    }
    final elapsedLabel = startedAt == null
        ? 'Não iniciada'
        : _formatElapsedDuration(DateTime.now().difference(startedAt));
    final nature = _selectedSubtype == _SheetSubtype.other
        ? (_naturezaOcorrenciaController.text.trim().isEmpty
              ? 'Outros'
              : _naturezaOcorrenciaController.text.trim())
        : (_selectedSubtype ?? 'Averiguação');

    return OccurrenceCommandHeader(
      nature: nature,
      status: status,
      dogName: widget.dogName,
      operatorName: operatorName,
      elapsedLabel: elapsedLabel,
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

  String _formatElapsedDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    }
    return '${minutes}m';
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
          onSelected: (option) {
            HapticFeedback.selectionClick();
            setState(() {
              _selectedSubtype = option.name;
              _naturezaOcorrenciaController.text = option.label;
              _occurrenceController.selectNature(option.name);
              _copyOccurrenceControllerToFields();
            });
          },
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

  void _applyOccurrenceWizardData(Map<String, dynamic> wizardData) {
    _occurrenceStatus = OccurrenceFormController.statusCompleted;
    _occurrenceController.setStatus(OccurrenceFormController.statusCompleted);

    _descriptionController.text = (wizardData['report'] ?? '').toString();

    final results = List<String>.from(wizardData['results'] ?? const []);
    _selectedOccurrenceOutcomes
      ..clear()
      ..addAll(results);
    _occurrenceController.outcomes
      ..clear()
      ..addAll(results);

    _occurrenceSuccessful =
        !(results.contains('Nada Localizado') ||
            results.contains('Sem constatação'));

    final details = wizardData['details'] is Map
        ? Map<String, dynamic>.from(wizardData['details'] as Map)
        : <String, dynamic>{};
    _formData['wizard_results'] = results;
    _formData['wizard_details'] = details;

    String detail(String key) => (details[key] ?? '').toString().trim();

    if (results.contains('Droga apreendida')) {
      _disposeDynamicResultRows(_detecaoDrogas, ['quantidade', 'especificar']);
      _detecaoDrogas.clear();
      final drugDetails = details['drogas'];
      if (drugDetails is List) {
        for (final item in drugDetails) {
          if (item is! Map) continue;
          final data = Map<String, dynamic>.from(item);
          final tipo = (data['tipo'] ?? '').toString().trim();
          final quantidade = (data['quantidade'] ?? '').toString().trim();
          if (tipo.isEmpty && quantidade.isEmpty) continue;
          _detecaoDrogas.add({
            'tipo': tipo.isEmpty ? 'Maconha' : tipo,
            'quantidade': TextEditingController(text: quantidade),
            'especificar': TextEditingController(),
          });
        }
      }
      if (_detecaoDrogas.isEmpty) {
        final tipo = detail('droga_tipo');
        final quantidade = detail('droga_quantidade');
        if (tipo.isNotEmpty || quantidade.isNotEmpty) {
          _detecaoDrogas.add({
            'tipo': tipo.isEmpty ? 'Maconha' : tipo,
            'quantidade': TextEditingController(text: quantidade),
            'especificar': TextEditingController(),
          });
        }
      }
      if (_detecaoDrogas.isEmpty) {
        _detecaoDrogas.add({
          'tipo': 'Maconha',
          'quantidade': TextEditingController(),
          'especificar': TextEditingController(),
        });
      }
    }

    if (results.contains('Objetos apreendidos')) {
      _disposeDynamicResultRows(_seizedObjects, ['descricao', 'quantidade']);
      _seizedObjects.clear();
      final descricao = detail('objetos_descricao');
      final quantidade = detail('objetos_quantidade');
      if (descricao.isNotEmpty || quantidade.isNotEmpty) {
        _seizedObjects.add({
          'descricao': TextEditingController(text: descricao),
          'quantidade': TextEditingController(text: quantidade),
        });
      }
    }

    if (results.contains('Veículo detido')) {
      _disposeDynamicResultRows(_detainedVehicles, ['tipo', 'placa']);
      _detainedVehicles.clear();
      final tipo = detail('veiculo_tipo');
      final placa = detail('veiculo_placa');
      if (tipo.isNotEmpty || placa.isNotEmpty) {
        _detainedVehicles.add({
          'tipo': TextEditingController(text: tipo),
          'placa': TextEditingController(text: placa),
        });
      }
    }

    if (results.contains('Indivíduo detido')) {
      _disposeDynamicResultRows(_detainedIndividuals, ['quantidade']);
      _detainedIndividuals.clear();
      final quantidade = detail('individuo_quantidade');
      if (quantidade.isNotEmpty) {
        _detainedIndividuals.add({
          'quantidade': TextEditingController(text: quantidade),
        });
      }
      final destino = detail('individuo_destino');
      if (destino.isNotEmpty) _formData['Destino do indivíduo'] = destino;
    }

    final bo = detail('bo_numero');
    if (bo.isNotEmpty) {
      _boController.text = bo;
    }

    final apoio = detail('apoio_observacao');
    if (apoio.isNotEmpty) _formData['Apoio prestado'] = apoio;
    final encaminhamento = detail('encaminhamento_observacao');
    if (encaminhamento.isNotEmpty) {
      _formData['Encaminhamento médico'] = encaminhamento;
    }

    _syncOccurrenceController();
  }

  Widget _buildStandardFormContent(Color tColor) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
        ),
      ),
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

    return [
      const SizedBox(height: 16),
      _buildChoiceChipGroup(
        label: 'Status da ocorrência',
        options: const [
          OccurrenceFormController.statusInProgress,
          OccurrenceFormController.statusCompleted,
          OccurrenceFormController.statusCanceled,
        ],
        selectedOption: _occurrenceStatus,
        onSelected: (value) {
          setState(() {
            _occurrenceController.setStatus(value);
            _copyOccurrenceControllerToFields(includeOutcomes: false);
          });
        },
      ),
      if (_occurrenceStatus != OccurrenceFormController.statusInProgress) ...[
        const SizedBox(height: 8),
        _buildChoiceChipGroup(
          label: 'Desfecho Operacional',
          options: const ['Com êxito', 'Sem êxito'],
          selectedOption: _occurrenceSuccessful == true
              ? 'Com êxito'
              : _occurrenceSuccessful == false
              ? 'Sem êxito'
              : null,
          onSelected: (value) {
            setState(() {
              _occurrenceSuccessful = value == 'Com êxito';
            });
          },
        ),
      ],
      const SizedBox(height: 8),
      _buildMultiChipGroup(
        label: 'Resultados Finais',
        options: _outcomeOptionsForOccurrenceSubtype(_selectedSubtype),
        selectedOptions: _selectedOccurrenceOutcomes,
        onToggle: (option) {
          setState(() {
            if (_selectedOccurrenceOutcomes.contains(option)) {
              _selectedOccurrenceOutcomes.remove(option);
            } else {
              _selectedOccurrenceOutcomes.add(option);
              _ensureOutcomeDetailRow(option);
            }
          });
        },
      ),
      const SizedBox(height: 16),
      ..._buildOccurrenceQuickUpdateShortcuts(),
      if (_selectedSubtype != null) const SizedBox(height: 12),
      TacticalTextField(
        controller: _occurrenceUpdateController,
        labelText: 'Atualização desta etapa',
        prefixIcon: Icons.timeline_rounded,
        maxLines: 3,
        minLines: 2,
      ),
      ..._buildOccurrenceTimelinePreview(),
    ];
  }

  List<Widget> _buildOccurrenceQuickUpdateShortcuts() {
    final shortcuts = OccurrenceQuickUpdateCatalog.forSubtype(_selectedSubtype);
    if (shortcuts.isEmpty) {
      return const [];
    }

    return [
      OccurrenceQuickUpdateShortcuts(
        titles: shortcuts.map((shortcut) => shortcut.title).toList(),
        selectedTitle: _selectedOccurrenceUpdateTitle,
        accent: _getCategoryColor(),
        onSelected: (title) {
          final shortcut = shortcuts.firstWhere(
            (shortcut) => shortcut.title == title,
          );
          _applyOccurrenceQuickUpdateShortcut(shortcut);
        },
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

  List<Widget> _buildOccurrenceTimelinePreview() {
    if (_occurrenceTimeline.isEmpty) {
      return const [];
    }

    return [
      OccurrenceTimelinePreview(
        updates: _occurrenceTimeline,
        accent: _getCategoryColor(),
        onEventTap: _openOccurrenceEventDetails,
      ),
    ];
  }

  Future<List<File>> _pickOccurrenceEventPhotos() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 60,
    );
    if (images.isEmpty) return const [];

    final files = <File>[];
    for (final image in images) {
      final originalFile = File(image.path);
      final compressed = await _compressImage(originalFile);
      files.add(compressed ?? originalFile);
    }
    HapticFeedback.lightImpact();
    return files;
  }

  Future<List<Map<String, dynamic>>> _uploadOccurrenceEventPhotos(
    List<File> files,
  ) async {
    if (files.isEmpty) return const [];

    final storageService = StorageService();
    final uploaded = <Map<String, dynamic>>[];
    final folder = 'incidents/${_activeIncidentId ?? widget.dogId}/events';

    for (var i = 0; i < files.length; i++) {
      final url = await storageService.uploadProfileImage(files[i], folder);
      if (url == null) {
        throw Exception('Falha ao subir a foto do evento ${i + 1}.');
      }
      uploaded.add({
        'url': url,
        'type': 'photo',
        'caption': '',
        'uploadedAt': DateTime.now().toIso8601String(),
      });
    }

    return uploaded;
  }

  Future<_OccurrenceEventLocation> _captureOccurrenceEventLocation() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    final point = LatLng(position.latitude, position.longitude);
    var address =
        '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';

    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final resolvedAddress = [
          p.thoroughfare,
          p.subLocality ?? p.subAdministrativeArea,
          p.locality,
        ].where((part) => part != null && part.trim().isNotEmpty).join(', ');
        if (resolvedAddress.isNotEmpty) {
          address = resolvedAddress;
        }
      }
    } catch (_) {
      // Mantém a coordenada mesmo quando o endereço textual não puder ser resolvido.
    }

    HapticFeedback.lightImpact();
    return _OccurrenceEventLocation(address: address, point: point);
  }

  Future<void> _openOccurrenceEventDetails(int index) async {
    if (index < 0 || index >= _occurrenceTimeline.length || _isSaving) return;

    final update = _occurrenceTimeline[index];
    final titleController = TextEditingController(text: update.title);
    final descriptionController = TextEditingController(
      text: update.description,
    );
    var eventLocation = update.location ?? '';
    var eventLatitude = update.latitude;
    var eventLongitude = update.longitude;
    final eventAttachments = List<Map<String, dynamic>>.from(
      update.attachments,
    );
    final pendingPhotos = <File>[];

    final result = await showModalBottomSheet<_OccurrenceEventChange>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) => OccurrenceEventDetailsSheet(
            update: update,
            titleController: titleController,
            descriptionController: descriptionController,
            timestampLabel: _formatOccurrenceEventTimestamp(update.timestamp),
            eventLocation: eventLocation,
            eventAttachments: eventAttachments,
            pendingPhotoCount: pendingPhotos.length,
            backgroundColor: _hudBackground,
            panelColor: _hudPanel,
            accentColor: _hudCyan,
            successColor: _hudGreen,
            warningColor: _hudAmber,
            dangerColor: _hudRed,
            onAddPhotos: () async {
              final files = await _pickOccurrenceEventPhotos();
              if (files.isEmpty) return;
              setSheetState(() => pendingPhotos.addAll(files));
            },
            onCaptureLocation: () async {
              try {
                final eventPoint = await _captureOccurrenceEventLocation();
                setSheetState(() {
                  eventLocation = eventPoint.address;
                  eventLatitude = eventPoint.point.latitude;
                  eventLongitude = eventPoint.point.longitude;
                });
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Não foi possível capturar o local: $e'),
                  ),
                );
              }
            },
            onDelete: () => Navigator.of(
              context,
            ).pop(const _OccurrenceEventChange.delete()),
            onSave: () async {
              try {
                final uploaded = await _uploadOccurrenceEventPhotos(
                  pendingPhotos,
                );
                eventAttachments.addAll(uploaded);
                final edited = IncidentProgressUpdate(
                  title: titleController.text.trim().isEmpty
                      ? update.title
                      : titleController.text.trim(),
                  description: descriptionController.text.trim(),
                  timestamp: update.timestamp,
                  location: eventLocation.trim(),
                  latitude: eventLatitude,
                  longitude: eventLongitude,
                  authorId: update.authorId,
                  authorName: update.authorName,
                  attachments: eventAttachments,
                );
                if (!context.mounted) return;
                Navigator.of(
                  context,
                ).pop(_OccurrenceEventChange.update(edited));
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
    titleController.dispose();
    descriptionController.dispose();
    if (result == null || !mounted) return;

    await _applyOccurrenceEventChange(index, result);
  }

  String _formatOccurrenceEventTimestamp(DateTime timestamp) {
    return '${timestamp.day.toString().padLeft(2, '0')}/'
        '${timestamp.month.toString().padLeft(2, '0')}/'
        '${timestamp.year} às '
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _applyOccurrenceEventChange(
    int index,
    _OccurrenceEventChange change,
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
      if (_activeIncidentId != null) {
        final authVM = Provider.of<AuthViewModel>(context, listen: false);
        final incidentVM = Provider.of<IncidentViewModel>(
          context,
          listen: false,
        );
        final userVM = Provider.of<UserViewModel>(context, listen: false);
        final currentRa = HandlerIdentityService.raFromUser(authVM.user) ?? '';
        final currentOperatorName = _currentOperatorName(
          authVM: authVM,
          userVM: userVM,
          currentRa: currentRa,
        );
        await _saveActiveOccurrenceSnapshot(
          incidentVM: incidentVM,
          currentRa: currentRa,
          currentOperatorName: currentOperatorName,
          updatedAt: DateTime.now(),
        );
      }
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
    _syncOccurrenceController();
    return _occurrenceController.resultSummary(
      nature: _selectedSubtype,
      fallback: _formData['Resultado da Busca'] ?? 'Averiguação',
    );
  }

  void _syncOccurrenceController() {
    _occurrenceController.status = _occurrenceStatus;
    _occurrenceController.successful = _occurrenceSuccessful;
    _occurrenceController.outcomes
      ..clear()
      ..addAll(_selectedOccurrenceOutcomes);
  }

  void _copyOccurrenceControllerToFields({bool includeOutcomes = true}) {
    _occurrenceStatus = _occurrenceController.status;
    _occurrenceSuccessful = _occurrenceController.successful;
    if (!includeOutcomes) {
      return;
    }
    _selectedOccurrenceOutcomes
      ..clear()
      ..addAll(_occurrenceController.outcomes);
  }

  List<String> _outcomeOptionsForOccurrenceSubtype(String? subtype) {
    return _occurrenceController.outcomeOptionsForNature(subtype);
  }

  void _ensureOutcomeDetailRow(String option) {
    final normalized = _normalizeOutcomeForMatch(option);
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

  String _normalizeOutcomeForMatch(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp('[áàâãä]'), 'a')
        .replaceAll(RegExp('[éèêë]'), 'e')
        .replaceAll(RegExp('[íìîï]'), 'i')
        .replaceAll(RegExp('[óòôõö]'), 'o')
        .replaceAll(RegExp('[úùûü]'), 'u')
        .replaceAll('ç', 'c');
  }

  String _currentOperatorName({
    required AuthViewModel authVM,
    required UserViewModel userVM,
    required String currentRa,
  }) {
    return userVM.displayNameFor(ra: currentRa, firebaseUser: authVM.user);
  }

  List<IncidentProgressUpdate> _buildIncidentProgressUpdates(
    DateTime finalDate, {
    required String authorId,
    required String authorName,
  }) {
    final updates = List<IncidentProgressUpdate>.from(_occurrenceTimeline);
    final note = _occurrenceUpdateController.text.trim();

    if (updates.isEmpty && widget.initialData == null) {
      updates.add(
        IncidentProgressUpdate(
          title: 'Registro inicial',
          description: _descriptionController.text.trim().isNotEmpty
              ? _descriptionController.text.trim()
              : 'Ocorrência registrada pela equipe.',
          timestamp: finalDate,
          location: _locationController.text.trim(),
          authorId: authorId,
          authorName: authorName,
        ),
      );
    }

    if (note.isNotEmpty) {
      final progressTitle =
          _selectedOccurrenceUpdateTitle ??
          (_occurrenceStatus == OccurrenceFormController.statusInProgress
              ? 'Atualização operacional'
              : 'Encerramento da ocorrência');
      updates.add(
        IncidentProgressUpdate(
          title: progressTitle,
          description: note,
          timestamp: finalDate,
          location: _locationController.text.trim(),
          authorId: authorId,
          authorName: authorName,
        ),
      );
    } else if (widget.documentId != null) {
      updates.add(
        IncidentProgressUpdate(
          title: 'Registro atualizado',
          description: 'Dados da ocorrência atualizados.',
          timestamp: finalDate,
          location: _locationController.text.trim(),
          authorId: authorId,
          authorName: authorName,
        ),
      );
    }

    return updates;
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

    _returnDateController.text =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
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
    if (widget.category == 'Treino') return 'Descrição do treino';
    if (widget.category == 'Saude') return 'Detalhes';
    if (widget.category == 'Rotina') {
      return _selectedSubtype == _SheetSubtype.feeding
          ? 'Observações da alimentação'
          : 'Detalhes da rotina';
    }
    return 'Descrição da ocorrência';
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
    if (widget.category == 'Treino') return 'SALVAR TREINO';
    if (widget.category == 'Saude') return 'SALVAR PRONTUÁRIO';
    if (widget.category == 'Rotina') return 'SALVAR ROTINA';
    return _occurrenceStatus == OccurrenceFormController.statusInProgress
        ? 'SALVAR EM ANDAMENTO'
        : 'CONCLUIR OCORRÊNCIA';
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

  List<Widget> _buildDynamicFields() {
    switch (_selectedSubtype) {
      case _SheetSubtype.searchCapture:
        return [
          _buildChipGroup('Idade da Trilha', [
            '< 30 min',
            '30m - 2h',
            '2h - 6h',
            '> 6h',
          ]),
          _buildChipGroup('Terreno', ['Urbano', 'Mata', 'Rural', 'Misto']),
          _buildChipGroup('Artigo de Odor', [
            'Roupa',
            'Objeto',
            'Veículo',
            'Odor de Cena',
          ]),
          _buildTrackingAction(
            startLabel: 'INICIAR RASTREIO TÁTICO',
            startIcon: Icons.satellite_alt_rounded,
            backgroundColor: const Color(0xFFFBBF24),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.only(bottom: 24),
          ),
        ];
      case _SheetSubtype.guardProtection:
        return [
          _buildChipGroup('Cenário', [
            'Abordagem',
            'Edificação',
            'Perseguição',
            'Estampido',
          ]),
          _buildChipGroup('Figurante', [
            'Manga',
            'Traje Completo',
            'Focinheira',
            'Civil',
          ]),
          _buildChipGroup('Controle/Out', [
            'Solta Limpa',
            'Comando Extra',
            'Correção Mecânica',
          ]),
          const SizedBox(height: 8),
          TacticalTextField(
            controller: _objetivoTreinoController,
            labelText: 'Objetivo do Treino',
            prefixIcon: Icons.flag_rounded,
          ),
          const SizedBox(height: 16),
        ];
      case _SheetSubtype.scentWork:
        return [
          _buildChipGroup('Direção do Vento', [
            'Face',
            'Cauda',
            'Lateral',
            'Sem Vento',
          ]),
          _buildChipGroup('Dificuldade', [
            'Cenário Limpo',
            'Distratores',
            'Efeito Chaminé',
            'Delta T',
          ]),
          _buildChipGroup('Resposta Final', [
            'Sentado',
            'Deitado',
            'Ativo',
            'Congelamento',
          ]),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: HudSelectField<String>(
              label: 'Tipo de Odor',
              icon: Icons.science_rounded,
              value: _formData['Tipo de Odor'] as String?,
              placeholder: 'Selecione o odor',
              accent: _hudAmber,
              items: const [
                'Maconha',
                'Cocaína',
                'Crack',
                'Sintéticos',
                'Nose MP',
                'Outros',
              ],
              labelBuilder: (item) => item,
              onChanged: (val) =>
                  setState(() => _formData['Tipo de Odor'] = val),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TacticalTextField(
                  controller: _tempController,
                  keyboardType: TextInputType.number,
                  labelText: 'Temp (°C)',
                  prefixIcon: Icons.thermostat_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TacticalTextField(
                  controller: _humidityController,
                  keyboardType: TextInputType.number,
                  labelText: 'Umidade (%)',
                  prefixIcon: Icons.water_drop_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _pullCurrentWeather,
              icon: const Icon(
                Icons.cloud_sync_rounded,
                color: Colors.white,
                size: 18,
              ),
              label: Text(
                'CAPTURAR CLIMA (GPS)',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B4F72),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ];
      case _SheetSubtype.obedience:
        return [
          TacticalTextField(
            controller: _objetivoTreinoController,
            labelText: 'Objetivos do Treino',
            prefixIcon: Icons.flag_rounded,
          ),
          const SizedBox(height: 16),
          _buildChipGroup('Distração', ['Baixa', 'Média', 'Alta', 'Extrema']),
          _buildChipGroup('Guia', ['Off-leash', 'Misto', 'Com Guia']),
          _buildChipGroup('Teve êxito?', ['Sim', 'Não']),
          TacticalTextField(
            controller: _dificuldadesController,
            labelText: 'Dificuldades Encontradas',
            prefixIcon: Icons.warning_amber_rounded,
            maxLines: 3,
            minLines: 2,
          ),
          const SizedBox(height: 16),
        ];
      case _SheetSubtype.leisureConditioning:
        return [
          _buildChipGroup('Atividade', [
            'Passeio Livre',
            'Bolinha/Tug',
            'Socialização',
            'Esteira',
            'Natação',
          ]),
          _buildChipGroup('Intensidade', [
            'Regenerativo',
            'Moderado',
            'Alta Intensidade',
          ]),
        ];
      case _SheetSubtype.walk:
        return [
          _buildChipGroup('Tipo de Piso', [
            'Asfalto',
            'Grama',
            'Terra',
            'Misto',
          ]),
          _buildChipGroup('Guia', ['Curta', 'Longa', 'Livre']),
          const SizedBox(height: 12),
          _buildTrackingAction(
            startLabel: 'INICIAR RASTREIO DE PASSEIO',
            startIcon: Icons.directions_walk_rounded,
            backgroundColor: const Color(0xFF43A047),
            foregroundColor: Colors.white,
            isLightMode: true,
            padding: const EdgeInsets.only(bottom: 24),
          ),
        ];
      default:
        return [];
    }
  }

  List<Widget> _buildDetecaoGrouped() {
    return [
      HudExpansionSection(
        title: 'Detalhes da apreensão',
        icon: Icons.shield_rounded,
        iconColor: Colors.orangeAccent,
        initiallyExpanded: true,
        children: [
          TacticalTextField(
            controller: _naturezaOcorrenciaController,
            labelText: 'Natureza da ocorrência',
            prefixIcon: Icons.category_rounded,
          ),
          const SizedBox(height: 16),
          ..._buildCategorySpecificFields(),
        ],
      ),
      const SizedBox(height: 12),
      HudExpansionSection(
        title: 'Contexto & Local',
        icon: Icons.location_on_rounded,
        iconColor: const Color(0xFF4ECDE4),
        children: [
          _buildTopActionRow(),
          const SizedBox(height: 16),
          _buildLocationTimeRow(),
        ],
      ),
      const SizedBox(height: 12),
      HudExpansionSection(
        title: 'Relatório & Anexos',
        icon: Icons.photo_library_rounded,
        iconColor: const Color(0xFF1B8A4C),
        children: [
          _buildDescriptionField(),
          const SizedBox(height: 24),
          _buildImageGallery(),
        ],
      ),
    ];
  }

  List<Widget> _buildBuscaPessoaGrouped() {
    return [
      HudExpansionSection(
        title: 'Detalhes da Busca',
        icon: Icons.person_search_rounded,
        iconColor: Colors.redAccent,
        initiallyExpanded: true,
        children: [
          TacticalTextField(
            controller: _naturezaOcorrenciaController,
            labelText: 'Natureza da ocorrência',
            prefixIcon: Icons.category_rounded,
          ),
          const SizedBox(height: 16),
          _buildChipGroup('Tipo de Busca', [
            _SheetSubtype.searchCapture,
            'Pessoa Desaparecida',
          ]),
          TacticalTextField(
            controller: _odorObjetoController,
            labelText: 'Objeto Fonte de Odor',
            prefixIcon: Icons.search,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TacticalTextField(
                  controller: _tempoDesaparecimentoController,
                  labelText: 'Tempo Desaparecido',
                  prefixIcon: Icons.access_time,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TacticalTextField(
                  controller: _durationController,
                  labelText: 'Duração (Busca)',
                  prefixIcon: Icons.timer,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 12),
      HudExpansionSection(
        title: 'Teatro de Operações',
        icon: Icons.terrain_rounded,
        iconColor: Colors.amber,
        children: [
          _buildTopActionRow(),
          const SizedBox(height: 16),
          _buildLocationTimeRow(),
          const SizedBox(height: 16),
          TacticalTextField(
            controller: _condicaoTerrenoController,
            labelText: 'Condições / Terreno',
            prefixIcon: Icons.terrain,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _pullCurrentWeather,
              icon: const Icon(Icons.cloud_sync, color: Colors.white),
              label: Text(
                'PUXAR CLIMA ATUAL (GPS)',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4ECDE4).withAlpha(50),
                foregroundColor: const Color(0xFF4ECDE4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildTrackingAction(
            startLabel: 'INICIAR RASTREIO TÁTICO',
            startIcon: Icons.satellite_alt_rounded,
            backgroundColor: const Color(0xFFFBBF24),
            foregroundColor: Colors.black,
          ),
        ],
      ),
      const SizedBox(height: 12),
      HudExpansionSection(
        title: 'Relatório & Anexos',
        icon: Icons.photo_library_rounded,
        iconColor: const Color(0xFF1B8A4C),
        children: [
          _buildDescriptionField(),
          const SizedBox(height: 24),
          _buildImageGallery(),
        ],
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
    if (!_isOccurrenceCategory) return [];

    switch (_selectedSubtype) {
      case _SheetSubtype.detection:
        return _buildDetectionOccurrenceFields();
      case _SheetSubtype.supportVehicle:
        return _buildSupportVehicleFields();
      case _SheetSubtype.missingPerson:
        return _buildMissingPersonFields();
      case _SheetSubtype.serviceOrder:
        return _buildServiceOrderFields();
      case _SheetSubtype.event:
        return _buildEventFields();
      default:
        return [];
    }
  }

  List<Widget> _buildDetectionOccurrenceFields() {
    return [
      OccurrenceDetectionFields(
        drugs: _detecaoDrogas,
        drugOptions: _detectionDrugOptions,
        accentColor: _hudCyan,
        supportTeamController: _equipeController,
        reportNumberController: _boController,
        onAddDrug: _addDrug,
        onRemoveDrug: _removeDrug,
        onDrugTypeChanged: (drug, type) {
          setState(() => drug['tipo'] = type);
        },
      ),
    ];
  }

  List<Widget> _buildSupportVehicleFields() {
    return [
      TacticalTextField(
        controller: _guarnicaoController,
        labelText: 'Guarnição apoiada',
        prefixIcon: Icons.local_police,
      ),
      const SizedBox(height: 16),
      TacticalTextField(
        controller: _situacaoController,
        labelText: 'Situação encontrada',
        prefixIcon: Icons.warning,
      ),
      const SizedBox(height: 16),
      TacticalTextField(
        controller: _desfechoController,
        labelText: 'Desfecho da intervenção',
        prefixIcon: Icons.check_circle,
      ),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _buildMissingPersonFields() {
    return [
      _buildChipGroup('Tipo de Busca', [
        _SheetSubtype.searchCapture,
        'Pessoa Desaparecida',
      ]),
      TacticalTextField(
        controller: _odorObjetoController,
        labelText: 'Objeto Fonte de Odor',
        prefixIcon: Icons.search,
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: TacticalTextField(
              controller: _tempoDesaparecimentoController,
              labelText: 'Tempo Desaparecido',
              prefixIcon: Icons.access_time,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TacticalTextField(
              controller: _durationController,
              labelText: 'Duração (Busca)',
              prefixIcon: Icons.timer,
              keyboardType: TextInputType.number,
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      TacticalTextField(
        controller: _condicaoTerrenoController,
        labelText: 'Condições / Terreno',
        prefixIcon: Icons.terrain,
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: _pullCurrentWeather,
          icon: const Icon(Icons.cloud_sync, color: Colors.white),
          label: Text(
            'PUXAR CLIMA ATUAL (GPS)',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1B8A4C),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _buildServiceOrderFields() {
    return [
      TacticalTextField(
        controller: _numeroOsController,
        labelText: 'Número da Ordem de Serviço',
        prefixIcon: Icons.numbers,
      ),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _buildEventFields() {
    return [
      TacticalTextField(
        controller: _publicoController,
        keyboardType: TextInputType.number,
        labelText: 'Público estimado',
        prefixIcon: Icons.groups_rounded,
      ),
      const SizedBox(height: 16),
      TacticalTextField(
        controller: _temaController,
        labelText: 'Tema (Ex: Cão Cidadão)',
        prefixIcon: Icons.lightbulb_rounded,
      ),
      const SizedBox(height: 24),
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
          _mediaAttachments[index]['caption']?.dispose();
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
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _examePdfFile = File(result.files.single.path!);
        _examePdfName = result.files.single.name;
      });
      HapticFeedback.lightImpact();
    }
  }

  Widget _buildChipGroup(String label, List<String> options) {
    final selectedOption = _formData[label] as String?;
    return HudToggleChipGroup(
      label: label,
      options: options,
      selectedOption: selectedOption,
      accent: _getCategoryColor(),
      onChanged: (value) {
        setState(() {
          if (value == null) {
            _formData.remove(label);
          } else {
            _formData[label] = value;
          }
        });
      },
    );
  }

  Widget _buildChoiceChipGroup({
    required String label,
    required List<String> options,
    required String? selectedOption,
    required ValueChanged<String> onSelected,
  }) {
    return HudChoiceChipGroup(
      label: label,
      options: options,
      selectedOption: selectedOption,
      accent: _getCategoryColor(),
      onSelected: onSelected,
    );
  }

  Widget _buildMultiChipGroup({
    required String label,
    required List<String> options,
    required Set<String> selectedOptions,
    required ValueChanged<String> onToggle,
  }) {
    return HudMultiChipGroup(
      label: label,
      options: options,
      selectedOptions: selectedOptions,
      accent: _getCategoryColor(),
      onToggle: onToggle,
    );
  }
}
