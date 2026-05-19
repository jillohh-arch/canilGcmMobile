import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';

class ActiveOccurrenceContextCard extends StatelessWidget {
  final String typeName;
  final String dogName;
  final String handlerName;
  final String locationAddress;
  final String startedAtLabel;
  final String durationLabel;
  final int eventCount;

  const ActiveOccurrenceContextCard({
    super.key,
    required this.typeName,
    required this.dogName,
    required this.handlerName,
    required this.locationAddress,
    required this.startedAtLabel,
    required this.durationLabel,
    required this.eventCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: title + badge
          Row(
            children: [
              Expanded(
                child: Text(
                  typeName,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StatusBadge(),
            ],
          ),
          const SizedBox(height: 12),

          // Binômio
          Row(
            children: [
              _MiniAvatar(label: dogName),
              const SizedBox(width: 6),
              _MiniAvatar(label: handlerName),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$dogName · $handlerName',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'K9 · CONDUTOR',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Info rows
          _InfoRow(label: 'Local:', value: locationAddress.isNotEmpty ? locationAddress : '—'),
          const SizedBox(height: 4),
          _InfoRow(
            label: 'Equipe:',
            value: '',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '+ Definir equipe',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _InfoRow(label: 'Início:', value: startedAtLabel),
          const SizedBox(height: 12),

          // Metrics
          Row(
            children: [
              _Metric(label: 'DURAÇÃO', value: durationLabel),
              const SizedBox(width: 24),
              _Metric(label: 'EVENTOS', value: '$eventCount'),
            ],
          ),
          const SizedBox(height: 12),

          // Sync indicator
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppTheme.primary.withAlpha(20)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_done_outlined, color: AppTheme.success, size: 12),
                const SizedBox(width: 6),
                Text(
                  'Sincronizado · em andamento',
                  style: GoogleFonts.inter(
                    color: AppTheme.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.success.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.success.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'EM ANDAMENTO',
            style: GoogleFonts.inter(
              color: AppTheme.success,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  final String label;

  const _MiniAvatar({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1A2A30),
        border: Border.all(color: AppTheme.primary.withAlpha(100)),
      ),
      alignment: Alignment.center,
      child: Text(
        label.length > 3 ? label.substring(0, 3).toUpperCase() : label.toUpperCase(),
        style: GoogleFonts.inter(
          color: AppTheme.primary,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;

  const _InfoRow({required this.label, required this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: const Color(0xFF5A7280),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        if (trailing != null)
          trailing!
        else
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: const Color(0xFF5A7280),
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
