import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/core/widgets/binomio_header.dart';

/// Condicionamento Físico — Visão geral + Nova sessão
/// Tela A: resumo semanal, catálogo de exercícios, sessões recentes
/// Tela B: formulário inteligente por exercício
class ConditioningScreen extends StatefulWidget {
  final Dog dog;

  const ConditioningScreen({super.key, required this.dog});

  @override
  State<ConditioningScreen> createState() => _ConditioningScreenState();
}

class _ConditioningScreenState extends State<ConditioningScreen> {
  _ExerciseType? _selectedExercise;

  @override
  Widget build(BuildContext context) {
    if (_selectedExercise != null) {
      return _ConditioningFormView(
        dog: widget.dog,
        exercise: _selectedExercise!,
        onBack: () => setState(() => _selectedExercise = null),
      );
    }
    return _ConditioningOverview(
      dog: widget.dog,
      onExerciseTap: (ex) => setState(() => _selectedExercise = ex),
    );
  }
}

// --- Exercise catalog data ---

class _ExerciseType {
  final String name;
  final String icon;
  final String category;
  final bool gpsDefault;
  final List<_FieldDef> fields;

  const _ExerciseType({
    required this.name,
    required this.icon,
    required this.category,
    this.gpsDefault = false,
    required this.fields,
  });
}

class _FieldDef {
  final String key;
  final String label;
  final String unit;
  const _FieldDef({required this.key, required this.label, required this.unit});
}

const _exerciseCatalog = <_ExerciseType>[
  // Cardiovascular
  _ExerciseType(name: 'Passeio', icon: '🚶', category: 'CARDIOVASCULAR', gpsDefault: true, fields: [
    _FieldDef(key: 'duration', label: 'DURAÇÃO', unit: 'min'),
    _FieldDef(key: 'distance', label: 'DISTÂNCIA', unit: 'km'),
  ]),
  _ExerciseType(name: 'Esteira', icon: '🏃', category: 'CARDIOVASCULAR', fields: [
    _FieldDef(key: 'sets', label: 'SÉRIES', unit: 'x'),
    _FieldDef(key: 'duration', label: 'DURAÇÃO/SÉRIE', unit: 'min'),
    _FieldDef(key: 'speed', label: 'VELOCIDADE', unit: 'km/h'),
  ]),
  _ExerciseType(name: 'Paraquedas', icon: '🪂', category: 'CARDIOVASCULAR', gpsDefault: true, fields: [
    _FieldDef(key: 'duration', label: 'DURAÇÃO', unit: 'min'),
    _FieldDef(key: 'distance', label: 'DISTÂNCIA', unit: 'm'),
  ]),
  _ExerciseType(name: 'Natação', icon: '🏊', category: 'CARDIOVASCULAR', fields: [
    _FieldDef(key: 'duration', label: 'DURAÇÃO', unit: 'min'),
  ]),
  // Força
  _ExerciseType(name: 'Tração c/ peso', icon: '🏋', category: 'FORÇA', fields: [
    _FieldDef(key: 'load', label: 'CARGA', unit: 'kg'),
    _FieldDef(key: 'reps', label: 'REPETIÇÕES', unit: 'x'),
    _FieldDef(key: 'duration', label: 'DURAÇÃO', unit: 'min'),
  ]),
  _ExerciseType(name: 'Tração elástica', icon: '🪢', category: 'FORÇA', fields: [
    _FieldDef(key: 'duration', label: 'DURAÇÃO', unit: 'min'),
  ]),
  _ExerciseType(name: 'Escalada', icon: '🧗', category: 'FORÇA', fields: [
    _FieldDef(key: 'reps', label: 'REPETIÇÕES', unit: 'x'),
    _FieldDef(key: 'height', label: 'ALTURA', unit: 'm'),
  ]),
  // Agilidade e Pliometria
  _ExerciseType(name: 'Bolinha em campo', icon: '⚽', category: 'AGILIDADE E PLIOMETRIA', fields: [
    _FieldDef(key: 'reps', label: 'REPETIÇÕES', unit: 'vezes'),
    _FieldDef(key: 'diagonal', label: 'DIAGONAL', unit: 'm'),
    _FieldDef(key: 'duration', label: 'DURAÇÃO', unit: 'min'),
  ]),
  _ExerciseType(name: 'A-Frame', icon: '📐', category: 'AGILIDADE E PLIOMETRIA', fields: [
    _FieldDef(key: 'reps', label: 'REPETIÇÕES', unit: 'x'),
  ]),
  _ExerciseType(name: 'Salto altura', icon: '⬆', category: 'AGILIDADE E PLIOMETRIA', fields: [
    _FieldDef(key: 'height', label: 'ALTURA MÁX', unit: 'cm'),
    _FieldDef(key: 'reps', label: 'REPETIÇÕES', unit: 'x'),
  ]),
  _ExerciseType(name: 'Salto distância', icon: '↔', category: 'AGILIDADE E PLIOMETRIA', fields: [
    _FieldDef(key: 'distance', label: 'DISTÂNCIA MÁX', unit: 'm'),
    _FieldDef(key: 'reps', label: 'REPETIÇÕES', unit: 'x'),
  ]),
  _ExerciseType(name: 'Cavaletes', icon: '🔢', category: 'AGILIDADE E PLIOMETRIA', fields: [
    _FieldDef(key: 'reps', label: 'REPETIÇÕES', unit: 'x'),
    _FieldDef(key: 'height', label: 'ALTURA', unit: 'cm'),
  ]),
];

