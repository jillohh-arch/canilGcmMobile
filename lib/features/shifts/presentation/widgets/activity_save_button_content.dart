part of 'activity_save_controls.dart';

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
          child: CircularProgressIndicator(
            color: AppTheme.textPrimary,
            strokeWidth: 2,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            saveStatus,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              color: AppTheme.textPrimary,
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
      style: GoogleFonts.inter(
        fontWeight: FontWeight.w900,
        color: color,
        fontSize: 15,
        letterSpacing: 1.6,
      ),
    );
  }
}
