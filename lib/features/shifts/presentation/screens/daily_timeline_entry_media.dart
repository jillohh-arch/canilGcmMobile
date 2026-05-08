part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryMedia on _DailyTimelineScreenState {
  List<Widget> _buildTimelineMediaSections(_TimelineEntry entry, Color color) {
    final attachments = entry.details['_mediaAttachments'] as List? ?? const [];

    return [
      ..._buildTimelinePhotoGallery(attachments, color),
      ..._buildTimelinePdfButton(entry, attachments),
    ];
  }

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

  List<Widget> _buildTimelinePdfButton(_TimelineEntry entry, List attachments) {
    final pdfs = attachments
        .where((media) => media is Map && media['type'] == 'pdf')
        .toList();

    if (entry.type != 'Saude' || pdfs.isEmpty) {
      return const [];
    }

    return [
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () async {
            final pdfMedia = pdfs.first as Map;
            final rawUrl = pdfMedia['url']?.toString() ?? '';
            if (rawUrl.isEmpty) {
              return;
            }

            final url = Uri.parse(rawUrl);
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
          icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.black),
          label: Text(
            'VISUALIZAR DOCUMENTO (PDF)',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFBBF24),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    ];
  }
}
