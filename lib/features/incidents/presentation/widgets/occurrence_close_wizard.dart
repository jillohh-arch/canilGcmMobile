import 'package:flutter/material.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

part 'occurrence_close_wizard_notices.dart';
part 'occurrence_close_wizard_roadmap.dart';
part 'occurrence_close_wizard_roadmap_header.dart';
part 'occurrence_close_wizard_roadmap_step.dart';
part 'occurrence_close_wizard_step_shell.dart';
part 'occurrence_close_wizard_instruction_box.dart';
part 'occurrence_close_wizard_narration_button.dart';
part 'occurrence_close_wizard_result_card.dart';
part 'occurrence_close_wizard_models.dart';
part 'occurrence_close_wizard_config.dart';
part 'occurrence_close_wizard_drug_fields.dart';
part 'occurrence_close_wizard_drug_add_button.dart';
part 'occurrence_close_wizard_drug_entry_row.dart';
part 'occurrence_close_wizard_speech.dart';
part 'occurrence_close_wizard_navigation.dart';
part 'occurrence_close_wizard_field_decoration.dart';
part 'occurrence_close_wizard_finish_payload.dart';
part 'occurrence_close_wizard_flow.dart';
part 'occurrence_close_wizard_report_step.dart';
part 'occurrence_close_wizard_result_step.dart';
part 'occurrence_close_wizard_details_step.dart';
part 'occurrence_close_wizard_steps.dart';
part 'occurrence_close_wizard_detail_specs.dart';
part 'occurrence_close_wizard_detail_fields.dart';

class OccurrenceCloseWizard extends StatefulWidget {
  final VoidCallback onCancel;
  final ValueChanged<Map<String, dynamic>> onFinish;
  final bool isSaving;

  const OccurrenceCloseWizard({
    super.key,
    required this.onCancel,
    required this.onFinish,
    this.isSaving = false,
  });

  @override
  State<OccurrenceCloseWizard> createState() => _OccurrenceCloseWizardState();
}

class _OccurrenceCloseWizardState extends State<OccurrenceCloseWizard> {
  static final _bg = AppTheme.background;
  static const _panel = const Color(0xFF0E1A1F);
  static final _cyan = AppTheme.primary;
  static final _red = AppTheme.error;

  int _currentStep = 0;
  late final stt.SpeechToText _speech;
  bool _speechReady = false;
  bool _isListening = false;

  final _reportController = TextEditingController();
  final Set<String> _selectedResults = {};
  final Map<String, TextEditingController> _detailControllers = {};
  final List<_DrugEntry> _drugEntries = [_DrugEntry()];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
  }

  @override
  void dispose() {
    _speech.cancel();
    _reportController.dispose();
    for (final controller in _detailControllers.values) {
      controller.dispose();
    }
    for (final entry in _drugEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ClosingRoadmap(currentStep: _currentStep),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _buildStep(),
        ),
        const SizedBox(height: 16),
        if (widget.isSaving) ...[
          const _SavingNotice(),
          const SizedBox(height: 12),
        ],
        _buildNavigation(),
      ],
    );
  }
}
