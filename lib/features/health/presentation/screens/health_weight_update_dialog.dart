part of 'health_dashboard_screen.dart';

class _WeightUpdateDialog extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<double> onSubmit;

  const _WeightUpdateDialog({required this.controller, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF070B14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0x9900E5FF)),
      ),
      title: Text(
        'ATUALIZAR PESO',
        style: GoogleFonts.oxanium(
          color: Colors.cyanAccent,
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Informe o peso atual do cão em quilogramas.',
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            style: GoogleFonts.shareTechMono(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
            decoration: InputDecoration(
              suffixText: 'kg',
              suffixStyle: GoogleFonts.robotoMono(
                color: Colors.cyanAccent.withValues(alpha: 0.75),
                fontWeight: FontWeight.w900,
              ),
              filled: true,
              fillColor: const Color(0xFF0B1020),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0x5500E5FF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(
                  color: Colors.cyanAccent,
                  width: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'CANCELAR',
            style: GoogleFonts.robotoMono(
              color: Colors.white54,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.cyanAccent,
            foregroundColor: const Color(0xFF070B14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          onPressed: () {
            final value = double.tryParse(
              controller.text.trim().replaceAll(',', '.'),
            );
            if (value == null || value <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Informe um peso válido.'),
                  backgroundColor: Color(0xFFE53935),
                ),
              );
              return;
            }
            onSubmit(value);
          },
          child: Text(
            'SALVAR',
            style: GoogleFonts.robotoMono(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}
