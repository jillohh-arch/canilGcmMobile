import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/data/detection_service.dart';
import 'package:canil_gcm/features/training/domain/detection/detection_formation_session.dart';
import 'package:canil_gcm/features/training/domain/detection/detection_line.dart';
import 'package:canil_gcm/features/training/domain/detection/detection_phase_config.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

class DetectionFormationScreen extends StatefulWidget {
  final Dog dog;
  final DetectionService? service;
  final String? initialLineType;

  const DetectionFormationScreen({
    super.key,
    required this.dog,
    this.service,
    this.initialLineType,
  });

  @override
  State<DetectionFormationScreen> createState() =>
      _DetectionFormationScreenState();
}

class _DetectionFormationScreenState extends State<DetectionFormationScreen> {
  static const _bg = AppTheme.background;
  static const _panel = AppTheme.surfacePanelSoft;
  static const _panelSoft = AppTheme.surfacePanel;
  static const _cyan = AppTheme.primary;
  static const _yellow = AppTheme.warning;
  static const _green = AppTheme.success;
  static const _red = AppTheme.error;
  static const _muted = AppTheme.textSecondary;
  static const _mutedDark = AppTheme.textMuted;

  late final DetectionService _service;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<DetectionLine> _lines = [];
  DetectionLine? _selectedLine;

