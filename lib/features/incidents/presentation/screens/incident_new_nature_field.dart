part of 'incident_form_screen.dart';

class _IncidentNatureField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<OccurrenceNature> onSelected;
  final ValueChanged<String> onChanged;

  const _IncidentNatureField({
    required this.controller,
    required this.focusNode,
    required this.onSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NATUREZA DA OCORRÊNCIA',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.white54,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        OccurrenceNatureSearch(
          controller: controller,
          focusNode: focusNode,
          natures: OccurrenceNatureSeed.items,
          panelColor: const Color(0xFF0E1A1F),
          accent: AppTheme.primary,
          onSelected: onSelected,
          onChanged: onChanged,
          fieldBuilder: (context, controller, focusNode, onChanged) {
            return _IncidentNatureTextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
            );
          },
        ),
      ],
    );
  }
}

class _IncidentNatureTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _IncidentNatureTextField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Ex: Busca de Entorpecentes',
        hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 14),
        prefixIcon: const Icon(
          Icons.radar_rounded,
          color: AppTheme.primary,
          size: 20,
        ),
        filled: true,
        fillColor: const Color(0xFF0E1A1F),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
      ),
    );
  }
}
