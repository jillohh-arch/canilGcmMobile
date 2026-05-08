part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryDocuments on _DailyTimelineScreenState {
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
          onPressed: () async => _openTimelinePdf(pdfs.first as Map),
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

  Future<void> _openTimelinePdf(Map pdfMedia) async {
    final rawUrl = pdfMedia['url']?.toString() ?? '';
    if (rawUrl.isEmpty) {
      return;
    }

    final url = Uri.parse(rawUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
