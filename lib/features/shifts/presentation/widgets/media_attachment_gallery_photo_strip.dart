part of 'media_attachment_gallery.dart';

class _PhotoStrip extends StatelessWidget {
  final List<Map<String, dynamic>> mediaAttachments;
  final int activePhotoIndex;
  final ValueChanged<int> onSelectPhoto;
  final ValueChanged<int> onRemovePhoto;

  const _PhotoStrip({
    required this.mediaAttachments,
    required this.activePhotoIndex,
    required this.onSelectPhoto,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: mediaAttachments.length,
            itemBuilder: (context, index) {
              final media = mediaAttachments[index];
              final isSelected = index == activePhotoIndex;
              return GestureDetector(
                onTap: () => onSelectPhoto(index),
                child: _PhotoTile(
                  file: MediaAttachmentRows.file(media),
                  status: _mediaStatus(media),
                  isSelected: isSelected,
                  onRemove: () => onRemovePhoto(index),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        if (_hasActivePhoto)
          TacticalTextField(
            controller: MediaAttachmentRows.captionController(
              mediaAttachments[activePhotoIndex],
            ),
            labelText: 'Descrição da foto ${activePhotoIndex + 1} *',
          ),
      ],
    );
  }

  bool get _hasActivePhoto {
    return activePhotoIndex >= 0 && activePhotoIndex < mediaAttachments.length;
  }

  String _mediaStatus(Map<String, dynamic> media) {
    return media['status']?.toString() ?? MediaAttachmentRows.statusPending;
  }
}
