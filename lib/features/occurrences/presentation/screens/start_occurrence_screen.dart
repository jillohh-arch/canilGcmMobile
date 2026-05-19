import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:canil_gcm/core/services/location_resolution_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/incidents/domain/occurrence_nature.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/start_occurrence_binomio.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/start_occurrence_cta.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/start_occurrence_header.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/start_occurrence_info_grid.dart';
import 'package:canil_gcm/features/occurrences/presentation/widgets/start_occurrence_nature_link.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/active_occurrence_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

class StartOccurrenceScreen extends StatefulWidget {
  const StartOccurrenceScreen({super.key});

  @override
  State<StartOccurrenceScreen> createState() => _StartOccurrenceScreenState();
}

class _StartOccurrenceScreenState extends State<StartOccurrenceScreen> {
  final _locationService = const LocationResolutionService();
  final _natureController = TextEditingController();
  final _natureFocusNode = FocusNode();

  // GPS state
  String _locationAddress = '';
  double? _gpsLat;
  double? _gpsLng;
  double? _gpsAccuracy;
  bool _isLoadingGps = true;
  GpsPrecision _gpsPrecision = GpsPrecision.unavailable;

  // Time state
  late DateTime _currentTime;

  // Nature state
  bool _natureExpanded = false;
  OccurrenceNature? _selectedNature;
  List<OccurrenceNature> _natures = [];

  // Loading
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _captureGps();
    _loadNatures();
  }

  @override
  void dispose() {
    _natureController.dispose();
    _natureFocusNode.dispose();
    super.dispose();
  }

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

  void _refreshTime() {
    HapticFeedback.lightImpact();
    setState(() => _currentTime = DateTime.now());
  }

  Future<void> _loadNatures() async {
    try {
      final incidentVM = context.read<IncidentViewModel>();
      final natures = await incidentVM.fetchNatures();
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

  Future<void> _createOccurrence() async {
    setState(() => _isCreating = true);
    HapticFeedback.mediumImpact();

    try {
      final shiftVM = context.read<ShiftViewModel>();
      final authVM = context.read<AuthViewModel>();
      final occVM = context.read<OccurrenceViewModel>();

      final id = const Uuid().v4();
      final shiftId = shiftVM.activeShiftId ?? '';
      final dogId = shiftVM.activeDogId ?? '';
      final handlerId = authVM.user?.uid ?? '';

      final typeCode = _selectedNature?.code ?? 'GERAL';
      final typeName = _selectedNature?.name ?? 'Ocorrência Geral';

      await occVM.createOccurrence(
        id: id,
        shiftId: shiftId,
        dogId: dogId,
        primaryHandlerId: handlerId,
        typeCode: typeCode,
        typeName: typeName,
        locationAddress: _locationAddress.isNotEmpty ? _locationAddress : null,
        gpsLat: _gpsLat,
        gpsLng: _gpsLng,
        gpsAccuracy: _gpsAccuracy,
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

    final handlerName = userVM.displayNameFor(
      ra: '',
      firebaseUser: authVM.user,
    );

    final timeStr =
        '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}';
    final dateStr =
        '${_currentTime.day.toString().padLeft(2, '0')}/${_currentTime.month.toString().padLeft(2, '0')}/${_currentTime.year}';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              child: Column(
                children: [
                  StartOccurrenceHeader(onBack: () => Navigator.of(context).pop()),
                  Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppTheme.primary.withAlpha(50),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  StartOccurrenceBinomio(
                    dogName: dogName,
                    dogImageUrl: dogImageUrl,
                    handlerName: handlerName,
                  ),
                  const SizedBox(height: 32),
                  StartOccurrenceInfoGrid(
                    locationLabel: _locationAddress,
                    gpsPrecision: _gpsPrecision,
                    timeLabel: timeStr,
                    dateLabel: dateStr,
                    isLoadingGps: _isLoadingGps,
                    onRefreshLocation: _captureGps,
                    onRefreshTime: _refreshTime,
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
                        _natureExpanded = false;
                      });
                    },
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Local e horário são preenchidos automaticamente.\nToque nos cards para ajustar antes de iniciar.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white.withAlpha(100),
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
                onPressed: _createOccurrence,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
