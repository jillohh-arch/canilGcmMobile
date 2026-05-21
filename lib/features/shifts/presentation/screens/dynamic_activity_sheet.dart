import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:flutter/services.dart';

import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/core/services/location_resolution_service.dart';
import 'package:canil_gcm/core/services/media_processing_service.dart';
import 'package:canil_gcm/core/services/pdf_attachment_service.dart';
import 'package:canil_gcm/core/services/pt_br_date_time_service.dart';
import 'package:canil_gcm/core/services/speech_dictation_service.dart';
import 'package:canil_gcm/core/services/weather_capture_service.dart';
import 'package:canil_gcm/core/domain/activity_subtype_ids.dart';
import 'package:canil_gcm/core/controllers/media_attachment_rows.dart';
import 'package:canil_gcm/features/training/presentation/widgets/dynamic_subtype_fields.dart';
import 'package:canil_gcm/features/training/presentation/widgets/training_activity_fields.dart';
import 'package:canil_gcm/features/health/presentation/widgets/health_activity_fields.dart';
import 'package:canil_gcm/core/widgets/quick_location_actions.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/activity_card_catalog.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/activity_category_menu_sheet.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/activity_common_fields.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/activity_form_body.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/activity_form_labels.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/media_attachment_gallery.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/activity_form_scaffold.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/activity_save_controls.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/activity_tracking_action.dart';
import 'package:canil_gcm/features/shifts/presentation/controllers/activity_sheet_training_ctrl.dart';
import 'package:canil_gcm/features/shifts/presentation/controllers/activity_sheet_health_ctrl.dart';
import 'live_tracking_screen.dart';

part '_standard_sheet_builders.dart';
part '_standard_sheet_controls.dart';
part '_standard_sheet_fields.dart';
part '_dynamic_activity_sheet_actions.dart';
part '_dynamic_activity_sheet_environment_actions.dart';
part '_dynamic_activity_sheet_media_actions.dart';
part '_dynamic_activity_sheet_media_status.dart';
part '_dynamic_activity_sheet_accessors.dart';
part '_dynamic_activity_sheet_hydration.dart';
part '_dynamic_activity_sheet_lifecycle.dart';
part '_dynamic_activity_sheet_status.dart';
part '_dynamic_activity_sheet_layout.dart';
part '_dynamic_activity_sheet_save.dart';
part '_dynamic_activity_sheet_category_save.dart';

// Aliases de cor — mapeiam para tokens do AppTheme.
// Mantidos como const para compatibilidade com part files existentes.
const Color _kHudBackground = AppTheme.background;
const Color _kHudCyan = AppTheme.primary;
const Color _kHudAmber = AppTheme.warning;
const Color _kHudGreen = AppTheme.success;

class DynamicActivitySheet extends StatefulWidget {
  final String category; // 'Treino' ou 'Saude'
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
  // Training controller (Fase 2)
  // ---------------------------------------------------------------------------
  late final ActivitySheetTrainingCtrl _trainingCtrl;

  // ---------------------------------------------------------------------------
  // Health controller (Fase 4)
  // ---------------------------------------------------------------------------
  late final ActivitySheetHealthCtrl _healthCtrl;

  final _locationCtrlOther = TextEditingController();
  final _descriptionCtrlOther = TextEditingController();
  final _timeCtrlOther = TextEditingController();
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
    if (widget.initialData != null) {
      _showMenu = false;
      _populateEditData();
    }
    _primeNewRecordTime();
  }

  bool _showMenu = true;
  String? _selectedSubtype;
  String? _selectedSubtypeImagePath;
  final Map<String, dynamic> _formData = {};
  // _selectedVacina, _examePdfFile, _examePdfName: agora getters => _healthCtrl (Fase 4)

  bool _isCompressing = false;
  bool _isSaving = false;
  String _saveStatus = '';
  bool _saveFailed = false;
  late SpeechDictationService _speechDictation;
  bool _isListening = false;
  int _activePhotoIndex = -1;
  // _timeController, _locationController, _descriptionController: getters por categoria
  // _returnDateController: getter => _healthCtrl.returnDateController (Fase 4)

  // Saúde: todos os campos agora são getters delegando para _healthCtrl (Fase 4)
  // _vetNameController, _clinicaController, _motivoController, _tipoVacinaController,
  // _tipoExameController, _produtosBanhoController, _returnDateController,
  // _materiaisController, _selectedVacina, _examePdfFile, _examePdfName

  // Faro / clima e campos de treino: migrados para _trainingCtrl (Fase 2)
  // _tempController, _humidityController, _objetivoTreinoController,
  // _dificuldadesController agora são getters delegando para _trainingCtrl

  // Fotos / mídias globais
  final List<Map<String, dynamic>> _mediaAttachments = [];

  @override
  void dispose() {
    _disposeActivityControllers();
    _disposeSheetResources();
    super.dispose();
  }

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