// ============================================================
// TELA A — VISÃO GERAL
// ============================================================

class _ConditioningOverview extends StatelessWidget {
  final Dog dog;
  final void Function(_ExerciseType) onExerciseTap;

  const _ConditioningOverview({required this.dog, required this.onExerciseTap});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWeekSummary(context),
                    const SizedBox(height: 16),
                    _buildExerciseCatalog(),
                    const SizedBox(height: 20),
                    _buildRecentSessions(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.primary.withAlpha(30)),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: AppTheme.textPrimary, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TREINO CONTÍNUO',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      'Condicionamento Físico',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Center(
                  child: Text('💪', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Dog status
          Consumer<TrainingViewModel>(
            builder: (_, vm, __) {
              final condSessions = vm.trainings
                  .where((t) => t.trainingType.toLowerCase().contains('condicionamento'))
                  .toList();
              int? lastDays;
              if (condSessions.isNotEmpty) {
                condSessions.sort((a, b) => b.date.compareTo(a.date));
                lastDays = DateTime.now().difference(condSessions.first.date).inDays;
              }
              final lastStr = lastDays != null ? 'Última sessão há $lastDays dias' : 'Sem sessões';
              return BinomioHeader(
                dog: dog,
                subtitle: '$lastStr · ${condSessions.length} sessões totais',
                subtitleColor: AppTheme.textSecondary,
                avatarSize: 44,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWeekSummary(BuildContext context) {
    return Consumer<TrainingViewModel>(
      builder: (_, vm, __) {
        final now = DateTime.now();
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final weekSessions = vm.trainings.where((t) {
          return t.trainingType.toLowerCase().contains('condicionamento') &&
              t.date.isAfter(weekStart);
        }).toList();

        final sessionCount = weekSessions.length;
        // Sum durations from metadata
        int totalMinutes = 0;
        double totalKm = 0;
        for (final s in weekSessions) {
          final meta = s.metadata;
          if (meta != null) {
            final dur = meta['duration'];
            if (dur != null) totalMinutes += int.tryParse(dur.toString()) ?? 0;
            final dist = meta['distance'];
            if (dist != null) totalKm += double.tryParse(dist.toString()) ?? 0;
          }
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primary.withAlpha(15),
                AppTheme.success.withAlpha(8),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primary.withAlpha(50)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '📊 ESTA SEMANA',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _weekStat('$sessionCount', 'SESSÕES'),
                  _weekStat('${totalMinutes}min', 'TEMPO'),
                  _weekStat('${totalKm.toStringAsFixed(1)}km', 'DISTÂNCIA'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _weekStat(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(50),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseCatalog() {
    // Group by category
    final categories = <String, List<_ExerciseType>>{};
    for (final ex in _exerciseCatalog) {
      categories.putIfAbsent(ex.category, () => []).add(ex);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'EXERCÍCIOS',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(height: 1, color: AppTheme.primary.withAlpha(40)),
            ),
            const SizedBox(width: 8),
            Text(
              'tap pra registrar',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        ...categories.entries.map((entry) {
          final isLastCategory = entry.key == categories.keys.last;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 8),
                child: Text(
                  entry.key,
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.2,
                children: [
                  ...entry.value.map((ex) => _exerciseCard(ex)),
                  if (isLastCategory) _otherExerciseCard(),
                ],
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _exerciseCard(_ExerciseType ex) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onExerciseTap(ex);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withAlpha(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Center(
                    child: Text(ex.icon, style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ex.name,
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Consumer<TrainingViewModel>(
              builder: (_, vm, __) {
                final sessions = vm.trainings.where((t) =>
                    t.metadata?['exercise'] == ex.name &&
                    t.trainingType.toLowerCase().contains('condicionamento'));
                String lastStr = 'Sem sessões';
                if (sessions.isNotEmpty) {
                  final sorted = sessions.toList()..sort((a, b) => b.date.compareTo(a.date));
                  final days = DateTime.now().difference(sorted.first.date).inDays;
                  lastStr = days == 0 ? 'Última: hoje' : 'Última: há $days dias';
                }
                return Text(
                  lastStr,
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 9,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _otherExerciseCard() {
    final otherExercise = _ExerciseType(
      name: 'Outro',
      icon: '+',
      category: 'AGILIDADE E PLIOMETRIA',
      fields: [
        _FieldDef(key: 'custom_name', label: 'EXERCÍCIO', unit: ''),
        _FieldDef(key: 'duration', label: 'DURAÇÃO', unit: 'min'),
        _FieldDef(key: 'reps', label: 'REPETIÇÕES', unit: 'x'),
      ],
    );
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onExerciseTap(otherExercise);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.primary.withAlpha(5),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: AppTheme.primary.withAlpha(80),
            style: BorderStyle.none,
          ),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: AppTheme.primary.withAlpha(80),
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Center(
                    child: Text('+', style: GoogleFonts.inter(fontSize: 16, color: AppTheme.primary, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Outro',
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Text(
              'Personalizado',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSessions(BuildContext context) {
    return Consumer<TrainingViewModel>(
      builder: (_, vm, __) {
        final recent = vm.trainings
            .where((t) => t.trainingType.toLowerCase().contains('condicionamento'))
            .take(5)
            .toList();

        if (recent.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'SESSÕES RECENTES',
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(height: 1, color: AppTheme.primary.withAlpha(40)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...recent.map((s) {
              final day = '${s.date.day.toString().padLeft(2, '0')}/${s.date.month.toString().padLeft(2, '0')}';
              final exName = s.metadata?['exercise'] ?? 'Condicionamento';
              final exIcon = _exerciseCatalog
                  .where((e) => e.name == exName)
                  .map((e) => e.icon)
                  .firstOrNull ?? '💪';
              final meta = s.metadata ?? {};
              final dur = meta['duration'];
              final intensity = meta['intensity'] ?? '';
              final metaStr = [
                if (dur != null) '${dur}min',
                if (intensity.toString().isNotEmpty) intensity,
              ].join(' · ');

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withAlpha(15)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 42,
                      child: Text(
                        day,
                        style: GoogleFonts.inter(
                          color: AppTheme.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(exIcon, style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exName,
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (metaStr.isNotEmpty)
                            Text(
                              metaStr,
                              style: GoogleFonts.inter(
                                color: AppTheme.textTertiary,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (meta['gps'] == true)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withAlpha(25),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'GPS',
                          style: GoogleFonts.inter(
                            color: AppTheme.primary,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                   ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

// ============================================================
// TELA B — NOVA SESSÃO (FORMULÁRIO INTELIGENTE)
// ============================================================

class _ConditioningFormView extends StatefulWidget {
  final Dog dog;
  final _ExerciseType exercise;
  final VoidCallback onBack;

  const _ConditioningFormView({
    required this.dog,
    required this.exercise,
    required this.onBack,
  });

  @override
  State<_ConditioningFormView> createState() => _ConditioningFormViewState();
}

class _ConditioningFormViewState extends State<_ConditioningFormView> {
  final _obsController = TextEditingController();
  final Map<String, TextEditingController> _fieldControllers = {};

  static const _intensities = ['Leve', 'Moderada', 'Intensa'];
  static const _conditions = ['Normal', 'Ofegante', 'Exausto'];

  int? _selectedIntensity;
  int? _selectedCondition;
  bool _gpsEnabled = false;

  @override
  void initState() {
    super.initState();
    _gpsEnabled = widget.exercise.gpsDefault;
    for (final f in widget.exercise.fields) {
      _fieldControllers[f.key] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _obsController.dispose();
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveSession() async {
    if (_selectedIntensity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione a intensidade'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final metadata = <String, dynamic>{
      'specialty': 'condicionamento',
      'exercise': widget.exercise.name,
      'intensity': _intensities[_selectedIntensity!],
      'gps': _gpsEnabled,
    };

    if (_selectedCondition != null) {
      metadata['condition'] = _conditions[_selectedCondition!];
    }

    for (final f in widget.exercise.fields) {
      final val = _fieldControllers[f.key]?.text.trim();
      if (val != null && val.isNotEmpty) {
        metadata[f.key] = val;
      }
    }

    final session = TrainingSessionModel(
      dogId: widget.dog.id,
      dogName: widget.dog.name,
      date: DateTime.now(),
      trainingType: 'Condicionamento',
      location: '',
      weather: '',
      handlerNotes: _obsController.text.trim(),
      metadata: metadata,
    );

    try {
      final vm = Provider.of<TrainingViewModel>(context, listen: false);
      await vm.addTrainingSession(session);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sessão de ${widget.exercise.name} salva!'),
          backgroundColor: AppTheme.success,
        ),
      );
      widget.onBack();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildExerciseSelected(),
                    const SizedBox(height: 14),
                    _buildHealthLink(),
                    const SizedBox(height: 14),
                    _buildDynamicFields(),
                    const SizedBox(height: 14),
                    _buildIntensityRow(),
                    const SizedBox(height: 14),
                    _buildGpsToggle(),
                    const SizedBox(height: 14),
                    _buildConditionRow(),
                    const SizedBox(height: 14),
                    _buildObservations(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: _buildCTA(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.primary.withAlpha(30)),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: widget.onBack,
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: AppTheme.textPrimary, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NOVA SESSÃO · CONDICIONAMENTO',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      'Registrar treino',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Center(
                  child: Text('💪', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          BinomioHeader(
            dog: widget.dog,
            subtitle: widget.exercise.name,
            subtitleColor: AppTheme.primary,
            avatarSize: 40,
            withBackground: false,
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseSelected() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withAlpha(80)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(40),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(widget.exercise.icon, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EXERCÍCIO',
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  widget.exercise.name,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: widget.onBack,
            child: Text(
              'Trocar',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthLink() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.error.withAlpha(10),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(color: AppTheme.error.withAlpha(130), width: 3),
        ),
      ),
      child: Row(
        children: [
          const Text('⚕', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cão se lesionou ou sentiu algo?',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Registre como evento de saúde · só veterinário confirma',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary, size: 16),
        ],
      ),
    );
  }

  Widget _buildDynamicFields() {
    final fields = widget.exercise.fields;
    if (fields.isEmpty) return const SizedBox.shrink();

    final pairs = <List<_FieldDef>>[];
    for (int i = 0; i < fields.length; i += 2) {
      if (i + 1 < fields.length) {
        pairs.add([fields[i], fields[i + 1]]);
      } else {
        pairs.add([fields[i]]);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: pairs.map((pair) {
        if (pair.length == 2) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(child: _numericField(pair[0])),
                const SizedBox(width: 8),
                Expanded(child: _numericField(pair[1])),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _numericField(pair[0]),
        );
      }).toList(),
    );
  }

  Widget _numericField(_FieldDef field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primary.withAlpha(65)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _fieldControllers[field.key],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                field.unit,
                style: GoogleFonts.inter(
                  color: AppTheme.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIntensityRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('INTENSIDADE'),
        const SizedBox(height: 8),
        Row(
          children: List.generate(_intensities.length, (i) {
            final selected = _selectedIntensity == i;
            final colors = [AppTheme.success, AppTheme.warning, AppTheme.error];
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedIntensity = i);
                },
                child: Container(
                  margin: EdgeInsets.only(left: i > 0 ? 6 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: selected ? colors[i].withAlpha(30) : Colors.white.withAlpha(8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? colors[i] : Colors.white.withAlpha(20),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _intensities[i],
                      style: GoogleFonts.inter(
                        color: selected ? colors[i] : AppTheme.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildGpsToggle() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _gpsEnabled = !_gpsEnabled);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _gpsEnabled ? AppTheme.primary.withAlpha(20) : AppTheme.primary.withAlpha(10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _gpsEnabled ? AppTheme.primary.withAlpha(100) : AppTheme.primary.withAlpha(50),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(40),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text('📡', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rastreador GPS',
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    widget.exercise.gpsDefault
                        ? 'Recomendado para este exercício'
                        : 'Não recomendado pra área pequena · ative se quiser',
                    style: GoogleFonts.inter(
                      color: AppTheme.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 42,
              height: 24,
              decoration: BoxDecoration(
                color: _gpsEnabled ? AppTheme.primary : Colors.white.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: _gpsEnabled ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: const BoxDecoration(
                    color: AppTheme.background,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('CONDIÇÃO PÓS-TREINO'),
        const SizedBox(height: 8),
        Row(
          children: List.generate(_conditions.length, (i) {
            final selected = _selectedCondition == i;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedCondition = i);
                },
                child: Container(
                  margin: EdgeInsets.only(left: i > 0 ? 6 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.primary.withAlpha(30)
                        : Colors.white.withAlpha(8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? AppTheme.primary : Colors.white.withAlpha(20),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _conditions[i],
                      style: GoogleFonts.inter(
                        color: selected ? AppTheme.primary : AppTheme.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildObservations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _fieldLabel('OBSERVAÇÕES'),
            const Spacer(),
            Text(
              'opcional',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _obsController,
          maxLines: 3,
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Notas sobre a sessão · pegada · recuperação...',
            hintStyle: GoogleFonts.inter(color: AppTheme.textTertiary),
            filled: true,
            fillColor: AppTheme.primary.withAlpha(10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.primary.withAlpha(50)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.primary.withAlpha(50)),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
      ],
    );
  }

  Widget _buildCTA() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.background.withAlpha(0),
            AppTheme.background,
            AppTheme.background,
          ],
          stops: const [0.0, 0.2, 1.0],
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saveSession,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.background,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '💾 SALVAR SESSÃO',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: AppTheme.primary,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }
}
