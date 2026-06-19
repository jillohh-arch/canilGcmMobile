import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/core/services/gps_tracking_service.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/data/training_program_service.dart';
import 'package:canil_gcm/features/training/data/training_promotion_service.dart';
import 'package:canil_gcm/features/training/data/training_service.dart';
import 'package:canil_gcm/features/training/domain/training_model.dart';
import 'package:canil_gcm/features/training/domain/training_program.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/training/presentation/screens/gps_tracking_summary_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/gps_tracking_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/busca_captura_manutencao_screen.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/widgets/bc_trail_config_sheet.dart';

class BuscaCapturaFormacaoScreen extends StatefulWidget {
  final Dog dog;

  const BuscaCapturaFormacaoScreen({super.key, required this.dog});

  @override
  State<BuscaCapturaFormacaoScreen> createState() =>
      _BuscaCapturaFormacaoScreenState();
}

class _BuscaCapturaFormacaoScreenState
    extends State<BuscaCapturaFormacaoScreen> {
  static const _modality = 'busca_captura';

  int _activeModeIndex = 0;
  int _activeTabIndex = 0;
  final TrainingProgramService _programService = TrainingProgramService();
  final TrainingPromotionService _promotionService = TrainingPromotionService();
  final TrainingService _trainingService = TrainingService();
  StreamSubscription<TrainingProgram?>? _programSub;
  StreamSubscription<TrainingProgress>? _progressSub;
  StreamSubscription<List<BonusTrainingMilestone>>? _bonusSub;
  StreamSubscription<List<TrainingHubSession>>? _sessionsSub;
  TrainingProgram? _program;
  TrainingProgress _progress = TrainingProgress.initial(_modality);
  List<BonusTrainingMilestone> _bonusMilestones =
      const <BonusTrainingMilestone>[];
  List<TrainingHubSession> _bcSessions = const <TrainingHubSession>[];
  Object? _programError;
  Object? _progressError;
  Object? _bonusError;
  Object? _sessionsError;
  bool _programLoaded = false;
  bool _progressLoaded = false;
  bool _bonusLoaded = false;
  bool _sessionsLoaded = false;
  bool _initializingProgress = false;
  bool _completingModule = false;
  bool _isInstructorK9 = false;
  bool _pendingDraftPrompted = false;
  final Set<String> _savingMilestoneIds = <String>{};
  final Set<String> _savingBonusMilestoneIds = <String>{};

  final List<String> _modeTabs = ['Formacao', 'Operacional'];

  final List<String> _tabs = [
    'Roadmap',
    'Módulo atual',
    'Histórico',
    'Estatísticas',
  ];

  @override
  void initState() {
    super.initState();
    _subscribeProgram();
    _subscribeProgress();
    _subscribeBonusMilestones();
    _subscribeSessions();
    unawaited(_loadInstructorRole());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_promptPendingTrailDraft());
    });
  }

  @override
  void didUpdateWidget(BuscaCapturaFormacaoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dog.id != widget.dog.id) {
      _pendingDraftPrompted = false;
      _subscribeProgress();
      _subscribeBonusMilestones();
      _subscribeSessions();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_promptPendingTrailDraft());
      });
    }
  }

  @override
  void dispose() {
    _programSub?.cancel();
    _progressSub?.cancel();
    _bonusSub?.cancel();
    _sessionsSub?.cancel();
    super.dispose();
  }

  void _subscribeProgram() {
    _programSub?.cancel();
    _programSub = _programService
        .watchProgram(_modality)
        .listen(
          (program) {
            if (!mounted) return;
            setState(() {
              _program = program;
              _programLoaded = true;
              _programError = null;
            });
            _ensureProgressInitializedIfNeeded();
          },
          onError: (error) {
            if (!mounted) return;
            setState(() {
              _programError = error;
              _programLoaded = true;
            });
          },
        );
  }

  void _subscribeProgress() {
    _progressSub?.cancel();
    _progressSub = _programService
        .watchProgress(widget.dog.id, _modality)
        .listen(
          (progress) {
            if (!mounted) return;
            setState(() {
              _progress = progress;
              _progressLoaded = true;
              _progressError = null;
            });
            _ensureProgressInitializedIfNeeded();
          },
          onError: (error) {
            if (!mounted) return;
            setState(() {
              _progressError = error;
              _progressLoaded = true;
            });
          },
        );
  }

  void _subscribeBonusMilestones() {
    _bonusSub?.cancel();
    setState(() {
      _bonusLoaded = false;
      _bonusError = null;
      _bonusMilestones = const <BonusTrainingMilestone>[];
    });
    _bonusSub = _programService
        .watchBonusMilestones(widget.dog.id, _modality)
        .listen(
          (items) {
            if (!mounted) return;
            setState(() {
              _bonusMilestones = items;
              _bonusLoaded = true;
              _bonusError = null;
            });
          },
          onError: (error) {
            if (!mounted) return;
            setState(() {
              _bonusError = error;
              _bonusLoaded = true;
            });
          },
        );
  }

  void _subscribeSessions() {
    _sessionsSub?.cancel();
    setState(() {
      _sessionsLoaded = false;
      _sessionsError = null;
      _bcSessions = const <TrainingHubSession>[];
    });
    _sessionsSub = _trainingService
        .watchSessionsForDog(widget.dog.id)
        .listen(
          (sessions) {
            if (!mounted) return;
            final filtered = sessions.where(_isBuscaCapturaSession).toList()
              ..sort((a, b) => b.date.compareTo(a.date));
            setState(() {
              _bcSessions = filtered;
              _sessionsLoaded = true;
              _sessionsError = null;
            });
          },
          onError: (error) {
            if (!mounted) return;
            setState(() {
              _sessionsError = error;
              _sessionsLoaded = true;
            });
          },
        );
  }

  Future<void> _loadInstructorRole() async {
    try {
      final result = await _promotionService.currentUserHasInstructorClaim(
        forceRefresh: true,
      );
      if (!mounted) return;
      setState(() => _isInstructorK9 = result);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isInstructorK9 = false);
    }
  }

  Future<void> _ensureProgressInitializedIfNeeded() async {
    final program = _program;
    if (!_programLoaded ||
        !_progressLoaded ||
        _initializingProgress ||
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
      _showError(error, 'Não foi possível inicializar a progressão de B&C.');
    } finally {
      if (mounted) {
        setState(() => _initializingProgress = false);
      }
    }
  }

  List<TrainingModule> get _modules => _program?.activeModules ?? const [];

  TrainingModule? get _currentModule {
    if (_progress.isOperational) return null;
    if (_modules.isEmpty) return null;
    final currentId = _progress.currentModuleId;
    if (currentId != null) {
      for (final module in _modules) {
        if (module.id == currentId) return module;
      }
    }
    for (final module in _modules) {
      if (!_progress.completedModuleIds.contains(module.id)) return module;
    }
    return _modules.last;
  }

  bool _isCompleted(TrainingModule module) {
    return _progress.completedModuleIds.contains(module.id) ||
        _progress.isOperational;
  }

  bool _isActive(TrainingModule module) {
    return !_progress.isOperational && _currentModule?.id == module.id;
  }

  bool _isLocked(TrainingModule module) {
    final current = _currentModule;
    if (current == null || _progress.isOperational) return false;
    return !_isCompleted(module) && module.order > current.order;
  }

  int _achievedCount(TrainingModule module) {
    return module.activeMilestones
        .where(
          (milestone) => _progress.isMilestoneAchieved(module.id, milestone.id),
        )
        .length;
  }

  int _requiredMissingCount(TrainingModule module) {
    return module.activeMilestones
        .where(
          (milestone) =>
              milestone.isRequired &&
              !_progress.isMilestoneAchieved(module.id, milestone.id),
        )
        .length;
  }

  bool _canCompleteModule(TrainingModule module) {
    return _isActive(module) &&
        !_completingModule &&
        _requiredMissingCount(module) == 0;
  }

  bool _isLastModule(TrainingModule module) {
    return _modules.isNotEmpty && _modules.last.id == module.id;
  }

  bool _isBuscaCapturaSession(TrainingHubSession session) {
    final metadata = session.metadata;
    final values = [
      session.trainingType,
      session.specialty,
      session.subtype,
      metadata['modality'],
      metadata['specialty'],
      metadata['type'],
      metadata['trainingType'],
      metadata['training_type'],
    ].map((value) => normalizeTrainingKey(value?.toString() ?? ''));
    return values.any(
      (value) =>
          value == 'busca_captura' ||
          value == 'busca_e_captura' ||
          value == 'busca_captura_track',
    );
  }

  Map<String, dynamic> _trackFor(TrainingHubSession session) {
    final metadata = session.metadata;
    final track = metadata['track'] ?? metadata['gps_track'];
    if (track is Map<String, dynamic>) return track;
    if (track is Map) return Map<String, dynamic>.from(track);
    return const <String, dynamic>{};
  }

  double _distanceMetersFor(TrainingHubSession session) {
    final track = _trackFor(session);
    return _readDouble(track['distance_m'] ?? session.metadata['distance_m']);
  }

  int _durationSecondsFor(TrainingHubSession session) {
    final track = _trackFor(session);
    return _readInt(track['duration_s'] ?? session.metadata['duration_s']);
  }

  String _resultFor(TrainingHubSession session) {
    final track = _trackFor(session);
    final raw = track['result'] ?? session.metadata['result'] ?? session.status;
    final normalized = normalizeTrainingKey(raw?.toString() ?? '');
    if (normalized == 'completa' ||
        normalized == 'completo' ||
        normalized == 'completed' ||
        normalized == 'alvo_encontrado') {
      return 'completa';
    }
    if (normalized == 'sem_exito' ||
        normalized == 'sem_sucesso' ||
        normalized == 'perda' ||
        normalized == 'perdeu_rastro') {
      return 'sem_exito';
    }
    if (normalized == 'parcial' || normalized == 'checagem') {
      return 'parcial';
    }
    return 'parcial';
  }

  String _resultLabel(String result) {
    switch (result) {
      case 'completa':
        return 'Completa';
      case 'sem_exito':
        return 'Sem exito';
      default:
        return 'Parcial';
    }
  }

  String _moduleLabelFor(TrainingHubSession session) {
    final moduleName = session.metadata['module_name']?.toString().trim();
    if (moduleName != null && moduleName.isNotEmpty) return moduleName;
    final moduleId = session.metadata['module_id']?.toString().trim();
    if (moduleId != null && moduleId.isNotEmpty) {
      for (final module in _modules) {
        if (module.id == moduleId) return module.name;
      }
      return moduleId.replaceAll('_', ' ');
    }
    return session.metadata['phase'] == 'maintenance'
        ? 'Manutencao'
        : 'Formacao';
  }

  String _milestoneLabelFor(TrainingHubSession session) {
    final label = session.metadata['milestone_label']?.toString().trim();
    if (label != null && label.isNotEmpty) return label;
    final milestoneId = session.metadata['milestone_id']?.toString().trim();
    if (milestoneId != null && milestoneId.isNotEmpty) {
      for (final module in _modules) {
        for (final milestone in module.activeMilestones) {
          if (milestone.id == milestoneId) return milestone.label;
        }
      }
      return milestoneId.replaceAll('_', ' ');
    }
    return 'Sessao operacional';
  }

  String _formatDistance(double meters) {
    if (meters <= 0) return '--';
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '--';
    final minutes = seconds / 60;
    if (minutes < 1) return '${seconds}s';
    if (minutes < 10) return '${minutes.toStringAsFixed(1)} min';
    return '${minutes.round()} min';
  }

  String _formatShortDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }

  double _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final currentModule = _currentModule;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: AppTheme.transparent,
          systemNavigationBarColor: AppTheme.background,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // Page Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      children: [
                        Row(
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
                                    'FORMAÇÃO',
                                    style: GoogleFonts.inter(
                                      color: AppTheme.warning,
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
                                color: AppTheme.warning.withAlpha(
                                  31,
                                ), // rgba(241, 196, 15, 0.12)
                                borderRadius: BorderRadius.circular(9),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                '🎯',
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Formation Status / Binomio Banner
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withAlpha(
                              15,
                            ), // rgba(241, 196, 15, 0.06)
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppTheme.warning.withAlpha(
                                51,
                              ), // rgba(241, 196, 15, 0.2)
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.warning,
                                    width: 1.5,
                                  ),
                                  color: AppTheme.surfacePanelAlt,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  widget.dog.name.isNotEmpty
                                      ? widget.dog.name[0]
                                      : 'K',
                                  style: GoogleFonts.inter(
                                    color: AppTheme.warning,
                                    fontSize: 9,
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
                                      '${widget.dog.name} · Condutor',
                                      style: GoogleFonts.inter(
                                        color: AppTheme.textPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    RichText(
                                      text: TextSpan(
                                        style: GoogleFonts.inter(
                                          color: AppTheme.textSecondary,
                                          fontSize: 10,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: _progress.isOperational
                                                ? 'Operacional'
                                                : 'Em formação no ',
                                          ),
                                          TextSpan(
                                            text: currentModule == null
                                                ? (_progress.isOperational
                                                      ? ''
                                                      : 'currículo')
                                                : 'Módulo ${currentModule.order}',
                                            style: const TextStyle(
                                              color: AppTheme.warning,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          TextSpan(
                                            text: _program == null
                                                ? ' · aguardando seed'
                                                : ' · currículo v${_program!.version}',
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
                      ],
                    ),
                  ),

                  _buildModeTabs(),
                  if (_activeModeIndex == 0) _buildFormationTabs(),

                  // Tab Content Area
                  Expanded(
                    child: _activeModeIndex == 0
                        ? IndexedStack(
                            index: _activeTabIndex,
                            children: [
                              _buildRoadmapTab(),
                              _buildModuloAtualTab(),
                              _buildHistoricoTab(),
                              _buildEstatisticasTab(),
                            ],
                          )
                        : _buildOperacionalTab(),
                  ),
                ],
              ),

              // Fixed bottom CTA
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
                      colors: [
                        AppTheme.background,
                        AppTheme.background.withAlpha(0),
                      ],
                    ),
                  ),
                  child: ElevatedButton(
                    onPressed: _activeModeIndex == 1 && !_progress.isOperational
                        ? null
                        : () async {
                            if (_activeModeIndex == 1) {
                              _openMaintenance();
                              return;
                            }
                            await _startFormationTrail(currentModule);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _activeModeIndex == 1
                          ? AppTheme.success
                          : AppTheme.primary,
                      foregroundColor: AppTheme.background,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _activeModeIndex == 1
                              ? Icons.verified_rounded
                              : Icons.play_arrow_rounded,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _activeModeIndex == 1
                              ? 'ABRIR OPERACIONAL'
                              : 'INICIAR SESSÃO DE TREINO',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeTabs() {
    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.textPrimary.withAlpha(16)),
        ),
      ),
      child: Row(
        children: List.generate(_modeTabs.length, (index) {
          final isActive = _activeModeIndex == index;
          final isOperationalTab = index == 1;
          final locked = isOperationalTab && !_progress.isOperational;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _activeModeIndex = index);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: EdgeInsets.only(left: index == 0 ? 0 : 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isActive
                      ? AppTheme.primary.withAlpha(28)
                      : AppTheme.textPrimary.withAlpha(8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActive
                        ? AppTheme.primary.withAlpha(80)
                        : AppTheme.textPrimary.withAlpha(18),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (locked) ...[
                      const Icon(
                        Icons.lock_outline_rounded,
                        color: AppTheme.textMuted,
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      _modeTabs[index],
                      style: GoogleFonts.inter(
                        color: isActive
                            ? AppTheme.primary
                            : locked
                            ? AppTheme.textMuted
                            : AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildFormationTabs() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.textPrimary.withAlpha(16)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(_tabs.length, (index) {
          final isActive = _activeTabIndex == index;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _activeTabIndex = index);
            },
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? AppTheme.primary : AppTheme.transparent,
                    width: 2,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _tabs[index],
                style: GoogleFonts.inter(
                  color: isActive ? AppTheme.primary : AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildOperacionalTab() {
    if (!_progress.isOperational) {
      return _buildProgramState(
        title: 'Operacional travado',
        body:
            'Conclua os modulos sequenciais de Formacao para destravar a manutencao operacional.',
        icon: Icons.lock_outline_rounded,
        color: AppTheme.warning,
      );
    }

    final program = _program;
    final bonusOffers = program == null
        ? const <TrainingBonusOffer>[]
        : _programService.bonusOffersFor(
            program: program,
            progress: _progress,
            completedBonuses: _bonusMilestones,
          );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 90),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.success.withAlpha(18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.success.withAlpha(70)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    color: AppTheme.success,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${widget.dog.name} operacional em Busca & Captura',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'A Formacao foi concluida pelo snapshot dos modulos. A manutencao registra a evolucao operacional e continua auditavel.',
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openMaintenance,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('ABRIR MANUTENCAO OPERACIONAL'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.success,
                    side: const BorderSide(color: AppTheme.success),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildBonusMilestonesSection(bonusOffers),
      ],
    );
  }

  Widget _buildBonusMilestonesSection(List<TrainingBonusOffer> offers) {
    if (!_bonusLoaded) {
      return _buildInlineOperationalCard(
        icon: Icons.sync_rounded,
        title: 'Verificando marcos-bonus',
        body: 'Comparando o curriculo atual com o snapshot de formacao.',
        color: AppTheme.primary,
      );
    }
    if (_bonusError != null) {
      return _buildInlineOperationalCard(
        icon: Icons.error_outline_rounded,
        title: 'Falha ao carregar bonus',
        body: _bonusError.toString(),
        color: AppTheme.error,
      );
    }

    final children = <Widget>[
      _buildInlineOperationalCard(
        icon: offers.isEmpty ? Icons.task_alt_rounded : Icons.add_task_rounded,
        title: offers.isEmpty
            ? 'Nenhum marco-bonus pendente'
            : 'Marcos-bonus disponiveis',
        body: offers.isEmpty
            ? 'Se o curriculo ganhar novo marco, ele aparece aqui como camada aditiva, sem rebaixar o cao operacional.'
            : 'Novos marcos foram adicionados ao curriculo depois da formacao. Registrar aqui soma ao historico sem alterar snapshots antigos.',
        color: offers.isEmpty ? AppTheme.success : AppTheme.warning,
      ),
    ];

    for (final offer in offers) {
      children.add(_buildBonusOfferCard(offer));
    }
    if (_bonusMilestones.isNotEmpty) {
      children.add(_buildCompletedBonusHeader());
      children.addAll(_bonusMilestones.map(_buildCompletedBonusCard));
    }
    return Column(children: children);
  }

  Widget _buildInlineOperationalCard({
    required IconData icon,
    required String title,
    required String body,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBonusOfferCard(TrainingBonusOffer offer) {
    final saving = _savingBonusMilestoneIds.contains(offer.id);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warning.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withAlpha(45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.control_point_duplicate_rounded,
                color: AppTheme.warning,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      offer.milestone.label,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${offer.module.name} · curriculo v${_program?.version ?? '-'}',
                      style: GoogleFonts.inter(
                        color: AppTheme.textMuted,
                        fontSize: 10,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: saving ? null : () => _completeBonusMilestone(offer),
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(saving ? 'REGISTRANDO...' : 'REGISTRAR BONUS'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.warning,
                side: const BorderSide(color: AppTheme.warning),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedBonusHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'BONUS CONCLUIDOS',
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
          ),
        ),
      ),
    );
  }

  Widget _buildCompletedBonusCard(BonusTrainingMilestone item) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.success.withAlpha(10),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppTheme.success.withAlpha(38)),
      ),
      child: Row(
        children: [
          const Icon(Icons.task_alt_rounded, color: AppTheme.success, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.moduleName} · por ${item.completedBy ?? 'condutor'}',
                  style: GoogleFonts.inter(
                    color: AppTheme.textMuted,
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

  void _openMaintenance() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BuscaCapturaManutencaoScreen(dog: widget.dog),
      ),
    );
  }

  String _resolveHandlerId() {
    try {
      final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
      final handlerId = shiftVM.handlerId?.trim();
      if (handlerId != null && handlerId.isNotEmpty) return handlerId;
    } catch (_) {
      // Sem ShiftViewModel no contexto, usa identidade autenticada.
    }
    return HandlerIdentityService.raFromUser(
          FirebaseAuth.instance.currentUser,
        ) ??
        'Condutor';
  }

  Future<void> _startFormationTrail(TrainingModule? module) async {
    if (module == null) {
      _showSnackBar(
        'Nenhum modulo atual disponivel para trilha.',
        AppTheme.error,
      );
      return;
    }
    HapticFeedback.mediumImpact();
    final handlerId = _resolveHandlerId();
    final config = await showModalBottomSheet<GpsTrackingSessionConfig>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.surfacePanel,
      builder: (_) => BcTrailConfigSheet(
        phase: 'formation',
        dogId: widget.dog.id,
        dogName: widget.dog.name,
        conductor: handlerId,
        module: module,
        milestones: module.activeMilestones,
      ),
    );
    if (config == null || !mounted) return;

    final trackingService = GpsTrackingService();
    final result = await Navigator.of(context).push<GpsTrackResult?>(
      MaterialPageRoute(
        builder: (_) => GpsTrackingScreen(
          activityLabel: 'Busca & Captura · Formação',
          dogName: widget.dog.name,
          handlerName: handlerId,
          trackingService: trackingService,
          sessionConfig: config,
          enableFieldEvents: true,
        ),
      ),
    );
    if (result == null || !mounted) return;
    await _persistBcTrailSession(result, config);
    if (!mounted) return;
    _offerManualMilestoneMark(module, config);
  }

  Future<void> _promptPendingTrailDraft() async {
    if (_pendingDraftPrompted || !mounted) return;
    _pendingDraftPrompted = true;
    final drafts = await GpsTrackResult.loadLocalDrafts(
      modality: _modality,
      phase: 'formation',
      dogId: widget.dog.id,
    );
    if (!mounted || drafts.isEmpty) return;
    final draft = drafts.last;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Ha uma trilha B&C de formacao nao salva neste aparelho.',
        ),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'REVISAR',
          onPressed: () => unawaited(_reviewPendingTrailDraft(draft)),
        ),
      ),
    );
  }

  Future<void> _reviewPendingTrailDraft(GpsTrackResult draft) async {
    final config = draft.sessionConfig;
    if (config == null || !mounted) return;
    final result = await Navigator.of(context).push<GpsTrackResult?>(
      MaterialPageRoute(
        builder: (_) => GpsTrackingSummaryScreen(
          result: draft,
          activityLabel: 'Busca & Captura - Formacao pendente',
          dogName: widget.dog.name,
          handlerName: config.conductor.isNotEmpty
              ? config.conductor
              : _resolveHandlerId(),
        ),
      ),
    );
    if (result == null || !mounted) return;
    await _persistBcTrailSession(result, config);

    TrainingModule? module;
    for (final candidate in _program?.modules ?? const <TrainingModule>[]) {
      if (candidate.id == config.moduleId) {
        module = candidate;
        break;
      }
    }
    if (module != null && mounted) {
      _offerManualMilestoneMark(module, config);
    }
  }

  Future<void> _persistBcTrailSession(
    GpsTrackResult result,
    GpsTrackingSessionConfig config,
  ) async {
    final track = result.toJson();
    final metadata = {
      'specialty': 'busca_captura',
      'modality': _modality,
      'type': 'busca_captura_track',
      'mode': 'formacao',
      'phase': 'formation',
      if (_program != null) 'program_version': _program!.version,
      ...config.toJson(),
      'result': result.result ?? 'completa',
      'gps': true,
      'track': track,
      'gps_track': track,
    };
    final session = TrainingSessionModel(
      dogId: widget.dog.id,
      dogName: widget.dog.name,
      handlerId: config.conductor,
      date: result.startedAt,
      trainingType: 'Busca & Captura',
      location: config.ambiente,
      weather: '',
      handlerNotes: result.observation ?? '',
      metadata: metadata,
    );

    try {
      final vm = Provider.of<TrainingViewModel>(context, listen: false);
      await vm.addDogTrainingSession(session);
      await result.deleteLocalDraft();
      if (!mounted) return;
      _showSnackBar('Sessao de trilha B&C registrada.', AppTheme.success);
    } catch (error) {
      if (!mounted) return;
      _showError(
        error,
        'Não foi possível salvar a sessão. O rascunho local foi preservado.',
      );
    }
  }

  void _offerManualMilestoneMark(
    TrainingModule module,
    GpsTrackingSessionConfig config,
  ) {
    final milestoneId = config.milestoneId;
    if (milestoneId == null) return;
    TrainingMilestone? milestone;
    for (final item in module.activeMilestones) {
      if (item.id == milestoneId) {
        milestone = item;
        break;
      }
    }
    if (milestone == null) return;
    final selectedMilestone = milestone;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Trabalhou "${selectedMilestone.label}". Marcar como atingido agora?',
        ),
        backgroundColor: AppTheme.success,
        action: SnackBarAction(
          label: 'MARCAR',
          textColor: AppTheme.background,
          onPressed: () => _toggleMilestone(module, selectedMilestone, true),
        ),
      ),
    );
  }

  // --- ABA ROADMAP ---
  Widget _buildRoadmapTab() {
    if (!_programLoaded) {
      return _buildProgramState(
        title: 'Carregando currículo',
        body: 'Buscando módulos de Busca & Captura no Firebase.',
        icon: Icons.cloud_sync_rounded,
      );
    }
    if (_programError != null) {
      return _buildProgramState(
        title: 'Falha ao carregar currículo',
        body: _programError.toString(),
        icon: Icons.error_outline_rounded,
        color: AppTheme.error,
      );
    }
    if (_program == null || _modules.isEmpty) {
      return _buildProgramState(
        title: 'Currículo não semeado',
        body:
            'Rode o seed de training_programs/busca_captura para liberar os módulos no app.',
        icon: Icons.inventory_2_outlined,
        color: AppTheme.warning,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        _buildCurriculumInfoCard(),
        ..._modules.map(_buildProgramModuleCard),
        _buildOperationalUnlockCard(),
      ],
    );
  }

  Widget _buildProgramModuleCard(TrainingModule module) {
    final completed = _isCompleted(module);
    final active = _isActive(module);
    final locked = _isLocked(module);
    final milestones = module.activeMilestones;
    final achievedCount = _achievedCount(module);
    final progress = completed
        ? 1.0
        : milestones.isEmpty
        ? 0.0
        : achievedCount / milestones.length;
    final status = completed
        ? 'CONCLUÍDO'
        : active
        ? 'EM TREINO'
        : locked
        ? 'BLOQUEADO'
        : 'A INICIAR';
    final progressText = completed
        ? '${milestones.length} marcos congelados no histórico'
        : active
        ? '$achievedCount/${milestones.length} marcos atingidos'
        : locked
        ? 'Disponível após concluir o módulo anterior'
        : '${milestones.length} marcos cadastrados';

    return _buildModuleCard(
      number: completed ? '✓' : module.order.toString(),
      title: module.name,
      subtitle: module.description,
      status: status,
      progress: progress,
      isCompleted: completed,
      isActive: active,
      progressText: progressText,
    );
  }

  Widget _buildCurriculumInfoCard() {
    final program = _program!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withAlpha(40)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_done_rounded,
            color: AppTheme.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${program.name} · currículo v${program.version} · ${program.activeModules.length} módulos ativos',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationalUnlockCard() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textPrimary.withAlpha(26), width: 1),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.verified_outlined,
            color: AppTheme.textMuted,
            size: 24,
          ),
          const SizedBox(height: 6),
          Text(
            'Conclusão do último módulo',
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'A aprovação do último módulo pelo instrutor certifica o cão como operacional. Prova formal, se houver, deve ser marco obrigatório do último módulo.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: AppTheme.textMuted,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgramState({
    required String title,
    required String body,
    required IconData icon,
    Color color = AppTheme.primary,
    bool compact = false,
  }) {
    return ListView(
      padding: compact
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(16, 24, 16, 90),
      shrinkWrap: compact,
      physics: compact
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withAlpha(18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withAlpha(55)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: compact ? 20 : 26),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                body,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppTheme.textMuted,
                  fontSize: compact ? 10 : 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
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

  Future<void> _toggleMilestone(
    TrainingModule module,
    TrainingMilestone milestone,
    bool achieved,
  ) async {
    final program = _program;
    if (program == null) return;
    setState(() => _savingMilestoneIds.add(milestone.id));
    try {
      await _programService.setMilestoneAchievement(
        dogId: widget.dog.id,
        program: program,
        module: module,
        milestone: milestone,
        achieved: achieved,
      );
      if (!mounted) return;
      _showSnackBar(
        achieved ? 'Marco atingido registrado.' : 'Marco desmarcado.',
        AppTheme.success,
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Não foi possível salvar o marco.');
    } finally {
      if (mounted) {
        setState(() => _savingMilestoneIds.remove(milestone.id));
      }
    }
  }

  Future<void> _completeBonusMilestone(TrainingBonusOffer offer) async {
    final program = _program;
    if (program == null) return;
    setState(() => _savingBonusMilestoneIds.add(offer.id));
    try {
      await _programService.completeBonusMilestone(
        dogId: widget.dog.id,
        program: program,
        module: offer.module,
        milestone: offer.milestone,
      );
      if (!mounted) return;
      _showSnackBar(
        'Marco-bonus registrado sem alterar a formacao original.',
        AppTheme.success,
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Não foi possível registrar o marco-bônus.');
    } finally {
      if (mounted) {
        setState(() => _savingBonusMilestoneIds.remove(offer.id));
      }
    }
  }

  Future<void> _requestModulePromotion(TrainingModule module) async {
    final program = _program;
    if (program == null || _completingModule) return;
    setState(() => _completingModule = true);
    try {
      final requestId = await _promotionService.requestPromotion(
        dog: widget.dog,
        program: program,
        progress: _progress,
        module: module,
        requesterRa: _resolveHandlerId(),
        requesterName: _resolveHandlerId(),
        directInstructor: _isInstructorK9,
      );
      if (_isInstructorK9) {
        await _promotionService.decideRequest(
          requestId: requestId,
          approve: true,
        );
      }
      if (!mounted) return;
      _showSnackBar(
        _isInstructorK9
            ? 'Aprovacao enviada. A Function vai aplicar a progressao.'
            : 'Solicitacao enviada aos Instrutores K9.',
        _isInstructorK9 ? AppTheme.success : AppTheme.primary,
      );
    } catch (error) {
      if (!mounted) return;
      _showError(error, 'Não foi possível solicitar a evolução.');
    } finally {
      if (mounted) {
        setState(() => _completingModule = false);
      }
    }
  }

  Widget _buildModuleCard({
    required String number,
    required String title,
    required String subtitle,
    required String status,
    required double progress,
    required bool isCompleted,
    required bool isActive,
    required String progressText,
  }) {
    Color sideColor = AppTheme.textSoft.withAlpha(80);
    Color numBg = AppTheme.textPrimary.withAlpha(20);
    Color numText = AppTheme.textSoft;
    Color statusBg = AppTheme.textPrimary.withAlpha(20);

    if (isCompleted) {
      sideColor = AppTheme.success;
      numBg = AppTheme.success.withAlpha(38);
      numText = AppTheme.success;
      statusBg = AppTheme.success.withAlpha(31);
    } else if (isActive) {
      sideColor = AppTheme.warning;
      numBg = AppTheme.warning.withAlpha(38);
      numText = AppTheme.warning;
      statusBg = AppTheme.warning.withAlpha(31);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isActive
            ? AppTheme.warning.withAlpha(10)
            : AppTheme.textPrimary.withAlpha(13),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: sideColor, width: 3),
          top: BorderSide(color: AppTheme.textPrimary.withAlpha(20), width: 1),
          right: BorderSide(
            color: AppTheme.textPrimary.withAlpha(20),
            width: 1,
          ),
          bottom: BorderSide(
            color: AppTheme.textPrimary.withAlpha(20),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: numBg,
                  border: Border.all(color: numText, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  number,
                  style: GoogleFonts.inter(
                    color: numText,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: AppTheme.textMuted,
                        fontSize: 10,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  status,
                  style: GoogleFonts.inter(
                    color: numText,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                progressText,
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
              if (progress > 0 && progress < 1.0)
                Text(
                  '${(progress * 100).round()}%',
                  style: GoogleFonts.inter(
                    color: AppTheme.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          if (progress > 0) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textPrimary.withAlpha(16),
                borderRadius: BorderRadius.circular(2),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: isCompleted ? AppTheme.success : AppTheme.warning,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- ABA MÓDULO ATUAL ---
  Widget _buildModuloAtualTab() {
    if (!_programLoaded) {
      return _buildProgramState(
        title: 'Carregando currículo',
        body: 'Buscando módulo atual no Firebase.',
        icon: Icons.cloud_sync_rounded,
      );
    }
    if (_programError != null) {
      return _buildProgramState(
        title: 'Falha ao carregar currículo',
        body: _programError.toString(),
        icon: Icons.error_outline_rounded,
        color: AppTheme.error,
      );
    }
    if (_progressError != null) {
      return _buildProgramState(
        title: 'Falha ao carregar progressao',
        body: _progressError.toString(),
        icon: Icons.error_outline_rounded,
        color: AppTheme.error,
      );
    }
    if (!_progressLoaded || _initializingProgress) {
      return _buildProgramState(
        title: 'Preparando progressao',
        body: 'Sincronizando dogs/${widget.dog.id}/training/$_modality.',
        icon: Icons.sync_rounded,
      );
    }
    if (_progress.isOperational) {
      return _buildProgramState(
        title: 'Formacao concluida',
        body:
            'Este cao ja esta operacional em Busca & Captura. Use a aba Operacional para manutencao.',
        icon: Icons.verified_rounded,
        color: AppTheme.success,
      );
    }
    final module = _currentModule;
    if (_program == null || module == null) {
      return _buildProgramState(
        title: 'Sem módulo ativo',
        body:
            'O currículo de Busca & Captura ainda não foi semeado ou não tem módulos ativos.',
        icon: Icons.inventory_2_outlined,
        color: AppTheme.warning,
      );
    }

    final milestones = module.activeMilestones;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        // Detail Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.warning.withAlpha(15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.warning.withAlpha(51), width: 1),
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
                      shape: BoxShape.circle,
                      color: AppTheme.warning.withAlpha(38),
                      border: Border.all(color: AppTheme.warning, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      module.order.toString(),
                      style: GoogleFonts.inter(
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    module.name,
                    style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                module.description,
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: AppTheme.warning.withAlpha(38),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _buildDetailMetaItem('VERSÃO', 'v${_program!.version}'),
                    const SizedBox(width: 24),
                    _buildDetailMetaItem(
                      'MARCOS',
                      milestones.length.toString(),
                    ),
                    const SizedBox(width: 24),
                    _buildDetailMetaItem(
                      'STATUS',
                      _isLocked(module)
                          ? 'Bloqueado'
                          : _isCompleted(module)
                          ? 'Concluído'
                          : 'Atual',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Section Title: Marcos pedagógicos
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'MARCOS PEDAGÓGICOS',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (milestones.isEmpty)
          _buildProgramState(
            title: 'Sem marcos ativos',
            body: 'Cadastre marcos neste módulo do currículo Firebase.',
            icon: Icons.flag_outlined,
            compact: true,
          )
        else
          ...milestones.map((milestone) {
            final achieved = _progress.isMilestoneAchieved(
              module.id,
              milestone.id,
            );
            final saving = _savingMilestoneIds.contains(milestone.id);
            return _buildMarcoItem(
              title: milestone.label,
              subtitle: milestone.isRequired
                  ? 'Marco obrigatório do currículo'
                  : 'Marco opcional do currículo',
              isAtingido: achieved,
              sessionsCount: saving
                  ? 'Salvando'
                  : milestone.isRequired
                  ? 'Obrigatório'
                  : 'Opcional',
              isSaving: saving,
              enabled: _isActive(module) && !_completingModule,
              onTap: () => _toggleMilestone(module, milestone, !achieved),
            );
          }),

        const SizedBox(height: 10),
        if (_isActive(module)) ...[
          _buildCompleteModuleCard(module),
          const SizedBox(height: 10),
        ],
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(10),
            borderRadius: BorderRadius.circular(6),
            border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
          ),
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 11,
                height: 1.5,
              ),
              children: const [
                TextSpan(text: 'Fonte: '),
                TextSpan(
                  text: 'training_programs/busca_captura',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(text: ' · editar no Firebase reflete nesta tela.'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompleteModuleCard(TrainingModule module) {
    final missing = _requiredMissingCount(module);
    final achieved = _achievedCount(module);
    final total = module.activeMilestones.length;
    final canComplete = _canCompleteModule(module);
    final isLast = _isLastModule(module);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: canComplete
            ? AppTheme.success.withAlpha(14)
            : AppTheme.warning.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: canComplete
              ? AppTheme.success.withAlpha(65)
              : AppTheme.warning.withAlpha(55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isLast ? 'Certificar operacional' : 'Solicitar evolucao',
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            missing == 0
                ? '$achieved/$total marcos atingidos. O snapshot sera enviado para validacao.'
                : '$missing marco(s) obrigatorio(s) ainda pendente(s).',
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: canComplete
                  ? () => _requestModulePromotion(module)
                  : null,
              icon: _completingModule
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.background,
                      ),
                    )
                  : Icon(
                      isLast
                          ? Icons.verified_rounded
                          : Icons.arrow_forward_rounded,
                      size: 18,
                    ),
              label: Text(
                _isInstructorK9
                    ? (isLast
                          ? 'VALIDAR E TORNAR OPERACIONAL'
                          : 'VALIDAR EVOLUCAO')
                    : 'SOLICITAR EVOLUCAO',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isLast ? AppTheme.success : AppTheme.primary,
                foregroundColor: AppTheme.background,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailMetaItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 9,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildMarcoItem({
    required String title,
    required String subtitle,
    required bool isAtingido,
    required String sessionsCount,
    required VoidCallback onTap,
    bool isSaving = false,
    bool enabled = true,
  }) {
    final content = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAtingido
            ? AppTheme.success.withAlpha(15)
            : AppTheme.textPrimary.withAlpha(13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isAtingido
              ? AppTheme.success.withAlpha(64)
              : AppTheme.textPrimary.withAlpha(20),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isAtingido
                    ? AppTheme.success
                    : AppTheme.textPrimary.withAlpha(51),
                width: 1.5,
              ),
              color: isAtingido ? AppTheme.success : AppTheme.transparent,
            ),
            alignment: Alignment.center,
            child: isSaving
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.success,
                    ),
                  )
                : Icon(
                    Icons.check_rounded,
                    color: isAtingido
                        ? AppTheme.background
                        : AppTheme.transparent,
                    size: 14,
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
                    color: enabled ? AppTheme.textPrimary : AppTheme.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              sessionsCount,
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.62,
      child: GestureDetector(
        onTap: enabled && !isSaving ? onTap : null,
        child: content,
      ),
    );
  }

  // --- ABA HISTORICO ---
  Widget _buildHistoricoTab() {
    if (!_sessionsLoaded) {
      return _buildProgramState(
        icon: Icons.hourglass_top_rounded,
        title: 'Carregando historico',
        body: 'Buscando sessoes reais de Busca & Captura.',
      );
    }
    if (_sessionsError != null) {
      return _buildProgramState(
        icon: Icons.warning_amber_rounded,
        title: 'Falha ao carregar historico',
        body: _sessionsError.toString(),
        color: AppTheme.error,
      );
    }
    if (_bcSessions.isEmpty) {
      return _buildProgramState(
        icon: Icons.history_rounded,
        title: 'Nenhuma sessao registrada',
        body:
            'Quando uma trilha de Busca & Captura for salva, ela aparece aqui com modulo, marco, resultado e metricas.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        Text(
          'SESSOES REGISTRADAS',
          style: GoogleFonts.inter(
            color: AppTheme.primary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        ..._bcSessions.map(_buildTrailSessionCard),
      ],
    );
  }

  // --- ABA ESTATISTICAS ---
  Widget _buildEstatisticasTab() {
    if (!_sessionsLoaded) {
      return _buildProgramState(
        icon: Icons.hourglass_top_rounded,
        title: 'Carregando estatisticas',
        body: 'Calculando metricas com as sessoes reais de B&C.',
      );
    }
    if (_sessionsError != null) {
      return _buildProgramState(
        icon: Icons.warning_amber_rounded,
        title: 'Falha ao carregar estatisticas',
        body: _sessionsError.toString(),
        color: AppTheme.error,
      );
    }
    if (_bcSessions.isEmpty) {
      return _buildProgramState(
        icon: Icons.analytics_outlined,
        title: 'Sem estatisticas ainda',
        body:
            'As medias e distribuicoes aparecem depois da primeira sessao de trilha salva.',
      );
    }

    final sessionsWithDistance = _bcSessions
        .where((session) => _distanceMetersFor(session) > 0)
        .toList();
    final sessionsWithDuration = _bcSessions
        .where((session) => _durationSecondsFor(session) > 0)
        .toList();
    final avgDistance = sessionsWithDistance.isEmpty
        ? 0.0
        : sessionsWithDistance.map(_distanceMetersFor).reduce((a, b) => a + b) /
              sessionsWithDistance.length;
    final avgDuration = sessionsWithDuration.isEmpty
        ? 0
        : (sessionsWithDuration
                      .map(_durationSecondsFor)
                      .reduce((a, b) => a + b) /
                  sessionsWithDuration.length)
              .round();
    final lastSeven = _bcSessions.take(7).toList().reversed.toList();
    final maxDistance = lastSeven
        .map(_distanceMetersFor)
        .fold<double>(0, (max, value) => value > max ? value : max);
    final resultCounts = <String, int>{
      'completa': 0,
      'parcial': 0,
      'sem_exito': 0,
    };
    for (final session in _bcSessions) {
      final result = _resultFor(session);
      resultCounts[result] = (resultCounts[result] ?? 0) + 1;
    }
    final totalResults = _bcSessions.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                value: _formatDistance(avgDistance),
                label: 'DISTANCIA MEDIA',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricCard(
                value: _formatDuration(avgDuration),
                label: 'TEMPO MEDIO',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.textPrimary.withAlpha(13),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.textPrimary.withAlpha(20)),
          ),
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DISTANCIA POR SESSAO (ULTIMAS ${lastSeven.length})',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDistance(maxDistance),
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 9,
                    ),
                  ),
                  Text(
                    '0m',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: lastSeven.map((session) {
                    final distance = _distanceMetersFor(session);
                    final ratio = maxDistance <= 0
                        ? 0.08
                        : distance / maxDistance;
                    final height = 10 + (ratio.clamp(0.08, 1.0) * 90);
                    return _buildChartBar(
                      height: height,
                      highlight: session.date.isAfter(
                        DateTime.now().subtract(const Duration(days: 7)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatShortDate(lastSeven.first.date),
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 9,
                    ),
                  ),
                  Text(
                    _formatShortDate(lastSeven.last.date),
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.textPrimary.withAlpha(13),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.textPrimary.withAlpha(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DISTRIBUICAO DE RESULTADOS',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              _buildDistributionRow(
                'Completa',
                resultCounts['completa']! / totalResults,
                '${((resultCounts['completa']! / totalResults) * 100).round()}%',
                AppTheme.success,
              ),
              const SizedBox(height: 8),
              _buildDistributionRow(
                'Parcial',
                resultCounts['parcial']! / totalResults,
                '${((resultCounts['parcial']! / totalResults) * 100).round()}%',
                AppTheme.warning,
              ),
              const SizedBox(height: 8),
              _buildDistributionRow(
                'Sem exito',
                resultCounts['sem_exito']! / totalResults,
                '${((resultCounts['sem_exito']! / totalResults) * 100).round()}%',
                AppTheme.attention,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrailSessionCard(TrainingHubSession session) {
    final distance = _formatDistance(_distanceMetersFor(session));
    final duration = _formatDuration(_durationSecondsFor(session));
    final result = _resultFor(session);
    final notes = session.notes.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textPrimary.withAlpha(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withAlpha(18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withAlpha(55)),
                ),
                child: const Icon(
                  Icons.route_rounded,
                  color: AppTheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _milestoneLabelFor(session),
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_moduleLabelFor(session)} - ${_formatShortDate(session.date)}',
                      style: GoogleFonts.inter(
                        color: AppTheme.textMuted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _resultColor(result).withAlpha(22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _resultLabel(result).toUpperCase(),
                  style: GoogleFonts.inter(
                    color: _resultColor(result),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSessionMeta(Icons.straighten_rounded, distance),
              const SizedBox(width: 12),
              _buildSessionMeta(Icons.timer_outlined, duration),
              const SizedBox(width: 12),
              _buildSessionMeta(
                Icons.person_outline_rounded,
                session.handlerId.isEmpty
                    ? _resolveHandlerId()
                    : session.handlerId,
              ),
            ],
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              notes,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionMeta(IconData icon, String value) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textMuted, size: 14),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.ibmPlexMono(
                color: AppTheme.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _resultColor(String result) {
    switch (result) {
      case 'completa':
        return AppTheme.success;
      case 'sem_exito':
        return AppTheme.attention;
      default:
        return AppTheme.warning;
    }
  }

  Widget _buildMetricCard({required String value, required String label}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.textPrimary.withAlpha(20)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: AppTheme.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartBar({required double height, bool highlight = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: highlight
                  ? [AppTheme.warning, AppTheme.warning.withAlpha(77)]
                  : [AppTheme.primary, AppTheme.primary.withAlpha(77)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDistributionRow(
    String label,
    double percent,
    String percentText,
    Color color,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: AppTheme.textPrimary.withAlpha(13),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: percent,
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 36,
          child: Text(
            percentText,
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
