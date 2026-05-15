part of 'incident_form_screen.dart';

class _NewIncidentForm extends StatefulWidget {
  final String dogId;
  final VoidCallback onSaved;
  const _NewIncidentForm({required this.dogId, required this.onSaved});

  @override
  State<_NewIncidentForm> createState() => _NewIncidentFormState();
}

class _NewIncidentFormState extends State<_NewIncidentForm> {
  final _formKey = GlobalKey<FormState>();
  final _observationsController = TextEditingController();

  // Natureza
  String? _selectedNatureCode;
  String _selectedNatureName = '';

  // Horário
  String _timeOption = 'agora';
  DateTime _selectedTime = DateTime.now();

  // GPS
  String _locationText = 'Obtendo localização...';
  double? _latitude;
  double? _longitude;
  double? _accuracy;
  bool _gpsLoading = true;
  bool _gpsFailed = false;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _captureGps();
    // Carrega naturezas
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<IncidentViewModel>(context, listen: false).fetchNatures();
    });
  }

  @override
  void dispose() {
    _observationsController.dispose();
    super.dispose();
  }

  Future<void> _captureGps() async {
    try {
      final service = const LocationResolutionService();
      final resolved = await service.currentHighAccuracy();
      if (!mounted) return;
      setState(() {
        _locationText = resolved.address;
        _latitude = resolved.point.latitude;
        _longitude = resolved.point.longitude;
        _gpsLoading = false;
        _gpsFailed = false;
      });
      // Tenta obter precisão
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high),
        );
        if (mounted) setState(() => _accuracy = pos.accuracy);
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _gpsLoading = false;
        _gpsFailed = true;
        _locationText = 'GPS indisponível';
      });
    }
  }

  void _startIncident() async {
    if (_selectedNatureName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione a natureza da ocorrência'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_gpsFailed && _locationText == 'GPS indisponível') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aguarde o GPS ou preencha o local manualmente'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final currentRa =
        HandlerIdentityService.raFromUser(authVM.user) ?? '000000';
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final userModel = userVM.users.cast<dynamic>().firstWhere(
      (u) => u?.ra == currentRa,
      orElse: () => null,
    );
    final authorName =
        userModel?.callsign?.toString() ??
        authVM.user?.displayName ??
        currentRa;

    final viewModel = Provider.of<IncidentViewModel>(context, listen: false);
    final openIncident = await viewModel.findOpenIncident(dogId: widget.dogId);
    if (openIncident != null) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Já existe uma ocorrência em andamento. Conclua ou cancele-a primeiro.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Calcula horário de início
    final startTime = _resolveStartTime();

    if (!mounted) return;
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final dog = dogVM.dogs.cast<dynamic>().firstWhere(
      (d) => d.id == widget.dogId,
      orElse: () => null,
    );

    final incident = Incident(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      dogId: widget.dogId,
      dogName: dog?.name ?? '',
      handlerId: currentRa,
      date: startTime,
      location: _locationText,
      description: _observationsController.text.trim().isNotEmpty
          ? _observationsController.text.trim()
          : 'Ocorrência iniciada.',
      result: 'Pendente',
      type: _selectedNatureName,
      extraFields: {
        if (_selectedNatureCode != null) 'naturezaCodigo': _selectedNatureCode,
        if (_latitude != null) 'latitude': _latitude,
        if (_longitude != null) 'longitude': _longitude,
        if (_accuracy != null) 'gps_accuracy': _accuracy,
      },
      status: 'Em andamento',
      startedAt: startTime,
      progressUpdates: [
        IncidentProgressUpdate(
          title: 'Ocorrência Iniciada',
          description: 'Natureza: $_selectedNatureName',
          timestamp: startTime,
          location: _locationText,
          latitude: _latitude,
          longitude: _longitude,
          authorId: currentRa,
          authorName: authorName,
        ),
      ],
    );

    try {
      await viewModel.saveIncident(incident);
      if (mounted) {
        HapticFeedback.heavyImpact();
        // Navega para o fluxo de ocorrência em andamento
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => OccurrenceFlowScreen(
              dogId: widget.dogId,
              dogName: dog?.name ?? '',
              incident: incident,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  DateTime _resolveStartTime() {
    final now = DateTime.now();
    switch (_timeOption) {
      case '5min':
        return now.subtract(const Duration(minutes: 5));
      case '15min':
        return now.subtract(const Duration(minutes: 15));
      case 'custom':
        return _selectedTime;
      default:
        return now;
    }
  }

  @override
  Widget build(BuildContext context) {
    final incidentVM = Provider.of<IncidentViewModel>(context);
    final natures = incidentVM.natures;

    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _TacticalGridPainter())),
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildNatureGrid(natures),
                const SizedBox(height: 20),
                _buildLocationCard(),
                const SizedBox(height: 20),
                _buildTimeChips(),
                const SizedBox(height: 20),
                _buildObservationsField(),
              ],
            ),
          ),
        ),
        // CTA sticky
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildStartButton(),
        ),
      ],
    );
  }

  // ─── Header ────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final dogVM = Provider.of<DogViewModel>(context);
    final dog = dogVM.dogs.cast<dynamic>().firstWhere(
      (d) => d.id == widget.dogId,
      orElse: () => null,
    );
    final dogName = dog?.name ?? 'K9';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.shield_outlined, color: AppTheme.error, size: 32),
        const SizedBox(height: 8),
        Text(
          'Nova Ocorrência',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$dogName • ${_formatTime(DateTime.now())}',
          style: GoogleFonts.inter(
            color: AppTheme.textTertiary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // ─── Grid de naturezas ─────────────────────────────────────────────

  Widget _buildNatureGrid(List<OccurrenceNature> natures) {
    // Fallback se não carregou do Firestore
    final displayNatures = natures.isNotEmpty
        ? natures.take(6).toList()
        : _defaultNatures();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('NATUREZA DA OCORRÊNCIA'),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.1,
          ),
          itemCount: displayNatures.length,
          itemBuilder: (_, i) {
            final nature = displayNatures[i];
            final selected = _selectedNatureCode == nature.code;
            return _buildNatureCard(nature, selected);
          },
        ),
      ],
    );
  }

  Widget _buildNatureCard(OccurrenceNature nature, bool selected) {
    final color = selected ? AppTheme.primary : AppTheme.textTertiary;
    final icon = _natureIcon(nature.code);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedNatureCode = nature.code;
          _selectedNatureName = nature.name;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: color.withAlpha(selected ? 15 : 8),
          border: Border.all(
            color: color.withAlpha(selected ? 120 : 30),
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              nature.name,
              style: GoogleFonts.inter(
                color: color,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  IconData _natureIcon(String code) {
    switch (code.toLowerCase()) {
      case 'patrulha':
      case 'patrulhamento':
        return Icons.shield_outlined;
      case 'faro_veiculo':
      case 'faro_veicular':
        return Icons.directions_car_outlined;
      case 'vistoria':
      case 'vistoria_residencial':
        return Icons.home_outlined;
      case 'busca':
      case 'busca_mata':
        return Icons.park_outlined;
      case 'apoio':
      case 'apoio_viatura':
        return Icons.people_outlined;
      case 'outra':
      case 'outros':
        return Icons.search_outlined;
      default:
        return Icons.radio_button_checked;
    }
  }

  List<OccurrenceNature> _defaultNatures() {
    return [
      OccurrenceNature(code: 'patrulha', name: 'Patrulha', group: 'operacional', active: true),
      OccurrenceNature(code: 'faro_veiculo', name: 'Faro Veicular', group: 'operacional', active: true),
      OccurrenceNature(code: 'vistoria', name: 'Vistoria', group: 'operacional', active: true),
      OccurrenceNature(code: 'busca_mata', name: 'Busca Mata', group: 'operacional', active: true),
      OccurrenceNature(code: 'apoio', name: 'Apoio', group: 'operacional', active: true),
      OccurrenceNature(code: 'outra', name: 'Outra', group: 'geral', active: true),
    ];
  }

  // ─── Card de localização ───────────────────────────────────────────

  Widget _buildLocationCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel('LOCAL'),
            const Spacer(),
            GestureDetector(
              onTap: _captureGps,
              child: Row(
                children: [
                  Icon(Icons.gps_fixed, color: AppTheme.primary, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'GPS',
                    style: GoogleFonts.inter(
                      color: AppTheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(8),
            border: Border.all(
              color: _gpsFailed
                  ? AppTheme.warning.withAlpha(60)
                  : AppTheme.primary.withAlpha(40),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: _gpsLoading
              ? Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        color: AppTheme.primary,
                        strokeWidth: 2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Obtendo localização GPS...',
                      style: GoogleFonts.inter(
                        color: AppTheme.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _gpsFailed
                              ? Icons.location_off
                              : Icons.location_on_rounded,
                          color: _gpsFailed
                              ? AppTheme.warning
                              : AppTheme.primary,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _locationText,
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_latitude != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}${_accuracy != null ? ' • ±${_accuracy!.toStringAsFixed(1)}m' : ''}',
                        style: GoogleFonts.inter(
                          color: AppTheme.textTertiary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                    if (_gpsFailed) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Toque em GPS para tentar novamente',
                        style: GoogleFonts.inter(
                          color: AppTheme.warning,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  // ─── Chips de horário ──────────────────────────────────────────────

  Widget _buildTimeChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('HORÁRIO DE INÍCIO'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _timeChip('agora', 'Agora · ${_formatTime(DateTime.now())}'),
            _timeChip('5min', 'Há 5min'),
            _timeChip('15min', 'Há 15min'),
            _timeChip('custom', 'Editar'),
          ],
        ),
      ],
    );
  }

  Widget _timeChip(String value, String label) {
    final selected = _timeOption == value;
    final color = selected ? AppTheme.primary : AppTheme.textTertiary;

    return GestureDetector(
      onTap: () async {
        HapticFeedback.selectionClick();
        if (value == 'custom') {
          final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(_selectedTime),
          );
          if (picked != null) {
            final now = DateTime.now();
            setState(() {
              _timeOption = 'custom';
              _selectedTime = DateTime(
                  now.year, now.month, now.day, picked.hour, picked.minute);
            });
          }
        } else {
          setState(() => _timeOption = value);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(selected ? 20 : 8),
          border: Border.all(color: color.withAlpha(selected ? 80 : 30)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          value == 'custom' && _timeOption == 'custom'
              ? _formatTime(_selectedTime)
              : label,
          style: GoogleFonts.inter(
            color: color,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ─── Observação inicial ────────────────────────────────────────────

  Widget _buildObservationsField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('OBSERVAÇÃO INICIAL · OPCIONAL'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(8),
            border: Border.all(color: Colors.white.withAlpha(30)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextField(
            controller: _observationsController,
            maxLines: 3,
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'Acionamento via rádio, suspeita de...',
              hintStyle: GoogleFonts.inter(
                color: AppTheme.textTertiary.withAlpha(100),
                fontSize: 12,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  // ─── CTA ───────────────────────────────────────────────────────────

  Widget _buildStartButton() {
    final enabled = _selectedNatureName.isNotEmpty && !_gpsLoading && !_saving;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.background.withAlpha(0),
            AppTheme.background,
            AppTheme.background,
          ],
          stops: const [0.0, 0.3, 1.0],
        ),
      ),
      child: GestureDetector(
        onTap: enabled ? _startIncident : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: enabled ? AppTheme.error : AppTheme.error.withAlpha(40),
            borderRadius: BorderRadius.circular(12),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: AppTheme.error.withAlpha(51),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_saving)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              else
                const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'INICIAR OCORRÊNCIA',
                style: GoogleFonts.inter(
                  color: Colors.white.withAlpha(enabled ? 255 : 100),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: AppTheme.textTertiary,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.0,
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
