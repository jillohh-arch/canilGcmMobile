import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';

// ─── Data Models ─────────────────────────────────────────────────────────────

enum _ImpulseState { consolidated, opening, development, notStarted }

class _ImpulseData {
  final String name;
  final String emoji;
  final _ImpulseState state;
  final String contextText;
  final double progress;

  const _ImpulseData({
    required this.name,
    required this.emoji,
    required this.state,
    required this.contextText,
    required this.progress,
  });

  String get stateLabel {
    switch (state) {
      case _ImpulseState.consolidated:
        return 'Consolidada';
      case _ImpulseState.opening:
        return 'Em abertura';
      case _ImpulseState.development:
        return 'Em desenvolvimento';
      case _ImpulseState.notStarted:
        return 'Não iniciada';
    }
  }

  Color get stateColor {
    switch (state) {
      case _ImpulseState.consolidated:
        return AppTheme.success;
      case _ImpulseState.opening:
        return AppTheme.warning;
      case _ImpulseState.development:
        return AppTheme.warning;
      case _ImpulseState.notStarted:
        return AppTheme.textTertiary;
    }
  }

  String get badge {
    switch (state) {
      case _ImpulseState.consolidated:
        return '●';
      case _ImpulseState.opening:
        return '◔';
      case _ImpulseState.development:
        return '◑';
      case _ImpulseState.notStarted:
        return '○';
    }
  }
}

enum _CapabilityState { done, inProgress, notStarted }

class _CapabilityData {
  final String name;
  final _CapabilityState state;

  const _CapabilityData({required this.name, required this.state});
}

// ─── Main Screen ─────────────────────────────────────────────────────────────

class GuardProtectionScreen extends StatefulWidget {
  final Dog dog;

  const GuardProtectionScreen({super.key, required this.dog});

  @override
  State<GuardProtectionScreen> createState() => _GuardProtectionScreenState();
}

