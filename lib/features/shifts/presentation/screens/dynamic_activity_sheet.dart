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
import 'package:canil_gcm/core/services/operator_context_service.dart';
import 'package:canil_gcm/core/services/pdf_attachment_service.dart';
import 'package:canil_gcm/core/services/pt_br_date_time_service.dart';
import 'package:canil_gcm/core/services/speech_dictation_service.dart';
import 'package:canil_gcm/core/services/storage_service.dart';
import 'package:canil_gcm/core/services/text_match_service.dart';
import 'package:canil_gcm/core/services/weather_capture_service.dart';
import 'package:canil_gcm/core/domain/activity_subtype_ids.dart';
import 'package:canil_gcm/core/controllers/media_attachment_rows.dart';
import 'package:canil_gcm/core/utils/firestore_date.dart';
import 'package:canil_gcm/features/training/presentation/widgets/dynamic_subtype_fields.dart';
import 'package:canil_gcm/features/training/presentation/widgets/training_activity_fields.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_activity_fields.dart';
import 'package:canil_gcm/features/incidents/data/occurrence_event_media_service.dart';
import 'package:canil_gcm/core/widgets/quick_location_actions.dart';
import 'package:canil_gcm/features/routine/presentation/widgets/routine_activity_fields.dart';
import 'package:canil_gcm/core/widgets/tactical_text_field.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/activity_card_catalog.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/activity_category_menu_sheet.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/activity_common_fields.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/activity_form_body.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/activity_form_labels.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/media_attachment_gallery.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/activity_form_scaffold.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/activity_save_controls.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/activity_tracking_action.dart';
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
part '_occurrence_sheet_context.dart';
part '_occurrence_sheet_events.dart';
part '_occurrence_sheet_wizard.dart';
part '_standard_sheet_builders.dart';
part '_dynamic_activity_sheet_actions.dart';
part '_dynamic_activity_sheet_accessors.dart';
part '_dynamic_activity_sheet_hydration.dart';
part '_dynamic_activity_sheet_occurrence_save.dart';

// Constantes HUD (compartilhadas com part files)
const Color _kHudBackground = Color(0xFF070B14);
const Color _kHudPanel = Color(0xFF0B1220);
const Color _kHudCyan = Color(0xFF00E5FF);
const Color _kHudAmber = Color(0xFFFFB84D);
const Color _kHudGreen = Color(0xFF00F5A0);
const Color _kHudRed = Color(0xFFFF3B5C);

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

  // Fallback para categorias sem controller dedicado para o campo.
  // _locationCtrlOther: Rotina não tem campo de localização.
  // _durationCtrlOther: duração de busca em Ocorrência/Evento.
  final _locationCtrlOther = TextEditingController();
  final _durationCtrlOther = TextEditingController();

  late PageController _menuPageController;
  int _currentMenuPage = 0;

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

  void _updateState(VoidCallback update) {
    if (!mounted) return;
    setState(update);
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

  // _disposeDrugRows foi migrado para _occCtrl.dispose()

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
    if (_selectedSubtype == ActivitySubtypeIds.detection ||
        _selectedSubtype == ActivitySubtypeIds.missingPerson) {
      return _buildGroupedFormContent(tColor);
    }
    return _buildStandardFormContent(tColor);
  }
}
