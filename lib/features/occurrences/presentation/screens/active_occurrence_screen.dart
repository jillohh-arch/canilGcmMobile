import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:canil_gcm/core/services/location_resolution_service.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event_category.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_nature.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/active_occurrence_context_card.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/active_occurrence_finalize_cta.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/active_occurrence_quick_grid.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/active_occurrence_timeline.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

import 'edit_event_screen.dart';
import 'edit_event_location_screen.dart';
import 'finalize_occurrence_screen.dart';
import 'occurrence_team_screen.dart';

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
      if (_elapsed.inSeconds <= 0 || !mounted) return;
      final vm = context.read<OccurrenceViewModel>();
      final authVM = context.read<AuthViewModel>();
      final occurrence = _currentOccurrence(vm);
      final currentRa = HandlerIdentityService.raFromUser(authVM.user);
      if (!_canCurrentUserEditOccurrence(
        occurrence,
        currentRa: currentRa,
        currentUid: authVM.user?.uid,
        currentEmail: authVM.user?.email,
      )) {
        return;
      }
      vm.updateDurationSoFar(widget.occurrenceId, _elapsed.inSeconds);
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
    final authVM = context.read<AuthViewModel>();
    final now = DateTime.now();
    final handlerRa = HandlerIdentityService.raFromUser(authVM.user);

    double? lat, lng;
    String? placeLabel;
    try {
      final loc = await _locationService.currentHighAccuracy();
      lat = loc.point.latitude;
      lng = loc.point.longitude;
      placeLabel = loc.address;
    } catch (_) {
      // GPS indisponível — continua sem coordenadas
    }

    final event = OccurrenceEvent(
      id: const Uuid().v4(),
      occurrenceId: widget.occurrenceId,
      category: item.category,
      timestamp: now,
      title: item.autoTitle,
      dogHandlerId: item.category == OccurrenceEventCategory.dogWork
          ? handlerRa
          : null,
      gpsLat: lat,
      gpsLng: lng,
      placeLabel: placeLabel,
      locationSource: lat != null && lng != null ? 'gps_atual' : null,
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
        AppFeedback.error(context, e);
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
    final authVM = context.read<AuthViewModel>();
    final occurrence = _currentOccurrence(vm);
    final currentRa = HandlerIdentityService.raFromUser(authVM.user);
    if (!_canCurrentUserFinalizeOccurrence(
      occurrence,
      currentRa: currentRa,
      currentUid: authVM.user?.uid,
    )) {
      _showNotEditableMessage();
      return;
    }
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

  void _openTeamManagement() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => OccurrenceTeamScreen(occurrenceId: widget.occurrenceId),
      ),
    );
    if (!mounted) return;
    await _loadOccurrence();
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
        backgroundColor: AppTheme.surfaceSheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Nenhum evento registrado',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Deseja finalizar a ocorrência sem nenhum evento?',
          style: GoogleFonts.inter(color: AppTheme.textPrimary.withAlpha(179)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(138),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _navigateToFinalize();
            },
            child: Text(
              'Finalizar',
              style: GoogleFonts.inter(color: AppTheme.error),
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
        backgroundColor: AppTheme.surfaceSheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Editar dados da ocorrência',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
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
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Endereço',
                  hintStyle: GoogleFonts.inter(
                    color: AppTheme.textPrimary.withAlpha(97),
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: AppTheme.textPrimary.withAlpha(8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: AppTheme.textPrimary.withAlpha(20),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: AppTheme.textPrimary.withAlpha(20),
                    ),
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
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Observação (opcional)',
                  hintStyle: GoogleFonts.inter(
                    color: AppTheme.textPrimary.withAlpha(97),
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: AppTheme.textPrimary.withAlpha(8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: AppTheme.textPrimary.withAlpha(20),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: AppTheme.textPrimary.withAlpha(20),
                    ),
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
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(138),
              ),
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

  void _showEditNatureSheet(OccurrenceViewModel vm, Occurrence? occ) {
    if (occ == null) return;

    final natures = vm.natures;
    final searchCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfacePanelSoft,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return _EditNatureSheetContent(
              natures: natures,
              currentTypeCode: occ.typeCode,
              currentTypeName: occ.typeName,
              searchController: searchCtrl,
              scrollController: scrollController,
              onSelected: (nature) async {
                if (nature.code == occ.typeCode) {
                  Navigator.of(ctx).pop();
                  return;
                }
                Navigator.of(ctx).pop();
                await vm.updateOccurrence(occ.id, {
                  'type_code': nature.code,
                  'type_name': nature.name,
                });
                if (mounted) _showSavedFeedback();
              },
            );
          },
        );
      },
    );
  }

  void _showDiscardDialog(OccurrenceViewModel vm) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceSheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Descartar ocorrência?',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Esta ação não pode ser desfeita. A ocorrência será marcada como descartada.',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(179),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Motivo (obrigatório)',
                hintStyle: GoogleFonts.inter(
                  color: AppTheme.textPrimary.withAlpha(97),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: AppTheme.textPrimary.withAlpha(8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: AppTheme.textPrimary.withAlpha(20),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: AppTheme.textPrimary.withAlpha(20),
                  ),
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
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(138),
              ),
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

  void _showLockedForSignaturesMessage() {
    AppFeedback.warning(
      context,
      'Ocorrência fechada para assinaturas. Use a tela de equipe.',
    );
  }

  void _showNotEditableMessage() {
    AppFeedback.warning(
      context,
      'Sem permissão de edição para esta ocorrência.',
    );
  }

  bool _canCurrentUserEditOccurrence(
    Occurrence? occurrence, {
    required String? currentRa,
    required String? currentUid,
    required String? currentEmail,
  }) {
    if (occurrence == null || !occurrence.status.isOpen) return false;
    if (_isCurrentUserPrimary(
      occurrence,
      currentRa: currentRa,
      currentUid: currentUid,
    )) {
      return true;
    }

    final ra = currentRa?.trim();
    final email = currentEmail?.trim().toLowerCase();
    final uid = currentUid?.trim();
    if (ra == null && email == null && uid == null) return false;
    if (ra != null && occurrence.declinedHandlerIds.contains(ra)) {
      return false;
    }
    if (occurrence.participationRevision > 0) {
      return ra != null && occurrence.acceptedHandlerIds.contains(ra);
    }

    final authorizedIds = occurrence.editAuthorizedHandlerIds;
    final authorizedEmails = occurrence.editAuthorizedEmails;
    if (authorizedIds.isNotEmpty || authorizedEmails.isNotEmpty) {
      return (ra != null && authorizedIds.contains(ra)) ||
          (email != null && authorizedEmails.contains(email));
    }

    return occurrence.team.any((member) {
      return (ra != null && member.handlerId == ra) ||
          (uid != null && member.authUid == uid) ||
          (email != null && member.handlerEmail?.trim().toLowerCase() == email);
    });
  }

  bool _canCurrentUserFinalizeOccurrence(
    Occurrence? occurrence, {
    required String? currentRa,
    required String? currentUid,
  }) {
    if (occurrence == null || !occurrence.status.isOpen) return false;
    return _isCurrentUserPrimary(
      occurrence,
      currentRa: currentRa,
      currentUid: currentUid,
    );
  }

  bool _isCurrentUserPrimary(
    Occurrence occurrence, {
    required String? currentRa,
    required String? currentUid,
  }) {
    final ra = currentRa?.trim();
    final uid = currentUid?.trim();
    final createdBy = occurrence.createdBy ?? const <String, dynamic>{};
    return (uid != null &&
            uid.isNotEmpty &&
            (occurrence.primaryHandlerId == uid || createdBy['uid'] == uid)) ||
        (ra != null &&
            ra.isNotEmpty &&
            (occurrence.primaryHandlerRa == ra ||
                occurrence.primaryHandlerId == ra ||
                createdBy['ra'] == ra));
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
    final canEditOccurrence = _canCurrentUserEditOccurrence(
      occ,
      currentRa: handlerRa,
      currentUid: authVM.user?.uid,
      currentEmail: authVM.user?.email,
    );
    final canFinalizeOccurrence = _canCurrentUserFinalizeOccurrence(
      occ,
      currentRa: handlerRa,
      currentUid: authVM.user?.uid,
    );
    final handlerUser = userVM.findByRa(handlerRa);
    final handlerName = userVM.displayNameFor(
      ra: handlerRa,
      firebaseUser: authVM.user,
    );
    final handlerImageUrl = handlerUser?.photoUrl ?? authVM.user?.photoURL;

    final typeName = occ?.typeName ?? 'Ocorrência';
    final isAwaitingSignatures =
        occ?.status == OccurrenceStatus.awaitingSignatures;
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
                    onEditData: !canEditOccurrence
                        ? null
                        : () => _showEditOccurrenceDialog(vm, occ),
                    onEditNature: !canEditOccurrence
                        ? null
                        : () => _showEditNatureSheet(vm, occ),
                    onDiscard: !canFinalizeOccurrence
                        ? null
                        : () => _showDiscardDialog(vm),
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
                    team: occ?.team ?? const [],
                    teamSizeMax: occ?.teamSizeMax ?? 3,
                    onTeamTap: occ == null ? null : _openTeamManagement,
                  ),
                  const SizedBox(height: 24),
                  if (isAwaitingSignatures)
                    _AwaitingSignaturesNotice(onOpenTeam: _openTeamManagement)
                  else if (!canEditOccurrence)
                    _ReadOnlyOccurrenceNotice(onOpenTeam: _openTeamManagement)
                  else
                    ActiveOccurrenceQuickGrid(
                      onQuickEvent: _addQuickEvent,
                      onOtherEvent: _openOtherEventSheet,
                      isLoading: _isAddingEvent,
                    ),
                  const SizedBox(height: 24),
                  ActiveOccurrenceTimeline(
                    events: vm.events,
                    onEventTap: isAwaitingSignatures
                        ? (_) => _showLockedForSignaturesMessage()
                        : canEditOccurrence
                        ? _onEventTap
                        : (_) => _showNotEditableMessage(),
                    onLocationTap: canEditOccurrence ? _onLocationTap : null,
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
              child: isAwaitingSignatures || !canFinalizeOccurrence
                  ? const SizedBox.shrink()
                  : ActiveOccurrenceFinalizeCta(onFinalize: _onFinalize),
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
  final VoidCallback? onEditNature;
  final VoidCallback? onDiscard;

  const _Header({
    required this.typeName,
    required this.durationLabel,
    required this.eventCount,
    required this.onBack,
    this.onEditData,
    this.onEditNature,
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
                color: AppTheme.textPrimary.withAlpha(10),
                border: Border.all(color: AppTheme.textPrimary.withAlpha(20)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                color: AppTheme.textPrimary,
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        typeName,
                        style: GoogleFonts.inter(
                          color: AppTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    if (onEditNature != null) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: onEditNature,
                        child: Icon(
                          Icons.edit_outlined,
                          color: AppTheme.primary.withAlpha(180),
                          size: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (onEditData != null || onDiscard != null)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: AppTheme.textPrimary.withAlpha(180),
                size: 22,
              ),
              color: AppTheme.surfaceSheet,
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
                if (onEditData != null)
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
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (onDiscard != null)
                  PopupMenuItem(
                    value: 'discard',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          color: AppTheme.error,
                          size: 18,
                        ),
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
          color: AppTheme.errorStrong.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.errorStrong.withAlpha(80)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppTheme.errorStrong,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sincronização com falha. Toque para tentar novamente.',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary.withAlpha(200),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(
              Icons.refresh_rounded,
              color: AppTheme.primary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _AwaitingSignaturesNotice extends StatelessWidget {
  final VoidCallback onOpenTeam;

  const _AwaitingSignaturesNotice({required this.onOpenTeam});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lock_clock_rounded,
                color: AppTheme.primary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Aguardando assinaturas',
                  style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'O registro está travado para edição até a conclusão das assinaturas.',
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary.withAlpha(170),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: onOpenTeam,
              icon: const Icon(Icons.groups_rounded, size: 18),
              label: const Text('Ver equipe'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyOccurrenceNotice extends StatelessWidget {
  final VoidCallback onOpenTeam;

  const _ReadOnlyOccurrenceNotice({required this.onOpenTeam});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.textPrimary.withAlpha(6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textPrimary.withAlpha(18)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.visibility_outlined,
            color: AppTheme.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Visualização sem edição para este condutor.',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(180),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          TextButton(onPressed: onOpenTeam, child: const Text('Equipe')),
        ],
      ),
    );
  }
}

class _EditNatureSheetContent extends StatefulWidget {
  final List<OccurrenceNature> natures;
  final String currentTypeCode;
  final String currentTypeName;
  final TextEditingController searchController;
  final ScrollController scrollController;
  final ValueChanged<OccurrenceNature> onSelected;

  const _EditNatureSheetContent({
    required this.natures,
    required this.currentTypeCode,
    required this.currentTypeName,
    required this.searchController,
    required this.scrollController,
    required this.onSelected,
  });

  @override
  State<_EditNatureSheetContent> createState() =>
      _EditNatureSheetContentState();
}

class _EditNatureSheetContentState extends State<_EditNatureSheetContent> {
  String _query = '';

  List<OccurrenceNature> get _filtered {
    if (_query.isEmpty) return widget.natures;
    return widget.natures.where((n) => n.matches(_query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textPrimary.withAlpha(40),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'ALTERAR NATUREZA',
            style: GoogleFonts.inter(
              color: AppTheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Atual: ${widget.currentTypeName}',
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary.withAlpha(120),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: widget.searchController,
            onChanged: (v) => setState(() => _query = v),
            style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Buscar natureza...',
              hintStyle: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(97),
                fontSize: 14,
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: AppTheme.primary,
                size: 18,
              ),
              filled: true,
              fillColor: AppTheme.textPrimary.withAlpha(8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppTheme.textPrimary.withAlpha(20),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppTheme.textPrimary.withAlpha(20),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.primary),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final nature = filtered[i];
                final isCurrent = nature.code == widget.currentTypeCode;
                return GestureDetector(
                  onTap: () => widget.onSelected(nature),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? AppTheme.primary.withAlpha(20)
                          : AppTheme.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isCurrent
                          ? Border.all(color: AppTheme.primary.withAlpha(60))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nature.name,
                                style: GoogleFonts.inter(
                                  color: isCurrent
                                      ? AppTheme.primary
                                      : AppTheme.textPrimary,
                                  fontSize: 14,
                                  fontWeight: isCurrent
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${nature.code} · ${nature.group}',
                                style: GoogleFonts.inter(
                                  color: AppTheme.textPrimary.withAlpha(80),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isCurrent)
                          Icon(
                            Icons.check_circle,
                            color: AppTheme.primary,
                            size: 18,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
