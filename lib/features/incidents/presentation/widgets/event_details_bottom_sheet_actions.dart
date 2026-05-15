part of 'event_details_bottom_sheet.dart';

class _EventDetailsActions extends StatelessWidget {
  final Color backgroundColor;
  final Color accentColor;
  final Color dangerColor;
  final VoidCallback onDelete;
  final Future<void> Function() onSave;

  const _EventDetailsActions({
    required this.backgroundColor,
    required this.accentColor,
    required this.dangerColor,
    required this.onDelete,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _EventOutlineActionButton(
            label: 'EXCLUIR',
            icon: Icons.delete_outline_rounded,
            color: dangerColor,
            onPressed: onDelete,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save_rounded),
            label: Text(
              'SALVAR',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: backgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EventOutlineActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _EventOutlineActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withAlpha(150)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}
