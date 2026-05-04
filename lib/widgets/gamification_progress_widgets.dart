import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/badge_progress.dart';
import '../models/level_progress.dart';
import '../models/weekly_mission_progress.dart';
import '../utils/badges_data.dart';

class LevelProgressCard extends StatelessWidget {
  final LevelProgress progress;

  const LevelProgressCard({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: const Color(0xFFFBBF24).withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  color: Color(0xFFFBBF24),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PROGRESSO DE NÍVEL',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Nível ${progress.level} • ${progress.currentXp} XP',
                      style: GoogleFonts.inter(
                        color: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(progress.progress * 100).round()}%',
                style: GoogleFonts.inter(
                  color: const Color(0xFFFBBF24),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.progress,
              minHeight: 8,
              backgroundColor: Colors.white.withAlpha(18),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFFBBF24),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Faltam ${progress.xpRemaining} XP para alcançar o nível ${progress.level + 1}.',
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class NextBadgeHighlightCard extends StatelessWidget {
  final BadgeData badge;
  final BadgeProgress progress;

  const NextBadgeHighlightCard({
    super.key,
    required this.badge,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            badge.color.withValues(alpha: 0.18),
            Colors.black.withValues(alpha: 0.24),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: badge.color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_rounded, color: badge.color, size: 18),
              const SizedBox(width: 8),
              Text(
                'PRÓXIMO TROFÉU',
                style: GoogleFonts.inter(
                  color: badge.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: badge.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(badge.icon, color: badge.color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      badge.name,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      badge.description,
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.progress,
              minHeight: 8,
              backgroundColor: Colors.white.withAlpha(18),
              valueColor: AlwaysStoppedAnimation<Color>(badge.color),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            progress.summary,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            progress.remaining == 0
                ? 'Pronto para desbloquear'
                : 'Faltam ${progress.remaining} ${progress.unitLabel}.',
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class BadgeProgressCard extends StatelessWidget {
  final BadgeData badge;
  final BadgeProgress progress;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  const BadgeProgressCard({
    super.key,
    required this.badge,
    required this.progress,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 18,
  });

  @override
  Widget build(BuildContext context) {
    final remainingLabel = progress.remaining == 0
        ? 'Pronto para desbloquear'
        : 'Faltam ${progress.remaining} ${progress.unitLabel}';

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: badge.color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: badge.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(badge.icon, color: badge.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      badge.name,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      progress.summary,
                      style: GoogleFonts.inter(
                        color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(progress.progress * 100).round()}%',
                style: GoogleFonts.inter(
                  color: badge.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.progress,
              minHeight: 8,
              backgroundColor: Colors.white.withAlpha(14),
              valueColor: AlwaysStoppedAnimation<Color>(badge.color),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            remainingLabel,
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class WeeklyMissionCard extends StatelessWidget {
  final WeeklyMissionProgress mission;

  const WeeklyMissionCard({super.key, required this.mission});

  IconData _iconForMission() {
    switch (mission.missionId) {
      case 'treino_da_semana':
        return Icons.fitness_center_rounded;
      case 'turno_da_semana':
        return Icons.badge_rounded;
      case 'ocorrencia_da_semana':
        return Icons.local_police_rounded;
      case 'cuidado_da_semana':
        return Icons.pets_rounded;
      default:
        return Icons.task_alt_rounded;
    }
  }

  Color _colorForMission() {
    switch (mission.missionId) {
      case 'treino_da_semana':
        return const Color(0xFF22C55E);
      case 'turno_da_semana':
        return const Color(0xFF38BDF8);
      case 'ocorrencia_da_semana':
        return const Color(0xFFF97316);
      case 'cuidado_da_semana':
        return const Color(0xFFA78BFA);
      default:
        return const Color(0xFFFBBF24);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _colorForMission();
    final statusLabel = mission.claimed
        ? 'Bônus aplicado'
        : mission.completed
        ? 'Pronto para bônus'
        : 'Faltam ${mission.remaining} ${mission.unitLabel}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(_iconForMission(), color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mission.title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mission.description,
                      style: GoogleFonts.inter(
                        color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '+${mission.rewardXp} XP',
                  style: GoogleFonts.inter(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: mission.progress,
              minHeight: 8,
              backgroundColor: Colors.white.withAlpha(14),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${mission.current} de ${mission.target} ${mission.unitLabel}',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                statusLabel,
                style: GoogleFonts.inter(
                  color: mission.claimed ? accent : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
