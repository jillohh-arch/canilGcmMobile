import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/core/widgets/binomio_header.dart';
import 'package:canil_gcm/features/training/presentation/widgets/update_command_stage_modal.dart';

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
  final String impulse;

  const _CapabilityData({required this.name, required this.state, required this.impulse});
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

  String _selectedImpulseFilter = 'Caça';

  int _largaStage = 3;
  int _atencaoStage = 1;

  final List<Map<String, dynamic>> _defesaMilestones = [
    {'title': 'Latido de alerta consistente', 'checked': true},
    {'title': 'Abordagem sem medo da vara', 'checked': true},
    {'title': 'Suportar pressão de ameaça física', 'checked': false},
    {'title': 'Mordida sob estresse moderado', 'checked': false},
    {'title': 'Transição imediata para caça (pagamento)', 'checked': false},
  ];

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

  final List<_CapabilityData> _capabilities = [
    const _CapabilityData(name: 'Material inicial', state: _CapabilityState.done, impulse: 'Caça'),
    const _CapabilityData(name: 'Mordida firme', state: _CapabilityState.done, impulse: 'Caça'),
    const _CapabilityData(name: 'Boca cheia', state: _CapabilityState.done, impulse: 'Caça'),
    const _CapabilityData(name: 'Estabilização', state: _CapabilityState.inProgress, impulse: 'Defesa'),
    const _CapabilityData(name: 'Manga jovem', state: _CapabilityState.done, impulse: 'Defesa'),
    const _CapabilityData(name: 'Manga adulta', state: _CapabilityState.inProgress, impulse: 'Defesa'),
    const _CapabilityData(name: 'Traje', state: _CapabilityState.notStarted, impulse: 'Agressão'),
    const _CapabilityData(name: 'Vara', state: _CapabilityState.notStarted, impulse: 'Agressão'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TrainingViewModel>(context, listen: false)
          .fetchTrainingsForDog(widget.dog.id);
    });
  }

  String _getCommandStatusLabel(int stage) {
    switch (stage) {
      case 1:
        return 'NÃO INICIADO';
      case 2:
        return 'INTRODUZIDO';
      case 3:
        return 'EM DESENVOLVIMENTO';
      case 4:
        return 'CONSOLIDADO';
      case 5:
        return 'OPERACIONAL';
      default:
        return 'NÃO INICIADO';
    }
  }

  Color _getCommandStatusColor(int stage) {
    switch (stage) {
      case 1:
        return AppTheme.textTertiary;
      case 2:
        return AppTheme.error;
      case 3:
        return AppTheme.warning;
      case 4:
        return AppTheme.warning;
      case 5:
        return AppTheme.success;
      default:
        return AppTheme.textTertiary;
    }
  }

  String _getCommandStatusIcon(int stage) {
    switch (stage) {
      case 1:
        return '○';
      case 2:
        return '●';
      case 3:
        return '◑';
      case 4:
        return '●';
      case 5:
        return '●';
      default:
        return '○';
    }
  }

  void _showUpdateCommandStageModal(String name, int currentStage, ValueChanged<int> onStageUpdated) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return UpdateCommandStageModal(
          commandName: name,
          currentStage: currentStage,
          onStageUpdated: onStageUpdated,
        );
      },
    );
  }

  void _showUpdateCapabilityModal(_CapabilityData capability) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0C1920),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(24),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Atualizar Estado da Capacidade',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Capacidade: "${capability.name}" (${capability.impulse})',
                style: GoogleFonts.inter(
                  color: const Color(0xFF4DD0E1),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              _buildCapabilityStateOption(
                context,
                capability,
                _CapabilityState.notStarted,
                '○ Não Iniciado',
                'Ainda não começou a treinar essa habilidade.',
                AppTheme.textTertiary,
              ),
              _buildCapabilityStateOption(
                context,
                capability,
                _CapabilityState.inProgress,
                '◔ Em Progresso',
                'O cão está desenvolvendo essa habilidade ativamente.',
                AppTheme.warning,
              ),
              _buildCapabilityStateOption(
                context,
                capability,
                _CapabilityState.done,
                '✓ Concluído',
                'Habilidade completamente assimilada pelo cão.',
                AppTheme.success,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCapabilityStateOption(
    BuildContext context,
    _CapabilityData capability,
    _CapabilityState state,
    String title,
    String desc,
    Color color,
  ) {
    final isSelected = capability.state == state;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          final idx = _capabilities.indexWhere((c) => c.name == capability.name && c.impulse == capability.impulse);
          if (idx != -1) {
            _capabilities[idx] = _CapabilityData(
              name: capability.name,
              state: state,
              impulse: capability.impulse,
            );
          }
        });
        Navigator.of(context).pop();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(20) : Colors.white.withAlpha(4),
          border: Border.all(
            color: isSelected ? color : Colors.white.withAlpha(12),
            width: isSelected ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: isSelected ? color : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
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
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: color, size: 20),
          ],
        ),
      ),
    );
  }

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
                child: _buildTabBodyContent(),
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
          Consumer<TrainingViewModel>(
            builder: (_, vm, __) {
              final sessions = vm.trainings
                  .where((t) => t.trainingType.toLowerCase().contains('guarda') ||
                      t.trainingType.toLowerCase().contains('proteção'))
                  .toList();
              return BinomioHeader(
                dog: widget.dog,
                subtitle: 'Iniciado · ${sessions.length} sessões',
                subtitleColor: AppTheme.warning,
                dogBorderColor: AppTheme.warning,
                conductorBorderColor: AppTheme.warning,
                showStatusDot: true,
                statusDotColor: AppTheme.warning,
                avatarSize: 44,
              );
            },
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

  Widget _buildTabBodyContent() {
    switch (_selectedTab) {
      case 0:
        return _buildTrilhasContent();
      case 1:
        return _buildImpulsoAtualContent();
      case 2:
        return _buildSessoesContent();
      case 3:
        return _buildEstatsContent();
      default:
        return _buildTrilhasContent();
    }
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
    final isSelected = _selectedImpulseFilter.toLowerCase() == impulse.name.toLowerCase();
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _selectedImpulseFilter = impulse.name;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? impulse.stateColor.withAlpha(20) : Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? impulse.stateColor.withAlpha(120) : Colors.white.withAlpha(20),
            width: isSelected ? 1.5 : 1.0,
          ),
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
      ),
    );
  }

  Widget _buildCapabilitiesSection() {
    final filteredCapabilities = _capabilities
        .where((cap) => cap.impulse.toLowerCase() == _selectedImpulseFilter.toLowerCase())
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel('CAPACIDADES TÉCNICAS'),
            const SizedBox(width: 6),
            Text(
              'na ${_selectedImpulseFilter.toLowerCase()}',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (filteredCapabilities.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'Nenhuma capacidade cadastrada para este impulso.',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: filteredCapabilities.map((cap) {
              final isDone = cap.state == _CapabilityState.done;
              final isInProgress = cap.state == _CapabilityState.inProgress;
              final color = isDone
                  ? AppTheme.success
                  : isInProgress
                      ? AppTheme.warning
                      : AppTheme.textTertiary;
              final icon = isDone ? '✓' : isInProgress ? '◔' : '○';

              return GestureDetector(
                onTap: () => _showUpdateCapabilityModal(cap),
                child: Container(
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
        _commandItem('Larga', 'Solta o equipamento sob comando', _largaStage, () {
          _showUpdateCommandStageModal('Larga', _largaStage, (newStage) {
            setState(() => _largaStage = newStage);
          });
        }),
        const SizedBox(height: 6),
        _commandItem('Atenção', 'Latir para o figurante', _atencaoStage, () {
          _showUpdateCommandStageModal('Atenção', _atencaoStage, (newStage) {
            setState(() => _atencaoStage = newStage);
          });
        }),
      ],
    );
  }

  Widget _commandItem(String name, String desc, int stage, VoidCallback onTap) {
    final status = _getCommandStatusLabel(stage);
    final color = _getCommandStatusColor(stage);
    final icon = _getCommandStatusIcon(stage);
    
    String bullets = '';
    for (int i = 0; i < 5; i++) {
      bullets += i < stage ? '●' : '○';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
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
                  Row(
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        bullets,
                        style: TextStyle(
                          color: color.withAlpha(180),
                          fontSize: 10,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
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
      ),
    );
  }

  Widget _buildImpulsoAtualContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('IMPULSO EM FOCO'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.warning.withAlpha(25),
                const Color(0xFF0C1920),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.warning.withAlpha(80), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.warning.withAlpha(10),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Text('🛡', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Defesa',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Fase Ativa · Em Abertura',
                          style: GoogleFonts.inter(
                            color: AppTheme.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '◔ 40%',
                      style: GoogleFonts.inter(
                        color: AppTheme.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white24),
              const SizedBox(height: 8),
              Text(
                'DIRETRIZES DO IMPULSO',
                style: GoogleFonts.inter(
                  color: AppTheme.warning,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'O impulso de defesa baseia-se no confronto direto e controlado com o cão. O foco principal é ensinar o cão a gerenciar o estresse de uma ameaça física e proteger o território/condutor. O pagamento emocional sempre deve retornar em caça para restabelecer o equilíbrio e a motivação do cão.',
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _sectionLabel('MARCOS PEDAGÓGICOS (CHECKLIST)'),
        const SizedBox(height: 10),
        ...List.generate(_defesaMilestones.length, (idx) {
          final item = _defesaMilestones[idx];
          final isChecked = item['checked'] as bool;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isChecked ? AppTheme.warning.withAlpha(40) : Colors.white.withAlpha(12),
              ),
            ),
            child: CheckboxListTile(
              value: isChecked,
              onChanged: (val) {
                HapticFeedback.lightImpact();
                setState(() {
                  _defesaMilestones[idx]['checked'] = val;
                });
              },
              title: Text(
                item['title'] as String,
                style: GoogleFonts.inter(
                  color: isChecked ? Colors.white : AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              activeColor: AppTheme.warning,
              checkColor: AppTheme.background,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSessoesContent() {
    return Consumer<TrainingViewModel>(
      builder: (context, vm, _) {
        final sessions = vm.trainings
            .where((t) =>
                t.trainingType.toLowerCase().contains('guarda') ||
                t.trainingType.toLowerCase().contains('proteção'))
            .toList();

        if (sessions.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40.0),
              child: Column(
                children: [
                  const Text('📭', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 12),
                  Text(
                    'Nenhuma sessão registrada para este cão.',
                    style: GoogleFonts.inter(
                      color: AppTheme.textTertiary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        sessions.sort((a, b) => b.date.compareTo(a.date));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _sectionLabel('HISTÓRICO COMPLETO'),
                Text(
                  '${sessions.length} sessões',
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...sessions.map((s) => _fullSessionCard(s)),
          ],
        );
      },
    );
  }

  Widget _fullSessionCard(TrainingSessionModel session) {
    final day =
        '${session.date.day.toString().padLeft(2, '0')}/${session.date.month.toString().padLeft(2, '0')}';
    final year = '${session.date.year}';
    final impulse = session.metadata?['impulse'] ?? 'Guarda & Proteção';
    final figurante = session.metadata?['figurante'] ?? 'Não especificado';
    final payment = session.metadata?['payment'] ?? 'SEM';
    final equipment = session.metadata?['equipment'] ?? '';
    final capabilities = session.metadata?['capabilities'] as List<dynamic>? ?? [];
    
    Color paymentColor = const Color(0xFF95A5A6);
    String paymentText = 'SEM PAGAMENTO';
    String paymentEmoji = '⊘';
    
    final pClean = payment.toString().toUpperCase();
    if (pClean.contains('CAÇA') || pClean.contains('CACA')) {
      paymentColor = const Color(0xFF2ECC71);
      paymentText = 'CAÇA';
      paymentEmoji = '🦌';
    } else if (pClean.contains('DEFESA')) {
      paymentColor = const Color(0xFFF1C40F);
      paymentText = 'DEFESA';
      paymentEmoji = '🛡';
    } else if (pClean.contains('AGRESSÃO') || pClean.contains('AGRESSAO')) {
      paymentColor = const Color(0xFFE74C3C);
      paymentText = 'AGRESSÃO';
      paymentEmoji = '⚔';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    day,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    year,
                    style: GoogleFonts.inter(
                      color: AppTheme.textTertiary,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      impulse,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Figurante: $figurante',
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: paymentColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: paymentColor.withAlpha(60), width: 1.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(paymentEmoji, style: const TextStyle(fontSize: 10)),
                    const SizedBox(width: 4),
                    Text(
                      paymentText,
                      style: GoogleFonts.inter(
                        color: paymentColor,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (equipment.isNotEmpty || capabilities.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (equipment.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '🎒 $equipment',
                      style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 9.5),
                    ),
                  ),
                ...capabilities.map((c) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.primary.withAlpha(30)),
                  ),
                  child: Text(
                    '✓ $c',
                    style: GoogleFonts.inter(color: AppTheme.primary, fontSize: 9.5, fontWeight: FontWeight.w500),
                  ),
                )),
              ],
            ),
          ],
          if (session.handlerNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              session.handlerNotes,
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEstatsContent() {
    return Consumer<TrainingViewModel>(
      builder: (context, vm, _) {
        final sessions = vm.trainings
            .where((t) =>
                t.trainingType.toLowerCase().contains('guarda') ||
                t.trainingType.toLowerCase().contains('proteção'))
            .toList();

        if (sessions.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40.0),
              child: Text(
                'Registre treinos para ver estatísticas.',
                style: GoogleFonts.inter(color: AppTheme.textTertiary, fontSize: 12),
              ),
            ),
          );
        }

        int cacaCount = 0;
        int defesaCount = 0;
        int agressaoCount = 0;

        int payCaca = 0;
        int payDefesa = 0;
        int payAgressao = 0;
        int paySem = 0;

        double sumScores = 0.0;
        int evalCount = 0;

        for (final s in sessions) {
          final imp = (s.metadata?['impulse'] ?? '').toString().toLowerCase();
          if (imp.contains('caça') || imp.contains('caca')) {
            cacaCount++;
          } else if (imp.contains('defesa')) {
            defesaCount++;
          } else if (imp.contains('agressão') || imp.contains('agressao')) {
            agressaoCount++;
          }

          final pay = (s.metadata?['payment'] ?? '').toString().toUpperCase();
          if (pay.contains('CAÇA') || pay.contains('CACA')) {
            payCaca++;
          } else if (pay.contains('DEFESA')) {
            payDefesa++;
          } else if (pay.contains('AGRESSÃO') || pay.contains('AGRESSAO')) {
            payAgressao++;
          } else {
            paySem++;
          }

          final evaluation = s.metadata?['evaluation'];
          if (evaluation is Map) {
            double sSum = 0;
            int sCount = 0;
            evaluation.forEach((k, v) {
              if (v is num) {
                sSum += v.toDouble();
                sCount++;
              }
            });
            if (sCount > 0) {
              sumScores += (sSum / sCount);
              evalCount++;
            }
          }
        }

        final totalImpulses = cacaCount + defesaCount + agressaoCount;
        final totalPayments = payCaca + payDefesa + payAgressao + paySem;
        final avgScore = evalCount > 0 ? (sumScores / evalCount) : 0.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('DISTRIBUIÇÃO DOS IMPULSOS'),
            const SizedBox(height: 12),
            _buildStatProgressBar(
              title: '🦌 Caça',
              count: cacaCount,
              total: totalImpulses,
              color: const Color(0xFF2ECC71),
            ),
            const SizedBox(height: 8),
            _buildStatProgressBar(
              title: '🛡 Defesa',
              count: defesaCount,
              total: totalImpulses,
              color: const Color(0xFFF1C40F),
            ),
            const SizedBox(height: 8),
            _buildStatProgressBar(
              title: '⚔ Agressão',
              count: agressaoCount,
              total: totalImpulses,
              color: const Color(0xFFE74C3C),
            ),
            const SizedBox(height: 24),
            _sectionLabel('PAGAMENTOS DA SESSÃO'),
            const SizedBox(height: 12),
            _buildStatProgressBar(
              title: '🦌 Caça Padrão',
              count: payCaca,
              total: totalPayments,
              color: const Color(0xFF2ECC71),
            ),
            const SizedBox(height: 8),
            _buildStatProgressBar(
              title: '🛡 Defesa',
              count: payDefesa,
              total: totalPayments,
              color: const Color(0xFFF1C40F),
            ),
            const SizedBox(height: 8),
            _buildStatProgressBar(
              title: '⚔ Agressão',
              count: payAgressao,
              total: totalPayments,
              color: const Color(0xFFE74C3C),
            ),
            const SizedBox(height: 8),
            _buildStatProgressBar(
              title: '⊘ Sem Pagamento',
              count: paySem,
              total: totalPayments,
              color: const Color(0xFF95A5A6),
            ),
            if (evalCount > 0) ...[
              const SizedBox(height: 24),
              _sectionLabel('DESEMPENHO MÉDIO'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withAlpha(12)),
                ),
                child: Row(
                  children: [
                    const Text('📈', style: TextStyle(fontSize: 24)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Avaliação Média do Figurante',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Calculado a partir de $evalCount avaliações.',
                            style: GoogleFonts.inter(
                              color: AppTheme.textTertiary,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _getRatingLabel(avgScore),
                          style: GoogleFonts.inter(
                            color: AppTheme.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${(avgScore + 1).toStringAsFixed(1)} / 4.0',
                          style: GoogleFonts.inter(
                            color: AppTheme.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _getRatingLabel(double score) {
    if (score >= 2.5) return 'Ótimo';
    if (score >= 1.5) return 'Bom';
    if (score >= 0.5) return 'Regular';
    return 'Ruim';
  }

  Widget _buildStatProgressBar({
    required String title,
    required int count,
    required int total,
    required Color color,
  }) {
    final pct = total > 0 ? (count / total) : 0.0;
    final pctString = (pct * 100).toStringAsFixed(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$count ($pctString%)',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.white.withAlpha(12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TrainingViewModel>(context, listen: false)
          .fetchTrainingsForDog(widget.dog.id);
    });
  }

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
          Consumer<TrainingViewModel>(
            builder: (_, vm, __) {
              final sessions = vm.trainings
                  .where((t) => t.trainingType.toLowerCase().contains('guarda') ||
                      t.trainingType.toLowerCase().contains('proteção'))
                  .toList();
              int? lastDays;
              if (sessions.isNotEmpty) {
                sessions.sort((a, b) => b.date.compareTo(a.date));
                lastDays = DateTime.now().difference(sessions.first.date).inDays;
              }
              return BinomioHeader(
                dog: widget.dog,
                subtitle: 'Operacional · ${sessions.length} sessões${lastDays != null ? ' · última há ${lastDays}d' : ''}',
                subtitleColor: AppTheme.success,
                dogBorderColor: AppTheme.success,
                conductorBorderColor: AppTheme.success,
                showStatusDot: true,
                statusDotColor: AppTheme.success,
                avatarSize: 44,
              );
            },
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

  static const _figuranteOptions = ['Fig. Souza', 'Fig. Oliveira', 'Fig. Lima'];

  void _showFiguranteSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0C1920),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(24),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Selecionar Figurante',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ..._figuranteOptions.map((fig) {
                return ListTile(
                  leading: const Text('👤', style: TextStyle(fontSize: 18)),
                  title: Text(
                    fig,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  trailing: _figuranteController.text == fig
                      ? const Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 20)
                      : null,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _figuranteController.text = fig;
                    });
                    Navigator.of(context).pop();
                  },
                );
              }),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Text('➕', style: TextStyle(fontSize: 16)),
                title: Text(
                  'Cadastrar outro figurante...',
                  style: GoogleFonts.inter(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _showCustomFiguranteDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCustomFiguranteDialog() {
    final controller = TextEditingController(text: _figuranteController.text);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0C1920),
          title: Text(
            'Novo Figurante',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Digite o nome do figurante',
              hintStyle: GoogleFonts.inter(color: AppTheme.textTertiary),
              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancelar', style: GoogleFonts.inter(color: AppTheme.textTertiary)),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  setState(() {
                    _figuranteController.text = controller.text.trim();
                  });
                }
                Navigator.of(context).pop();
              },
              child: Text('Confirmar', style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

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
          BinomioHeader(
            dog: widget.dog,
            subtitle: widget.isFormation ? 'FORMAÇÃO' : 'MANUTENÇÃO',
            subtitleColor: widget.isFormation ? AppTheme.warning : AppTheme.success,
            dogBorderColor: widget.isFormation ? AppTheme.warning : AppTheme.success,
            avatarSize: 38,
            withBackground: false,
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
            Color chipColor = AppTheme.primary;
            if (opt.contains('Caça')) {
              chipColor = const Color(0xFF2ECC71);
            } else if (opt.contains('Defesa')) {
              chipColor = const Color(0xFFF1C40F);
            } else if (opt.contains('Agressão')) {
              chipColor = const Color(0xFFE74C3C);
            } else {
              chipColor = const Color(0xFF95A5A6);
            }

            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _selectedImpulse = selected ? null : opt);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? chipColor.withAlpha(20) : Colors.white.withAlpha(8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? chipColor : Colors.white.withAlpha(25),
                    width: selected ? 1.5 : 1.0,
                  ),
                ),
                child: Text(
                  opt,
                  style: GoogleFonts.inter(
                    color: selected ? chipColor : AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildFiguranteField() {
    final isSelected = _figuranteController.text.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('FIGURANTE'),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _showFiguranteSelector,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? AppTheme.primary.withAlpha(60) : Colors.white.withAlpha(20),
              ),
            ),
            child: Row(
              children: [
                const Text('👤', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isSelected ? _figuranteController.text : 'Selecionar figurante...',
                    style: GoogleFonts.inter(
                      color: isSelected ? Colors.white : AppTheme.textTertiary,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textTertiary),
              ],
            ),
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
                    if (opt == 'Nenhum') {
                      _selectedCommands.clear();
                      _selectedCommands.add('Nenhum');
                    } else {
                      _selectedCommands.remove('Nenhum');
                      _selectedCommands.add(opt);
                    }
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
            color: _scenarioActive ? const Color(0xFFE74C3C).withAlpha(15) : Colors.white.withAlpha(8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _scenarioActive ? const Color(0xFFE74C3C).withAlpha(60) : Colors.white.withAlpha(20),
              width: _scenarioActive ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Text('🎬', style: TextStyle(fontSize: 16, color: _scenarioActive ? const Color(0xFFE74C3C) : AppTheme.textTertiary)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cenário simulado',
                  style: GoogleFonts.inter(
                    color: _scenarioActive ? const Color(0xFFE74C3C) : AppTheme.textPrimary,
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
                activeTrackColor: const Color(0xFFE74C3C).withAlpha(100),
                activeThumbColor: const Color(0xFFE74C3C),
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
                borderSide: BorderSide(color: const Color(0xFFE74C3C).withAlpha(40)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: const Color(0xFFE74C3C).withAlpha(40)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE74C3C)),
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
              const cyanColor = Color(0xFF4DD0E1);
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
                      color: selected ? cyanColor.withAlpha(25) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected ? cyanColor : Colors.white.withAlpha(15),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _evalLevels[i],
                        style: GoogleFonts.inter(
                          color: selected ? cyanColor : AppTheme.textTertiary,
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

            Color themedColor = color;
            if (label == 'CAÇA') {
              themedColor = const Color(0xFF2ECC71);
            } else if (label == 'DEFESA') {
              themedColor = const Color(0xFFF1C40F);
            } else if (label == 'AGRESSÃO') {
              themedColor = const Color(0xFFE74C3C);
            } else if (label == 'SEM') {
              themedColor = const Color(0xFF95A5A6);
            }

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
                    color: selected ? themedColor.withAlpha(20) : Colors.white.withAlpha(8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? themedColor : Colors.white.withAlpha(20),
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
                          color: selected ? themedColor : AppTheme.textTertiary,
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
