part of 'occurrence_detection_fields.dart';

class _DetectionDrugAddButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _DetectionDrugAddButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add, size: 16, color: Colors.white),
      label: Text(
        'ADICIONAR ENTORPECENTE',
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.white24),
      ),
    );
  }
}
