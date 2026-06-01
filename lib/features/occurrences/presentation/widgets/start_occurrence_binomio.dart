import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';

class StartOccurrenceBinomio extends StatelessWidget {
  final String dogName;
  final String? dogImageUrl;
  final String handlerName;
  final String? handlerImageUrl;

  const StartOccurrenceBinomio({
    super.key,
    required this.dogName,
    this.dogImageUrl,
    required this.handlerName,
    this.handlerImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Avatar(
              label: dogName,
              imageUrl: dogImageUrl,
              borderColor: AppTheme.primary,
            ),
            const SizedBox(width: 16),
            _Avatar(
              label: handlerName,
              imageUrl: handlerImageUrl,
              borderColor: AppTheme.primary,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '$dogName  ·  $handlerName',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'K9  ·  CONDUTOR',
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 16),
        _StatusBadge(),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String label;
  final String? imageUrl;
  final Color borderColor;

  const _Avatar({
    required this.label,
    this.imageUrl,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
      ),
      child: ClipOval(
        child: imageUrl != null && imageUrl!.isNotEmpty
            ? Image.network(imageUrl!, fit: BoxFit.cover)
            : Container(
                color: AppTheme.surfacePanelAlt,
                alignment: Alignment.center,
                child: Text(
                  label.length > 6 ? label.substring(0, 6) : label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: borderColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.success.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.success.withAlpha(75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'TURNO ATIVO',
            style: GoogleFonts.inter(
              color: AppTheme.success,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
