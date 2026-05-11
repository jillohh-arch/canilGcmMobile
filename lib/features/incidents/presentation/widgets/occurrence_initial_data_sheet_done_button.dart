part of 'occurrence_initial_data_sheet.dart';

class _InitialDataDoneButton extends StatelessWidget {
  final Color accentColor;
  final Color backgroundColor;
  final VoidCallback onDone;

  const _InitialDataDoneButton({
    required this.accentColor,
    required this.backgroundColor,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        onPressed: onDone,
        style: FilledButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: backgroundColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(
          'CONCLUIR EDIÇÃO',
          style: GoogleFonts.robotoMono(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }
}
