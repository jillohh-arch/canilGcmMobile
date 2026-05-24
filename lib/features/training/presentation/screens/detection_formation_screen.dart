import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';

class DetectionFormationScreen extends StatefulWidget {
  final Dog dog;

  const DetectionFormationScreen({super.key, required this.dog});

  @override
  State<DetectionFormationScreen> createState() => _DetectionFormationScreenState();
}

class _DetectionFormationScreenState extends State<DetectionFormationScreen> {
  bool _showLiveSession = false;

  // Overview states
  int _drugsPhase = 3;
  int _drugsConsecutiveHits = 7;
  int _weaponsPhase = 2;
  int _weaponsConsecutiveHits = 1;
  bool _corpseStarted = false;

  // Live session states
  int _currentAttempt = 5;
  String _selectedBoxPos = 'MEIO';
  List<bool> _attemptHistory = [true, true, false, true]; // true = Hit, false = Miss
  int _liveDrugsHits = 9; // 9/10
  int _liveWeaponsHits = 2; // 2/3

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050D10),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: const Color(0xFF050D10),
        ),
        child: SafeArea(
          child: _showLiveSession ? _buildLiveSession() : _buildOverview(),
        ),
      ),
    );
  }

  // ====== TELA A: VISÃO GERAL DE DETECÇÃO ======
  Widget _buildOverview() {
    return Column(
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
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ESPECIALIDADE',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF4DD0E1),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Detecção',
                      style: GoogleFonts.inter(
                        color: Colors.white,
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
                  color: const Color(0x1F4DD0E1),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: const Text('👃', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              // Dog Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0x0A4DD0E1),
                  border: Border.all(color: const Color(0x334DD0E1)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1A2A30),
                        border: Border.all(color: const Color(0xFF4DD0E1), width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        widget.dog.name.toUpperCase().substring(0, math.min(widget.dog.name.length, 4)),
                        style: GoogleFonts.inter(
                          color: const Color(0xFF4DD0E1),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.dog.name,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Conduzido por GCM Silva',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF4DD0E1),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Multi-session active shortcut card
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  setState(() {
                    _showLiveSession = true;
                    _currentAttempt = 5;
                    _liveDrugsHits = 9;
                    _liveWeaponsHits = 2;
                    _attemptHistory = [true, true, false, true];
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0x1AF1C40F), Color(0x0AE74C3C)],
                    ),
                    border: Border.all(color: const Color(0x4DF1C40F)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0x26F1C40F),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        alignment: Alignment.center,
                        child: const Text('⚡', style: TextStyle(fontSize: 16)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sessão multi-linha disponível',
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'Drogas + Armas em formação ativa — pode treinar junto',
                              style: GoogleFonts.inter(color: const Color(0xFFB0C4CC), fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      const Text(
                        '▶',
                        style: TextStyle(color: Color(0xFFF1C40F), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Section label
              Row(
                children: [
                  Text(
                    'LINHAS DE DETECÇÃO',
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
                      color: Color(0x264DD0E1),
                      thickness: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Card: Drogas (F3)
              _buildLineCard(
                emoji: '💊',
                title: 'Drogas',
                status: 'Em formação · Fase $_drugsPhase',
                tags: ['maconha', 'cocaína', 'crack', 'LSD', 'ecstasy', '+ outros'],
                phaseNum: _drugsPhase,
                phaseHits: _drugsConsecutiveHits,
                phaseGoal: 10,
                sessionsLabel: '42 sessões · última: hoje',
                color: const Color(0xFFF1C40F),
                onTap: () {
                  setState(() {
                    _showLiveSession = true;
                    _currentAttempt = 1;
                    _liveDrugsHits = _drugsConsecutiveHits;
                    _attemptHistory = [];
                  });
                },
              ),

              // Card: Armas (F2)
              _buildLineCard(
                emoji: '🔫',
                title: 'Armas',
                status: 'Em formação · Fase $_weaponsPhase',
                tags: ['pólvora', 'munição', '+ derivados'],
                phaseNum: _weaponsPhase,
                phaseHits: _weaponsConsecutiveHits,
                phaseGoal: 3,
                sessionsLabel: '28 sessões · última: hoje',
                color: const Color(0xFFF1C40F),
                onTap: () {
                  setState(() {
                    _showLiveSession = true;
                    _currentAttempt = 1;
                    _liveWeaponsHits = _weaponsConsecutiveHits;
                    _attemptHistory = [];
                  });
                },
              ),

              // Card: Cadáver (Não Iniciada)
              _buildLineCard(
                emoji: '🕯',
                title: 'Cadáver',
                status: _corpseStarted ? 'Em formação · Fase 1' : 'Não iniciada',
                tags: [],
                phaseNum: _corpseStarted ? 1 : 0,
                phaseHits: 0,
                phaseGoal: 10,
                sessionsLabel: _corpseStarted ? '0 sessões' : 'Especialidade não iniciada com ${widget.dog.name}',
                color: _corpseStarted ? const Color(0xFFF1C40F) : const Color(0xFF95A5A6),
                showBtn: !_corpseStarted,
                onBtnTap: () {
                  setState(() {
                    _corpseStarted = true;
                  });
                },
                onTap: _corpseStarted ? () {
                  setState(() {
                    _showLiveSession = true;
                    _currentAttempt = 1;
                    _attemptHistory = [];
                  });
                } : null,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLineCard({
    required String emoji,
    required String title,
    required String status,
    required List<String> tags,
    required int phaseNum,
    required int phaseHits,
    required int phaseGoal,
    required String sessionsLabel,
    required Color color,
    bool showBtn = false,
    VoidCallback? onBtnTap,
    VoidCallback? onTap,
  }) {
    final isNotStarted = phaseNum == 0;
    final sideColor = isNotStarted ? const Color(0x4D95A5A6) : color;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isNotStarted ? const Color(0x06FFFFFF) : const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border(
            left: BorderSide(color: sideColor, width: 3),
            top: const BorderSide(color: Color(0x14FFFFFF)),
            right: const BorderSide(color: Color(0x14FFFFFF)),
            bottom: const BorderSide(color: Color(0x14FFFFFF)),
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isNotStarted ? const Color(0x1495A5A6) : const Color(0x1FF1C40F),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        status,
                        style: GoogleFonts.inter(
                          color: isNotStarted ? const Color(0xFF95A5A6) : const Color(0xFFF1C40F),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showBtn) ...[
                  ElevatedButton(
                    onPressed: onBtnTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0x144DD0E1),
                      foregroundColor: const Color(0xFF4DD0E1),
                      elevation: 0,
                      side: const BorderSide(color: Color(0x4D4DD0E1)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '+ Iniciar',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: tags.map((t) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x0DFFFFFF),
                    border: Border.all(color: const Color(0x0AFFFFFF)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    t,
                    style: GoogleFonts.inter(color: const Color(0xFFB0C4CC), fontSize: 9, fontWeight: FontWeight.w500),
                  ),
                )).toList(),
              ),
            ],
            if (!isNotStarted) ...[
              const SizedBox(height: 12),
              // Progress Section
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Protocolo Ragonha · Fase $phaseNum de 5',
                        style: GoogleFonts.inter(color: const Color(0xFFB0C4CC), fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '$phaseHits / $phaseGoal',
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: List.generate(5, (index) {
                      final phaseIndex = index + 1;
                      Widget segment;
                      if (phaseIndex < phaseNum) {
                        // Done phases
                        segment = Expanded(
                          child: Container(
                            height: 6,
                            margin: EdgeInsets.only(right: index == 4 ? 0 : 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1C40F),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        );
                      } else if (phaseIndex == phaseNum) {
                        // Active phase (partial progress based on hits)
                        final ratio = phaseHits / phaseGoal;
                        segment = Expanded(
                          child: Container(
                            height: 6,
                            margin: EdgeInsets.only(right: index == 4 ? 0 : 2),
                            decoration: BoxDecoration(
                              color: const Color(0x1FFFFFFF),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: ratio.clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1C40F),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        );
                      } else {
                        // Locked phases
                        segment = Expanded(
                          child: Container(
                            height: 6,
                            margin: EdgeInsets.only(right: index == 4 ? 0 : 2),
                            decoration: BoxDecoration(
                              color: const Color(0x0DFFFFFF),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        );
                      }
                      return segment;
                    }),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0x0DFFFFFF))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    sessionsLabel,
                    style: GoogleFonts.inter(color: const Color(0xFF7A8A92), fontSize: 10),
                  ),
                  if (!showBtn) ...[
                    Text(
                      'Continuar →',
                      style: GoogleFonts.inter(color: const Color(0xFF4DD0E1), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ====== TELA C: SESSÃO MULTI-LINHA AO VIVO ======
  Widget _buildLiveSession() {
    return Column(
      children: [
        // Live Top Bar
        Container(
          color: const Color(0x14F1C40F),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0x33F1C40F))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1C40F),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SESSÃO EM ANDAMENTO',
                    style: GoogleFonts.inter(
                      color: const Color(0xFFF1C40F),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              Text(
                '${widget.dog.name} · GCM Silva',
                style: GoogleFonts.inter(
                  color: const Color(0xFFB0C4CC),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),

        // Multi-line banner
        Container(
          width: double.infinity,
          color: const Color(0x0FF1C40F),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0x26F1C40F))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LINHAS SENDO TRABALHADAS NESTA SESSÃO',
                style: GoogleFonts.inter(
                  color: const Color(0xFFF1C40F),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _buildSubstanceChip('💊 Drogas · F3'),
                  const SizedBox(width: 6),
                  _buildSubstanceChip('🔫 Armas · F2'),
                ],
              ),
            ],
          ),
        ),

        // Live interactive content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Attempt Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0x0D4DD0E1),
                  border: Border.all(color: const Color(0x4D4DD0E1)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TENTATIVA $_currentAttempt',
                          style: GoogleFonts.inter(color: const Color(0xFF4DD0E1), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0),
                        ),
                        Text(
                          'de até 15 nesta sessão',
                          style: GoogleFonts.inter(color: const Color(0xFF5A7280), fontSize: 10),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Posicionar caixa de odor',
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 14),

                    // Position Selector
                    Column(
                      children: [
                        Text(
                          'ONDE A CAIXA COM ODOR ESTÁ?',
                          style: GoogleFonts.inter(color: const Color(0xFFF1C40F), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.0),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildPosBtn('ESQ', '◧'),
                            const SizedBox(width: 8),
                            _buildPosBtn('MEIO', '◨'),
                            const SizedBox(width: 8),
                            _buildPosBtn('DIR', '▣'),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Hit / Miss triggers
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _registerAttempt(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2ECC71),
                              foregroundColor: const Color(0xFF050D10),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Column(
                              children: [
                                const Text('✓', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(
                                  'ACERTO',
                                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _registerAttempt(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFE74C3C),
                              side: const BorderSide(color: Color(0xFFE74C3C), width: 1.5),
                              backgroundColor: const Color(0x26E74C3C),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Column(
                              children: [
                                const Text('✗', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(
                                  'ERRO',
                                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Progress counters per line
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PROGRESSO POR LINHA · CONSECUTIVOS HISTÓRICOS',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF4DD0E1),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Line Counter 1: Drugs (F3)
                  _buildLiveCounterCard(
                    emoji: '💊',
                    name: 'Drogas',
                    subtext: 'Fase 3 · critério 10/10',
                    hits: _liveDrugsHits,
                    goal: 10,
                    alert: _liveDrugsHits == 9 ? '⚠ 1 PARA AVANÇAR!' : null,
                    isCritical: _liveDrugsHits == 9,
                  ),

                  // Line Counter 2: Weapons (F2)
                  _buildLiveCounterCard(
                    emoji: '🔫',
                    name: 'Armas',
                    subtext: 'Fase 2 · critério 3/3',
                    hits: _liveWeaponsHits,
                    goal: 3,
                    alert: _liveWeaponsHits == 2 ? '⚠ 1 PARA AVANÇAR!' : null,
                    isCritical: _liveWeaponsHits == 2,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Session History list
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HISTÓRICO DE TENTATIVAS DESTA SESSÃO',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF4DD0E1),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: List.generate(_attemptHistory.length, (index) {
                      final isHit = _attemptHistory[index];
                      return Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isHit ? const Color(0x1F2ECC71) : const Color(0x1FE74C3C),
                          border: Border.all(
                            color: isHit ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'T${index + 1}',
                              style: GoogleFonts.inter(color: isHit ? const Color(0x992ECC71) : const Color(0x99E74C3C), fontSize: 7, fontWeight: FontWeight.w700),
                            ),
                            Text(
                              isHit ? '✓' : '✗',
                              style: TextStyle(color: isHit ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // End Buttons row
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _showLiveSession = false;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF1C40F),
                      side: const BorderSide(color: Color(0x4DF1C40F)),
                      backgroundColor: const Color(0x14F1C40F),
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      'PAUSAR',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _endLiveSession,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0x26E74C3C),
                        foregroundColor: const Color(0xFFE74C3C),
                        side: const BorderSide(color: Color(0xFFE74C3C), width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        'ENCERRAR SESSÃO',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5),
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

  Widget _buildSubstanceChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x1FF1C40F),
        border: Border.all(color: const Color(0x4DF1C40F)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: const Color(0xFFF1C40F),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPosBtn(String label, String icon) {
    final isActive = _selectedBoxPos == label;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            _selectedBoxPos = label;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? const Color(0x1FF1C40F) : const Color(0x0DFFFFFF),
            border: Border.all(
              color: isActive ? const Color(0xFFF1C40F) : const Color(0x1AFFFFFF),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Column(
            children: [
              Text(
                icon,
                style: TextStyle(
                  color: isActive ? const Color(0xFFF1C40F) : const Color(0xFF7A8A92),
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: isActive ? const Color(0xFFF1C40F) : const Color(0xFF7A8A92),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveCounterCard({
    required String emoji,
    required String name,
    required String subtext,
    required int hits,
    required int goal,
    String? alert,
    required bool isCritical,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCritical ? const Color(0x0F2ECC71) : const Color(0x0DFFFFFF),
        border: Border.all(
          color: isCritical ? const Color(0x4D2ECC71) : const Color(0x14FFFFFF),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0x1FF1C40F),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 1),
                Text(
                  subtext,
                  style: GoogleFonts.inter(color: const Color(0xFF7A8A92), fontSize: 9),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              RichText(
                text: TextSpan(
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                  children: [
                    TextSpan(
                      text: '$hits',
                      style: TextStyle(color: isCritical ? const Color(0xFF2ECC71) : const Color(0xFFF1C40F)),
                    ),
                    const TextSpan(text: ' / '),
                    TextSpan(text: '$goal', style: const TextStyle(color: Color(0xFF7A8A92))),
                  ],
                ),
              ),
              if (alert != null) ...[
                Text(
                  alert,
                  style: GoogleFonts.inter(color: const Color(0xFF2ECC71), fontSize: 9, fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _registerAttempt(bool isHit) {
    HapticFeedback.mediumImpact();
    setState(() {
      _attemptHistory.add(isHit);
      _currentAttempt++;

      // In a real session, we can advance hits on consecutive successes
      if (isHit) {
        // Increase hits count
        if (_liveDrugsHits < 10) {
          _liveDrugsHits++;
          if (_liveDrugsHits == 10) {
            // Drugs phase passed! Show dialog later, promote to next phase in session
            _drugsPhase = 4;
            _drugsConsecutiveHits = 0;
            _showPromotionDialog('Drogas', 4);
          }
        }
        if (_liveWeaponsHits < 3) {
          _liveWeaponsHits++;
          if (_liveWeaponsHits == 3) {
            _weaponsPhase = 3;
            _weaponsConsecutiveHits = 0;
            _showPromotionDialog('Armas', 3);
          }
        }
      } else {
        // Error resets consecutive count! (Protocolo Ragonha criterion)
        _liveDrugsHits = 0;
        _liveWeaponsHits = 0;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro registrado! Contador de acertos consecutivos reiniciado.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _showPromotionDialog(String line, int nextPhase) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0C1920),
        title: Row(
          children: const [
            Text('🎉 ', style: TextStyle(fontSize: 20)),
            Text(
              'Avanço de Fase!',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Excelente desempenho! O K9 atingiu a meta de acertos consecutivos na linha de $line e avançou para a Fase $nextPhase do Protocolo Ragonha.',
          style: GoogleFonts.inter(color: const Color(0xFFB0C4CC)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4DD0E1)),
            child: Text(
              'Confirmar',
              style: GoogleFonts.inter(color: const Color(0xFF050D10), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _endLiveSession() {
    HapticFeedback.heavyImpact();
    // Update local overview stats with current session state
    setState(() {
      _drugsConsecutiveHits = _liveDrugsHits;
      _weaponsConsecutiveHits = _liveWeaponsHits;
      _showLiveSession = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sessão encerrada e progresso salvo com sucesso!')),
    );
  }
}
