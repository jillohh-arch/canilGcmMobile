part of 'user_management_screen.dart';

class _UserFormAvatar extends StatelessWidget {
  final File? imageFile;
  final String? currentPhotoUrl;
  final VoidCallback onPickImage;

  const _UserFormAvatar({
    required this.imageFile,
    required this.currentPhotoUrl,
    required this.onPickImage,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ImageProvider? image = imageFile != null
        ? FileImage(imageFile!) as ImageProvider
        : (currentPhotoUrl != null ? NetworkImage(currentPhotoUrl!) : null);

    return Center(
      child: GestureDetector(
        onTap: onPickImage,
        child: Stack(
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: colorScheme.primaryContainer,
              backgroundImage: image,
              child: image == null
                  ? Icon(
                      Icons.person,
                      size: 44,
                      color: colorScheme.onPrimaryContainer,
                    )
                  : null,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: CircleAvatar(
                radius: 14,
                backgroundColor: colorScheme.primary,
                child: Icon(
                  Icons.camera_alt,
                  size: 14,
                  color: colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserAccessLevelPicker extends StatelessWidget {
  final String accessLevel;
  final ValueChanged<String> onChanged;

  const _UserAccessLevelPicker({
    required this.accessLevel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'Condutor',
          label: Text('Condutor'),
          icon: Icon(Icons.person_outline),
        ),
        ButtonSegment(
          value: 'Admin',
          label: Text('Admin'),
          icon: Icon(Icons.admin_panel_settings_outlined),
        ),
      ],
      selected: {accessLevel},
      onSelectionChanged: (selected) => onChanged(selected.first),
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: colorScheme.primaryContainer,
        selectedForegroundColor: colorScheme.onPrimaryContainer,
      ),
    );
  }
}