  bool _liveMode = false;
  DetectionLine? _liveLine;
  DetectionPhaseConfig? _livePhase;
  DetectionFormationSession? _liveSession;
  DetectionSessionRecorder? _recorder;
  DateTime? _startedAt;
  int? _selectedOdorBox;
  String _odorMaterial = DetectionOdorMaterials.noseMp;
  bool _completionDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? DetectionService();
    Future.microtask(_loadLines);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_liveMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _liveMode) _leaveLiveSession();
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: AppTheme.transparent,
            systemNavigationBarColor: _bg,
          ),
          child: SafeArea(
            child: _liveMode ? _buildLiveSession() : _buildSelector(),
          ),
        ),
      ),
    );
  }

  Future<void> _loadLines({String? keepLineType}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final actor = _resolveActor();
      final lines = await _service.getOrCreateDefaultLines(
        dogId: widget.dog.id,
        handlerId: actor.ra,
        handlerName: actor.name,
      );
      final selected = _resolveSelectedLine(
        lines,
        keepLineType ?? widget.initialLineType,
      );
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _selectedLine = selected;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Falha ao carregar formação: $e';
        _loading = false;
      });
    }
  }

  DetectionLine? _resolveSelectedLine(List<DetectionLine> lines, String? type) {
    if (lines.isEmpty) return null;
    final wanted = type ?? _selectedLine?.normalizedType;
    if (wanted != null) {
      for (final line in lines) {
        if (line.normalizedType == wanted) return line;
      }
    }
    return lines.first;
  }

  Widget _buildSelector() {
    return Column(
      children: [
        _buildHeader(
          title: 'Formação · Detecção',
          subtitle: '${widget.dog.name} · selecione a fase',
          onBack: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _yellow))
              : _error != null
              ? _buildErrorState()
              : RefreshIndicator(
                  color: _yellow,
                  onRefresh: () => _loadLines(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
                    children: [
                      _buildDogProgressCard(),
                      const SizedBox(height: 12),
                      _buildOdorMaterialSelector(),
                      const SizedBox(height: 12),
                      _buildLineSelector(),
                      const SizedBox(height: 12),
                      if (_selectedLine != null)
                        _buildPhaseTrail(_selectedLine!),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildLiveSession() {
    final line = _liveLine;
    final phase = _livePhase;
    final recorder = _recorder;
    if (line == null || phase == null || recorder == null) {
      return _buildSelector();
    }

    final target = phase.targetConsecutiveHits;
    final progress = target == null || target == 0
        ? 0.0
        : (recorder.currentStreak / target).clamp(0.0, 1.0);

    return Column(
      children: [
        _buildHeader(
          title: 'Formação · Detecção',
          subtitle:
              '${widget.dog.name} · ${line.displayName} · sessão em andamento',
          onBack: _leaveLiveSession,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
            children: [
              _buildPhaseLiveBar(phase, target),
              const SizedBox(height: 13),
              _buildBoxesPanel(phase, recorder.totalReps + 1),
              const SizedBox(height: 13),
              _buildCounterPanel(phase, recorder, target, progress),
              const SizedBox(height: 11),
              _buildSeries(recorder.repetitions),
              const SizedBox(height: 14),
              _buildLiveActions(),
              TextButton(
                onPressed: _saving ? null : _finishLiveSession,
                child: Text(
                  _saving
                      ? 'Salvando sessão...'
                      : 'Encerrar e registrar sessão',
                  style: GoogleFonts.inter(
                    color: _mutedDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader({
    required String title,
    required String subtitle,
    required VoidCallback onBack,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.textPrimary.withAlpha(10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            color: AppTheme.textPrimary,
            tooltip: 'Voltar',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: _cyan,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.science_outlined, color: _cyan.withAlpha(210)),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _boxDecoration(borderColor: _red.withAlpha(80)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Não foi possível carregar a formação.',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? '',
                style: GoogleFonts.inter(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _loadLines(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDogProgressCard() {
    final line = _selectedLine;
    final implementedCodes = DetectionPhaseCatalog.phases
        .where((phase) => phase.isImplemented)
        .map((phase) => phase.code)
        .toSet();
    final completed =
        line?.phasesCompleted.where(implementedCodes.contains).length ?? 0;
    final total = implementedCodes.length;
    final ratio = total == 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Progresso no protocolo',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$completed / $total fases',
                style: GoogleFonts.robotoMono(
                  color: _cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: ratio,
              backgroundColor: AppTheme.textPrimary.withAlpha(18),
              valueColor: const AlwaysStoppedAnimation(_green),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            line == null
                ? 'Selecione uma linha de detecção.'
                : '${line.displayName} · fase atual ${line.normalizedCurrentPhase} · melhor série ${line.bestStreak}',
            style: GoogleFonts.inter(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOdorMaterialSelector() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MATERIAL DE ODOR', style: _sectionStyle(_yellow)),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: DetectionOdorMaterials.values.map((material) {
              final selected = material == _odorMaterial;
              return ChoiceChip(
                selected: selected,
                showCheckmark: false,
                label: Text(DetectionOdorMaterials.label(material)),
                labelStyle: GoogleFonts.inter(
                  color: selected ? _bg : AppTheme.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
                selectedColor: _yellow,
                backgroundColor: AppTheme.textPrimary.withAlpha(9),
                side: BorderSide(
                  color: selected
                      ? _yellow
                      : AppTheme.textPrimary.withAlpha(18),
                ),
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  setState(() => _odorMaterial = material);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLineSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LINHA DE DETECÇÃO', style: _sectionStyle(_cyan)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _lines.map((line) {
              final selected = line.id == _selectedLine?.id;
              final color = line.status == 'not_started' ? _mutedDark : _yellow;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: selected,
                  showCheckmark: false,
                  avatar: Icon(
                    _lineIcon(line),
                    color: selected ? _bg : color,
                    size: 18,
                  ),
                  label: Text(line.displayName),
                  labelStyle: GoogleFonts.inter(
                    color: selected ? _bg : AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                  selectedColor: _yellow,
                  backgroundColor: AppTheme.textPrimary.withAlpha(9),
                  side: BorderSide(
                    color: selected
                        ? _yellow
                        : AppTheme.textPrimary.withAlpha(18),
                  ),
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedLine = line);
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildPhaseTrail(DetectionLine line) {
    final widgets = <Widget>[];
    String? lastGroup;
    for (final phase in DetectionPhaseCatalog.phases) {
      if (phase.groupLabel != lastGroup) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(38, 14, 0, 8),
            child: Text(
              phase.groupLabel.toUpperCase(),
              style: GoogleFonts.inter(
                color: _mutedDark,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
          ),
        );
        lastGroup = phase.groupLabel;
      }
      widgets.add(_buildPhaseRow(line, phase));
    }
    return Column(children: widgets);
  }

  Widget _buildPhaseRow(DetectionLine line, DetectionPhaseConfig phase) {
    final completed = line.phasesCompleted.contains(phase.code);
    final current = line.normalizedCurrentPhase == phase.code;
    final currentIndex = DetectionPhaseCatalog.indexOf(line.currentPhase);
    final phaseIndex = DetectionPhaseCatalog.indexOf(phase.code);
    final lineNotStarted = line.status == 'not_started';
    final firstPhase = phaseIndex == 0;
    final canStart =
        phase.isImplemented &&
        (completed || current || lineNotStarted && firstPhase);
    final locked = !canStart && !completed;
    final color = completed
        ? _green
        : current
        ? _yellow
        : _mutedDark;
    final nodeIcon = completed
        ? Icons.check_rounded
        : locked
        ? Icons.lock_rounded
        : Icons.play_arrow_rounded;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.only(top: 9),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: completed
                        ? _green
                        : current
                        ? _yellow
                        : _panelSoft,
                    border: Border.all(color: color.withAlpha(180)),
                  ),
                  child: Icon(
                    nodeIcon,
                    color: completed || current ? _bg : _mutedDark,
                    size: 15,
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: AppTheme.textPrimary.withAlpha(18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: canStart ? () => _startPhase(line, phase) : null,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.only(bottom: 9),
                padding: const EdgeInsets.all(13),
                decoration: _phaseDecoration(
                  completed: completed,
                  current: current || lineNotStarted && firstPhase,
                  locked: locked,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          phase.code,
                          style: GoogleFonts.robotoMono(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            phase.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: locked ? _muted : AppTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (completed)
                          Text(
                            'REVISAR',
                            style: GoogleFonts.robotoMono(
                              color: _green,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          )
                        else if (!phase.isImplemented)
                          Icon(
                            Icons.construction_rounded,
                            color: _mutedDark,
                            size: 16,
                          )
                        else if (locked)
                          Icon(Icons.lock_rounded, color: _mutedDark, size: 15),
                      ],
                    ),
                    if (canStart || current || phaseIndex <= currentIndex) ...[
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _metaChip('${phase.boxCount} caixas'),
                          _metaChip(phase.modeLabel),
                          _metaChip(phase.ballLabel),
                          _metaChip(phase.criterionLabel, accent: true),
                        ],
                      ),
                      if (canStart) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _startPhase(line, phase),
                            style: FilledButton.styleFrom(
                              backgroundColor: _yellow,
                              foregroundColor: AppTheme.background,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 18,
                            ),
                            label: Text(
                              completed ? 'INICIAR REVISÃO' : 'INICIAR SESSÃO',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                    if (!phase.isImplemented) ...[
                      const SizedBox(height: 8),
                      Text(
                        phase.description,
                        style: GoogleFonts.inter(
                          color: _mutedDark,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseLiveBar(DetectionPhaseConfig phase, int? target) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _yellow.withAlpha(18),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _yellow.withAlpha(55)),
      ),
      child: Row(
        children: [
          Text(
            phase.code,
            style: GoogleFonts.inter(
              color: _yellow,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '·',
              style: GoogleFonts.inter(color: _yellow.withAlpha(80)),
            ),
          ),
          Expanded(
            child: Text(
              '${phase.boxCount} caixas · ${phase.modeLabel} · ${phase.ballLabel} · ${DetectionOdorMaterials.label(_liveSession?.odorMaterial ?? _odorMaterial)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: _muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text.rich(
            TextSpan(
              text: 'meta ',
              children: [
                TextSpan(
                  text: target?.toString() ?? '-',
                  style: const TextStyle(color: _yellow),
                ),
              ],
            ),
            style: GoogleFonts.robotoMono(
              color: _mutedDark,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoxesPanel(DetectionPhaseConfig phase, int repetitionNumber) {
    if (phase.isSquare) {
      return _buildSquareBoxesPanel(phase, repetitionNumber);
    }

    final fixed = phase.isFixedLast;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 15, 14, 14),
      decoration: _boxDecoration(radius: 16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _yellow.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'REP $repetitionNumber',
                  style: GoogleFonts.robotoMono(
                    color: _yellow,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fixed
                      ? 'Odor fixo na última caixa'
                      : 'Toque na caixa onde está o odor',
                  style: GoogleFonts.inter(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(phase.boxCount, (index) {
              final number = index + 1;
              final selected = fixed
                  ? number == phase.fixedOdorBox
                  : number == _selectedOdorBox;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index == phase.boxCount - 1 ? 0 : 12,
                  ),
                  child: _buildBox(
                    number: number,
                    selected: selected,
                    enabled: !fixed,
                    showBall: phase.usedBall && selected,
                    onTap: () {
                      if (fixed) return;
                      HapticFeedback.selectionClick();
                      setState(() => _selectedOdorBox = number);
                    },
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.air_rounded, color: _yellow, size: 14),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  fixed
                      ? 'Odor travado na caixa ${phase.fixedOdorBox}'
                      : _selectedOdorBox == null
                      ? 'Selecione a posição do odor antes de registrar'
                      : 'Odor na caixa $_selectedOdorBox · alterne a cada repetição',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: _yellow,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSquareBoxesPanel(
    DetectionPhaseConfig phase,
    int repetitionNumber,
  ) {
    final recorder = _recorder;
    final direction =
        recorder?.currentDirection ?? DetectionDirections.clockwise;
    final directionLabel = DetectionDirections.label(direction);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 15, 14, 14),
      decoration: _boxDecoration(radius: 16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _yellow.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'REP $repetitionNumber',
                  style: GoogleFonts.robotoMono(
                    color: _yellow,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Quadrado · etapa $directionLabel · toque na caixa do odor',
                  style: GoogleFonts.inter(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final boxWidth = (width * 0.23).clamp(58.0, 76.0);
              final height = boxWidth * 2.9;
              final centerX = width / 2 - boxWidth / 2;
              final centerY = height / 2 - 46;
              return SizedBox(
                height: height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _SquarePathPainter(
                          color: _cyan.withAlpha(95),
                          clockwise: direction == DetectionDirections.clockwise,
                        ),
                      ),
                    ),
                    Positioned(
                      left: centerX,
                      top: 0,
                      width: boxWidth,
                      child: _buildBox(
                        number: 1,
                        selected: _selectedOdorBox == 1,
                        enabled: true,
                        onTap: () => _selectOdorBox(1),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: centerY,
                      width: boxWidth,
                      child: _buildBox(
                        number: 2,
                        selected: _selectedOdorBox == 2,
                        enabled: true,
                        onTap: () => _selectOdorBox(2),
                      ),
                    ),
                    Positioned(
                      left: centerX,
                      bottom: 0,
                      width: boxWidth,
                      child: _buildBox(
                        number: 3,
                        selected: _selectedOdorBox == 3,
                        enabled: true,
                        onTap: () => _selectOdorBox(3),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: centerY,
                      width: boxWidth,
                      child: _buildBox(
                        number: 4,
                        selected: _selectedOdorBox == 4,
                        enabled: true,
                        onTap: () => _selectOdorBox(4),
                      ),
                    ),
                    Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _panel,
                          shape: BoxShape.circle,
                          border: Border.all(color: _cyan.withAlpha(120)),
                        ),
                        child: Text(
                          'CONDUTOR',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: _cyan,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                direction == DetectionDirections.clockwise
                    ? Icons.rotate_right_rounded
                    : Icons.rotate_left_rounded,
                color: _yellow,
                size: 16,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _selectedOdorBox == null
                      ? 'Selecione a posição do odor antes de registrar'
                      : 'Odor na caixa $_selectedOdorBox · sentido $directionLabel',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: _yellow,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBox({
    required int number,
    required bool selected,
    required bool enabled,
    bool showBall = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 74,
            decoration: BoxDecoration(
              color: selected ? _yellow.withAlpha(28) : AppTheme.surfacePanel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? _yellow : AppTheme.textPrimary.withAlpha(25),
                width: selected ? 1.6 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: _yellow.withAlpha(35),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: 28,
                    height: 16,
                    margin: const EdgeInsets.only(top: 12),
                    decoration: const BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.all(Radius.elliptical(28, 16)),
                    ),
                  ),
                ),
                if (showBall)
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _yellow,
                        boxShadow: [
                          BoxShadow(
                            color: _yellow.withAlpha(90),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$number',
            style: GoogleFonts.robotoMono(
              color: selected ? _yellow : _mutedDark,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  void _selectOdorBox(int number) {
    HapticFeedback.selectionClick();
    setState(() => _selectedOdorBox = number);
  }

  Widget _buildCounterPanel(
    DetectionPhaseConfig phase,
    DetectionSessionRecorder recorder,
    int? target,
    double progress,
  ) {
    final missing = target == null ? null : target - recorder.currentStreak;
    final criterionMet = recorder.criterionMet;
    final heading = phase.isSquare
        ? 'ETAPA ${recorder.activeDirectionLabel.toUpperCase()}'
        : 'CONSECUTIVAS SEM ERRO';
    final detail = phase.isSquare && target != null
        ? 'Horário ${recorder.clockwiseStreak.clamp(0, target)}/$target · anti-horário ${recorder.counterClockwiseStreak.clamp(0, target)}/$target'
        : null;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _green.withAlpha(18),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _green.withAlpha(55)),
      ),
      child: Row(
        children: [
          Text.rich(
            TextSpan(
              text: '${recorder.currentStreak}',
              children: [
                TextSpan(
                  text: '/${target ?? '-'}',
                  style: const TextStyle(
                    color: _mutedDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            style: GoogleFonts.inter(
              color: _green,
              fontSize: 42,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  heading,
                  style: GoogleFonts.inter(
                    color: _muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 7),
                if (detail != null) ...[
                  Text(
                    detail,
                    style: GoogleFonts.robotoMono(
                      color: _cyan,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                ],
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: AppTheme.textPrimary.withAlpha(18),
                    valueColor: const AlwaysStoppedAnimation(_green),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  criterionMet
                      ? 'Critério atingido · fase será concluída automaticamente'
                      : missing == null
                      ? 'Critério definido pelo instrutor'
                      : phase.isSquare
                      ? 'Faltam $missing para concluir esta etapa'
                      : 'Faltam $missing para concluir a fase',
                  style: GoogleFonts.inter(
                    color: criterionMet ? _green : _muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeries(List<DetectionRepetition> repetitions) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            'SÉRIE',
            style: GoogleFonts.inter(
              color: _mutedDark,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 5,
            runSpacing: 5,
            children: repetitions.isEmpty
                ? [
                    Text(
                      'Nenhuma repetição registrada.',
                      style: GoogleFonts.inter(color: _mutedDark, fontSize: 11),
                    ),
                  ]
                : repetitions.map((rep) {
                    final hit = rep.isHit;
                    return Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: (hit ? _green : _red).withAlpha(32),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (hit ? _green : _red).withAlpha(130),
                        ),
                      ),
                      child: Icon(
                        hit ? Icons.check_rounded : Icons.close_rounded,
                        color: hit ? _green : _red,
                        size: 15,
                      ),
                    );
                  }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveActions() {
    final canRecord =
        _livePhase?.isFixedLast == true || _selectedOdorBox != null;
    final actionsDisabled = _saving || _completionDialogOpen || !canRecord;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: actionsDisabled ? null : () => _recordResult(false),
            style: OutlinedButton.styleFrom(
              foregroundColor: _red,
              side: BorderSide(
                color: canRecord ? _red.withAlpha(150) : _mutedDark,
              ),
              backgroundColor: _red.withAlpha(28),
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            icon: const Icon(Icons.close_rounded, size: 22),
            label: Text(
              'ERROU',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: actionsDisabled ? null : () => _recordResult(true),
            style: FilledButton.styleFrom(
              backgroundColor: canRecord ? _green : _mutedDark,
              foregroundColor: AppTheme.background,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            icon: const Icon(Icons.check_rounded, size: 23),
            label: Text(
              'ACERTOU',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _metaChip(String label, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: (accent ? _yellow : AppTheme.textPrimary).withAlpha(
          accent ? 22 : 10,
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: (accent ? _yellow : AppTheme.textPrimary).withAlpha(
            accent ? 65 : 18,
          ),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: accent ? _yellow : _muted,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  TextStyle _sectionStyle(Color color) {
    return GoogleFonts.inter(
      color: color,
      fontSize: 10,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.2,
    );
  }

  BoxDecoration _boxDecoration({Color? borderColor, double radius = 13}) {
    return BoxDecoration(
      color: AppTheme.textPrimary.withAlpha(8),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? AppTheme.textPrimary.withAlpha(20),
      ),
    );
  }

  BoxDecoration _phaseDecoration({
    required bool completed,
    required bool current,
    required bool locked,
  }) {
    return BoxDecoration(
      color: completed
          ? _green.withAlpha(12)
          : current
          ? _yellow.withAlpha(18)
          : AppTheme.textPrimary.withAlpha(8),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: current
            ? _yellow.withAlpha(90)
            : completed
            ? _green.withAlpha(45)
            : AppTheme.textPrimary.withAlpha(18),
      ),
    );
  }

  IconData _lineIcon(DetectionLine line) {
    switch (line.normalizedType) {
      case 'armas':
        return Icons.gps_fixed_rounded;
      case 'cadaver':
        return Icons.landscape_outlined;
      default:
        return Icons.science_outlined;
    }
  }

  Future<void> _startPhase(
    DetectionLine line,
    DetectionPhaseConfig phase,
  ) async {
    if (!phase.isImplemented) {
      _showMessage(
        'Esta fase está prevista, mas a tela ainda não foi liberada.',
      );
      return;
    }

    try {
      setState(() => _saving = true);
      final actor = _resolveActor();
      final startedLine = await _service.ensureLineStarted(
        dogId: widget.dog.id,
        line: line,
        handlerId: actor.ra,
        handlerName: actor.name,
      );
      final lineDocId = startedLine.id ?? startedLine.normalizedType;
      final openSession = await _service.getOpenFormationSession(
        dogId: widget.dog.id,
        lineId: lineDocId,
        phase: phase.code,
      );
      final session =
          openSession ??
          await _service.startFormationSession(
            dogId: widget.dog.id,
            dogName: widget.dog.name,
            line: startedLine,
            phase: phase,
            odorMaterial: _odorMaterial,
            handlerId: actor.ra,
            handlerName: actor.name,
          );
      final recorder = DetectionSessionRecorder(
        phase: phase,
        initialRepetitions: session.repetitions,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _liveLine = startedLine;
        _livePhase = phase;
        _liveSession = session;
        _recorder = recorder;
        _startedAt = session.startedAt;
        _odorMaterial = session.odorMaterial;
        _selectedOdorBox = phase.isFixedLast ? phase.fixedOdorBox : null;
        _completionDialogOpen = false;
        _liveMode = true;
        _saving = false;
      });
      if (openSession != null) {
        _showMessage('Sessão em andamento retomada.');
      }
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _showMessage('Falha ao iniciar sessão: $e', error: true);
    }
  }

  Future<void> _recordResult(bool hit) async {
    if (_saving || _completionDialogOpen) return;
    final session = _liveSession;
    final line = _liveLine;
    final phase = _livePhase;
    final recorder = _recorder;
    if (session == null || line == null || phase == null || recorder == null) {
      return;
    }

    final odorBox = phase.isFixedLast ? phase.fixedOdorBox : _selectedOdorBox;
    if (odorBox == null) {
      _showMessage('Selecione a caixa do odor antes de registrar.');
      return;
    }

    final direction = phase.isSquare ? recorder.currentDirection : null;
    HapticFeedback.mediumImpact();
    setState(() {
      recorder.record(odorBox: odorBox, hit: hit, direction: direction);
      if (!phase.isFixedLast) _selectedOdorBox = null;
      _saving = true;
    });

    try {
      final actor = _resolveActor();
      if (recorder.criterionMet) {
        await _completePhaseAutomatically(
          session: session,
          line: line,
          phase: phase,
          recorder: recorder,
          handlerId: actor.ra,
          handlerName: actor.name,
        );
        return;
      }

      final updated = await _service.autosaveFormationProgress(
        session: session,
        phase: phase,
        recorder: recorder,
        handlerId: actor.ra,
        handlerName: actor.name,
      );
      if (!mounted) return;
      setState(() {
        _liveSession = updated;
        _saving = false;
      });
      if (!hit) {
        _showMessage('Erro registrado. Contador de consecutivas reiniciado.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('Falha ao salvar repetição: $e', error: true);
    }
  }

  Future<void> _finishLiveSession() async {
    final line = _liveLine;
    final phase = _livePhase;
    final session = _liveSession;
    final recorder = _recorder;
    final startedAt = _startedAt;
    if (line == null ||
        phase == null ||
        session == null ||
        recorder == null ||
        startedAt == null) {
      return;
    }
    if (recorder.totalReps == 0) {
      _showMessage('Registre ao menos uma repetição antes de salvar.');
      return;
    }

    setState(() => _saving = true);
    try {
      final actor = _resolveActor();
      await _service.endFormationWithoutCriterion(
        session: session,
        phase: phase,
        recorder: recorder,
        handlerId: actor.ra,
        handlerName: actor.name,
      );
      if (!mounted) return;
      final keepLineType = line.normalizedType;
      setState(() {
        _liveMode = false;
        _saving = false;
        _liveLine = null;
        _livePhase = null;
        _liveSession = null;
        _recorder = null;
        _startedAt = null;
        _selectedOdorBox = null;
        _completionDialogOpen = false;
      });
      _showMessage('Sessão encerrada sem conclusão de fase.');
      await _loadLines(keepLineType: keepLineType);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('Falha ao salvar sessão: $e', error: true);
    }
  }

  Future<void> _completePhaseAutomatically({
    required DetectionFormationSession session,
    required DetectionLine line,
    required DetectionPhaseConfig phase,
    required DetectionSessionRecorder recorder,
    required String handlerId,
    required String handlerName,
  }) async {
    if (!mounted) return;
    setState(() => _completionDialogOpen = true);

    try {
      final completed = await _service.completeFormationByCriterion(
        session: session,
        line: line,
        phase: phase,
        recorder: recorder,
        handlerId: handlerId,
        handlerName: handlerName,
      );
      if (!mounted) return;
      setState(() {
        _liveSession = completed;
        _saving = false;
      });

      await _showPhaseCompletedDialog(phase, recorder, completed);
      if (!mounted) return;

      final keepLineType = line.normalizedType;
      setState(() {
        _liveMode = false;
        _liveLine = null;
        _livePhase = null;
        _liveSession = null;
        _recorder = null;
        _startedAt = null;
        _selectedOdorBox = null;
        _completionDialogOpen = false;
      });
      await _loadLines(keepLineType: keepLineType);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _completionDialogOpen = false;
      });
      _showMessage('Falha ao concluir fase: $e', error: true);
    }
  }

  Future<void> _showPhaseCompletedDialog(
    DetectionPhaseConfig phase,
    DetectionSessionRecorder recorder,
    DetectionFormationSession completed,
  ) {
    final next = completed.advancedTo == null
        ? null
        : DetectionPhaseCatalog.byCode(completed.advancedTo);
    final summary = phase.isSquare
        ? '${recorder.clockwiseStreak} acertos no sentido horário e ${recorder.counterClockwiseStreak} no anti-horário.'
        : '${recorder.currentStreak} acertos consecutivos registrados.';
    final advancementText = completed.phaseAdvanced && next != null
        ? 'A linha foi avançada para a fase ${next.code}.'
        : 'A sessão foi encerrada pelo critério objetivo.';

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: _panel,
        title: Text(
          'Fase concluída',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          'Fase ${phase.code} concluída.\n$summary\n$advancementText',
          style: GoogleFonts.inter(color: _muted, height: 1.4),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(backgroundColor: _yellow),
            child: Text(
              'Concluir',
              style: GoogleFonts.inter(color: _bg, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _leaveLiveSession() async {
    final hasReps = (_recorder?.totalReps ?? 0) != 0;
    if (!hasReps) {
      setState(() {
        _liveMode = false;
        _liveLine = null;
        _livePhase = null;
        _liveSession = null;
        _recorder = null;
        _startedAt = null;
        _selectedOdorBox = null;
        _completionDialogOpen = false;
      });
      return;
    }

    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _panel,
        title: Text(
          'Sair da sessão?',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          'As repetições já registradas ficam salvas para retomada. Para encerrar a sessão sem concluir a fase, use o botão de encerramento.',
          style: GoogleFonts.inter(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continuar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );

    if (leave == true && mounted) {
      setState(() {
        _liveMode = false;
        _liveLine = null;
        _livePhase = null;
        _liveSession = null;
        _recorder = null;
        _startedAt = null;
        _selectedOdorBox = null;
        _completionDialogOpen = false;
      });
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? _red : _panelSoft,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  _Actor _resolveActor() {
    AuthViewModel? authVM;
    UserViewModel? userVM;
    ShiftViewModel? shiftVM;

    try {
      authVM = Provider.of<AuthViewModel>(context, listen: false);
    } catch (_) {}
    try {
      userVM = Provider.of<UserViewModel>(context, listen: false);
    } catch (_) {}
    try {
      shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    } catch (_) {}

    final ra =
        shiftVM?.handlerId ??
        HandlerIdentityService.raFromUser(authVM?.user) ??
        '';
    final name =
        userVM?.displayNameFor(
          ra: ra,
          firebaseUser: authVM?.user,
          fallback: 'Condutor',
        ) ??
        (ra.isEmpty ? 'Condutor' : 'RA $ra');

    return _Actor(ra: ra, name: name);
  }
}

class _Actor {
  final String ra;
  final String name;

  const _Actor({required this.ra, required this.name});
}

class _SquarePathPainter extends CustomPainter {
  final Color color;
  final bool clockwise;

  const _SquarePathPainter({required this.color, required this.clockwise});

  @override
  void paint(Canvas canvas, Size size) {
    final padding = size.shortestSide * 0.16;
    final rect = Rect.fromLTWH(
      padding,
      padding,
      size.width - padding * 2,
      size.height - padding * 2,
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
      paint,
    );

    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final arrow = Path();
    final top = Offset(size.width / 2, rect.top - 2);
    if (clockwise) {
      arrow
        ..moveTo(top.dx + 15, top.dy)
        ..lineTo(top.dx + 2, top.dy - 7)
        ..lineTo(top.dx + 2, top.dy + 7)
        ..close();
    } else {
      arrow
        ..moveTo(top.dx - 15, top.dy)
        ..lineTo(top.dx - 2, top.dy - 7)
        ..lineTo(top.dx - 2, top.dy + 7)
        ..close();
    }
    canvas.drawPath(arrow, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _SquarePathPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.clockwise != clockwise;
  }
}