class _GuardProtectionScreenState extends State<GuardProtectionScreen> {
  bool get _isOperational {
    final specialties = widget.dog.specialties ?? [];
    return specialties.any(
      (s) => s.toLowerCase().contains('guarda') && !s.toLowerCase().contains('form'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _isOperational
        ? _MaintenanceView(dog: widget.dog)
        : _FormationView(dog: widget.dog);
  }
}

// ─── TELA A — FORMAÇÃO ───────────────────────────────────────────────────────

class _FormationView extends StatefulWidget {
  final Dog dog;
  const _FormationView({required this.dog});

  @override
  State<_FormationView> createState() => _FormationViewState();
}

class _FormationViewState extends State<_FormationView> {
  int _selectedTab = 0;
  static const _tabs = ['Trilhas', 'Impulso atual', 'Sessões', 'Estats'];

  static const _impulseTrails = [
    _ImpulseData(
      name: 'Caça',
      emoji: '🦌',
      state: _ImpulseState.consolidated,
      contextText: 'Equipamento se move e ativa o impulso · base emocional do trabalho',
      progress: 1.0,
    ),
    _ImpulseData(
      name: 'Defesa',
      emoji: '🛡',
      state: _ImpulseState.opening,
      contextText: 'Confronto direto com o cão · pagamento volta em caça pra equilibrar',
      progress: 0.4,
    ),
    _ImpulseData(
      name: 'Agressão',
      emoji: '⚔',
      state: _ImpulseState.notStarted,
      contextText: 'Cão como parceiro de luta · trabalha após defesa consolidada',
      progress: 0.0,
    ),
  ];

  static const _capabilities = [
    _CapabilityData(name: 'Material inicial', state: _CapabilityState.done),
    _CapabilityData(name: 'Mordida firme', state: _CapabilityState.done),
    _CapabilityData(name: 'Boca cheia', state: _CapabilityState.done),
    _CapabilityData(name: 'Estabilização', state: _CapabilityState.inProgress),
    _CapabilityData(name: 'Manga jovem', state: _CapabilityState.done),
    _CapabilityData(name: 'Manga adulta', state: _CapabilityState.inProgress),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabsRow(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                child: _buildTrilhasContent(),
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
          bottom: BorderSide(color: AppTheme.warning.withAlpha(40)),
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
                      'FORMAÇÃO · EM ANDAMENTO',
                      style: GoogleFonts.inter(
                        color: AppTheme.warning,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      'Guarda & Proteção',
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
                  color: AppTheme.warning.withAlpha(30),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Center(
                  child: Text('🛡', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDogStatusCard(AppTheme.warning),
        ],
      ),
    );
  }

  Widget _buildDogStatusCard(Color themeColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: themeColor.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: themeColor.withAlpha(50)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1A2A30),
              border: Border.all(color: themeColor, width: 2),
            ),
            child: ClipOval(
              child: widget.dog.profileImageUrl != null &&
                      widget.dog.profileImageUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: widget.dog.profileImageUrl!,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Center(
                        child: Text(
                          widget.dog.name.isNotEmpty ? widget.dog.name[0] : 'K',
                          style: GoogleFonts.inter(
                              color: themeColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Center(
                        child: Text(
                          widget.dog.name.isNotEmpty ? widget.dog.name[0] : 'K',
                          style: GoogleFonts.inter(
                              color: themeColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        widget.dog.name.isNotEmpty ? widget.dog.name[0] : 'K',
                        style: GoogleFonts.inter(
                            color: themeColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.dog.name,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.dog.breed,
                      style: GoogleFonts.inter(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                Consumer<TrainingViewModel>(
                  builder: (_, vm, __) {
                    final sessions = vm.trainings
                        .where((t) => t.trainingType.toLowerCase().contains('guarda') ||
                            t.trainingType.toLowerCase().contains('proteção'))
                        .toList();
                    final count = sessions.length;
                    return Text(
                      'Iniciado em 03/2024 · $count sessões',
                      style: GoogleFonts.inter(
                        color: AppTheme.textTertiary,
                        fontSize: 10,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final selected = _selectedTab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _selectedTab = i);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                margin: EdgeInsets.only(left: i > 0 ? 4 : 0),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.primary.withAlpha(20)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? AppTheme.primary.withAlpha(60)
                        : Colors.white.withAlpha(15),
                  ),
                ),
                child: Center(
                  child: Text(
                    _tabs[i],
                    style: GoogleFonts.inter(
                      color: selected ? AppTheme.primary : AppTheme.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTrilhasContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildImpulseTrailsSection(),
        const SizedBox(height: 20),
        _buildCapabilitiesSection(),
        const SizedBox(height: 20),
        _buildCommandsSection(),
        const SizedBox(height: 20),
        _buildRecentSessionsSection(),
      ],
    );
  }

  Widget _buildImpulseTrailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('JORNADA DOS IMPULSOS'),
        const SizedBox(height: 10),
        ..._impulseTrails.map((impulse) => _impulseTrailCard(impulse)),
      ],
    );
  }

  Widget _impulseTrailCard(_ImpulseData impulse) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: impulse.stateColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(impulse.emoji, style: const TextStyle(fontSize: 14)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  impulse.name,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                impulse.stateLabel,
                style: GoogleFonts.inter(
                  color: impulse.stateColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                impulse.badge,
                style: TextStyle(
                  color: impulse.stateColor,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: impulse.progress,
              minHeight: 4,
              backgroundColor: Colors.white.withAlpha(15),
              valueColor: AlwaysStoppedAnimation(impulse.stateColor),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            impulse.contextText,
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilitiesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel('CAPACIDADES TÉCNICAS'),
            const SizedBox(width: 6),
            Text(
              'na caça',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _capabilities.map((cap) {
            final isDone = cap.state == _CapabilityState.done;
            final isInProgress = cap.state == _CapabilityState.inProgress;
            final color = isDone
                ? AppTheme.success
                : isInProgress
                    ? AppTheme.warning
                    : AppTheme.textTertiary;
            final icon = isDone ? '✓' : isInProgress ? '◔' : '○';

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withAlpha(40)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    icon,
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    cap.name,
                    style: GoogleFonts.inter(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCommandsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('COMANDOS DA ESPECIALIDADE'),
        const SizedBox(height: 10),
        _commandItem('◑', 'Larga', 'Solta o equipamento sob comando',
            'EM DESENVOLVIMENTO', AppTheme.warning),
        const SizedBox(height: 6),
        _commandItem('○', 'Atenção', 'Latir para o figurante',
            'NÃO INICIADO', AppTheme.textTertiary),
      ],
    );
  }

  Widget _commandItem(
      String icon, String name, String desc, String status, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Row(
        children: [
          Text(icon, style: TextStyle(color: color, fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  desc,
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              status,
              style: GoogleFonts.inter(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSessionsSection() {
    return Consumer<TrainingViewModel>(
      builder: (_, vm, __) {
        final recent = vm.trainings
            .where((t) =>
                t.trainingType.toLowerCase().contains('guarda') ||
                t.trainingType.toLowerCase().contains('proteção'))
            .take(3)
            .toList();

        if (recent.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('SESSÕES RECENTES'),
            const SizedBox(height: 10),
            ...recent.map((s) => _recentSessionCard(s)),
          ],
        );
      },
    );
  }

  Widget _recentSessionCard(TrainingSessionModel session) {
    final day =
        '${session.date.day.toString().padLeft(2, '0')}/${session.date.month.toString().padLeft(2, '0')}';
    final impulse = session.metadata?['impulse'] ?? '';
    final figurante = session.metadata?['figurante'] ?? '';

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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  impulse.isNotEmpty ? impulse : 'Guarda & Proteção',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (figurante.isNotEmpty)
                  Text(
                    'Figurante: $figurante',
                    style: GoogleFonts.inter(
                      color: AppTheme.textTertiary,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _SessionFormScreen(
                    dog: widget.dog,
                    isFormation: true,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.background,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '▶ NOVA SESSÃO DE FORMAÇÃO',
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

  Widget _sectionLabel(String text) {
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

// ─── TELA B — MANUTENÇÃO ─────────────────────────────────────────────────────

class _MaintenanceView extends StatefulWidget {
  final Dog dog;
  const _MaintenanceView({required this.dog});

  @override
  State<_MaintenanceView> createState() => _MaintenanceViewState();
}

class _MaintenanceViewState extends State<_MaintenanceView> {
  final _focusController = TextEditingController();

  static const _focusSuggestions = [
    'Mordida calma',
    'Larga melhor',
    'Atenção firme',
    'Rotina',
  ];

  static const _impulseTrailsMaintenance = [
    _ImpulseData(
      name: 'Caça',
      emoji: '🦌',
      state: _ImpulseState.consolidated,
      contextText: 'Base emocional consolidada · pagamento principal',
      progress: 1.0,
    ),
    _ImpulseData(
      name: 'Defesa',
      emoji: '🛡',
      state: _ImpulseState.consolidated,
      contextText: 'Confronto direto consolidado · equilíbrio mantido',
      progress: 1.0,
    ),
    _ImpulseData(
      name: 'Agressão',
      emoji: '⚔',
      state: _ImpulseState.consolidated,
      contextText: 'Parceiro de luta · trabalho completo',
      progress: 1.0,
    ),
  ];

  @override
  void dispose() {
    _focusController.dispose();
    super.dispose();
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
                    _buildFocusCard(),
                    const SizedBox(height: 20),
                    _buildImpulsesSection(),
                    const SizedBox(height: 20),
                    _buildRecentSessions(),
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
          bottom: BorderSide(color: AppTheme.success.withAlpha(40)),
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
                      'MANUTENÇÃO OPERACIONAL',
                      style: GoogleFonts.inter(
                        color: AppTheme.success,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      'Guarda & Proteção',
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
                  color: AppTheme.success.withAlpha(30),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Center(
                  child: Text('🛡', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDogStatusCard(),
        ],
      ),
    );
  }

  Widget _buildDogStatusCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.success.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.success.withAlpha(50)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1A2A30),
              border: Border.all(color: AppTheme.success, width: 2),
            ),
            child: ClipOval(
              child: widget.dog.profileImageUrl != null &&
                      widget.dog.profileImageUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: widget.dog.profileImageUrl!,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Center(
                        child: Text(
                          widget.dog.name.isNotEmpty ? widget.dog.name[0] : 'K',
                          style: GoogleFonts.inter(
                              color: AppTheme.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Center(
                        child: Text(
                          widget.dog.name.isNotEmpty ? widget.dog.name[0] : 'K',
                          style: GoogleFonts.inter(
                              color: AppTheme.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        widget.dog.name.isNotEmpty ? widget.dog.name[0] : 'K',
                        style: GoogleFonts.inter(
                            color: AppTheme.success,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Consumer<TrainingViewModel>(
              builder: (_, vm, __) {
                final sessions = vm.trainings
                    .where((t) =>
                        t.trainingType.toLowerCase().contains('guarda') ||
                        t.trainingType.toLowerCase().contains('proteção'))
                    .toList();
                final count = sessions.length;
                int? lastDays;
                if (sessions.isNotEmpty) {
                  sessions.sort((a, b) => b.date.compareTo(a.date));
                  lastDays = DateTime.now()
                      .difference(sessions.first.date)
                      .inDays;
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.dog.name,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Operacional há ${widget.dog.age > 2 ? widget.dog.age - 2 : 1} anos · $count sessões${lastDays != null ? ' · última há ${lastDays}d' : ''}',
                      style: GoogleFonts.inter(
                        color: AppTheme.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withAlpha(20),
            AppTheme.success.withAlpha(10),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🎯 FOCO DESTA SESSÃO',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _focusController,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'O que você quer aprimorar?',
              hintStyle: GoogleFonts.inter(color: AppTheme.textTertiary),
              filled: true,
              fillColor: Colors.black.withAlpha(65),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.primary.withAlpha(65)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppTheme.primary.withAlpha(65)),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _focusSuggestions.map((s) {
              return GestureDetector(
                onTap: () {
                  _focusController.text = s;
                  setState(() {});
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.primary.withAlpha(65)),
                  ),
                  child: Text(
                    s,
                    style: GoogleFonts.inter(
                      color: AppTheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildImpulsesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'IMPULSOS · ${widget.dog.name.toUpperCase()}',
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        ..._impulseTrailsMaintenance.map((impulse) => _impulseCard(impulse)),
      ],
    );
  }

  Widget _impulseCard(_ImpulseData impulse) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: impulse.stateColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child:
                      Text(impulse.emoji, style: const TextStyle(fontSize: 14)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  impulse.name,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                impulse.stateLabel,
                style: GoogleFonts.inter(
                  color: impulse.stateColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                impulse.badge,
                style: TextStyle(color: impulse.stateColor, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: impulse.progress,
              minHeight: 4,
              backgroundColor: Colors.white.withAlpha(15),
              valueColor: AlwaysStoppedAnimation(impulse.stateColor),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            impulse.contextText,
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSessions() {
    return Consumer<TrainingViewModel>(
      builder: (_, vm, __) {
        final recent = vm.trainings
            .where((t) =>
                t.trainingType.toLowerCase().contains('guarda') ||
                t.trainingType.toLowerCase().contains('proteção'))
            .take(3)
            .toList();

        if (recent.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MANUTENÇÕES RECENTES',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            ...recent.map((s) => _recentCard(s)),
          ],
        );
      },
    );
  }

  Widget _recentCard(TrainingSessionModel session) {
    final day =
        '${session.date.day.toString().padLeft(2, '0')}/${session.date.month.toString().padLeft(2, '0')}';
    final impulse = session.metadata?['impulse'] ?? '';
    final figurante = session.metadata?['figurante'] ?? '';

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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  impulse.isNotEmpty ? impulse : 'Manutenção',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (figurante.isNotEmpty)
                  Text(
                    'Figurante: $figurante',
                    style: GoogleFonts.inter(
                      color: AppTheme.textTertiary,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _SessionFormScreen(
                    dog: widget.dog,
                    isFormation: false,
                    initialFocus: _focusController.text.trim(),
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.background,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '▶ INICIAR MANUTENÇÃO',
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
}

// ─── TELA C — NOVA SESSÃO (Formulário) ──────────────────────────────────────

class _SessionFormScreen extends StatefulWidget {
  final Dog dog;
  final bool isFormation;
  final String? initialFocus;

  const _SessionFormScreen({
    required this.dog,
    required this.isFormation,
    this.initialFocus,
  });

  @override
  State<_SessionFormScreen> createState() => _SessionFormScreenState();
}

class _SessionFormScreenState extends State<_SessionFormScreen> {
  final _figuranteController = TextEditingController();
  final _scenarioDescController = TextEditingController();
  final _observacoesController = TextEditingController();

  // Impulso trabalhado
  static const _impulseOptions = ['🦌 Caça', '🛡 Defesa', '⚔ Agressão', 'Mista'];
  String? _selectedImpulse;

  // Equipamento
  static const _equipmentOptions = [
    'Material filhote',
    'Manga jovem',
    'Manga adulta',
    'Traje',
    'Vara',
  ];
  String? _selectedEquipment;

  // Capacidades (multi-select)
  static const _capabilityOptions = [
    'Mordida firme',
    'Boca cheia',
    'Estabilização',
    'Mordida calma',
    'Pressão sustentada',
  ];
  final Set<String> _selectedCapabilities = {};

  // Comandos (multi-select)
  static const _commandOptions = ['Larga', 'Atenção', 'Nenhum'];
  final Set<String> _selectedCommands = {};

  // Cenário simulado
  bool _scenarioActive = false;

  // Comportamento
  static const _behaviorOptions = ['Hesitante', 'Equilibrado', 'Firme', 'Exagerado'];
  String? _selectedBehavior;

  // Avaliação (4 critérios x 4 níveis)
  static const _evalCriteria = [
    'Drive (intensidade)',
    'Mordida (qualidade técnica)',
    'Controle (resposta a comandos)',
    'Equilíbrio emocional',
  ];
  static const _evalLevels = ['Ruim', 'Regular', 'Bom', 'Ótimo'];
  final Map<String, int> _evalScores = {};

  // Pagamento
  static const _paymentOptions = [
    ('🦌', 'CAÇA', AppTheme.success),
    ('🛡', 'DEFESA', AppTheme.warning),
    ('⚔', 'AGRESSÃO', AppTheme.error),
    ('⊘', 'SEM', AppTheme.textTertiary),
  ];
  String? _selectedPayment;

  @override
  void dispose() {
    _figuranteController.dispose();
    _scenarioDescController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> _saveSession() async {
    if (_selectedImpulse == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione o impulso trabalhado'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final metadata = <String, dynamic>{
      'specialty': 'guarda_protecao',
      'mode': widget.isFormation ? 'formacao' : 'manutencao',
      'impulse': _selectedImpulse,
      'figurante': _figuranteController.text.trim(),
      'equipment': _selectedEquipment,
      'capabilities': _selectedCapabilities.toList(),
      'commands': _selectedCommands.toList(),
      'scenarioActive': _scenarioActive,
      if (_scenarioActive)
        'scenarioDescription': _scenarioDescController.text.trim(),
      'behavior': _selectedBehavior,
      'evaluation': _evalScores,
      'payment': _selectedPayment,
      'observations': _observacoesController.text.trim(),
      if (widget.initialFocus != null && widget.initialFocus!.isNotEmpty)
        'focus': widget.initialFocus,
    };

    final session = TrainingSessionModel(
      dogId: widget.dog.id,
      dogName: widget.dog.name,
      date: DateTime.now(),
      trainingType: 'Guarda & Proteção',
      location: '',
      weather: '',
      handlerNotes: _observacoesController.text.trim(),
      metadata: metadata,
    );

    try {
      final vm = Provider.of<TrainingViewModel>(context, listen: false);
      await vm.addTrainingSession(session);
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Sessão de guarda & proteção salva!'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e'), backgroundColor: AppTheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = widget.isFormation ? AppTheme.warning : AppTheme.success;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildFormHeader(themeColor),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImpulseField(),
                    const SizedBox(height: 16),
                    _buildFiguranteField(),
                    const SizedBox(height: 16),
                    _buildEquipmentField(),
                    const SizedBox(height: 16),
                    _buildCapabilitiesField(),
                    const SizedBox(height: 16),
                    _buildCommandsField(),
                    const SizedBox(height: 16),
                    _buildScenarioField(),
                    const SizedBox(height: 16),
                    _buildBehaviorField(),
                    const SizedBox(height: 16),
                    _buildEvaluationField(),
                    const SizedBox(height: 16),
                    _buildPaymentField(),
                    const SizedBox(height: 16),
                    _buildObservationsField(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: _buildSaveCTA(),
    );
  }

  Widget _buildFormHeader(Color themeColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: themeColor.withAlpha(40)),
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
                      'NOVA SESSÃO · GUARDA & PROTEÇÃO',
                      style: GoogleFonts.inter(
                        color: themeColor,
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
                  color: themeColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Center(
                  child: Text('🛡', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: themeColor.withAlpha(15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: themeColor.withAlpha(40)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1A2A30),
                    border: Border.all(color: themeColor, width: 1.5),
                  ),
                  child: ClipOval(
                    child: widget.dog.profileImageUrl != null &&
                            widget.dog.profileImageUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.dog.profileImageUrl!,
                            width: 28,
                            height: 28,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Center(
                              child: Text(
                                widget.dog.name.isNotEmpty
                                    ? widget.dog.name[0]
                                    : 'K',
                                style: GoogleFonts.inter(
                                    color: themeColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Center(
                              child: Text(
                                widget.dog.name.isNotEmpty
                                    ? widget.dog.name[0]
                                    : 'K',
                                style: GoogleFonts.inter(
                                    color: themeColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              widget.dog.name.isNotEmpty
                                  ? widget.dog.name[0]
                                  : 'K',
                              style: GoogleFonts.inter(
                                  color: themeColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.dog.name,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '· ${TimeOfDay.now().format(context)}',
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImpulseField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('IMPULSO TRABALHADO'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _impulseOptions.map((opt) {
            final selected = _selectedImpulse == opt;
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _selectedImpulse = selected ? null : opt);
              },
              child: _chip(opt, selected),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFiguranteField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('FIGURANTE'),
        const SizedBox(height: 8),
        TextField(
          controller: _figuranteController,
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Text('👤', style: const TextStyle(fontSize: 16)),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
            hintText: 'Nome do figurante',
            hintStyle: GoogleFonts.inter(color: AppTheme.textTertiary),
            filled: true,
            fillColor: Colors.white.withAlpha(8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withAlpha(20)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withAlpha(20)),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildEquipmentField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('EQUIPAMENTO'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _equipmentOptions.map((opt) {
            final selected = _selectedEquipment == opt;
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _selectedEquipment = selected ? null : opt);
              },
              child: _chip(opt, selected),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCapabilitiesField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('CAPACIDADES TRABALHADAS'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _capabilityOptions.map((opt) {
            final selected = _selectedCapabilities.contains(opt);
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  if (selected) {
                    _selectedCapabilities.remove(opt);
                  } else {
                    _selectedCapabilities.add(opt);
                  }
                });
              },
              child: _chip(opt, selected),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCommandsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('COMANDOS TRABALHADOS'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _commandOptions.map((opt) {
            final selected = _selectedCommands.contains(opt);
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  if (selected) {
                    _selectedCommands.remove(opt);
                  } else {
                    _selectedCommands.add(opt);
                  }
                });
              },
              child: _chip(opt, selected),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildScenarioField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('CENÁRIO'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withAlpha(20)),
          ),
          child: Row(
            children: [
              const Text('🎬', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cenário simulado',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Switch(
                value: _scenarioActive,
                onChanged: (v) {
                  HapticFeedback.lightImpact();
                  setState(() => _scenarioActive = v);
                },
                activeTrackColor: AppTheme.primary,
                activeThumbColor: AppTheme.primary,
                inactiveThumbColor: AppTheme.textTertiary,
                inactiveTrackColor: Colors.white.withAlpha(15),
              ),
            ],
          ),
        ),
        if (_scenarioActive) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _scenarioDescController,
            maxLines: 2,
            style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Descreva o cenário simulado...',
              hintStyle: GoogleFonts.inter(color: AppTheme.textTertiary),
              filled: true,
              fillColor: Colors.white.withAlpha(8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withAlpha(20)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withAlpha(20)),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBehaviorField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('COMPORTAMENTO DO CÃO'),
        const SizedBox(height: 8),
        Row(
          children: List.generate(_behaviorOptions.length, (i) {
            final opt = _behaviorOptions[i];
            final selected = _selectedBehavior == opt;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedBehavior = selected ? null : opt);
                },
                child: Container(
                  margin: EdgeInsets.only(left: i > 0 ? 6 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.primary.withAlpha(20)
                        : Colors.white.withAlpha(8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? AppTheme.primary.withAlpha(60)
                          : Colors.white.withAlpha(20),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      opt,
                      style: GoogleFonts.inter(
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.textTertiary,
                        fontSize: 10,
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

  Widget _buildEvaluationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _fieldLabel('AVALIAÇÃO DA SESSÃO'),
            const SizedBox(width: 6),
            Text(
              'pelo figurante',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ..._evalCriteria.map((criterion) => _evalRow(criterion)),
      ],
    );
  }

  Widget _evalRow(String criterion) {
    final currentScore = _evalScores[criterion];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            criterion,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(_evalLevels.length, (i) {
              final selected = currentScore == i;
              final color = i == 0
                  ? AppTheme.error
                  : i == 1
                      ? AppTheme.warning
                      : i == 2
                          ? AppTheme.primary
                          : AppTheme.success;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _evalScores[criterion] = i);
                  },
                  child: Container(
                    margin: EdgeInsets.only(left: i > 0 ? 4 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? color.withAlpha(25) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected ? color : Colors.white.withAlpha(15),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _evalLevels[i],
                        style: GoogleFonts.inter(
                          color: selected ? color : AppTheme.textTertiary,
                          fontSize: 9,
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
      ),
    );
  }

  Widget _buildPaymentField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('PAGAMENTO DA SESSÃO'),
        const SizedBox(height: 4),
        Text(
          'Onde a sessão terminou emocionalmente · imensa maioria das vezes em caça',
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(_paymentOptions.length, (i) {
            final (emoji, label, color) = _paymentOptions[i];
            final selected = _selectedPayment == label;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedPayment = selected ? null : label);
                },
                child: Container(
                  margin: EdgeInsets.only(left: i > 0 ? 6 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? color.withAlpha(20) : Colors.white.withAlpha(8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? color : Colors.white.withAlpha(20),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          color: selected ? color : AppTheme.textTertiary,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildObservationsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _fieldLabel('OBSERVAÇÕES DO FIGURANTE'),
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
          controller: _observacoesController,
          maxLines: 3,
          style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Notas do figurante sobre a sessão...',
            hintStyle: GoogleFonts.inter(color: AppTheme.textTertiary),
            filled: true,
            fillColor: Colors.white.withAlpha(8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withAlpha(20)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withAlpha(20)),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveCTA() {
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

  // --- Helpers ---

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: AppTheme.textTertiary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _chip(String label, bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected
            ? AppTheme.primary.withAlpha(20)
            : Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AppTheme.primary.withAlpha(60) : Colors.white.withAlpha(25),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: selected ? AppTheme.primary : AppTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
