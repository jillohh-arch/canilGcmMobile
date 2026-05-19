import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class ActiveOccurrenceFinalizeCta extends StatelessWidget {
  final VoidCallback onFinalize;

  const ActiveOccurrenceFinalizeCta({
    super.key,
    required this.onFinalize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1A1F),
        border: Border(
          top: BorderSide(color: Colors.white.withAlpha(10)),
        ),
      ),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          onFinalize();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFE74C3C).withAlpha(180),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '🏁',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(width: 10),
              Text(
                'FINALIZAR OCORRÊNCIA',
                style: GoogleFonts.inter(
                  color: const Color(0xFFE74C3C),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
