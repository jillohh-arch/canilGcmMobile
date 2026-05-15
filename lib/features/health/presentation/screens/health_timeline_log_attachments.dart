part of 'health_dashboard_screen.dart';

class _ExamAttachmentButton extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onPressed;

  const _ExamAttachmentButton({
    required this.accentColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: accentColor, width: 1.5),
        foregroundColor: accentColor,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.document_scanner_rounded, size: 18),
      label: Text(
        'ACESSAR LAUDO PDF',
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _TacticalHealthThumbnail extends StatelessWidget {
  final String? url;
  final Color accentColor;

  const _TacticalHealthThumbnail({
    required this.url,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    if (url == null) return const SizedBox.shrink();

    return Container(
      width: 75,
      height: 75,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFF030712),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.8),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: url!,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: Colors.white10),
          errorWidget: (context, url, error) => const Icon(
            Icons.image_not_supported,
            color: Colors.white24,
            size: 24,
          ),
        ),
      ),
    );
  }
}
