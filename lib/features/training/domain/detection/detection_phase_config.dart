class DetectionPhaseConfig {
  final String code;
  final String title;
  final String groupLabel;
  final int boxCount;
  final String odorPositionMode;
  final bool usedBall;
  final int? targetConsecutiveHits;
  final bool isImplemented;
  final String description;

  const DetectionPhaseConfig({
    required this.code,
    required this.title,
    required this.groupLabel,
    required this.boxCount,
    required this.odorPositionMode,
    required this.usedBall,
    required this.targetConsecutiveHits,
    required this.isImplemented,
    required this.description,
  });

  bool get isVariable => odorPositionMode == 'variable';
  bool get isFixedLast => odorPositionMode == 'fixed_last';
  int get fixedOdorBox => boxCount;

  String get modeLabel {
    if (isVariable) return 'odor variável';
    if (isFixedLast) return 'odor fixo na última';
    return 'layout especial';
  }

  String get ballLabel => usedBall ? 'com bola' : 'sem bola';

  String get criterionLabel {
    final target = targetConsecutiveHits;
    if (target == null) return 'critério operacional';
    return '$target consecutivas';
  }

  Map<String, dynamic> toMetadata() {
    return {
      'phase': code,
      'phase_name': title,
      'box_count': boxCount,
      'odor_position_mode': odorPositionMode,
      'used_ball': usedBall,
      'target_consecutive_hits': targetConsecutiveHits,
      'implemented': isImplemented,
    };
  }
}

class DetectionPhaseCatalog {
  static const List<DetectionPhaseConfig> phases = [
    DetectionPhaseConfig(
      code: '1b',
      title: 'Resposta',
      groupLabel: '1 caixa',
      boxCount: 1,
      odorPositionMode: 'fixed_last',
      usedBall: true,
      targetConsecutiveHits: 3,
      isImplemented: true,
      description: 'Associação inicial do odor com resposta e recompensa.',
    ),
    DetectionPhaseConfig(
      code: '2b',
      title: 'Processo de busca',
      groupLabel: '2 caixas',
      boxCount: 2,
      odorPositionMode: 'fixed_last',
      usedBall: true,
      targetConsecutiveHits: 3,
      isImplemented: true,
      description: 'Odor fixo na última caixa para construir varredura.',
    ),
    DetectionPhaseConfig(
      code: '2v',
      title: 'Busca com odor variável',
      groupLabel: '2 caixas',
      boxCount: 2,
      odorPositionMode: 'variable',
      usedBall: true,
      targetConsecutiveHits: 3,
      isImplemented: true,
      description:
          'Odor alternado entre caixas; critério confirmado em 3 acertos.',
    ),
    DetectionPhaseConfig(
      code: '3b',
      title: 'Independência com odor fixo',
      groupLabel: '3 caixas',
      boxCount: 3,
      odorPositionMode: 'fixed_last',
      usedBall: true,
      targetConsecutiveHits: 3,
      isImplemented: true,
      description:
          'Três caixas com odor fixo. A bola ainda é usada nesta fase.',
    ),
    DetectionPhaseConfig(
      code: '3v',
      title: 'Independência com odor variável',
      groupLabel: '3 caixas',
      boxCount: 3,
      odorPositionMode: 'variable',
      usedBall: false,
      targetConsecutiveHits: 10,
      isImplemented: true,
      description:
          'Ponto crítico do protocolo: 10 acertos consecutivos, sem bola.',
    ),
    DetectionPhaseConfig(
      code: '4b',
      title: 'Distância + comando "Busca"',
      groupLabel: '4 caixas',
      boxCount: 4,
      odorPositionMode: 'fixed_last',
      usedBall: false,
      targetConsecutiveHits: 3,
      isImplemented: true,
      description: 'Quatro caixas com odor fixo e aumento de distância.',
    ),
    DetectionPhaseConfig(
      code: '4v',
      title: 'Odor variável em 4 caixas',
      groupLabel: '4 caixas',
      boxCount: 4,
      odorPositionMode: 'variable',
      usedBall: false,
      targetConsecutiveHits: 3,
      isImplemented: true,
      description:
          'Odor variável em quatro caixas; critério confirmado em 3 acertos.',
    ),
    DetectionPhaseConfig(
      code: '4c',
      title: 'Quadrado horário/anti-horário',
      groupLabel: '4 caixas',
      boxCount: 4,
      odorPositionMode: 'square',
      usedBall: false,
      targetConsecutiveHits: 3,
      isImplemented: false,
      description:
          'Fase prevista no protocolo; layout será implementado depois.',
    ),
    DetectionPhaseConfig(
      code: 'final',
      title: 'Cenários reais progressivos',
      groupLabel: 'Ambientes reais',
      boxCount: 0,
      odorPositionMode: 'real_environment',
      usedBall: false,
      targetConsecutiveHits: null,
      isImplemented: false,
      description:
          'Treino em ambientes reais, fora do fluxo de caixas desta tela.',
    ),
  ];

