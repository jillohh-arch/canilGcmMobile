import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:canil_gcm/core/services/location_resolution_service.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/active_occurrence_context_card.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/active_occurrence_finalize_cta.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/active_occurrence_quick_grid.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/active_occurrence_timeline.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

import 'edit_event_screen.dart';
import 'edit_event_location_screen.dart';
import 'finalize_occurrence_screen.dart';

class ActiveOccurrenceScreen extends StatefulWidget {
  final String occurrenceId;

  const ActiveOccurrenceScreen({super.key, required this.occurrenceId});

  @override
  State<ActiveOccurrenceScreen> createState() => _ActiveOccurrenceScreenState();
}

class _ActiveOccurrenceScreenState extends State<ActiveOccurrenceScreen> {
  final _locationService = const LocationResolutionService();
  Timer? _durationTimer;
  Timer? _durationPersistTimer;
  Timer? _savedBadgeTimer;
  Duration _elapsed = Duration.zero;
  DateTime? _startedAt;
  Occurrence? _loadedOccurrence;
  bool _showSavedBadge = false;
  bool _isAddingEvent = false;

  @override
  void initState() {
    super.initState();
    final vm = context.read<OccurrenceViewModel>();
    vm.watchEvents(widget.occurrenceId);
    _loadOccurrence();

    _startedAt = _currentOccurrence(vm)?.startedAt;
    _updateElapsed();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateElapsed();
    });

    _durationPersistTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_elapsed.inSeconds > 0) {
        context.read<OccurrenceViewModel>().updateDurationSoFar(
          widget.occurrenceId,
          _elapsed.inSeconds,
        );
      }
    });
  }

  Occurrence? _currentOccurrence(OccurrenceViewModel vm) {
    final open = vm.openOccurrence;
    if (open != null && open.id == widget.occurrenceId) return open;
    return _loadedOccurrence;
  }

  Future<void> _loadOccurrence() async {
    final vm = context.read<OccurrenceViewModel>();
    final loaded = await vm.getById(widget.occurrenceId);
    if (!mounted) return;
    setState(() {
      _loadedOccurrence = loaded;
      _startedAt ??= loaded?.startedAt;
    });
    _updateElapsed();
  }

  void _updateElapsed() {
    if (_startedAt == null) {
      final vm = context.read<OccurrenceViewModel>();
      _startedAt = _currentOccurrence(vm)?.startedAt;
    }
    if (_startedAt != null) {
      setState(() {
        _elapsed = DateTime.now().difference(_startedAt!);
      });
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _durationPersistTimer?.cancel();
    _savedBadgeTimer?.cancel();
    super.dispose();
  }

  String get _durationLabel {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes.remainder(60);
    final s = _elapsed.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}min';
    if (m > 0) return '${m}min ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  void _showSavedFeedback() {
    _savedBadgeTimer?.cancel();
    setState(() => _showSavedBadge = true);
    _savedBadgeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showSavedBadge = false);
    });
  }

  Future<void> _addQuickEvent(QuickEventItem item) async {
    setState(() => _isAddingEvent = true);
    HapticFeedback.lightImpact();

    final vm = context.read<OccurrenceViewModel>();
    final now = DateTime.now();

    double? lat, lng;
    try {
      final loc = await _locationService.currentHighAccuracy();
      lat = loc.point.latitude;
      lng = loc.point.longitude;
    } catch (_) {
      // GPS indisponível — continua sem coordenadas
    }

    final event = OccurrenceEvent(
      id: const Uuid().v4(),
      occurrenceId: widget.occurrenceId,
      category: item.category,
      timestamp: now,
      title: item.autoTitle,
      gpsLat: lat,
      gpsLng: lng,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await vm.addEvent(event);
      if (mounted) {
        _showSavedFeedback();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao registrar evento: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAddingEvent = false);
    }
  }

  void _openOtherEventSheet() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditEventScreen(occurrenceId: widget.occurrenceId),
      ),
    );
    if (result == 'saved' && mounted) {
      _showSavedFeedback();
    }
  }

  void _onEventTap(OccurrenceEvent event) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditEventScreen(
          occurrenceId: widget.occurrenceId,
          existingEvent: event,
        ),
      ),
    );
    if (result == 'saved' || result == 'deleted') {
      if (mounted) _showSavedFeedback();
    }
  }

  void _onLocationTap(OccurrenceEvent event) async {
    final vm = context.read<OccurrenceViewModel>();
    final totalEvents = vm.events.length;
    final eventIndex = vm.events.indexOf(event) + 1;

    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (_) => EditEventLocationScreen(
          event: event,
          eventIndex: eventIndex > 0 ? eventIndex : 1,
          totalEvents: totalEvents > 0 ? totalEvents : 1,
        ),
      ),
    );

    if (result == true && mounted) {
      _showSavedFeedback();
    }
  }

  void _onFinalize() {
    final vm = context.read<OccurrenceViewModel>();
    if (vm.events.isEmpty) {
      _showEmptyFinalizeDialog();
    } else {
      _navigateToFinalize();
    }
  }

  void _navigateToFinalize() async {
    final vm = context.read<OccurrenceViewModel>();
    final dogVM = context.read<DogViewModel>();
    final authVM = context.read<AuthViewModel>();
    final userVM = context.read<UserViewModel>();

    final occ = _currentOccurrence(vm);
    final dogs = dogVM.dogs.where((d) => d.id == occ?.dogId);
    final dog = dogs.isNotEmpty ? dogs.first : null;
    final dogName = dog?.name ?? 'K9';
    final handlerRa = HandlerIdentityService.raFromUser(authVM.user);
    final handlerName = userVM.displayNameFor(
      ra: handlerRa,
      firebaseUser: authVM.user,
    );

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => FinalizeOccurrenceScreen(
          occurrenceId: widget.occurrenceId,
          typeName: occ?.typeName ?? '',
          durationLabel: _durationLabel,
          eventCount: vm.events.length,
          dogName: dogName,
          handlerName: handlerName,
          locationAddress: occ?.locationAddress,
        ),
      ),
    );
    if (result == 'finalized' && mounted) {
      Navigator.of(context).pop();
    }
  }

  String _translateError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('permission') || lower.contains('permission_denied')) {
      return 'Sem permissão para acessar esses dados.';
    }
    if (lower.contains('failed-precondition') ||
        lower.contains('precondition')) {
      return 'Erro de configuração do servidor.';
    }
    if (lower.contains('unavailable') || lower.contains('network')) {
      return 'Sem conexão com o servidor.';
    }
    if (lower.contains('not-found')) {
      return 'Dados não encontrados.';
    }
    return 'Erro ao carregar dados. Tente novamente.';
  }

  void _showEmptyFinalizeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F2027),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Nenhum evento registrado',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Deseja finalizar a ocorrência sem nenhum evento?',
          style: GoogleFonts.inter(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _navigateToFinalize();
            },
            child: Text(
              'Finalizar',
              style: GoogleFonts.inter(color: const Color(0xFFE74C3C)),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditOccurrenceDialog(OccurrenceViewModel vm, Occurrence? occ) {
    if (occ == null) return;
    final locationCtrl = TextEditingController(text: occ.locationAddress ?? '');
    final observationCtrl = TextEditingController(
      text: occ.initialObservation ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F2027),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Editar dados da ocorrência',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LOCAL',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: locationCtrl,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Endereço',
                  hintStyle: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 14,
                  ),
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
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.primary),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'OBSERVAÇÃO INICIAL',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: observationCtrl,
                maxLines: 3,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Observação (opcional)',
                  hintStyle: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 14,
                  ),
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
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.primary),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () async {
              final updates = <String, dynamic>{};
              final newLocation = locationCtrl.text.trim();
              final newObs = observationCtrl.text.trim();

              if (newLocation != (occ.locationAddress ?? '')) {
                updates['location_address'] = newLocation;
              }
              if (newObs != (occ.initialObservation ?? '')) {
                updates['initial_observation'] = newObs;
              }

              if (updates.isEmpty) {
                Navigator.of(ctx).pop();
                return;
              }

              Navigator.of(ctx).pop();
              await vm.updateOccurrence(occ.id, updates);
              if (mounted) _showSavedFeedback();
            },
            child: Text(
              'Salvar',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDiscardDialog(OccurrenceViewModel vm) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F2027),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Descartar ocorrência?',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Esta ação não pode ser desfeita. A ocorrência será marcada como descartada.',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Motivo (obrigatório)',
                hintStyle: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 14,
                ),
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
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppTheme.error),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) return;
              Navigator.of(ctx).pop();
              final authVM = context.read<AuthViewModel>();
              final userId = authVM.user?.uid ?? '';
              await vm.cancelOccurrence(widget.occurrenceId, userId, reason);
              if (mounted) Navigator.of(context).pop();
            },
            child: Text(
              'Descartar',
              style: GoogleFonts.inter(
                color: AppTheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<OccurrenceViewModel>();
    final dogVM = context.watch<DogViewModel>();
    final authVM = context.watch<AuthViewModel>();
    final userVM = context.watch<UserViewModel>();
    final occ = _currentOccurrence(vm);

    // Resolve dog name and photo from dogId
    final dogId = occ?.dogId;
    final dogs = dogVM.dogs.where((d) => d.id == dogId);
    final dog = dogs.isNotEmpty ? dogs.first : null;
    final dogName = dog?.name ?? 'K9';
    final dogImageUrl = dog?.profileImageUrl;

    // Resolve handler name and photo from primaryHandlerId (Firebase UID → RA → UserModel)
    final handlerRa = HandlerIdentityService.raFromUser(authVM.user);
    final handlerUser = userVM.findByRa(handlerRa);
    final handlerName = userVM.displayNameFor(
      ra: handlerRa,
      firebaseUser: authVM.user,
    );
    final handlerImageUrl = handlerUser?.photoUrl ?? authVM.user?.photoURL;

    final typeName = occ?.typeName ?? 'Ocorrência';
    final locationAddress = occ?.locationAddress ?? '';
    final startedAtLabel = _startedAt != null
        ? '${_startedAt!.hour.toString().padLeft(2, '0')}:${_startedAt!.minute.toString().padLeft(2, '0')}'
        : '--:--';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(
                    typeName: typeName,
                    durationLabel: _durationLabel,
                    eventCount: vm.events.length,
                    onBack: () => Navigator.of(context).pop(),
                    onEditData: () => _showEditOccurrenceDialog(vm, occ),
                    onDiscard: () => _showDiscardDialog(vm),
                  ),
                  if (vm.error != null)
                    _SyncErrorBanner(
                      onRetry: () {
                        vm.clearError();
                        vm.watchEvents(widget.occurrenceId);
                      },
                    ),
                  AnimatedOpacity(
                    opacity: _showSavedBadge ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: _showSavedBadge
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  color: AppTheme.success,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Salvo agora',
                                  style: GoogleFonts.inter(
                                    color: AppTheme.success,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 16),
                  ActiveOccurrenceContextCard(
                    typeName: typeName,
                    dogName: dogName,
                    dogImageUrl: dogImageUrl,
                    handlerName: handlerName,
                    handlerImageUrl: handlerImageUrl,
                    locationAddress: locationAddress,
                    startedAtLabel: startedAtLabel,
                    durationLabel: _durationLabel,
                    eventCount: vm.events.length,
                  ),
                  const SizedBox(height: 24),
                  ActiveOccurrenceQuickGrid(
                    onQuickEvent: _addQuickEvent,
                    onOtherEvent: _openOtherEventSheet,
                    isLoading: _isAddingEvent,
                  ),
                  const SizedBox(height: 24),
                  ActiveOccurrenceTimeline(
                    events: vm.events,
                    onEventTap: _onEventTap,
                    onLocationTap: _onLocationTap,
                    handlerName: handlerName,
                    locationLabel: locationAddress.isNotEmpty
                        ? locationAddress
                        : null,
                    errorMessage: vm.error != null
                        ? _translateError(vm.error!)
                        : null,
                    onRetry: vm.error != null
                        ? () {
                            vm.clearError();
                            vm.watchEvents(widget.occurrenceId);
                          }
                        : null,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ActiveOccurrenceFinalizeCta(onFinalize: _onFinalize),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String typeName;
  final String durationLabel;
  final int eventCount;
  final VoidCallback onBack;
  final VoidCallback? onEditData;
  final VoidCallback? onDiscard;

  const _Header({
    required this.typeName,
    required this.durationLabel,
    required this.eventCount,
    required this.onBack,
    this.onEditData,
    this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle =
        'Em andamento · $durationLabel · $eventCount evento${eventCount != 1 ? 's' : ''}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onBack();
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(10),
                border: Border.all(color: Colors.white.withAlpha(20)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: AppTheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  typeName,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: Colors.white.withAlpha(180),
              size: 22,
            ),
            color: const Color(0xFF0F2027),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) {
              if (value == 'edit') {
                onEditData?.call();
              } else if (value == 'discard') {
                onDiscard?.call();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      color: AppTheme.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Editar dados',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'discard',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: AppTheme.error, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      'Descartar ocorrência',
                      style: GoogleFonts.inter(
                        color: AppTheme.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncErrorBanner extends StatelessWidget {
  final VoidCallback onRetry;

  const _SyncErrorBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE53935).withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE53935).withAlpha(80)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFE53935),
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sincronização com falha. Toque para tentar novamente.',
                style: GoogleFonts.inter(
                  color: Colors.white.withAlpha(200),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(
              Icons.refresh_rounded,
              color: Color(0xFF4DD0E1),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
