part of 'occurrence_event_center_sheet.dart';

class _CustomEventComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color accentColor;
  final Color backgroundColor;
  final VoidCallback onSubmit;

  const _CustomEventComposer({
    required this.controller,
    required this.focusNode,
    required this.accentColor,
    required this.backgroundColor,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TacticalTextField(
          controller: controller,
          focusNode: focusNode,
          labelText: 'Evento personalizado / observação',
          prefixIcon: Icons.edit_note_rounded,
          maxLines: 3,
          minLines: 2,
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            onPressed: onSubmit,
            icon: const Icon(Icons.add_rounded),
            label: Text(
              'REGISTRAR EVENTO',
              style: GoogleFonts.robotoMono(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: backgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
