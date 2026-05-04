import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/incident.dart';

class EventDetailsBottomSheet extends StatelessWidget {
  final IncidentProgressUpdate event;
  final VoidCallback onEditTime;
  final VoidCallback onAddPhoto;
  final VoidCallback onAddNote;
  final VoidCallback onDelete;

  const EventDetailsBottomSheet({
    super.key,
    required this.event,
    required this.onEditTime,
    required this.onAddPhoto,
    required this.onAddNote,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      decoration: const BoxDecoration(
        color: Color(0xFF070B14),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: Color(0xFF1D2C33), width: 1.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  event.title.toUpperCase(),
                  style: GoogleFonts.oxanium(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            event.description,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.white54,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          _buildOption(
            icon: Icons.access_time_rounded,
            label: 'EDITAR HORÁRIO',
            color: const Color(0xFF4ECDE4),
            onTap: onEditTime,
          ),
          const SizedBox(height: 12),
          _buildOption(
            icon: Icons.camera_alt_rounded,
            label: 'ADICIONAR FOTO',
            color: const Color(0xFFFFB300),
            onTap: onAddPhoto,
          ),
          const SizedBox(height: 12),
          _buildOption(
            icon: Icons.edit_note_rounded,
            label: 'ADICIONAR OBSERVAÇÃO',
            color: const Color(0xFF00F5A0),
            onTap: onAddNote,
          ),
          const SizedBox(height: 12),
          _buildOption(
            icon: Icons.delete_outline_rounded,
            label: 'EXCLUIR EVENTO',
            color: const Color(0xFFFF5252),
            onTap: onDelete,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1220),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: color.withOpacity(isDestructive ? 0.3 : 0.1),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.robotoMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isDestructive ? color : Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white24,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
