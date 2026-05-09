part of 'health_dashboard_screen.dart';

class _SensorCard extends StatelessWidget {
  final String label;
  final String value;
  final Widget icon;
  final bool isSelected;
  final VoidCallback? onTap;

  const _SensorCard({
    required this.label,
    required this.value,
    required this.icon,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF082F49).withValues(alpha: 0.3)
              : const Color(0xFF111827),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(6),
            topRight: const Radius.circular(6),
            bottomLeft: Radius.circular(isSelected ? 0 : 8),
            bottomRight: Radius.circular(isSelected ? 0 : 8),
          ),
          border: Border.all(
            color: isSelected
                ? Colors.cyanAccent
                : Colors.cyanAccent.withValues(alpha: 0.2),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Stack(
          children: [
            if (onTap != null)
              Positioned(
                top: 0,
                right: 6,
                child: Icon(
                  Icons.edit_rounded,
                  size: 14,
                  color: Colors.cyanAccent.withValues(alpha: 0.85),
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(height: 12),
                Text(
                  value,
                  style: GoogleFonts.shareTechMono(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? Colors.cyanAccent
                        : Colors.cyanAccent.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white : Colors.white54,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (onTap != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'TOQUE PARA ALTERAR',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.robotoMono(
                      fontSize: 7,
                      fontWeight: FontWeight.w900,
                      color: Colors.cyanAccent.withValues(alpha: 0.68),
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
