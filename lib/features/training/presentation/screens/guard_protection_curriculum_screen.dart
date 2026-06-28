import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/binomio_header.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/data/training_program_service.dart';
import 'package:canil_gcm/features/training/data/training_promotion_service.dart';
import 'package:canil_gcm/features/training/data/training_service.dart';
import 'package:canil_gcm/features/training/domain/training_model.dart';
import 'package:canil_gcm/features/training/domain/training_program.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';

class GuardProtectionCurriculumScreen extends StatefulWidget {
  final Dog dog;

  const GuardProtectionCurriculumScreen({super.key, required this.dog});

  @override
  State<GuardProtectionCurriculumScreen> createState() =>
      _GuardProtectionCurriculumScreenState();
}

class _GuardProtectionCurriculumScreenState
    extends State<GuardProtectionCurriculumScreen> {
  static const _modality = 'guarda_protecao';
  static const _tabs = ['Roadmap', 'Módulo atual', 'Histórico', 'Estats'];

  final _programService = TrainingProgramService();
  final _promotionService = TrainingPromotionService();
  final _trainingService = TrainingService();

  StreamSubscription<TrainingProgram?>? _programSub;
  StreamSubscription<TrainingProgress>? _progressSub;
  StreamSubscription<List<TrainingHubSession>>? _sessionsSub;

  TrainingProgram? _program;
  TrainingProgress _progress = TrainingProgress.initial(_modality);
  List<TrainingHubSession> _sessions = const [];

  bool _programLoading = true;
  bool _progressLoading = true;
  bool _sessionsLoading = true;
  bool _initializingProgress = false;
  bool _isInstructorK9 = false;
  bool _requestingPromotion = false;
  int _modeIndex = 0;
  int _tabIndex = 0;

  final Set<String> _savingMilestoneIds = <String>{};

  @override
  void initState() {
    super.initState();
    _subscribeProgram();
    _subscribeProgress();
    _subscribeSessions();
    unawaited(_loadInstructorState());
  }

  @override
  void dispose() {
    unawaited(_programSub?.cancel());
    unawaited(_progressSub?.cancel());
    unawaited(_sessionsSub?.cancel());
    super.dispose();
  }

  void _subscribeProgram() {
    _programSub = _programService
        .watchProgram(_modality)
        .listen(
          (program) {
            if (!mounted) return;
            setState(() {
              _program = program;
              _programLoading = false;
            });
            _maybeEnsureProgressInitialized();
          },
          onError: (error) {
            if (!mounted) return;
            setState(() => _programLoading = false);
            _showSnackBar(
              'Falha ao carregar currículo de G&P. $error',
              AppTheme.error,
            );
          },
        );
  }

  void _subscribeProgress() {
    _progressSub = _programService
        .watchProgress(widget.dog.id, _modality)
        .listen(
          (progress) {
            if (!mounted) return;
            setState(() {
              _progress = progress;
              _progressLoading = false;
              if (progress.isOperational) {
                _modeIndex = 1;
              } else if (_modeIndex == 1) {
                _modeIndex = 0;
              }
            });
            _maybeEnsureProgressInitialized();
          },
          onError: (error) {
            if (!mounted) return;
            setState(() => _progressLoading = false);
            _showSnackBar(
              'Falha ao carregar progressão de G&P. $error',
              AppTheme.error,
            );
          },
        );
  }

  void _subscribeSessions() {
    _sessionsSub = _trainingService
        .watchSessionsForDog(widget.dog.id)
        .listen(
          (sessions) {
            if (!mounted) return;
            final filtered = sessions.where(_isGuardProtectionSession).toList()
              ..sort((a, b) => b.date.compareTo(a.date));
            setState(() {
              _sessions = filtered;
              _sessionsLoading = false;
            });
          },
          onError: (error) {
            if (!mounted) return;
            setState(() => _sessionsLoading = false);
            _showSnackBar(
              'Falha ao carregar sessões de G&P. $error',
              AppTheme.error,
            );
          },
        );
  }

  Future<void> _loadInstructorState() async {
    try {
      final isInstructor = await _promotionService.currentUserIsInstructorK9();
      if (!mounted) return;
      setState(() => _isInstructorK9 = isInstructor);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isInstructorK9 = false);
    }
  }

  void _maybeEnsureProgressInitialized() {
    if (_programLoading || _progressLoading) return;
    unawaited(_ensureProgressInitializedIfNeeded());
  }

  Future<void> _ensureProgressInitializedIfNeeded() async {
    final program = _program;
    if (_initializingProgress ||
        _progress.exists ||
        program == null ||
        program.activeModules.isEmpty) {
      return;
    }

    setState(() => _initializingProgress = true);
    try {
      await _programService.ensureProgressInitialized(
        dogId: widget.dog.id,
        program: program,
      );
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(
        'Falha ao inicializar progressão de G&P. $error',
        AppTheme.error,
      );
    } finally {
      if (mounted) setState(() => _initializingProgress = false);
    }
  }

  bool _isGuardProtectionSession(TrainingHubSession session) {
    final metadata = session.metadata;
    final parts = [
      session.trainingType,
      session.specialty,
      session.subtype,
      metadata['modality'],
      metadata['specialty'],
      metadata['type'],
    ].whereType<Object>().join(' ');
    final normalized = _normalize(parts);
    return normalized.contains('guarda') ||
        normalized.contains('protecao') ||
        normalized.contains('protec');
  }

  List<TrainingModule> get _modules =>
      _program?.activeModules ?? const <TrainingModule>[];

  TrainingModule? get _currentModule {
    final modules = _modules;
    if (modules.isEmpty) return null;
    final currentId = _progress.currentModuleId ?? modules.first.id;
    for (final module in modules) {
      if (module.id == currentId) return module;
    }
    return modules.first;
  }

  int _achievedCount(TrainingModule module) {
    return module.activeMilestones
        .where(
          (milestone) => _progress.isMilestoneAchieved(module.id, milestone.id),
        )
        .length;
  }

  int _pendingRequiredCount(TrainingModule module) {
    return module.activeMilestones
        .where(
          (milestone) =>
              milestone.isRequired &&
              !_progress.isMilestoneAchieved(module.id, milestone.id),
        )
        .length;
  }

  bool _isCompleted(TrainingModule module) {
    return _progress.completedModuleIds.contains(module.id) ||
        _progress.completedModule(module.id) != null;
  }

  bool _isLocked(TrainingModule module) {
    if (_progress.isOperational || _isCompleted(module)) return false;
    return module.id != _currentModule?.id;
  }

  Future<void> _toggleMilestone(
    TrainingModule module,
    TrainingMilestone milestone,
    bool achieved,
  ) async {
    final program = _program;
    if (program == null || _isLocked(module)) return;
    HapticFeedback.selectionClick();
    setState(() => _savingMilestoneIds.add(milestone.id));
    try {
      await _programService.setMilestoneAchievement(
        dogId: widget.dog.id,
        program: program,
        module: module,
        milestone: milestone,
        achieved: achieved,
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Não foi possível salvar o marco.');
    } finally {
      if (mounted) setState(() => _savingMilestoneIds.remove(milestone.id));
    }
  }

  Future<void> _requestPromotion(TrainingModule module) async {
    final program = _program;
    if (program == null || _requestingPromotion) return;

    final pendingRequired = _pendingRequiredCount(module);
    if (pendingRequired > 0) {
      _showSnackBar(
        'Ainda há $pendingRequired marco(s) obrigatório(s) pendente(s).',
        AppTheme.warning,
      );
      return;
    }

    final requesterRa = _resolveRequesterRa();
    if (requesterRa.isEmpty) {
      _showSnackBar(
        'Não foi possível identificar o RA do condutor.',
        AppTheme.error,
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _requestingPromotion = true);
    try {
      final hasInstructorClaim = await _promotionService
          .currentUserHasInstructorClaim(forceRefresh: true);
      final requestId = await _promotionService.requestPromotion(
        dog: widget.dog,
        program: program,
        progress: _progress,
        module: module,
        requesterRa: requesterRa,
        requesterName: requesterRa,
        directInstructor: hasInstructorClaim,
      );

      if (hasInstructorClaim) {
        await _promotionService.decideRequest(
          requestId: requestId,
          approve: true,
        );
        if (!mounted) return;
        _showSnackBar(
          module.id == _modules.last.id
              ? 'Certificação concluída. Cão operacional em G&P.'
              : 'Módulo concluído pelo Instrutor K9.',
          AppTheme.success,
        );
      } else {
        if (!mounted) return;
        _showSnackBar(
          'Solicitação enviada aos Instrutores K9.',
          AppTheme.success,
        );
      }
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Não foi possível solicitar a evolução.');
    } finally {
      if (mounted) setState(() => _requestingPromotion = false);
    }
  }

  String _resolveRequesterRa() {
    final shift = context.read<ShiftViewModel>();
    final shiftRa = shift.handlerId?.trim();
    if (shiftRa != null && shiftRa.isNotEmpty) return shiftRa;
    return HandlerIdentityService.raFromUser(
          FirebaseAuth.instance.currentUser,
        ) ??
        '';
  }

  Future<void> _openSessionForm({
    required String phase,
    TrainingModule? module,
    TrainingMilestone? milestone,
  }) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _GuardProtectionSessionFormScreen(
          dog: widget.dog,
          phase: phase,
          program: _program,
          module: module,
          milestone: milestone,
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    AppFeedback.show(context, message, type: _feedbackTypeFor(color));
  }

  void _showError(Object error, String fallback) {
    AppFeedback.error(context, error, fallback: fallback);
  }

  AppFeedbackType _feedbackTypeFor(Color color) {
    if (color == AppTheme.success) return AppFeedbackType.success;
    if (color == AppTheme.error || color == AppTheme.errorStrong) {
      return AppFeedbackType.error;
    }
    if (color == AppTheme.warning || color == AppTheme.warningAccent) {
      return AppFeedbackType.warning;
    }
    return AppFeedbackType.info;
  }

  @override
  Widget build(BuildContext context) {
    final loading =
        _programLoading || _progressLoading || _initializingProgress;
    final current = _currentModule;
    final subtitle = _progress.isOperational
        ? 'Operacional em Guarda & Proteção'
        : current == null
        ? 'Formação em Guarda & Proteção'
        : 'Em formação no ${current.name.replaceFirst('Módulo ', 'M')}';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: AppTheme.transparent,
          systemNavigationBarColor: AppTheme.surfaceNavigation,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: BinomioHeader(
                  dog: widget.dog,
                  subtitle: subtitle,
                  subtitleColor: _progress.isOperational
                      ? AppTheme.success
                      : AppTheme.warning,
                  showProfileButton: false,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTitleCard(),
                      const SizedBox(height: 14),
                      _buildModeTabs(),
                      const SizedBox(height: 14),
                      if (loading)
                        const _LoadingPanel(label: 'Carregando currículo...')
                      else if (_program == null)
                        _buildMissingProgram()
                      else if (_modeIndex == 1 && !_progress.isOperational)
                        _buildOperationalLocked()
                      else if (_modeIndex == 1)
                        _buildOperationalContent()
                      else
                        _buildFormationContent(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleCard() {
    final completed = _progress.completedModuleIds.length;
    final total = _modules.length;
    return _Panel(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTheme.warning.withValues(alpha: 0.45),
              ),
            ),
            child: const Icon(Icons.security_rounded, color: AppTheme.warning),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guarda & Proteção',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _progress.isOperational
                      ? 'Manutenção operacional sem GPS'
                      : '$completed/$total módulos concluídos · currículo v${_program?.version ?? 1}',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          _StatusPill(
            label: _progress.isOperational ? 'OPERACIONAL' : 'FORMAÇÃO',
            color: _progress.isOperational
                ? AppTheme.success
                : AppTheme.warning,
          ),
        ],
      ),
    );
  }

  Widget _buildModeTabs() {
    return Row(
      children: [
        Expanded(
          child: _SegmentButton(
            label: 'Formação',
            icon: Icons.timeline_rounded,
            selected: _modeIndex == 0,
            onTap: () => setState(() => _modeIndex = 0),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SegmentButton(
            label: 'Operacional',
            icon: _progress.isOperational
                ? Icons.verified_rounded
                : Icons.lock_rounded,
            selected: _modeIndex == 1,
            onTap: () => setState(() => _modeIndex = 1),
          ),
        ),
      ],
    );
  }

  Widget _buildFormationContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInnerTabs(),
        const SizedBox(height: 14),
        if (_tabIndex == 0)
          _buildRoadmap()
        else if (_tabIndex == 1)
          _buildCurrentModule()
        else if (_tabIndex == 2)
          _buildHistory()
        else
          _buildStats(),
      ],
    );
  }

  Widget _buildInnerTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(_tabs.length, (index) {
          final selected = index == _tabIndex;
          return Padding(
            padding: EdgeInsets.only(right: index == _tabs.length - 1 ? 0 : 8),
            child: _SmallTab(
              label: _tabs[index],
              selected: selected,
              onTap: () => setState(() => _tabIndex = index),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildRoadmap() {
    final modules = _modules;
    if (modules.isEmpty) {
      return _EmptyPanel(
        icon: Icons.school_outlined,
        title: 'Sem módulos ativos',
        message:
            'O currículo de Guarda & Proteção ainda não tem módulos ativos.',
      );
    }

    return Column(
      children: [
        _InfoBanner(
          icon: Icons.psychology_alt_rounded,
          text:
              'Currículo sequencial: caça e mordida técnica abrem a formação; defesa entra com maturidade e sempre retorna ao equilíbrio por caça.',
        ),
        const SizedBox(height: 12),
        ...modules.map(_buildModuleCard),
      ],
    );
  }

  Widget _buildModuleCard(TrainingModule module) {
    final completed = _isCompleted(module);
    final locked = _isLocked(module);
    final current = module.id == _currentModule?.id && !completed;
    final achieved = _achievedCount(module);
    final total = module.activeMilestones.length;
    final color = completed
        ? AppTheme.success
        : current
        ? AppTheme.warning
        : AppTheme.textMuted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Panel(
        borderColor: color.withValues(alpha: current ? 0.55 : 0.28),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
                color: color.withValues(alpha: 0.08),
              ),
              child: Icon(
                completed
                    ? Icons.check_rounded
                    : locked
                    ? Icons.lock_rounded
                    : Icons.play_arrow_rounded,
                color: color,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    module.name,
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (module.description.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      module.description,
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    completed
                        ? 'Concluído'
                        : current
                        ? '$achieved/$total marcos atingidos'
                        : 'Disponível após concluir o módulo anterior',
                    style: GoogleFonts.inter(
                      color: completed
                          ? AppTheme.success
                          : current
                          ? AppTheme.warning
                          : AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentModule() {
    final module = _currentModule;
    if (module == null) {
      return _EmptyPanel(
        icon: Icons.school_outlined,
        title: 'Currículo vazio',
        message: 'Sem módulo atual para Guarda & Proteção.',
      );
    }

    final completed = _isCompleted(module);
    final pendingRequired = _pendingRequiredCount(module);
    final canRequest =
        pendingRequired == 0 && !completed && !_requestingPromotion;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          borderColor: AppTheme.warning.withValues(alpha: 0.45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusPill(
                    label: 'MÓDULO ${module.order}',
                    color: AppTheme.warning,
                  ),
                  const Spacer(),
                  Text(
                    'v${_program?.version ?? 1}',
                    style: GoogleFonts.ibmPlexMono(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                module.name,
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                module.description,
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'MARCOS PEDAGÓGICOS',
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        ...module.activeMilestones.map((milestone) {
          final achieved = _progress.isMilestoneAchieved(
            module.id,
            milestone.id,
          );
          final saving = _savingMilestoneIds.contains(milestone.id);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MilestoneTile(
              milestone: milestone,
              achieved: achieved,
              saving: saving,
              enabled: !completed,
              onChanged: (value) => _toggleMilestone(module, milestone, value),
              onNewSession: () => _openSessionForm(
                phase: 'formation',
                module: module,
                milestone: milestone,
              ),
            ),
          );
        }),
        const SizedBox(height: 6),
        _Panel(
          borderColor: AppTheme.warning.withValues(alpha: 0.45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isInstructorK9
                    ? 'Conclusão por Instrutor K9'
                    : 'Solicitar evolução',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                pendingRequired == 0
                    ? 'Todos os marcos obrigatórios foram atingidos.'
                    : '$pendingRequired marco(s) obrigatório(s) ainda pendente(s).',
                style: GoogleFonts.inter(
                  color: pendingRequired == 0
                      ? AppTheme.success
                      : AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'NOVA SESSÃO',
                      icon: Icons.add_rounded,
                      onTap: () =>
                          _openSessionForm(phase: 'formation', module: module),
                      secondary: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      label: _isInstructorK9 ? 'CONCLUIR' : 'SOLICITAR',
                      icon: _isInstructorK9
                          ? Icons.verified_rounded
                          : Icons.arrow_forward_rounded,
                      onTap: canRequest
                          ? () => _requestPromotion(module)
                          : null,
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

  Widget _buildHistory() {
    if (_sessionsLoading) {
      return const _LoadingPanel(label: 'Carregando histórico...');
    }
    if (_sessions.isEmpty) {
      return _EmptyPanel(
        icon: Icons.history_rounded,
        title: 'Nenhuma sessão registrada',
        message: 'As sessões reais de Guarda & Proteção aparecerão aqui.',
      );
    }
    return Column(children: _sessions.take(12).map(_buildSessionTile).toList());
  }

  Widget _buildSessionTile(TrainingHubSession session) {
    final meta = session.metadata;
    final phase = _readText(meta['phase'] ?? meta['mode']);
    final moduleName = _readText(meta['module_name']);
    final milestoneLabel = _readText(meta['milestone_label']);
    final impulse = _readText(meta['impulse']);
    final result = _readText(meta['result']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _Panel(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.shield_rounded, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    impulse.isNotEmpty ? impulse : 'Sessão de G&P',
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (moduleName.isNotEmpty) moduleName,
                      if (milestoneLabel.isNotEmpty) milestoneLabel,
                      if (phase.isNotEmpty) _phaseLabel(phase),
                      if (result.isNotEmpty) result,
                    ].join(' · '),
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              DateFormat('dd/MM').format(session.date),
              style: GoogleFonts.ibmPlexMono(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    final formation = _sessions
        .where(
          (session) => _readText(session.metadata['phase']) != 'maintenance',
        )
        .length;
    final maintenance = _sessions.length - formation;
    final current = _currentModule;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Sessões',
                value: '${_sessions.length}',
                icon: Icons.fitness_center_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: 'Módulos',
                value:
                    '${_progress.completedModuleIds.length}/${_modules.length}',
                icon: Icons.school_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Formação',
                value: '$formation',
                icon: Icons.timeline_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: 'Manutenção',
                value: '$maintenance',
                icon: Icons.verified_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _InfoBanner(
          icon: Icons.assignment_turned_in_rounded,
          text: current == null
              ? 'Sem módulo atual definido.'
              : 'Módulo atual: ${current.name}. A aprovação do último módulo certifica o cão como operacional.',
        ),
      ],
    );
  }

  Widget _buildOperationalContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          borderColor: AppTheme.success.withValues(alpha: 0.45),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified_rounded, color: AppTheme.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Manutenção operacional',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Treinos de manutenção registram controle, estabilidade e cenário. Não usam GPS e não geram selo de prova.',
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              _ActionButton(
                label: 'NOVA SESSÃO DE MANUTENÇÃO',
                icon: Icons.play_arrow_rounded,
                onTap: () => _openSessionForm(phase: 'maintenance'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'ÚLTIMAS SESSÕES',
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        if (_sessions.isEmpty)
          _EmptyPanel(
            icon: Icons.history_rounded,
            title: 'Sem manutenção registrada',
            message: 'As sessões operacionais aparecerão aqui.',
          )
        else
          ..._sessions.take(8).map(_buildSessionTile),
      ],
    );
  }

  Widget _buildOperationalLocked() {
    return _EmptyPanel(
      icon: Icons.lock_rounded,
      title: 'Operacional bloqueado',
      message:
          'A aba operacional destrava quando o Instrutor K9 aprova o Módulo 5 — Certificação.',
    );
  }

  Widget _buildMissingProgram() {
    return _EmptyPanel(
      icon: Icons.cloud_off_rounded,
      title: 'Currículo não encontrado',
      message:
          'Rode o seed UTF-8 de tools/training_programs_guarda_protecao_seed.json para publicar training_programs/guarda_protecao.',
    );
  }
}

class _GuardProtectionSessionFormScreen extends StatefulWidget {
  final Dog dog;
  final String phase;
  final TrainingProgram? program;
  final TrainingModule? module;
  final TrainingMilestone? milestone;

  const _GuardProtectionSessionFormScreen({
    required this.dog,
    required this.phase,
    this.program,
    this.module,
    this.milestone,
  });

  @override
  State<_GuardProtectionSessionFormScreen> createState() =>
      _GuardProtectionSessionFormScreenState();
}

class _GuardProtectionSessionFormScreenState
    extends State<_GuardProtectionSessionFormScreen> {
  final _figuranteController = TextEditingController();
  final _scenarioController = TextEditingController();
  final _observationController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String _impulse = 'Caça';
  String _equipment = 'Material jovem';
  String _result = 'completa';
  String _payment = 'Caça';
  bool _scenarioActive = false;
  bool _saving = false;
  final Set<String> _commands = <String>{};
  final Set<String> _capabilities = <String>{};

  @override
  void initState() {
    super.initState();
    _impulse = _defaultImpulseFor(widget.module);
  }

  @override
  void dispose() {
    _figuranteController.dispose();
    _scenarioController.dispose();
    _observationController.dispose();
    super.dispose();
  }

  String _defaultImpulseFor(TrainingModule? module) {
    final id = _normalize(module?.id ?? module?.name ?? '');
    if (id.contains('defesa')) return 'Defesa';
    if (id.contains('comando')) return 'Controle';
    if (id.contains('cenario')) return 'Cenário';
    if (id.contains('certificacao')) return 'Certificação';
    return 'Caça';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);

    final now = DateTime.now();
    final handlerRa = _resolveHandlerRa();
    final metadata = <String, dynamic>{
      'specialty': 'guarda_protecao',
      'modality': 'guarda_protecao',
      'type': 'guarda_protecao_session',
      'mode': widget.phase == 'maintenance' ? 'manutencao' : 'formacao',
      'phase': widget.phase,
      if (widget.program != null) 'program_version': widget.program!.version,
      if (widget.module != null) 'module_id': widget.module!.id,
      if (widget.module != null) 'module_name': widget.module!.name,
      if (widget.milestone != null) 'milestone_id': widget.milestone!.id,
      if (widget.milestone != null) 'milestone_label': widget.milestone!.label,
      'result': _result,
      'impulse': _impulse,
      'figurante': _figuranteController.text.trim(),
      'equipment': _equipment,
      'capabilities': _capabilities.toList()..sort(),
      'commands': _commands.toList()..sort(),
      'scenario_active': _scenarioActive,
      if (_scenarioActive)
        'scenario_description': _scenarioController.text.trim(),
      'payment': _payment,
      'gps': false,
    };

    final session = TrainingSessionModel(
      dogId: widget.dog.id,
      dogName: widget.dog.name,
      handlerId: handlerRa,
      date: now,
      trainingType: 'Guarda & Proteção',
      location: '',
      weather: '',
      handlerNotes: _observationController.text.trim(),
      metadata: metadata,
    );

    try {
      await context.read<TrainingViewModel>().addTrainingSession(session);
      if (!mounted) return;
      AppFeedback.success(context, 'Sessão de Guarda & Proteção registrada.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      AppFeedback.error(context, error, fallback: 'Falha ao salvar sessão.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _resolveHandlerRa() {
    final shiftRa = context.read<ShiftViewModel>().handlerId?.trim();
    if (shiftRa != null && shiftRa.isNotEmpty) return shiftRa;
    return HandlerIdentityService.raFromUser(
          FirebaseAuth.instance.currentUser,
        ) ??
        '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: BinomioHeader(
                  dog: widget.dog,
                  subtitle: widget.phase == 'maintenance'
                      ? 'Manutenção operacional'
                      : 'Sessão de formação',
                  showProfileButton: false,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Panel(
                        borderColor: AppTheme.warning.withValues(alpha: 0.45),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.module?.name ?? 'Sessão operacional',
                              style: GoogleFonts.inter(
                                color: AppTheme.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (widget.milestone != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                widget.milestone!.label,
                                style: GoogleFonts.inter(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionTitle('IMPULSO TRABALHADO'),
                      _ChipWrap(
                        values: const [
                          'Caça',
                          'Defesa',
                          'Controle',
                          'Cenário',
                          'Certificação',
                        ],
                        selected: _impulse,
                        onSelected: (value) => setState(() => _impulse = value),
                      ),
                      const SizedBox(height: 14),
                      _SectionTitle('EQUIPAMENTO'),
                      _ChipWrap(
                        values: const [
                          'Material filhote',
                          'Material jovem',
                          'Manga jovem',
                          'Manga adulta',
                          'Traje',
                          'Vara',
                          'Outros',
                        ],
                        selected: _equipment,
                        onSelected: (value) =>
                            setState(() => _equipment = value),
                      ),
                      const SizedBox(height: 14),
                      _SectionTitle('CAPACIDADES OBSERVADAS'),
                      _MultiChipWrap(
                        values: const [
                          'Mordida firme',
                          'Boca cheia',
                          'Estabilização',
                          'Mordida calma',
                          'Pressão sustentada',
                        ],
                        selected: _capabilities,
                        onChanged: (value) {
                          setState(() {
                            if (_capabilities.contains(value)) {
                              _capabilities.remove(value);
                            } else {
                              _capabilities.add(value);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      _SectionTitle('COMANDOS'),
                      _MultiChipWrap(
                        values: const [
                          'Larga',
                          'Atenção',
                          'Reengajar',
                          'Nenhum',
                        ],
                        selected: _commands,
                        onChanged: (value) {
                          setState(() {
                            if (value == 'Nenhum') {
                              _commands
                                ..clear()
                                ..add(value);
                            } else {
                              _commands.remove('Nenhum');
                              if (_commands.contains(value)) {
                                _commands.remove(value);
                              } else {
                                _commands.add(value);
                              }
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      _TextFieldPanel(
                        controller: _figuranteController,
                        label: 'Figurante / apoio',
                        hint: 'Nome ou RA do figurante',
                      ),
                      const SizedBox(height: 14),
                      _SwitchPanel(
                        value: _scenarioActive,
                        title: 'Cenário operacional simulado',
                        subtitle:
                            'Use quando houver ambiente, abordagem ou guarda simulada.',
                        onChanged: (value) =>
                            setState(() => _scenarioActive = value),
                      ),
                      if (_scenarioActive) ...[
                        const SizedBox(height: 10),
                        _TextFieldPanel(
                          controller: _scenarioController,
                          label: 'Descrição do cenário',
                          hint:
                              'Ex.: abordagem em pátio, guarda de perímetro...',
                          maxLines: 3,
                          validator: (value) {
                            if (!_scenarioActive) return null;
                            if ((value ?? '').trim().isEmpty) {
                              return 'Descreva o cenário.';
                            }
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 14),
                      _SectionTitle('RESULTADO'),
                      _ChipWrap(
                        values: const ['completa', 'parcial', 'sem_exito'],
                        selected: _result,
                        onSelected: (value) => setState(() => _result = value),
                      ),
                      const SizedBox(height: 14),
                      _SectionTitle('PAGAMENTO'),
                      _ChipWrap(
                        values: const [
                          'Caça',
                          'Defesa',
                          'Pressão',
                          'Sem pagamento',
                        ],
                        selected: _payment,
                        onSelected: (value) => setState(() => _payment = value),
                      ),
                      const SizedBox(height: 14),
                      _TextFieldPanel(
                        controller: _observationController,
                        label: 'Observações técnicas',
                        hint:
                            'Como o cão respondeu? Houve equilíbrio? O que corrigir?',
                        maxLines: 4,
                      ),
                      const SizedBox(height: 20),
                      _ActionButton(
                        label: _saving ? 'SALVANDO...' : 'SALVAR SESSÃO',
                        icon: Icons.save_rounded,
                        onTap: _saving ? null : _save,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final Color? borderColor;

  const _Panel({required this.child, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfacePanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor ?? AppTheme.outlineVariant.withValues(alpha: 0.9),
        ),
      ),
      child: child,
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.18)
              : AppTheme.surfacePanel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.55)
                : AppTheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? AppTheme.primary : AppTheme.textMuted,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SmallTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.14)
              : AppTheme.surfacePanelSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.55)
                : AppTheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: selected ? AppTheme.primary : AppTheme.textSecondary,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _MilestoneTile extends StatelessWidget {
  final TrainingMilestone milestone;
  final bool achieved;
  final bool saving;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onNewSession;

  const _MilestoneTile({
    required this.milestone,
    required this.achieved,
    required this.saving,
    required this.enabled,
    required this.onChanged,
    required this.onNewSession,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      borderColor: achieved
          ? AppTheme.success.withValues(alpha: 0.42)
          : AppTheme.outlineVariant,
      child: Row(
        children: [
          InkWell(
            onTap: enabled && !saving ? () => onChanged(!achieved) : null,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: achieved ? AppTheme.success : AppTheme.textMuted,
                  width: 2,
                ),
                color: achieved
                    ? AppTheme.success.withValues(alpha: 0.14)
                    : AppTheme.transparent,
              ),
              child: saving
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : achieved
                  ? const Icon(Icons.check_rounded, color: AppTheme.success)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  milestone.label,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  milestone.isRequired
                      ? 'Marco obrigatório'
                      : 'Marco complementar',
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Registrar sessão neste marco',
            onPressed: enabled ? onNewSession : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
            color: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool secondary;

  const _ActionButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = secondary ? AppTheme.surfacePanelAlt : AppTheme.primary;
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? color : AppTheme.outlineVariant,
          foregroundColor: secondary
              ? AppTheme.textPrimary
              : AppTheme.background,
          disabledBackgroundColor: AppTheme.outlineVariant,
          disabledForegroundColor: AppTheme.textMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.ibmPlexMono(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      borderColor: AppTheme.primary.withValues(alpha: 0.35),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primary),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.ibmPlexMono(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        children: [
          Icon(icon, color: AppTheme.primary, size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  final String label;

  const _LoadingPanel({required this.label});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.inter(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;

  const _SectionTitle(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: AppTheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.8,
        ),
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  final List<String> values;
  final String selected;
  final ValueChanged<String> onSelected;

  const _ChipWrap({
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values
          .map(
            (value) => _ToggleChip(
              label: value,
              selected: value == selected,
              onTap: () => onSelected(value),
            ),
          )
          .toList(),
    );
  }
}

class _MultiChipWrap extends StatelessWidget {
  final List<String> values;
  final Set<String> selected;
  final ValueChanged<String> onChanged;

  const _MultiChipWrap({
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values
          .map(
            (value) => _ToggleChip(
              label: value,
              selected: selected.contains(value),
              onTap: () => onChanged(value),
            ),
          )
          .toList(),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.16)
              : AppTheme.surfacePanel,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.55)
                : AppTheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: selected ? AppTheme.primary : AppTheme.textSecondary,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _TextFieldPanel extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final String? Function(String?)? validator;

  const _TextFieldPanel({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      style: GoogleFonts.inter(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.inter(color: AppTheme.primary),
        hintStyle: GoogleFonts.inter(color: AppTheme.textMuted),
        filled: true,
        fillColor: AppTheme.surfacePanel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
      ),
    );
  }
}

class _SwitchPanel extends StatelessWidget {
  final bool value;
  final String title;
  final String subtitle;
  final ValueChanged<bool> onChanged;

  const _SwitchPanel({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppTheme.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

String _readText(dynamic value) => value?.toString().trim() ?? '';

String _phaseLabel(String value) {
  final normalized = _normalize(value);
  if (normalized == 'maintenance' || normalized == 'manutencao') {
    return 'manutenção';
  }
  if (normalized == 'formation' || normalized == 'formacao') {
    return 'formação';
  }
  return value;
}

String _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c');
}
