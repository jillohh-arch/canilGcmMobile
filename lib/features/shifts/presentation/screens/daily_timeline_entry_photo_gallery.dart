part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryPhotoGallery on _DailyTimelineScreenState {
  List<Widget> _buildTimelinePhotoGallery(List attachments, Color color) {
    final photos = attachments
        .where((media) => media is Map && media['type'] != 'pdf')
        .toList();

    if (photos.isEmpty) {
      return const [];
    }

    return [
      const SizedBox(height: 12),
      SizedBox(
        height: 100,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: photos.length,
          itemBuilder: (context, index) {
            final media = photos[index] as Map;
            return _buildTimelinePhotoTile(media: media, color: color);
          },
        ),
      ),
    ];
  }

  Widget _buildTimelinePhotoTile({required Map media, required Color color}) {
    final caption = media['caption']?.toString() ?? '';

    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: const Color(0xFF070B14),
        border: Border.all(color: color.withAlpha(120)),
        boxShadow: [BoxShadow(color: color.withAlpha(35), blurRadius: 12)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: media['url']?.toString() ?? '',
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white38,
                  ),
                ),
                errorWidget: (context, url, err) => const Center(
                  child: Icon(Icons.broken_image, color: Colors.white24),
                ),
              ),
            ),
            if (caption.isNotEmpty)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  color: Colors.black87,
                  child: Text(
                    caption,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
