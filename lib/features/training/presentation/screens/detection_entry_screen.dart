import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/binomio_header.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/training/data/detection_service.dart';
import 'package:canil_gcm/features/training/domain/detection/detection_line.dart';
import 'package:canil_gcm/features/training/domain/detection/detection_phase_config.dart';
import 'package:canil_gcm/features/training/presentation/screens/detection_formation_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/detection_maintenance_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/detection_triagem_screen.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

/// Tela 5.0 — Entrada da Detecção (seletor de linha com estado real).
///
/// Mostra 3 cards (Drogas, Armas, Cadáver) lendo o estado real de cada
/// linha do Firestore e roteia automaticamente para o fluxo correto:
/// - not_started → Triagem (3.12)
/// - triagem → Continuar triagem (3.12)
/// - in_formation → Formação (Parte 4)
/// - operational → Manutenção (3.11)
class DetectionEntryScreen extends StatelessWidget {
  final Dog dog;

  const DetectionEntryScreen({super.key, required this.dog});

  @override
  Widget build(BuildContext context) {
    final detectionService = DetectionService();
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final currentRa = HandlerIdentityService.raFromUser(authVM.user);
    final handlerName = userVM.displayNameFor(
      ra: currentRa,
      firebaseUser: authVM.user,
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header Universal
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: BinomioHeader(
                dog: dog,
                showStatusDot: true,
                statusDotColor: AppTheme.success,
                subtitle: 'Turno ativo',
              ),
            ),
            const SizedBox(height: 16),

            // Breadcrumb + Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Row(
                          children: [
                            const Icon(Icons.arrow_back_ios_new_rounded,
                                color: Color(0xFF5A7280), size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'Treino',
                              style: GoogleFonts.inter(
                                color: const Color(0xFF5A7280),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        ' › Detecção',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF7D8D99),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Detecção',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Escolha a linha de trabalho do ${dog.name}',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF7D8D99),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Line cards (stream from Firestore)
            Expanded(
              child: StreamBuilder<List<DetectionLine>>(
                stream: detectionService.watchLines(dog.id),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(
                      child:
                          CircularProgressIndicator(color: AppTheme.primary),
                    );
                  }

                  final lines = snapshot.data ?? [];

                  // Ensure all 3 default lines are represented
                  final displayLines = _ensureAllLines(lines);

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: displayLines.length,
                    itemBuilder: (context, index) {
                      return _DetectionLineCard(
                        line: displayLines[index],
                        dog: dog,
                        onTap: () => _routeToDestination(
                          context,
                          displayLines[index],
                          dog,
                          currentRa,
                          handlerName,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<DetectionLine> _ensureAllLines(List<DetectionLine> lines) {
    final types = ['drogas', 'armas', 'cadaver'];
    final result = <DetectionLine>[];

    for (final type in types) {
      final existing = lines.where((l) => l.normalizedType == type).toList();
      if (existing.isNotEmpty) {
        result.add(existing.first);
      } else {
        result.add(DetectionLine(type: type, status: 'not_started'));
      }
    }
    return result;
  }

  void _routeToDestination(
    BuildContext context,
    DetectionLine line,
    Dog dog,
    String? handlerId,
    String handlerName,
  ) {
    HapticFeedback.mediumImpact();

    switch (line.status) {
      case 'not_started':
      case 'triagem':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetectionTriagemScreen(dog: dog),
          ),
        );
        break;
      case 'in_formation':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetectionFormationScreen(dog: dog),
          ),
        );
        break;
      case 'operational':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetectionMaintenanceScreen(dog: dog),
          ),
        );
        break;
      default:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetectionTriagemScreen(dog: dog),
          ),
        );
    }
  }
}

// ─── Line Card Widget ─────────────────────────────────────────────────

class _DetectionLineCard extends StatelessWidget {
  final DetectionLine line;
  final Dog dog;
  final VoidCallback onTap;

  const _DetectionLineCard({
    required this.line,
    required this.dog,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final state = _LineVisualState.from(line);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(6), // rgba(255,255,255,0.025)
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withAlpha(18)), // 0.07
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Head: icon + name + badge
            Row(
              children: [
                _buildIcon(state),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.displayName,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        state.kindLabel,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF5A7280),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildBadge(state),
              ],
            ),

            // Contextual info
            if (line.status == 'in_formation') ...[
              const SizedBox(height: 12),
              _buildProgressBar(),
            ] else ...[
              const SizedBox(height: 13),
              _buildMetaInfo(state),
            ],