  static DetectionPhaseConfig byCode(String? rawCode) {
    final normalized = normalizePhaseCode(rawCode);
    return phases.firstWhere(
      (phase) => phase.code == normalized,
      orElse: () => phases.first,
    );
  }

  static int indexOf(String? rawCode) {
    final code = normalizePhaseCode(rawCode);
    return phases.indexWhere((phase) => phase.code == code);
  }

  static DetectionPhaseConfig? nextAfter(String? rawCode) {
    final index = indexOf(rawCode);
    if (index < 0 || index >= phases.length - 1) return null;
    return phases[index + 1];
  }

  static String normalizePhaseCode(String? rawCode) {
    final value = (rawCode ?? '').trim().toLowerCase();
    switch (value) {
      case '':
      case 'triagem':
      case 'f1':
      case 'fase_1':
      case 'fase 1':
      case '1':
        return '1b';
      case 'f2':
      case 'fase_2':
      case 'fase 2':
      case '2':
        return '2b';
      case 'f3':
      case 'fase_3':
      case 'fase 3':
      case '3':
        return '3v';
      case 'f4':
      case 'fase_4':
      case 'fase 4':
      case '4':
        return '4b';
      case 'f5':
      case 'fase_5':
      case 'fase 5':
      case '5':
        return 'final';
      default:
        return value;
    }
  }
}

class DetectionSessionRecorder {
  final DetectionPhaseConfig phase;
  final List<DetectionRepetition> _repetitions;

  int currentStreak;
  int longestStreak;

  DetectionSessionRecorder({
    required this.phase,
    List<DetectionRepetition>? initialRepetitions,
  }) : _repetitions = List<DetectionRepetition>.from(
         initialRepetitions ?? const [],
       ),
       currentStreak = _calculateCurrentStreak(initialRepetitions ?? const []),
       longestStreak = _calculateLongestStreak(initialRepetitions ?? const []);

  List<DetectionRepetition> get repetitions => List.unmodifiable(_repetitions);
  int get totalReps => _repetitions.length;

  bool get criterionMet {
    final target = phase.targetConsecutiveHits;
    if (target == null) return false;
    return currentStreak >= target;
  }

  DetectionRepetition record({
    required int odorBox,
    required bool hit,
    DateTime? at,
  }) {
    if (phase.boxCount > 0 && (odorBox < 1 || odorBox > phase.boxCount)) {
      throw ArgumentError.value(
        odorBox,
        'odorBox',
        'A posição do odor deve existir na fase ${phase.code}.',
      );
    }

    final repetition = DetectionRepetition(
      order: _repetitions.length + 1,
      odorBox: odorBox,
      result: hit
          ? DetectionRepetitionResult.hit
          : DetectionRepetitionResult.miss,
      at: at ?? DateTime.now(),
    );

    _repetitions.add(repetition);
    if (hit) {
      currentStreak += 1;
      if (currentStreak > longestStreak) longestStreak = currentStreak;
    } else {
      currentStreak = 0;
    }
    return repetition;
  }

  static int _calculateCurrentStreak(List<DetectionRepetition> repetitions) {
    var count = 0;
    for (final repetition in repetitions.reversed) {
      if (!repetition.isHit) break;
      count += 1;
    }
    return count;
  }

  static int _calculateLongestStreak(List<DetectionRepetition> repetitions) {
    var longest = 0;
    var current = 0;
    for (final repetition in repetitions) {
      if (repetition.isHit) {
        current += 1;
        if (current > longest) longest = current;
      } else {
        current = 0;
      }
    }
    return longest;
  }
}

enum DetectionRepetitionResult { hit, miss }

class DetectionRepetition {
  final int order;
  final int odorBox;
  final DetectionRepetitionResult result;
  final DateTime at;

  const DetectionRepetition({
    required this.order,
    required this.odorBox,
    required this.result,
    required this.at,
  });

  bool get isHit => result == DetectionRepetitionResult.hit;

  String get resultValue => isHit ? 'hit' : 'miss';

  factory DetectionRepetition.fromJson(Map<String, dynamic> json) {
    return DetectionRepetition(
      order: _readInt(json['order']) ?? 0,
      odorBox: _readInt(json['odor_box'] ?? json['odorBox']) ?? 1,
      result: (json['result'] ?? '').toString() == 'hit'
          ? DetectionRepetitionResult.hit
          : DetectionRepetitionResult.miss,
      at: _readDate(json['ts'] ?? json['at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'order': order,
      'odor_box': odorBox,
      'result': resultValue,
      'ts': at,
    };
  }
}

int? _readInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _readDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  final dynamic timestamp = value;
  try {
    return timestamp.toDate() as DateTime;
  } catch (_) {
    return null;
  }
}
