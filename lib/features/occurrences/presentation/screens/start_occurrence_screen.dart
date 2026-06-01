import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:canil_gcm/core/domain/occurrence_team_member.dart';
import 'package:canil_gcm/core/services/location_resolution_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_nature.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/start_occurrence_binomio.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/start_occurrence_cta.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/start_occurrence_header.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/start_occurrence_info_grid.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/start_occurrence_nature_link.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/start_occurrence_observation.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/start_occurrence_time_chips.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/active_occurrence_screen.dart';
import 'package:canil_gcm/features/shifts/data/vehicle_crew_service.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

class StartOccurrenceScreen extends StatefulWidget {
  const StartOccurrenceScreen({super.key});

  @override
  State<StartOccurrenceScreen> createState() => _StartOccurrenceScreenState();
}

class _StartOccurrenceScreenState extends State<StartOccurrenceScreen> {
  final _locationService = const LocationResolutionService();
  final _crewService = VehicleCrewService();
  final _natureController = TextEditingController();
  final _natureFocusNode = FocusNode();
  final _observationController = TextEditingController();

  // GPS state
  String _locationAddress = '';
  double? _gpsLat;
  double? _gpsLng;
  double? _gpsAccuracy;
  bool _isLoadingGps = true;
  bool _manualLocationSet = false;
  GpsPrecision _gpsPrecision = GpsPrecision.unavailable;

  // Time state
  DateTime _startedAt = DateTime.now();
  int _selectedTimeChip = 0;

  // Nature state
  bool _natureExpanded = false;
  OccurrenceNature? _selectedNature;
  List<OccurrenceNature> _natures = [];

