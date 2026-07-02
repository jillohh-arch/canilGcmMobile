part of 'active_shift_dashboard_screen.dart';

// _buildCockpit foi movido para _ActiveShiftDashboardScreenState
// como método _buildCockpitBody() para permitir uso de _animateSection.

Dog? _localDogFallback(DogViewModel dogVM, String dogId) {
  try {
    return dogVM.dogs.firstWhere((d) => d.id == dogId);
  } catch (_) {
    return null;
  }
}

void _assumeVehicleDuringShift(
  BuildContext context,
  Vehicle vehicle, {
  String role = 'motorista',
  String? name,
}) async {
  HapticFeedback.mediumImpact();
  final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
  await shiftVM.assumeVehicle(vehicle, role: role, name: name);
  if (!context.mounted) return;
  final error = shiftVM.error;
  if (error != null) {
    AppFeedback.error(context, error);
  } else {
    AppFeedback.success(context, 'Viatura ${vehicle.label} assumida.');
  }
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
