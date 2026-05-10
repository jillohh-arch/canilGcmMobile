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
import 'package:canil_gcm/core/services/operator_context_service.dart';
import 'package:canil_gcm/core/services/pdf_attachment_service.dart';
import 'package:canil_gcm/core/services/pt_br_date_time_service.dart';
import 'package:canil_gcm/core/services/speech_dictation_service.dart';
import 'package:canil_gcm/core/services/text_match_service.dart';
import 'package:canil_gcm/core/services/weather_capture_service.dart';
import 'package:canil_gcm/core/domain/activity_subtype_ids.dart';
import 'package:canil_gcm/core/controllers/media_attachment_rows.dart';
import 'package:canil_gcm/core/utils/firestore_date.dart';
import 'package:canil_gcm/features/training/presentation/widgets/dynamic_subtype_fields.dart';
import 'package:canil_gcm/features/training/presentation/widgets/training_activity_fields.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_activity_fields.dart';
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
part '_occurrence_sheet_command_header.dart';
part '_occurrence_sheet_initial_data.dart';
part '_occurrence_sheet_active_snapshot.dart';
part '_occurrence_sheet_events.dart';
part '_occurrence_sheet_event_details.dart';
part '_occurrence_sheet_event_registration.dart';
part '_occurrence_sheet_event_sync.dart';
part '_occurrence_sheet_grouped_fields.dart';
part '_occurrence_sheet_helpers.dart';
part '_occurrence_sheet_wizard.dart';
part '_occurrence_sheet_wizard_results.dart';
part '_standard_sheet_builders.dart';
part '_standard_sheet_controls.dart';
part '_standard_sheet_fields.dart';
part '_dynamic_activity_sheet_actions.dart';
part '_dynamic_activity_sheet_environment_actions.dart';
part '_dynamic_activity_sheet_media_actions.dart';
part '_dynamic_activity_sheet_media_status.dart';
part '_dynamic_activity_sheet_accessors.dart';
part '_dynamic_activity_sheet_hydration.dart';
part '_dynamic_activity_sheet_occurrence_hydration.dart';
part '_dynamic_activity_sheet_occurrence_extra_fields.dart';
part '_dynamic_activity_sheet_occurrence_nature.dart';
part '_dynamic_activity_sheet_occurrence_timeline.dart';
part '_dynamic_activity_sheet_lifecycle.dart';
part '_dynamic_activity_sheet_status.dart';
part '_dynamic_activity_sheet_layout.dart';
part '_dynamic_activity_sheet_save.dart';
part '_dynamic_activity_sheet_category_save.dart';
part '_dynamic_activity_sheet_occurrence_open_incident.dart';
part '_dynamic_activity_sheet_occurrence_payload.dart';
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
    _initActivityControllers();
    _speechDictation = SpeechDictationService();
    _initSelectedActivityController();
    _initMenuPager();
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
    _primeNewRecordTime();
    if (_isOccurrenceCategory) {
      _occCtrl.loadNatures();
      _scheduleOccurrenceStartContext();
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
    _disposeActivityControllers();
    _disposeSheetResources();
    super.dispose();
  }

  // _disposeDrugRows foi migrado para _occCtrl.dispose()

  // _uploadExamePdf, _prepareHealthMetadata, _saveHealth:
  // migrados para ActivitySheetHealthCtrl (Fase 4)

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
}
