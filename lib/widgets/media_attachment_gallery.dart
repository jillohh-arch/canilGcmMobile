import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tactical_text_field.dart';

class MediaAttachmentGallery extends StatelessWidget {
  final bool isCompressing;
  final bool showPdfAttachment;
  final String? pdfName;
  final List<Map<String, dynamic>> mediaAttachments;
  final int activePhotoIndex;
  final VoidCallback onPickImage;
  final VoidCallback onPickPdf;
  final VoidCallback onRemovePdf;
  final ValueChanged<int> onSelectPhoto;
  final ValueChanged<int> onRemovePhoto;

  const MediaAttachmentGallery({
    super.key,
    required this.isCompressing,
    required this.showPdfAttachment,
    required this.pdfName,
    required this.mediaAttachments,
    required this.activePhotoIndex,
    required this.onPickImage,
    required this.onPickPdf,
    required this.onRemovePdf,
    required this.onSelectPhoto,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ANEXOS PERICIAIS / FOTOS',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white54,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        if (isCompressing) _CompressionStatus(),
        if (showPdfAttachment) _buildPdfAttachment(),
        if (mediaAttachments.isNotEmpty) _buildPhotoStrip(),
        if (!isCompressing)
          OutlinedButton.icon(
            onPressed: onPickImage,
            icon: const Icon(Icons.camera_alt, size: 16, color: Colors.white70),
            label: Text(
              'ANEXAR FOTO',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPdfAttachment() {
    if (pdfName != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.picture_as_pdf_rounded,
              color: Colors.redAccent,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                pdfName ?? 'arquivo.pdf',
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white38, size: 18),
              onPressed: onRemovePdf,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton.icon(
        onPressed: onPickPdf,
        icon: const Icon(
          Icons.upload_file_rounded,
          size: 16,
          color: Colors.redAccent,
        ),
        label: Text(
          'ANEXAR LAUDO (PDF)',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.redAccent,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.redAccent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }

  Widget _buildPhotoStrip() {
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
                  file: media['file'] as File,
                  status: media['status']?.toString() ?? 'pending',
                  isSelected: isSelected,
                  onRemove: () => onRemovePhoto(index),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        if (activePhotoIndex >= 0 && activePhotoIndex < mediaAttachments.length)
          TacticalTextField(
            controller: mediaAttachments[activePhotoIndex]['caption'],
            labelText: 'Descrição da foto ${activePhotoIndex + 1} *',
          ),
      ],
    );
  }
}

class _CompressionStatus extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COMPRIMINDO IMAGEM...',
          style: GoogleFonts.inter(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const LinearProgressIndicator(color: Colors.white70),
        const SizedBox(height: 16),
      ],
    );
  }
}

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
          if (status == 'uploading')
            Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            )
          else if (status == 'done')
            Container(
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Center(
                child: Icon(
                  Icons.check_circle,
                  color: Color(0xFF43A047),
                  size: 32,
                ),
              ),
            ),
          if (status == 'pending')
            Positioned(
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
            ),
        ],
      ),
    );
  }
}
