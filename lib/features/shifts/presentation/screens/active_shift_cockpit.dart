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

class _VehicleAssumptionPrompt extends StatelessWidget {
  const _VehicleAssumptionPrompt();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        VehicleCrewPostSheet.show(context);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.primary.withAlpha(10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary.withAlpha(30)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.directions_car_filled_rounded,
              color: AppTheme.primary,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VIATURA',
                    style: GoogleFonts.inter(
                      color: AppTheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toque para assumir um posto na guarnicao',
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.primary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
