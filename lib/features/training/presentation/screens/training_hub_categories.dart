part of 'training_hub_screen.dart';

class _TrainingSpecialtiesSection extends StatelessWidget {
  final List<TrainingSpecialtyModel> specialties;
  final List<TrainingHubSession> sessions;
  final bool loading;
  final ValueChanged<String> onTap;
  final VoidCallback onAddSpecialtyTap;

  const _TrainingSpecialtiesSection({
    required this.specialties,
    required this.sessions,
    required this.loading,
    required this.onTap,
    required this.onAddSpecialtyTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeCount = specialties.where((s) => s.isActive).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Label
        Row(
          children: [
            Text(
              'ESPECIALIDADES',
              style: GoogleFonts.inter(
                color: const Color(0xFF4DD0E1),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Divider(
                color: Color(0x264DD0E1), // rgba(77, 208, 225, 0.15)
                thickness: 1,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0x1A4DD0E1), // rgba(77, 208, 225, 0.1)
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$activeCount ativas',
                style: GoogleFonts.inter(
                  color: const Color(0xFF4DD0E1),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (specialties.isEmpty)
          _TrainingEmptyState(
            icon: loading ? Icons.sync_rounded : Icons.shield_outlined,
            message: loading
                ? 'Carregando especialidades...'
                : 'Nenhuma especialidade cadastrada',
          )
        else
          ...specialties.map((specialty) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SpecialtyRow(
                specialty: specialty,
                sessions: sessions,
                onTap: () => onTap(specialty.name),
              ),
            );
          }),
        const SizedBox(height: 4),
        // Add new specialty button
        CustomPaint(
          painter: DashedBorderPainter(
            color: const Color(0x4D4DD0E1), // rgba(77, 208, 225, 0.3)
            borderRadius: 12.0,
            dashLength: 6,
            gap: 4,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onAddSpecialtyTap,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: const Color(0x0A4DD0E1), // rgba(77, 208, 225, 0.04)
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '+',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF4DD0E1),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Iniciar nova especialidade',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF4DD0E1),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SpecialtyRow extends StatelessWidget {
  final TrainingSpecialtyModel specialty;
  final List<TrainingHubSession> sessions;
  final VoidCallback onTap;

  const _SpecialtyRow({
    required this.specialty,
    required this.sessions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final key = normalizeTrainingKey(specialty.name);
    final isDetection = key.contains('detec') || key.contains('faro');

    // Para detecção, derivar badge do estado real das linhas
    if (isDetection && specialty.dogId.isNotEmpty) {
      return _DetectionSpecialtyRow(
        specialty: specialty,
        sessions: sessions,
        onTap: onTap,
      );
    }

    return _buildCard(
      context,
      isOperational: specialty.isOperational,
      lastTrainingLabel: specialty.lastTrainingLabel,
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required bool isOperational,
    required String lastTrainingLabel,
  }) {
    final Color sideColor =
        isOperational ? const Color(0xFF2ECC71) : const Color(0xFFF1C40F);
    final String emoji = _specialtyEmojiFor(specialty.name);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: specialty.isInFormation
                ? const Color(0x0AF1C40F)
                : const Color(0x0DFFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0x14FFFFFF),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 78,
                  color: sideColor,
                ),
                const SizedBox(width: 12),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isOperational
                        ? const Color(0x1F2ECC71)
                        : const Color(0x1FF1C40F),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          specialty.name,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: isOperational
                                    ? const Color(0x1F2ECC71)
                                    : const Color(0x1FF1C40F),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    isOperational ? '● ' : '◔ ',
                                    style: TextStyle(
                                      color: sideColor,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    isOperational
                                        ? 'OPERACIONAL'
                                        : 'EM FORMAÇÃO',
                                    style: GoogleFonts.inter(
                                      color: sideColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '· última $lastTrainingLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: const Color(0xFFB0C4CC),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _buildSpecialtyMeta(specialty, sessions),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '›',
                  style: TextStyle(
                    color: Color(0xFF5A7280),
                    fontSize: 24,
                  ),
                ),
                const SizedBox(width: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Card de Detecção que deriva badge e meta dos estados reais das linhas.
class _DetectionSpecialtyRow extends StatelessWidget {
  final TrainingSpecialtyModel specialty;
  final List<TrainingHubSession> sessions;
  final VoidCallback onTap;

  const _DetectionSpecialtyRow({
    required this.specialty,
    required this.sessions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final detectionService = DetectionService();
    return StreamBuilder<List<DetectionLine>>(
      stream: detectionService.watchLines(specialty.dogId),
      builder: (context, snapshot) {
        final lines = snapshot.data ?? [];

        // Derivar badge agregado (prioridade: in_formation > operational > not_started)
        final hasFormation =
            lines.any((l) => l.status == 'in_formation' || l.status == 'triagem');
        final hasOperational = lines.any((l) => l.status == 'operational');

        final bool isOperational;
        final String badgeLabel;
        final Color badgeColor;

        if (hasFormation) {
          isOperational = false;
          badgeLabel = 'EM FORMAÇÃO';
          badgeColor = const Color(0xFFF1C40F);
        } else if (hasOperational) {
          isOperational = true;
          badgeLabel = 'OPERACIONAL';
          badgeColor = const Color(0xFF2ECC71);
        } else {
          isOperational = false;
          badgeLabel = 'NÃO INICIADA';
          badgeColor = const Color(0xFF5A7280);
        }

        // Última sessão entre todas as linhas
        DateTime? lastSession;
        for (final line in lines) {
          final ls = line.lastSessionAt ?? line.updatedAt;
          if (ls != null && (lastSession == null || ls.isAfter(lastSession))) {
            lastSession = ls;
          }
        }
        final lastLabel = lastSession != null
            ? formatRelativeTrainingDate(lastSession)
            : specialty.lastTrainingLabel;

        final String emoji = _specialtyEmojiFor(specialty.name);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                color: hasFormation
                    ? const Color(0x0AF1C40F)
                    : const Color(0x0DFFFFFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0x14FFFFFF),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 78,
                      color: badgeColor,
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: badgeColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              specialty.name,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withAlpha(30),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        isOperational ? '● ' : '◔ ',
                                        style: TextStyle(
                                          color: badgeColor,
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        badgeLabel,
                                        style: GoogleFonts.inter(
                                          color: badgeColor,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    '· última $lastLabel',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      color: const Color(0xFFB0C4CC),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            _DetectionMetaFromLines(dogId: specialty.dogId),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '›',
                      style: TextStyle(
                        color: Color(0xFF5A7280),
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TrainingGeneralSection extends StatelessWidget {
  final List<TrainingGeneralTypeModel> trainings;
  final ValueChanged<String> onTap;

  const _TrainingGeneralSection({
    required this.trainings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Label
        Row(
          children: [
            Text(
              'TREINOS GERAIS',
              style: GoogleFonts.inter(
                color: const Color(0xFF4DD0E1),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Divider(
                color: Color(0x264DD0E1), // rgba(77, 208, 225, 0.15)
                thickness: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (trainings.isEmpty)
          const _TrainingEmptyState(
            icon: Icons.fitness_center_rounded,
            message: 'Nenhum treino geral registrado',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final double itemWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: trainings.map((training) {
                  return SizedBox(
                    width: itemWidth,
                    child: _GeneralTrainingTile(
                      training: training,
                      onTap: () => onTap(training.name),
                    ),
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }
}

class _GeneralTrainingTile extends StatelessWidget {
  final TrainingGeneralTypeModel training;
  final VoidCallback onTap;

  const _GeneralTrainingTile({
    required this.training,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String emoji = _specialtyEmojiFor(training.name);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x0DFFFFFF), // rgba(255, 255, 255, 0.03)
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0x14FFFFFF), // rgba(255, 255, 255, 0.08)
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Icon Box
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0x1A4DD0E1), // rgba(77, 208, 225, 0.1)
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(width: 10),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      training.name,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      training.lastTrainingLabel,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF5A7280),
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrainingEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _TrainingEmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0x264DD0E1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                color: const Color(0xFFA7B4BA),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Helpers
String _specialtyEmojiFor(String value) {
  final key = normalizeTrainingKey(value);
  if (key.contains('detec') || key.contains('faro')) return '👃';
  if (key.contains('guarda') || key.contains('protec')) return '🛡';
  if (key.contains('busca') || key.contains('captura')) return '🎯';
  if (key.contains('obediencia')) return '🐾';
  if (key.contains('condicionamento')) return '💪';
  return '🎯';
}

Widget _buildSpecialtyMeta(TrainingSpecialtyModel specialty, List<TrainingHubSession> sessions) {
  final key = normalizeTrainingKey(specialty.name);
  final sessionsCount = sessions.where((s) =>
    normalizeTrainingKey(s.specialty) == key &&
    s.date.year == DateTime.now().year &&
    s.date.month == DateTime.now().month
  ).length;

  if (key.contains('detec') || key.contains('faro')) {
    if (specialty.subAreas.isNotEmpty) {
      return _buildSubAreasText(specialty.subAreas);
    }
    // Derivar dos dados reais das detection_lines
    if (specialty.dogId.isNotEmpty) {
      return _DetectionMetaFromLines(dogId: specialty.dogId);
    }
    return const SizedBox.shrink();
  }

  if (key.contains('guarda') || key.contains('protec')) {
    if (specialty.subAreas.isNotEmpty) {
      return _buildSubAreasText(specialty.subAreas);
    }
    return Text(
      'Caça consolidada · Defesa em abertura',
      style: GoogleFonts.inter(
        color: const Color(0xFF7A8A92),
        fontSize: 10,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  // Default for B&C or other specialties
  final prefix = specialty.isOperational ? 'Manutenção' : 'Formação';
  return Text(
    '$prefix · $sessionsCount sessões neste mês',
    style: GoogleFonts.inter(
      color: const Color(0xFF7A8A92),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    ),
  );
}

/// Widget que lê as detection_lines reais do Firestore e monta o resumo
/// derivado (ex: "Drogas: operacional · Armas/Cadáver: não iniciadas").
class _DetectionMetaFromLines extends StatelessWidget {
  final String dogId;

  const _DetectionMetaFromLines({required this.dogId});

  @override
  Widget build(BuildContext context) {
    final detectionService = DetectionService();
    return StreamBuilder<List<DetectionLine>>(
      stream: detectionService.watchLines(dogId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Text(
            'Carregando linhas...',
            style: GoogleFonts.inter(
              color: const Color(0xFF7A8A92),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          );
        }

        final lines = snapshot.data!;
        final operationalList = <String>[];
        final inFormationList = <String>[];
        final notStartedList = <String>[];

        for (final line in lines) {
          switch (line.status) {
            case 'operational':
              operationalList.add(line.displayName);
              break;
            case 'in_formation':
              inFormationList.add(line.displayName);
              break;
            case 'triagem':
              inFormationList.add(line.displayName);
              break;
            default:
              notStartedList.add(line.displayName);
          }
        }

        final List<TextSpan> spans = [];

        void addGroup(List<String> list, String label) {
          if (list.isEmpty) return;
          if (spans.isNotEmpty) {
            spans.add(const TextSpan(
              text: ' · ',
              style: TextStyle(color: Color(0xFFB0C4CC)),
            ));
          }
          spans.add(TextSpan(
            text: '${list.join("/")} ',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white),
          ));
          spans.add(TextSpan(
            text: label,
            style: const TextStyle(color: Color(0xFFB0C4CC)),
          ));
        }

        addGroup(operationalList, 'operacional');
        addGroup(inFormationList, 'em formação');
        addGroup(notStartedList, 'não iniciada');

        if (spans.isEmpty) {
          return Text(
            'Nenhuma linha configurada',
            style: GoogleFonts.inter(
              color: const Color(0xFF7A8A92),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          );
        }

        return RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            style: GoogleFonts.inter(fontSize: 10, height: 1.3),
            children: spans,
          ),
        );
      },
    );
  }
}

Widget _buildSubAreasText(List<TrainingSubAreaModel> subAreas) {
  if (subAreas.isEmpty) return const SizedBox.shrink();
  final List<String> operationalList = [];
  final List<String> notStartedList = [];
  final List<String> inFormationList = [];
  for (final area in subAreas) {
    if (area.isOperational) {
      operationalList.add(area.name);
    } else if (area.status == 'not_started' || area.status == 'nao_iniciada') {
      notStartedList.add(area.name);
    } else {
      inFormationList.add(area.name);
    }
  }
  final List<TextSpan> spans = [];

  void addGroup(List<String> list, String label) {
    if (list.isEmpty) return;
    if (spans.isNotEmpty) {
      spans.add(const TextSpan(text: ' · ', style: TextStyle(color: Color(0xFFB0C4CC))));
    }
    spans.add(TextSpan(
      text: '${list.join('/')}: ',
      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
    ));
    spans.add(TextSpan(
      text: label,
      style: const TextStyle(color: Color(0xFFB0C4CC)),
    ));
  }

  addGroup(operationalList, 'operacional');
  addGroup(inFormationList, 'em formação');
  addGroup(notStartedList, 'não iniciada');

  return RichText(
    text: TextSpan(
      style: GoogleFonts.inter(fontSize: 10, height: 1.3),
      children: spans,
    ),
  );
}

// Dashed Border Custom Painter
class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double dashLength;
  final double borderRadius;

  DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.0,
    this.gap = 4.0,
    this.dashLength = 6.0,
    this.borderRadius = 12.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(borderRadius),
    );

    final Path path = Path()..addRRect(rrect);
    final Path dashedPath = Path();

    double distance = 0.0;
    for (final PathMetric measure in path.computeMetrics()) {
      while (distance < measure.length) {
        final double len = dashLength;
        dashedPath.addPath(
          measure.extractPath(distance, (distance + len).clamp(0.0, measure.length)),
          Offset.zero,
        );
        distance += len + gap;
      }
    }

    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.gap != gap ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.borderRadius != borderRadius;
  }
}
