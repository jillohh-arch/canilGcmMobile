import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AddEventBottomSheet extends StatelessWidget {
  final ValueChanged<String> onEventSelected;

  const AddEventBottomSheet({super.key, required this.onEventSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      decoration: const BoxDecoration(
        color: Color(0xFF070B14),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: Color(0xFF1D2C33), width: 1.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'OUTROS EVENTOS',
                  style: GoogleFonts.oxanium(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildOption(
            icon: Icons.health_and_safety_rounded,
            label: 'PAUSA / DESCANSO K9',
            color: const Color(0xFF00E5FF),
            onTap: () {
              Navigator.of(context).pop();
              onEventSelected('PAUSA / DESCANSO K9');
            },
          ),
          const SizedBox(height: 12),
          _buildOption(
            icon: Icons.local_police_rounded,
            label: 'APOIO DE VIATURA',
            color: const Color(0xFF00E5FF),
            onTap: () {
              Navigator.of(context).pop();
              onEventSelected('APOIO DE VIATURA');
            },
          ),
          const SizedBox(height: 12),
          _buildOption(
            icon: Icons.description_rounded,
            label: 'OBSERVAÇÃO GERAL',
            color: const Color(0xFF00E5FF),
            onTap: () {
              Navigator.of(context).pop();
              onEventSelected('OBSERVAÇÃO GERAL');
            },
          ),
          const SizedBox(height: 12),
          _buildOption(
            icon: Icons.warning_rounded,
            label: 'ALTERAÇÃO RELEVANTE',
            color: const Color(0xFFFFB300),
            onTap: () {
              Navigator.of(context).pop();
              onEventSelected('ALTERAÇÃO RELEVANTE');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1220),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.robotoMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
