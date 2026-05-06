import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OccurrenceResultDetailSection extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onAdd;
  final List<Widget> children;

  const OccurrenceResultDetailSection({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.onAdd,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Colors.transparent,
        border: Border(left: BorderSide(color: Color(0xFF00E5FF), width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.white54,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(
              Icons.add_outlined,
              size: 16,
              color: Color(0xFF00E5FF),
            ),
            label: Text(
              actionLabel,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF2A2A2A)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OccurrenceCompactDynamicRow extends StatelessWidget {
  final List<Widget> children;
  final VoidCallback onRemove;

  const OccurrenceCompactDynamicRow({
    super.key,
    required this.children,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          ...children,
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFFE57373)),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
