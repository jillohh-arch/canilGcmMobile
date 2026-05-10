part of 'shift_assumption_screen.dart';

class _EmptyDogState extends StatelessWidget {
  const _EmptyDogState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _hudPanel.withAlpha(230),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _hudCyan.withAlpha(80)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                FontAwesomeIcons.dog,
                size: 44,
                color: _hudCyan.withAlpha(160),
              ),
              const SizedBox(height: 16),
              Text(
                'NENHUM CÃO DISPONÍVEL',
                textAlign: TextAlign.center,
                style: GoogleFonts.oxanium(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Cadastre ou libere um K9 para iniciar o plantão.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
