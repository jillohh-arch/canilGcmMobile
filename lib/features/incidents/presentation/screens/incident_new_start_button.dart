part of 'incident_form_screen.dart';

class _IncidentStartButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _IncidentStartButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Consumer<IncidentViewModel>(
      builder: (context, vm, _) {
        return SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton(
            onPressed: vm.isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: const Color(0xFF070B14),
              elevation: 0,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: vm.isLoading
                    ? const CircularProgressIndicator(color: Color(0xFF070B14))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow_rounded, size: 28),
                          const SizedBox(width: 12),
                          Text(
                            'INICIAR OCORRÊNCIA',
                            style: GoogleFonts.oxanium(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
