part of 'occurrence_grouped_sections.dart';

class _OccurrenceNatureField extends StatelessWidget {
  final TextEditingController controller;

  const _OccurrenceNatureField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TacticalTextField(
      controller: controller,
      labelText: 'Natureza da ocorrência',
      prefixIcon: Icons.category_rounded,
    );
  }
}

class _OccurrenceReportAttachmentsSection extends StatelessWidget {
  final Widget descriptionField;
  final Widget imageGallery;

  const _OccurrenceReportAttachmentsSection({
    required this.descriptionField,
    required this.imageGallery,
  });

  @override
  Widget build(BuildContext context) {
    return HudExpansionSection(
      title: 'Relatório & Anexos',
      icon: Icons.photo_library_rounded,
      iconColor: const Color(0xFF1B8A4C),
      children: [descriptionField, const SizedBox(height: 24), imageGallery],
    );
  }
}
