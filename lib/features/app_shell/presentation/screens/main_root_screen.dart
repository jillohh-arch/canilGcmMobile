import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/permission_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/presentation/screens/dog_prontuario_tab_screen.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/incidents/presentation/screens/occurrence_flow_screen.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/start_occurrence_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/active_shift_dashboard_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/screens/training_hub_screen.dart';

part 'main_root_actions.dart';
part 'main_root_action_sheet.dart';
part 'main_root_exit_dialog.dart';
part 'main_root_widgets.dart';

class MainRootScreen extends StatefulWidget {
  const MainRootScreen({super.key});

  @override
  State<MainRootScreen> createState() => _MainRootScreenState();
}

class _MainRootScreenState extends State<MainRootScreen> {
  int _currentIndex = 0;
  String? _lastIncidentFetchDogId;

  @override
  void initState() {
    super.initState();
    PermissionService.requestInitialPermissions();
  }

  final List<Widget> _screens = [
    const ActiveShiftDashboardScreen(),
    const HistoryScreen(),
    const TrainingHubScreen(),
    const DogProntuarioTabScreen(),
  ];

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final activeDogId = shiftVM.activeDogId;
    final incidentVM = Provider.of<IncidentViewModel>(context);
    final activeIncident = activeDogId == null
        ? null
        : _activeIncidentForDog(incidentVM.incidents, activeDogId);

    if (activeDogId != null && activeDogId != _lastIncidentFetchDogId) {
      _lastIncidentFetchDogId = activeDogId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Provider.of<IncidentViewModel>(
          context,
          listen: false,
        ).fetchIncidentsForDog(activeDogId);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await _handleBackNavigation(context);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Stack(
          children: [
            IndexedStack(index: _currentIndex, children: _screens),
            if (activeDogId != null && activeIncident != null)
              Positioned(
                left: 14,
                right: 14,
                bottom: 88,
                child: _ActiveIncidentBanner(
                  incident: activeIncident,
                  dogName: _dogNameFor(context, activeDogId),
                  onTap: () => _continueActiveIncident(
                    context,
                    dogId: activeDogId,
                    incident: activeIncident,
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: _buildBottomNavigation(context, activeDogId),
      ),
    );
  }
}
