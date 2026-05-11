import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

class ActivitySaveStatusPanel extends StatelessWidget {
  final Color accentColor;
  final bool isSaving;
  final bool saveFailed;
  final String saveStatus;

  const ActivitySaveStatusPanel({
    super.key,
    required this.accentColor,
    required this.isSaving,
    required this.saveFailed,
    required this.saveStatus,
  });

  @override
  Widget build(BuildContext context) {
    if (!isSaving && !saveFailed) {
      return const SizedBox.shrink();
    }

    final statusColor = saveFailed ? const Color(0xFFE53935) : accentColor;
    final statusText = saveStatus.isEmpty
        ? (saveFailed ? 'Falha ao salvar.' : 'Sincronizando...')
        : saveStatus;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF070B14).withAlpha(235),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: statusColor.withAlpha(150)),
        boxShadow: [
          BoxShadow(color: statusColor.withAlpha(30), blurRadius: 16),
        ],
      ),
      child: Row(
        children: [
          if (isSaving)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: statusColor,
                strokeWidth: 2,
              ),
            )
          else
            Icon(Icons.error_outline_rounded, color: statusColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              statusText,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavingButtonContent extends StatelessWidget {
  final String saveStatus;

  const _SavingButtonContent({required this.saveStatus});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            saveStatus,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              color: Colors.white,
              fontSize: 14,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _IdleButtonLabel extends StatelessWidget {
  final String label;
  final Color color;

  const _IdleButtonLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.robotoMono(
        fontWeight: FontWeight.w900,
        color: color,
        fontSize: 15,
        letterSpacing: 1.6,
      ),
    );
  }
}
