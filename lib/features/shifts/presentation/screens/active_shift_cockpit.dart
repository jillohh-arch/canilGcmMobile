part of 'active_shift_dashboard_screen.dart';

/// Monta o dashboard fiel ao mockup 10_dashboard.html.
Widget _buildCockpit(BuildContext context, Dog dog, String callsign) {
  final state = context
      .findAncestorStateOfType<_ActiveShiftDashboardScreenState>()!;
  final userVM = Provider.of<UserViewModel>(context);
  final authVM = Provider.of<AuthViewModel>(context);
  final currentRa = HandlerIdentityService.raFromUser(authVM.user);
  final userModel = userVM.findByRa(currentRa);
  final userPhoto = userModel?.photoUrl?.trim();
  final firebasePhoto = authVM.user?.photoURL?.trim();
  final conductorPhoto = userPhoto != null && userPhoto.isNotEmpty
      ? userPhoto
      : firebasePhoto != null && firebasePhoto.isNotEmpty
      ? firebasePhoto
      : null;

  return SafeArea(
    child: Column(
      children: [
        // Header compacto (fixo no topo)
        _ShiftHeader(
          dog: dog,
          currentRa: currentRa,
          conductorPhotoUrl: conductorPhoto,
          onSwitchDog: () => _showDogSwitcher(context),
          onDogHealth: state.widget.onOpenHealthTab,
          onProfile: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const HandlerProfilePage(showBottomNav: false),
            ),
          ),
        ),
        // Scroll area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!Provider.of<ShiftViewModel>(context).hasVehicle) ...[
                  _VehicleAssumptionPrompt(
                    vehicleService: state._vehicleService,
                    onAssume: (vehicle) =>
                        _assumeVehicleDuringShift(context, vehicle),
                  ),
                  const SizedBox(height: 16),
                ],
                _ShiftProfileCardsSection(
                  dog: dog,
                  callsign: callsign,
                  conductorPhotoUrl: conductorPhoto,
                ),
                const SizedBox(height: 18),
                const _OperationalPulseSection(),
                const SizedBox(height: 18),
                _QuickActionsSection(
                  dog: dog,
                  actions: state._quickActions,
                  onOpenTrainingHub: state.widget.onOpenTrainingHub,
                  onOpenHealthTab: state.widget.onOpenHealthTab,
                ),
                const SizedBox(height: 18),
                const _LatestRecordsSection(),
                const SizedBox(height: 18),
                // Alertas (condicional)
                if (state._alerts.isNotEmpty) ...[
                  _AlertsSection(
                    alerts: state._alerts,
                    totalAlerts: state._totalAlerts,
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Dog? _localDogFallback(DogViewModel dogVM, String dogId) {
  try {
    return dogVM.dogs.firstWhere((d) => d.id == dogId);
  } catch (_) {
    return null;
  }
}

void _assumeVehicleDuringShift(BuildContext context, Vehicle vehicle) async {
  HapticFeedback.mediumImpact();
  final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
  await shiftVM.assumeVehicle(vehicle);
  if (!context.mounted) return;
  final error = shiftVM.error;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error ?? 'Viatura ${vehicle.label} assumida.'),
      backgroundColor: error == null ? AppTheme.primary : AppTheme.error,
    ),
  );
}

class _VehicleAssumptionPrompt extends StatelessWidget {
  final VehicleService vehicleService;
  final ValueChanged<Vehicle> onAssume;

  const _VehicleAssumptionPrompt({
    required this.vehicleService,
    required this.onAssume,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Vehicle>>(
      stream: vehicleService.watchActiveVehicles(),
      builder: (context, snapshot) {
        final vehicles = snapshot.data ?? const <Vehicle>[];
        final error = snapshot.error;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primary.withAlpha(30)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.directions_car_filled_rounded,
                    color: AppTheme.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'VIATURA',
                    style: GoogleFonts.inter(
                      color: AppTheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Turno iniciado sem viatura. Assuma uma viatura antes de registrar ocorrencias operacionais em guarnicao.',
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              if (error != null)
                Text(
                  'Nao foi possivel carregar viaturas: $error',
                  style: GoogleFonts.inter(color: AppTheme.error, fontSize: 11),
                )
              else if (vehicles.isEmpty)
                Text(
                  'Nenhuma viatura ativa cadastrada.',
                  style: GoogleFonts.inter(
                    color: AppTheme.textTertiary,
                    fontSize: 11,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: vehicles
                      .map(
                        (vehicle) => OutlinedButton.icon(
                          onPressed: () => onAssume(vehicle),
                          icon: const Icon(Icons.add_road_rounded, size: 16),
                          label: Text(vehicle.label),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: BorderSide(
                              color: AppTheme.primary.withAlpha(60),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        );
      },
    );
  }
}
