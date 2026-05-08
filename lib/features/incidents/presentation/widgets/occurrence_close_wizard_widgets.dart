part of 'occurrence_close_wizard.dart';

class _SavingNotice extends StatelessWidget {
  const _SavingNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF082031),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00E5FF).withAlpha(110)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withAlpha(24),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF00E5FF),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Finalizando ocorrência... sincronizando dados e anexos.',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClosingRoadmap extends StatelessWidget {
  final int currentStep;

  const _ClosingRoadmap({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    const labels = ['RELATO', 'RESULTADO', 'DETALHES'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF00E5FF).withAlpha(75)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.flag_rounded,
                color: Color(0xFFFFB84D),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ROTEIRO DE ENCERRAMENTO',
                  style: GoogleFonts.robotoMono(
                    color: const Color(0xFFFFB84D),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
              Text(
                '${currentStep + 1} / 3',
                style: GoogleFonts.robotoMono(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(3, (index) {
              final active = index <= currentStep;
              final done = index < currentStep;
              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: active
                                  ? const Color(0xFF00E5FF).withAlpha(25)
                                  : Colors.transparent,
                              border: Border.all(
                                color: active
                                    ? const Color(0xFF00E5FF)
                                    : Colors.white24,
                              ),
                              boxShadow: active
                                  ? [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF00E5FF,
                                        ).withAlpha(70),
                                        blurRadius: 12,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: done
                                  ? const Icon(
                                      Icons.check_rounded,
                                      color: Color(0xFF00F5A0),
                                      size: 20,
                                    )
                                  : Text(
                                      '${index + 1}',
                                      style: GoogleFonts.oxanium(
                                        color: active
                                            ? const Color(0xFF00E5FF)
                                            : Colors.white38,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            labels[index],
                            maxLines: 1,
                            style: GoogleFonts.robotoMono(
                              color: active
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white30,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (index < 2)
                      Container(
                        width: 34,
                        height: 2,
                        color: index < currentStep
                            ? const Color(0xFF00F5A0)
                            : Colors.white12,
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _StepShell extends StatelessWidget {
  final String title;
  final Color accent;
  final Widget child;

  const _StepShell({
    super.key,
    required this.title,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              title,
              style: GoogleFonts.robotoMono(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: accent.withAlpha(120))),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _InstructionBox extends StatelessWidget {
  final String text;

  const _InstructionBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF082031),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: Color(0xFF00E5FF), width: 3),
        ),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: Colors.white70,
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NarrationButton extends StatelessWidget {
  final bool listening;
  final VoidCallback onPressed;

  const _NarrationButton({required this.listening, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        listening ? Icons.stop_circle_rounded : Icons.mic_rounded,
        size: 17,
      ),
      label: Text(listening ? 'PARAR NARRAÇÃO' : 'NARRAÇÃO'),
      style: OutlinedButton.styleFrom(
        foregroundColor: listening
            ? const Color(0xFFFF3B5C)
            : const Color(0xFF00E5FF),
        side: BorderSide(
          color: listening
              ? const Color(0xFFFF3B5C).withAlpha(145)
              : const Color(0xFF00E5FF).withAlpha(145),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: GoogleFonts.robotoMono(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final double width;
  final _ResultOption option;
  final bool selected;
  final VoidCallback onTap;

  const _ResultCard({
    required this.width,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 96,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected
                ? option.color.withAlpha(28)
                : const Color(0xFF0B1220),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? option.color : Colors.white12,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [BoxShadow(color: option.color.withAlpha(40), blurRadius: 14)]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: option.color.withAlpha(24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(option.icon, color: option.color, size: 20),
              ),
              const SizedBox(height: 9),
              Text(
                option.label.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.oxanium(
                  color: selected ? Colors.white : Colors.white60,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EvidenceNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.camera_alt_rounded,
            color: Color(0xFFB8C2D6),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Anexos e fotos vinculados à ocorrência serão mantidos no relatório final.',
              style: GoogleFonts.inter(
                color: Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrugEntry {
  String type;
  final TextEditingController quantityController;

  _DrugEntry() : type = 'Maconha', quantityController = TextEditingController();

  void dispose() {
    quantityController.dispose();
  }
}

class _ResultOption {
  final String label;
  final IconData icon;
  final Color color;

  const _ResultOption({
    required this.label,
    required this.icon,
    required this.color,
  });
}
