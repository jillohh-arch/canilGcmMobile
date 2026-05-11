import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

part 'occurrence_command_header_avatar.dart';
part 'occurrence_command_header_binomium.dart';
part 'occurrence_command_header_frame.dart';
part 'occurrence_command_header_metrics.dart';
part 'occurrence_command_header_sections.dart';
part 'occurrence_command_header_visuals.dart';

class OccurrenceCommandHeader extends StatelessWidget {
  final String nature;
  final String status;
  final String dogName;
  final String operatorName;
  final String elapsedLabel;
  final int? eventCount;
  final bool showOperationalMetrics;
  final String? dogImageUrl;
  final String? operatorImageUrl;
  final Color accent;
  final Color statusColor;
  final VoidCallback? onBack;

  const OccurrenceCommandHeader({
    super.key,
    required this.nature,
    required this.status,
    required this.dogName,
    this.operatorName = 'Condutor',
    required this.elapsedLabel,
    this.eventCount,
    this.showOperationalMetrics = false,
    this.dogImageUrl,
    this.operatorImageUrl,
    required this.accent,
    required this.statusColor,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return _CommandHeaderFrame(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeaderTopBar(
            onBack: onBack,
            status: status,
            statusColor: statusColor,
          ),
          const SizedBox(height: 12),
          _HeaderTitleBlock(nature: nature, accent: accent),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white.withAlpha(22)),
          const SizedBox(height: 12),
          _BinomiumBlock(
            dogName: dogName,
            dogImageUrl: dogImageUrl,
            dogAccent: accent,
            operatorName: operatorName,
            operatorImageUrl: operatorImageUrl,
            operatorAccent: const Color(0xFF00F5A0),
          ),
          if (showOperationalMetrics) ...[
            const SizedBox(height: 12),
            _OperationalMetricsRow(
              elapsedLabel: elapsedLabel,
              eventCount: eventCount,
              accent: accent,
            ),
          ],
        ],
      ),
    );
  }
}
