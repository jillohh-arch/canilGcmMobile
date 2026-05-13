part of 'profile_screen.dart';

class _ProfileHeroSliver extends StatelessWidget {
  final String? photoStr;
  final File? newPhotoFile;
  final String callsign;
  final String nameStr;
  final String raStr;
  final int level;
  final int xp;
  final bool isEditMode;
  final VoidCallback onToggleEditMode;
  final Future<void> Function() onPickPhoto;

  const _ProfileHeroSliver({
    required this.photoStr,
    required this.newPhotoFile,
    required this.callsign,
    required this.nameStr,
    required this.raStr,
    required this.level,
    required this.xp,
    required this.isEditMode,
    required this.onToggleEditMode,
    required this.onPickPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: _hudBackground,
      iconTheme: const IconThemeData(color: Colors.white),
      actions: [
        IconButton(
          icon: Icon(
            isEditMode ? Icons.close_rounded : Icons.edit_rounded,
            color: Colors.white,
          ),
          onPressed: onToggleEditMode,
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            _ProfileHeroBackground(photoStr: photoStr),
            _ProfileHeroOverlay(),
            _ProfileHeroContent(
              photoStr: photoStr,
              newPhotoFile: newPhotoFile,
              callsign: callsign,
              nameStr: nameStr,
              raStr: raStr,
              level: level,
              xp: xp,
              isEditMode: isEditMode,
              onPickPhoto: onPickPhoto,
            ),
          ],
        ),
      ),
    );
  }
}
