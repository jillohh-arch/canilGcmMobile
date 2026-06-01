import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/controllers/media_attachment_rows.dart';
import 'package:canil_gcm/core/widgets/tactical_text_field.dart';

part 'media_attachment_gallery_actions.dart';
part 'media_attachment_gallery_pdf.dart';
part 'media_attachment_gallery_photo_strip.dart';
part 'media_attachment_gallery_photo_tile.dart';
part 'media_attachment_gallery_widgets.dart';

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
        const _MediaAttachmentSectionLabel(),
        const SizedBox(height: 12),
        if (isCompressing) const _CompressionStatus(),
        if (showPdfAttachment)
          _PdfAttachment(
            pdfName: pdfName,
            onPickPdf: onPickPdf,
            onRemovePdf: onRemovePdf,
          ),
        if (mediaAttachments.isNotEmpty)
          _PhotoStrip(
            mediaAttachments: mediaAttachments,
            activePhotoIndex: activePhotoIndex,
            onSelectPhoto: onSelectPhoto,
            onRemovePhoto: onRemovePhoto,
          ),
        if (!isCompressing) _AttachPhotoButton(onPressed: onPickImage),
      ],
    );
  }
}
