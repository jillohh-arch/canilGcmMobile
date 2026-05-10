part of 'occurrence_grouped_sections.dart';

class OccurrenceDetectionGroupedSections extends StatelessWidget {
  final TextEditingController natureController;
  final List<Widget> specificFields;
  final Widget topActionRow;
  final Widget locationTimeRow;
  final Widget descriptionField;
  final Widget imageGallery;

  const OccurrenceDetectionGroupedSections({
    super.key,
    required this.natureController,
    required this.specificFields,
    required this.topActionRow,
    required this.locationTimeRow,
    required this.descriptionField,
    required this.imageGallery,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HudExpansionSection(
          title: 'Detalhes da apreensão',
          icon: Icons.shield_rounded,
          iconColor: Colors.orangeAccent,
          initiallyExpanded: true,
          children: [
            _OccurrenceNatureField(controller: natureController),
            const SizedBox(height: 16),
            ...specificFields,
          ],
        ),
        const SizedBox(height: 12),
        HudExpansionSection(
          title: 'Contexto & Local',
          icon: Icons.location_on_rounded,
          iconColor: const Color(0xFF4ECDE4),
          children: [topActionRow, const SizedBox(height: 16), locationTimeRow],
        ),
        const SizedBox(height: 12),
        _OccurrenceReportAttachmentsSection(
          descriptionField: descriptionField,
          imageGallery: imageGallery,
        ),
      ],
    );
  }
}
