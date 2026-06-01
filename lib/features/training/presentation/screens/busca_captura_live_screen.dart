import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';

enum LiveSessionState { preTrail, running, summary }

class MapEvent {
  final Offset position;
  final String type;
  final Color color;
  final String label;
  final String time;
  final int distance;

  MapEvent({
    required this.position,
    required this.type,
    required this.color,
    required this.label,
    required this.time,
    required this.distance,
  });
}

class BuscaCapturaLiveScreen extends StatefulWidget {
  final Dog dog;
  final String scenario;
  final int distanceGoal;

  const BuscaCapturaLiveScreen({
    super.key,
    required this.dog,
    required this.scenario,
    required this.distanceGoal,
  });

  @override
  State<BuscaCapturaLiveScreen> createState() => _BuscaCapturaLiveScreenState();
}

class _BuscaCapturaLiveScreenState extends State<BuscaCapturaLiveScreen> {
  LiveSessionState _sessionState = LiveSessionState.preTrail;

  // Run stats
  int _seconds = 0;
  int _distance = 0; // meters
  Timer? _timer;
  List<Offset> _trailPoints = [];
  List<MapEvent> _events = [];

  // Random walk parameters
  double _currentX = 0;
  double _currentY = 0;
  double _angle = 0;

  // Summary state
  String _finalResult = 'Completa';
  final TextEditingController _summaryNotesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _angle = math.Random().nextDouble() * 2 * math.pi;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _summaryNotesController.dispose();
    super.dispose();
  }

  void _startSession() {
    HapticFeedback.heavyImpact();
    setState(() {
      _sessionState = LiveSessionState.running;
      _seconds = 0;
      _distance = 0;
      _trailPoints = [const Offset(150, 150)];
      _currentX = 150;
      _currentY = 150;
      _events = [];
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _seconds++;
        // Simulate distance: 2 to 4 meters per second
        _distance += 2 + math.Random().nextInt(3);

        // Simulate path random walk
        _angle +=
            (math.Random().nextDouble() - 0.5) *
            0.5; // slight directional change
        double step = 3.0 + math.Random().nextDouble() * 3.0;
        _currentX += math.cos(_angle) * step;
        _currentY += math.sin(_angle) * step;

        // Keep inside boundary simulator
        if (_currentX < 20 || _currentX > 320) _angle = math.pi - _angle;
        if (_currentY < 20 || _currentY > 260) _angle = -_angle;

        _trailPoints.add(Offset(_currentX, _currentY));
      });
    });
  }

  void _logEvent(String type, String label, Color color) {
    HapticFeedback.mediumImpact();
    final minutes = (_seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_seconds % 60).toString().padLeft(2, '0');
    final timeStr = '$minutes:$secs';

    setState(() {
      _events.add(
        MapEvent(
          position: Offset(_currentX, _currentY),
          type: type,
          color: color,
          label: label,
          time: timeStr,
          distance: _distance,
        ),
      );
    });
  }

  void _stopSession(bool success) {
    HapticFeedback.heavyImpact();
    _timer?.cancel();
    if (success) {
      _logEvent('LOCALIZAÇÃO', 'Alvo localizado', AppTheme.success);
      _finalResult = 'Completa';
    } else {
      _finalResult = 'Checagem';
    }
    setState(() {
      _sessionState = LiveSessionState.summary;
    });
  }

  String _formatDuration(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: AppTheme.transparent,
          systemNavigationBarColor: AppTheme.background,
        ),
        child: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    switch (_sessionState) {
      case LiveSessionState.preTrail:
        return _buildPreTrail();
      case LiveSessionState.running:
        return _buildRunning();
      case LiveSessionState.summary:
        return _buildSummary();
    }
  }

  // ====== ESTADO 1: PRÉ-TRILHA ======
  Widget _buildPreTrail() {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.centerLeft,
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: AppTheme.textPrimary,
                        size: 20,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PREPARAÇÃO DE RASTRO',
                          style: GoogleFonts.inter(
                            color: AppTheme.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Busca & Captura',
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
                      color: AppTheme.primary.withAlpha(31),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: const Text('📡', style: TextStyle(fontSize: 18)),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // System Status Checklist
                    Text(
                      'STATUS DE SENSORES E SINAIS',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.textPrimary.withAlpha(13),
                        border: Border.all(
                          color: AppTheme.textPrimary.withAlpha(20),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _buildSystemRow(
                            'Sinal de GPS',
                            'Precisão de 3 metros (Excelente)',
                            'OK',
                            AppTheme.success,
                            true,
                          ),
                          _buildSystemRow(
                            'Bateria do Celular',
                            '74% restante',
                            'OK',
                            AppTheme.success,
                            true,
                          ),
                          _buildSystemRow(
                            'Armazenamento Local',
                            '18.4 GB livres',
                            'OK',
                            AppTheme.success,
                            true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Configuration overview
                    Text(
                      'CONFIGURAÇÕES DEFINIDAS',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.textPrimary.withAlpha(13),
                        border: Border.all(
                          color: AppTheme.textPrimary.withAlpha(20),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _buildConfigOverviewRow(
                            'Cenário ativo',
                            widget.scenario,
                          ),
                          _buildConfigOverviewRow(
                            'Objetivo de distância',
                            '${widget.distanceGoal}m',
                          ),
                          _buildConfigOverviewRow('Cão', widget.dog.name),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Battery warning
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withAlpha(15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border(
                          left: BorderSide(color: AppTheme.warning, width: 3),
                        ),
                      ),
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.inter(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                            height: 1.5,
                          ),
                          children: const [
                            TextSpan(
                              text:
                                  'Importante: O rastreamento contínuo utiliza o GPS em segundo plano. ',
                            ),
                            TextSpan(
                              text:
                                  'Certifique-se de que a bateria é suficiente.',
                              style: TextStyle(
                                color: AppTheme.warning,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        // Big green start button
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [AppTheme.background, AppTheme.background.withAlpha(0)],
              ),
            ),
            child: ElevatedButton(
              onPressed: _startSession,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: AppTheme.background,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 4,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.navigation_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'INICIAR TRILHA GPS',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSystemRow(
    String title,
    String desc,
    String badge,
    Color badgeColor,
    bool ok,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: badgeColor.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              ok
                  ? Icons.check_circle_outline_rounded
                  : Icons.warning_amber_rounded,
              color: badgeColor,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  desc,
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              badge,
              style: GoogleFonts.inter(
                color: badgeColor,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigOverviewRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.textPrimary.withAlpha(10)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ====== ESTADO 2: DURANTE A TRILHA (LIVE TRACKER) ======
  Widget _buildRunning() {
    return Column(
      children: [
        // Live status top bar
        Container(
          color: AppTheme.success.withAlpha(20), // rgba(46, 204, 113, 0.08)
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppTheme.success.withAlpha(51)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppTheme.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'GRAVANDO RASTRO GPS',
                    style: GoogleFonts.inter(
                      color: AppTheme.success,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              Text(
                'Binômio: ${widget.dog.name}',
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // Map and Metrics area
        Expanded(
          child: Stack(
            children: [
              // Simulated map (Grid + Line Draw)
              Positioned.fill(
                child: Container(
                  color: AppTheme.surfacePanelAlt,
                  child: CustomPaint(
                    painter: LiveMapPainter(
                      points: _trailPoints,
                      events: _events,
                    ),
                  ),
                ),
              ),

              // Metrics Overlay Card
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.background.withAlpha(250),
                    border: Border.all(color: AppTheme.primary.withAlpha(51)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  'DISTÂNCIA',
                                  style: GoogleFonts.inter(
                                    color: AppTheme.textMuted,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      '$_distance',
                                      style: GoogleFonts.inter(
                                        color: AppTheme.textPrimary,
                                        fontSize: 26,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      'm',
                                      style: GoogleFonts.inter(
                                        color: AppTheme.primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 35,
                            color: AppTheme.primary.withAlpha(38),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  'DURAÇÃO',
                                  style: GoogleFonts.inter(
                                    color: AppTheme.textMuted,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      _formatDuration(_seconds),
                                      style: GoogleFonts.inter(
                                        color: AppTheme.textPrimary,
                                        fontSize: 26,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      'min',
                                      style: GoogleFonts.inter(
                                        color: AppTheme.primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.only(top: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: AppTheme.primary.withAlpha(31),
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            RichText(
                              text: TextSpan(
                                style: GoogleFonts.inter(
                                  color: AppTheme.textSecondary,
                                  fontSize: 10,
                                ),
                                children: [
                                  const TextSpan(text: 'Precisão: '),
                                  TextSpan(
                                    text: '3.1m',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            RichText(
                              text: TextSpan(
                                style: GoogleFonts.inter(
                                  color: AppTheme.textSecondary,
                                  fontSize: 10,
                                ),
                                children: [
                                  const TextSpan(text: 'Velocidade: '),
                                  TextSpan(
                                    text: '3.6 km/h',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Marker Actions Panel
        Container(
          color: AppTheme.background.withAlpha(250),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            children: [
              Text(
                'REGISTRAR MARCAÇÃO OPERACIONAL',
                style: GoogleFonts.inter(
                  color: AppTheme.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildMarkBtn(
                      emoji: '🎯',
                      label: 'Indicação',
                      color: AppTheme.primary,
                      onTap: () => _logEvent(
                        'INDICAÇÃO',
                        'Indicação positiva',
                        AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMarkBtn(
                      emoji: '⚠️',
                      label: 'Checagem',
                      color: AppTheme.warning,
                      onTap: () => _logEvent(
                        'CHECAGEM',
                        'Checagem de rastro',
                        AppTheme.warning,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMarkBtn(
                      emoji: '❌',
                      label: 'Perda',
                      color: AppTheme.attention,
                      onTap: () => _logEvent(
                        'PERDA',
                        'Perda de rastro',
                        AppTheme.attention,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Stop / Target Found buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _stopSession(false),
                      icon: const Icon(
                        Icons.stop_rounded,
                        color: AppTheme.error,
                        size: 16,
                      ),
                      label: Text(
                        'PARAR SESSÃO',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.error,
                        side: BorderSide(color: AppTheme.error, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _stopSession(true),
                      icon: const Icon(Icons.check_circle_rounded, size: 16),
                      label: Text(
                        'ALVO LOCALIZADO',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        foregroundColor: AppTheme.background,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMarkBtn({
    required String emoji,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.textPrimary.withAlpha(10),
          border: Border.all(color: AppTheme.textPrimary.withAlpha(26)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ====== ESTADO 3: RESUMO DA TRILHA ======
  Widget _buildSummary() {
    return Stack(
      children: [
        Column(
          children: [
            // Summary Header
            Container(
              color: AppTheme.success.withAlpha(15),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppTheme.success.withAlpha(51)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.success.withAlpha(51),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.check_rounded,
                      color: AppTheme.success,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SESSÃO CONCLUÍDA',
                          style: GoogleFonts.inter(
                            color: AppTheme.success,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Resumo da trilha de B&C',
                          style: GoogleFonts.inter(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Scroll content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Simulated Static Map Box
                    Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: AppTheme.surfacePanelAlt,
                        border: Border.all(
                          color: AppTheme.primary.withAlpha(51),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CustomPaint(
                          painter: LiveMapPainter(
                            points: _trailPoints,
                            events: _events,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Big numbers metrics grid
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.textPrimary.withAlpha(13),
                              border: Border.all(
                                color: AppTheme.textPrimary.withAlpha(20),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Column(
                              children: [
                                Text(
                                  'DISTÂNCIA',
                                  style: GoogleFonts.inter(
                                    color: AppTheme.textMuted,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_distance}m',
                                  style: GoogleFonts.inter(
                                    color: AppTheme.primary,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.textPrimary.withAlpha(13),
                              border: Border.all(
                                color: AppTheme.textPrimary.withAlpha(20),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Column(
                              children: [
                                Text(
                                  'DURAÇÃO',
                                  style: GoogleFonts.inter(
                                    color: AppTheme.textMuted,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDuration(_seconds),
                                  style: GoogleFonts.inter(
                                    color: AppTheme.primary,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Events list
                    Text(
                      'EVENTOS REGISTRADOS',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_events.isEmpty)
                      Text(
                        'Nenhum evento registrado.',
                        style: GoogleFonts.inter(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      )
                    else
                      ..._events.map((ev) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.textPrimary.withAlpha(13),
                            border: Border.all(
                              color: AppTheme.textPrimary.withAlpha(10),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Text(
                                ev.time,
                                style: GoogleFonts.inter(
                                  color: AppTheme.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: ev.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  ev.label,
                                  style: GoogleFonts.inter(
                                    color: AppTheme.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                '${ev.distance}m',
                                style: GoogleFonts.inter(
                                  color: AppTheme.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 20),

                    // Result rating
                    Text(
                      'RESULTADO DA SESSÃO',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: ['Completa', 'Checagem', 'Perda'].map((res) {
                        final isSelected = _finalResult == res;
                        Color selectCol = AppTheme.success;
                        if (res == 'Checagem') selectCol = AppTheme.warning;
                        if (res == 'Perda') selectCol = AppTheme.attention;

                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                _finalResult = res;
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? selectCol.withAlpha(20)
                                    : AppTheme.textPrimary.withAlpha(13),
                                border: Border.all(
                                  color: isSelected
                                      ? selectCol
                                      : AppTheme.textPrimary.withAlpha(20),
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                res.toUpperCase(),
                                style: GoogleFonts.inter(
                                  color: isSelected
                                      ? selectCol
                                      : AppTheme.textTertiary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Observations field
                    Text(
                      'OBSERVAÇÕES ADICIONAIS',
                      style: GoogleFonts.inter(
                        color: AppTheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _summaryNotesController,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                      ),
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Digite aqui observações adicionais...',
                        hintStyle: GoogleFonts.inter(color: AppTheme.textMuted),
                        filled: true,
                        fillColor: AppTheme.textPrimary.withAlpha(13),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: AppTheme.textPrimary.withAlpha(20),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.primary),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        // Save Bottom bar
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [AppTheme.background, AppTheme.background.withAlpha(0)],
              ),
            ),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).pop();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textTertiary,
                    side: BorderSide(color: AppTheme.textPrimary.withAlpha(26)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 20,
                    ),
                  ),
                  child: Text(
                    'Descartar',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      // Show success snackbar
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sessão de rastro salva com sucesso!'),
                        ),
                      );
                      // Pop back twice (first pops live, second pops maintenance/formation to go back to training hub)
                      Navigator.of(context).pop();
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: AppTheme.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'SALVAR REGISTRO',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// Custom Painter for path drawing on Map Grid
class LiveMapPainter extends CustomPainter {
  final List<Offset> points;
  final List<MapEvent> events;

  LiveMapPainter({required this.points, required this.events});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw map grid lines
    final gridPaint = Paint()
      ..color = AppTheme.primary.withAlpha(13)
      ..strokeWidth = 1.0;

    const double gridSize = 30.0;
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (points.isEmpty) return;

    // Draw trail line
    final trailPaint = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, trailPaint);

    // Draw start marker
    final startPaint = Paint()..color = AppTheme.warning;
    canvas.drawCircle(points.first, 8.0, startPaint);

    // Draw event markers
    for (final ev in events) {
      final evPaint = Paint()..color = ev.color;
      canvas.drawCircle(ev.position, 8.0, evPaint);
    }

    // Draw current location marker
    final currentPaint = Paint()
      ..color = AppTheme.success
      ..style = PaintingStyle.fill;
    final currentOutline = Paint()
      ..color = AppTheme.textPrimary
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(points.last, 6.0, currentPaint);
    canvas.drawCircle(points.last, 6.0, currentOutline);
  }

  @override
  bool shouldRepaint(covariant LiveMapPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.events != events;
  }
}
