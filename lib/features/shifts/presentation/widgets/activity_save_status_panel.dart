part of 'activity_save_controls.dart';

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
          _SaveStatusLeadingIcon(isSaving: isSaving, color: statusColor),
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

class _SaveStatusLeadingIcon extends StatelessWidget {
  final bool isSaving;
  final Color color;

  const _SaveStatusLeadingIcon({required this.isSaving, required this.color});

  @override
  Widget build(BuildContext context) {
    if (!isSaving) {
      return Icon(Icons.error_outline_rounded, color: color, size: 18);
    }

    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(color: color, strokeWidth: 2),
    );
  }
}
