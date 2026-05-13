part of 'media_attachment_gallery.dart';

class _PhotoTile extends StatelessWidget {
  final File file;
  final String status;
  final bool isSelected;
  final VoidCallback onRemove;

  const _PhotoTile({
    required this.file,
    required this.status,
    required this.isSelected,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected ? const Color(0xFFFBBF24) : Colors.transparent,
          width: 2,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(file, fit: BoxFit.cover),
            ),
          ),
          _PhotoTileStatusOverlay(status: status),
          if (status == MediaAttachmentRows.statusPending)
            _PhotoTileRemoveButton(onRemove: onRemove),
        ],
      ),
    );
  }
}

class _PhotoTileStatusOverlay extends StatelessWidget {
  final String status;

  const _PhotoTileStatusOverlay({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == MediaAttachmentRows.statusUploading) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        ),
      );
    }

    if (status == MediaAttachmentRows.statusDone) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Center(
          child: Icon(Icons.check_circle, color: Color(0xFF43A047), size: 32),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _PhotoTileRemoveButton extends StatelessWidget {
  final VoidCallback onRemove;

  const _PhotoTileRemoveButton({required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 4,
      right: 4,
      child: InkWell(
        onTap: onRemove,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}
