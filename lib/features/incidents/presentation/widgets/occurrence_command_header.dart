import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

part 'occurrence_command_header_components.dart';

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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF07101C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withAlpha(150), width: 1.2),
        boxShadow: [
          BoxShadow(color: accent.withAlpha(34), blurRadius: 26),
          const BoxShadow(
            color: Color(0xAA000000),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: RadialGradient(
                  center: const Alignment(0.55, -0.55),
                  radius: 1.2,
                  colors: [
                    accent.withAlpha(32),
                    const Color(0xFF07101C).withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 22,
            top: 34,
            child: Icon(
              Icons.shield_rounded,
              size: 126,
              color: accent.withAlpha(18),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final centerMaxWidth = (constraints.maxWidth - 144)
                      .clamp(120.0, 210.0)
                      .toDouble();

                  return SizedBox(
                    height: 42,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (onBack != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: IconButton(
                                onPressed: onBack,
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: centerMaxWidth,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _AppMark(accent: accent),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'K9 COMANDO',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.robotoMono(
                                      color: Colors.white70,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _HeaderChip(
                            label: _displayStatus(status),
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ClipboardIcon(accent: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _safeNature(nature).toUpperCase(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.oxanium(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                            height: 1.08,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 44,
                          height: 2,
                          decoration: BoxDecoration(
                            color: accent,
                            boxShadow: [
                              BoxShadow(color: accent, blurRadius: 10),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: Colors.white.withAlpha(22)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _CrewMeta(
                      title: 'K9',
                      name: dogName.isNotEmpty ? dogName : 'K9',
                      subtitle: 'Em serviço',
                      imageUrl: dogImageUrl,
                      fallbackIcon: Icons.pets_rounded,
                      accent: accent,
                      alignEnd: false,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 48,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: Colors.white.withAlpha(35),
                  ),
                  Expanded(
                    child: _CrewMeta(
                      title: 'GCM',
                      name: operatorName.isNotEmpty ? operatorName : 'Condutor',
                      subtitle: 'Condutor',
                      imageUrl: operatorImageUrl,
                      fallbackIcon: Icons.badge_rounded,
                      accent: const Color(0xFF00F5A0),
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
              if (showOperationalMetrics) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _WideMetric(
                        icon: Icons.timer_outlined,
                        title: 'Tempo',
                        label: elapsedLabel,
                        accent: accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _WideMetric(
                        icon: Icons.bolt_rounded,
                        title: 'Ações',
                        label: '${eventCount ?? 0}',
                        accent: const Color(0xFFFFB84D),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _displayStatus(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('andamento')) return 'EM ANDAMENTO';
    if (normalized.contains('conclu')) return 'FINALIZAÇÃO';
    if (normalized.contains('cancel')) return 'CANCELADA';
    return value.toUpperCase();
  }

  String _safeNature(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Averiguação' : trimmed;
  }
}