  // Loading
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _captureGps();
    _loadNatures();
    _checkOpenOccurrence();
  }

  @override
  void dispose() {
    _natureController.dispose();
    _natureFocusNode.dispose();
    _observationController.dispose();
    super.dispose();
  }

  bool get _hasUnsavedData =>
      _selectedNature != null ||
      _observationController.text.isNotEmpty ||
      _locationAddress.trim().isNotEmpty ||
      _manualLocationSet ||
      _selectedTimeChip != 0;

  bool get _ctaEnabled =>
      _selectedNature != null &&
      (_locationAddress.trim().isNotEmpty ||
          _gpsLat != null ||
          _manualLocationSet);

  // ─── GPS ────────────────────────────────────────────────────────────

  Future<void> _captureGps() async {
    setState(() => _isLoadingGps = true);
    try {
      final resolved = await _locationService.currentHighAccuracy();
      if (!mounted) return;
      setState(() {
        _locationAddress = resolved.address;
        _gpsLat = resolved.point.latitude;
        _gpsLng = resolved.point.longitude;
        _gpsAccuracy = resolved.accuracy;
        _gpsPrecision = _precisionFromAccuracy(resolved.accuracy);
        _isLoadingGps = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationAddress = '';
        _gpsPrecision = GpsPrecision.unavailable;
        _isLoadingGps = false;
      });
    }
  }

  GpsPrecision _precisionFromAccuracy(double accuracy) {
    if (accuracy <= 10) return GpsPrecision.high;
    if (accuracy <= 50) return GpsPrecision.medium;
    return GpsPrecision.low;
  }

  void _showManualLocationDialog() {
    final cepController = TextEditingController();
    final addressController = TextEditingController(text: _locationAddress);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfacePanel,
        title: Text(
          'Preencher local',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: cepController,
              keyboardType: TextInputType.number,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'CEP (opcional)',
                hintStyle: GoogleFonts.inter(
                  color: AppTheme.textPrimary.withAlpha(100),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: AppTheme.primary.withAlpha(100),
                  ),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressController,
              autofocus: true,
              maxLines: 2,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Endereço completo',
                hintStyle: GoogleFonts.inter(
                  color: AppTheme.textPrimary.withAlpha(100),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: AppTheme.primary.withAlpha(100),
                  ),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primary),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'CANCELAR',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(150),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              final cep = cepController.text.trim();
              final address = addressController.text.trim();
              if (address.isNotEmpty) {
                setState(() {
                  _locationAddress = cep.isEmpty
                      ? address
                      : '$address · CEP $cep';
                  _manualLocationSet = true;
                });
              }
              Navigator.of(ctx).pop();
            },
            child: Text(
              'CONFIRMAR',
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

  // ─── Time Chips ─────────────────────────────────────────────────────

  void _onTimeChipSelected(int index) {
    setState(() {
      _selectedTimeChip = index;
      _startedAt = switch (index) {
        1 => DateTime.now().subtract(const Duration(minutes: 5)),
        2 => DateTime.now().subtract(const Duration(minutes: 15)),
        _ => DateTime.now(),
      };
    });
  }

  Future<void> _onTimeEditTap() async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: now);
    if (picked == null || !mounted) return;

    final today = DateTime.now();
    final candidate = DateTime(
      today.year,
      today.month,
      today.day,
      picked.hour,
      picked.minute,
    );

    if (candidate.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Horário não pode ser no futuro',
            style: GoogleFonts.inter(),
          ),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _selectedTimeChip = 3;
      _startedAt = candidate;
    });
  }

  // ─── Natures ────────────────────────────────────────────────────────

  Future<void> _loadNatures() async {
    try {
      final occurrenceVM = context.read<OccurrenceViewModel>();
      final natures = await occurrenceVM.fetchNatures();
      if (!mounted) return;
      setState(() {
        _natures = natures.isNotEmpty ? natures : OccurrenceNatureSeed.items;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _natures = OccurrenceNatureSeed.items;
      });
    }
  }

  // ─── Open Occurrence Check ──────────────────────────────────────────

  void _checkOpenOccurrence() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final occVM = context.read<OccurrenceViewModel>();
      final dogId = context.read<ShiftViewModel>().activeDogId;
      final openOccurrence =
          occVM.openOccurrence ??
          (dogId == null ? null : await occVM.findOpen(dogId));
      if (!mounted || openOccurrence == null) return;
      _showOpenOccurrenceDialog(openOccurrence.id);
    });
  }

  void _showOpenOccurrenceDialog(String existingId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfacePanel,
        title: Text(
          'Ocorrência em andamento',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Voce ja tem uma ocorrencia aberta. Continue nela para finalizar ou registrar novos eventos.',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary.withAlpha(200),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).maybePop();
            },
            child: Text(
              'VOLTAR',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(150),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) =>
                      ActiveOccurrenceScreen(occurrenceId: existingId),
                ),
              );
            },
            child: Text(
              'CONTINUAR',
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

  // ─── Pop Confirmation ───────────────────────────────────────────────

  Future<bool> _onPopAttempt() async {
    if (!_hasUnsavedData) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfacePanel,
        title: Text(
          'Descartar dados?',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Você tem dados preenchidos que serão perdidos.',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary.withAlpha(200),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'CANCELAR',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary.withAlpha(150),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'DESCARTAR',
              style: GoogleFonts.inter(
                color: AppTheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _requestExit() async {
    final navigator = Navigator.of(context);
    final shouldPop = await _onPopAttempt();
    if (shouldPop && mounted) {
      navigator.pop();
    }
  }

  Future<List<OccurrenceTeamMember>> _buildGuarnicaoSnapshot({
    required ShiftViewModel shiftVM,
    required UserViewModel userVM,
    required DogViewModel dogVM,
    required String? handlerRa,
    required String? handlerAuthUid,
    required String? handlerEmail,
  }) async {
    final currentRa = handlerRa?.trim();
    if (currentRa == null || currentRa.isEmpty) {
      throw StateError('Condutor autenticado sem RA para abrir ocorrência.');
    }

    final crewId = shiftVM.vehicleCrewId?.trim();
    if (crewId == null || crewId.isEmpty) {
      throw StateError(
        'Assuma uma viatura antes de abrir ocorrência operacional.',
      );
    }

    final crew = await _crewService.getCrew(crewId);
    if (crew == null || !crew.active) {
      throw StateError('Guarnição ativa não encontrada para esta viatura.');
    }

    final now = DateTime.now();
    final activeMembers = (await _crewService.getMembers(
      crewId,
    )).where((member) => member.isActive).toList();
    if (!activeMembers.any((member) => member.handlerId == currentRa)) {
      throw StateError(
        'Seu condutor não está confirmado na guarnição desta viatura.',
      );
    }

    final serviceDog =
        _dogForId(dogVM, crew.serviceDogId) ??
        _dogForId(dogVM, shiftVM.serviceDogId) ??
        _dogForId(dogVM, shiftVM.activeDogId);
    final members = <OccurrenceTeamMember>[];
    final seenHandlers = <String>{};

    for (final member in activeMembers) {
      final ra = member.handlerId.trim();
      if (ra.isEmpty || !seenHandlers.add(ra)) continue;
      final isCurrentHandler = ra == currentRa;
      members.add(
        OccurrenceTeamMember(
          handlerId: ra,
          authUid: member.authUid ?? (isCurrentHandler ? handlerAuthUid : null),
          handlerEmail:
              member.handlerEmail ??
              (isCurrentHandler ? handlerEmail : null) ??
              HandlerIdentityService.emailFromRa(ra),
          displayName: userVM.displayNameFor(ra: ra),
          dogId: serviceDog?.id ?? crew.serviceDogId,
          dogName: serviceDog?.name,
          dogMatricula: serviceDog?.registrationNumber,
          dogBreed: serviceDog?.breed,
          role: isCurrentHandler ? TeamRole.titular : TeamRole.integrante,
          addedAt: now,
          addedBy: currentRa,
        ),
      );
    }

    members.sort((a, b) {
      if (a.role != b.role) return a.role == TeamRole.titular ? -1 : 1;
      return a.handlerId.compareTo(b.handlerId);
    });
    return members;
  }

  Dog? _dogForId(DogViewModel dogVM, String? dogId) {
    if (dogId == null || dogId.isEmpty) return null;
    for (final dog in dogVM.dogs) {
      if (dog.id == dogId) return dog;
    }
    return null;
  }

  // ─── Create ─────────────────────────────────────────────────────────

  Future<void> _createOccurrence() async {
    setState(() => _isCreating = true);
    HapticFeedback.mediumImpact();

    try {
      final shiftVM = context.read<ShiftViewModel>();
      final authVM = context.read<AuthViewModel>();
      final occVM = context.read<OccurrenceViewModel>();
      final dogVM = context.read<DogViewModel>();
      final userVM = context.read<UserViewModel>();

      final id = const Uuid().v4();
      final shiftId = shiftVM.activeShiftId ?? '';
      final dogId = shiftVM.activeDogId ?? '';
      final handlerId = authVM.user?.uid ?? '';
      final handlerRa = HandlerIdentityService.raFromUser(authVM.user);
      final teamSnapshot = await _buildGuarnicaoSnapshot(
        shiftVM: shiftVM,
        userVM: userVM,
        dogVM: dogVM,
        handlerRa: handlerRa,
        handlerAuthUid: authVM.user?.uid,
        handlerEmail: authVM.user?.email,
      );

      final typeCode = _selectedNature?.code ?? 'GERAL';
      final typeName = _selectedNature?.name ?? 'Ocorrência Geral';

      await occVM.createOccurrence(
        id: id,
        shiftId: shiftId,
        dogId: dogId,
        serviceDogId: shiftVM.serviceDogId,
        crewId: shiftVM.vehicleCrewId,
        primaryHandlerId: handlerId,
        primaryHandlerRa: handlerRa,
        vehicleId: shiftVM.vehicleId,
        vehicleLabel: shiftVM.vehicleLabel,
        vehiclePrefix: shiftVM.vehiclePrefix,
        vehicleModel: shiftVM.vehicleModel,
        vehicleUnit: shiftVM.vehicleUnit,
        teamSnapshot: teamSnapshot,
        teamSizeMax: teamSnapshot.length,
        typeCode: typeCode,
        typeName: typeName,
        locationAddress: _locationAddress.isNotEmpty ? _locationAddress : null,
        gpsLat: _gpsLat,
        gpsLng: _gpsLng,
        gpsAccuracy: _gpsAccuracy,
        initialObservation: _observationController.text.trim().isNotEmpty
            ? _observationController.text.trim()
            : null,
        startedAt: _startedAt,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ActiveOccurrenceScreen(occurrenceId: id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao criar ocorrência: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final shiftVM = context.watch<ShiftViewModel>();
    final dogVM = context.watch<DogViewModel>();
    final authVM = context.watch<AuthViewModel>();
    final userVM = context.watch<UserViewModel>();

    final dogId = shiftVM.activeDogId;
    final dogs = dogVM.dogs.where((d) => d.id == dogId);
    final dog = dogs.isNotEmpty ? dogs.first : null;
    final dogName = dog?.name ?? 'K9';
    final dogImageUrl = dog?.profileImageUrl;

    final handlerRa = HandlerIdentityService.raFromUser(authVM.user);
    final handlerUser = userVM.findByRa(handlerRa);
    final handlerName = userVM.displayNameFor(
      ra: handlerRa,
      firebaseUser: authVM.user,
    );
    final handlerImageUrl = handlerUser?.photoUrl ?? authVM.user?.photoURL;

    final timeStr =
        '${_startedAt.hour.toString().padLeft(2, '0')}:${_startedAt.minute.toString().padLeft(2, '0')}';
    final dateStr =
        '${_startedAt.day.toString().padLeft(2, '0')}/${_startedAt.month.toString().padLeft(2, '0')}/${_startedAt.year}';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _requestExit();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                child: Column(
                  children: [
                    StartOccurrenceHeader(
                      onBack: _requestExit,
                      onClose: _requestExit,
                    ),
                    Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.transparent,
                            AppTheme.primary.withAlpha(50),
                            AppTheme.transparent,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    StartOccurrenceBinomio(
                      dogName: dogName,
                      dogImageUrl: dogImageUrl,
                      handlerName: handlerName,
                      handlerImageUrl: handlerImageUrl,
                    ),
                    const SizedBox(height: 32),
                    StartOccurrenceInfoGrid(
                      locationLabel: _locationAddress,
                      gpsPrecision: _gpsPrecision,
                      gpsAccuracy: _gpsAccuracy,
                      timeLabel: timeStr,
                      dateLabel: dateStr,
                      isLoadingGps: _isLoadingGps,
                      onRefreshLocation: _captureGps,
                      onRefreshTime: () {},
                      onManualLocation: _showManualLocationDialog,
                    ),
                    const SizedBox(height: 20),
                    StartOccurrenceTimeChips(
                      selectedIndex: _selectedTimeChip,
                      formattedTime: timeStr,
                      onSelected: _onTimeChipSelected,
                      onEditTap: _onTimeEditTap,
                    ),
                    const SizedBox(height: 24),
                    StartOccurrenceNatureLink(
                      expanded: _natureExpanded,
                      natureText: _selectedNature?.label ?? '',
                      controller: _natureController,
                      focusNode: _natureFocusNode,
                      natures: _natures,
                      onToggle: () =>
                          setState(() => _natureExpanded = !_natureExpanded),
                      onSelected: (nature) {
                        setState(() {
                          _selectedNature = nature;
                          _natureController.text = nature.label;
                          _natureExpanded = false;
                        });
                      },
                      onChanged: (_) {},
                    ),
                    const SizedBox(height: 20),
                    StartOccurrenceObservation(
                      controller: _observationController,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Local e horário são preenchidos automaticamente.\nToque nos cards para ajustar antes de iniciar.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary.withAlpha(100),
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: StartOccurrenceCta(
                  isLoading: _isCreating,
                  enabled: _ctaEnabled,
                  onPressed: _createOccurrence,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
