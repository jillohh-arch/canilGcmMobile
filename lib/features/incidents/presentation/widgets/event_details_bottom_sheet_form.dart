part of 'event_details_bottom_sheet.dart';

class _EventDetailsFormFields extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController descriptionController;

  const _EventDetailsFormFields({
    required this.titleController,
    required this.descriptionController,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TacticalTextField(
          controller: titleController,
          labelText: 'Título do evento',
          prefixIcon: Icons.label_rounded,
        ),
        const SizedBox(height: 10),
        TacticalTextField(
          controller: descriptionController,
          labelText: 'Observação',
          prefixIcon: Icons.notes_rounded,
          maxLines: 4,
          minLines: 2,
        ),
      ],
    );
  }
}