            // CTA
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.only(top: 13),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        state.ctaLabel,
                        style: GoogleFonts.inter(
                          color: AppTheme.primary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        state.ctaDestination,
                        style: GoogleFonts.inter(
                          color: const Color(0xFF5A7280),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.primary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(_LineVisualState state) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: state.color.withAlpha(25),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: state.color.withAlpha(72)),
      ),
      child: Icon(
        Icons.air_rounded, // nose/faro icon
        color: state.color,
        size: 22,
      ),
    );
  }

  Widget _buildBadge(_LineVisualState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: state.color.withAlpha(30),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        state.badgeLabel,
        style: GoogleFonts.inter(
          color: state.color,
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final phasesCompleted = line.phasesCompleted.length;
    const totalPhases = 8; // 1b,2b,2v,3b,3v,4b,4v,4c
    final progress = phasesCompleted / totalPhases;
    final phaseConfig = DetectionPhaseCatalog.byCode(line.currentPhase);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            RichText(
              text: TextSpan(
                style: GoogleFonts.inter(
                  color: const Color(0xFF7D8D99),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
                children: [
                  const TextSpan(text: 'Fase atual '),
                  TextSpan(
                    text: line.currentPhase,
                    style: GoogleFonts.ibmPlexMono(
                      color: AppTheme.warning,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: ' · ${phaseConfig.title}'),
                ],
              ),
            ),
            Text(
              '$phasesCompleted / $totalPhases fases',
              style: GoogleFonts.inter(
                color: const Color(0xFF7D8D99),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: Colors.white.withAlpha(18),
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppTheme.warning),
          ),
        ),
      ],
    );
  }

  Widget _buildMetaInfo(_LineVisualState state) {
    if (line.status == 'operational') {
      final freshness = _calculateFreshness();
      final isStale = freshness > 14;
      final freshnessColor =
          isStale ? AppTheme.warning : AppTheme.success;
      final freshnessLabel =
          isStale ? 'Manutenção atrasada' : 'Manutenção em dia';

      return Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: freshnessColor,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            freshnessLabel,
            style: GoogleFonts.inter(
              color: freshnessColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            ' · última sessão há ',
            style: GoogleFonts.inter(
              color: const Color(0xFFAEBCC4),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            '${freshness}d',
            style: GoogleFonts.ibmPlexMono(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    // not_started or triagem
    return Text(
      state.metaLabel,
      style: GoogleFonts.inter(
        color: const Color(0xFF7D8D99),
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  int _calculateFreshness() {
    final lastSession = line.lastSessionAt ?? line.updatedAt;
    if (lastSession == null) return 999;
    return DateTime.now().difference(lastSession).inDays;
  }
}

// ─── Visual State Helper ──────────────────────────────────────────────

class _LineVisualState {
  final Color color;
  final String badgeLabel;
  final String kindLabel;
  final String ctaLabel;
  final String ctaDestination;
  final String metaLabel;

  const _LineVisualState({
    required this.color,
    required this.badgeLabel,
    required this.kindLabel,
    required this.ctaLabel,
    required this.ctaDestination,
    required this.metaLabel,
  });

  factory _LineVisualState.from(DetectionLine line) {
    final kindMap = {
      'drogas': 'FARO · NARCÓTICOS',
      'armas': 'FARO · ARMAMENTO',
      'cadaver': 'FARO · RESTOS HUMANOS',
    };
    final kind = kindMap[line.normalizedType] ?? 'FARO';

    switch (line.status) {
      case 'operational':
        return _LineVisualState(
          color: const Color(0xFF2ECC71),
          badgeLabel: 'OPERACIONAL',
          kindLabel: kind,
          ctaLabel: 'Abrir manutenção',
          ctaDestination: '· ambientes reais',
          metaLabel: '',
        );
      case 'in_formation':
        return _LineVisualState(
          color: const Color(0xFFF1C40F),
          badgeLabel: 'EM FORMAÇÃO',
          kindLabel: kind,
          ctaLabel: 'Continuar formação',
          ctaDestination: '· caixas',
          metaLabel: '',
        );
      case 'triagem':
        return _LineVisualState(
          color: const Color(0xFF4DD0E1),
          badgeLabel: 'EM TRIAGEM',
          kindLabel: kind,
          ctaLabel: 'Continuar triagem',
          ctaDestination: '· fase 0',
          metaLabel: 'Triagem em andamento',
        );
      default: // not_started
        return _LineVisualState(
          color: const Color(0xFF5A7280),
          badgeLabel: 'NÃO INICIADA',
          kindLabel: kind,
          ctaLabel: 'Iniciar triagem',
          ctaDestination: '· fase 0',
          metaLabel: 'Triagem ainda não realizada',
        );
    }
  }
}
