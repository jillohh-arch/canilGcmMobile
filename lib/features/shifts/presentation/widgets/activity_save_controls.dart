import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

part 'activity_save_button_content.dart';
part 'activity_save_status_panel.dart';

class ActivitySaveButton extends StatelessWidget {
  final Color accentColor;
  final Color foregroundColor;
  final bool isSaving;
  final bool isCompressing;
  final bool saveFailed;
  final String saveStatus;
  final String idleLabel;
  final VoidCallback onSave;

  const ActivitySaveButton({
    super.key,
    required this.accentColor,
    required this.foregroundColor,
    required this.isSaving,
    required this.isCompressing,
    required this.saveFailed,
    required this.saveStatus,
    required this.idleLabel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ActivitySaveStatusPanel(
          accentColor: accentColor,
          isSaving: isSaving,
          saveFailed: saveFailed,
          saveStatus: saveStatus,
        ),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ActivityPrimarySaveButton(
            accentColor: accentColor,
            foregroundColor: foregroundColor,
            isSaving: isSaving,
            isCompressing: isCompressing,
            saveStatus: saveStatus,
            idleLabel: idleLabel,
            onSave: onSave,
          ),
        ),
      ],
    );
  }
}

class ActivityPrimarySaveButton extends StatelessWidget {
  final Color accentColor;
  final Color foregroundColor;
  final bool isSaving;
  final bool isCompressing;
  final String saveStatus;
  final String idleLabel;
  final VoidCallback onSave;

  const ActivityPrimarySaveButton({
    super.key,
    required this.accentColor,
    required this.foregroundColor,
    required this.isSaving,
    required this.isCompressing,
    required this.saveStatus,
    required this.idleLabel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: (isSaving || isCompressing) ? null : onSave,
      style: ElevatedButton.styleFrom(
        backgroundColor: isSaving ? Colors.black45 : const Color(0xFF00E5FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        elevation: 0,
      ),
      child: isSaving
          ? _SavingButtonContent(saveStatus: saveStatus)
          : _IdleButtonLabel(label: idleLabel, color: foregroundColor),
    );
  }
}
