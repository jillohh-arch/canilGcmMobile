import 'package:flutter/material.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/active_shift_dashboard_screen.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'package:canil_gcm/features/dogs/presentation/screens/dog_prontuario_tab_screen.dart';
import 'package:canil_gcm/features/incidents/presentation/screens/occurrence_flow_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/dynamic_activity_sheet.dart';
import 'package:canil_gcm/features/training/presentation/screens/training_hub_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canil_gcm/core/services/permission_service.dart';

part 'main_root_actions.dart';
part 'main_root_action_sheet.dart';
part 'main_root_action_widgets.dart';
part 'main_root_exit_dialog.dart';
part 'main_root_widgets.dart';

class MainRootScreen extends StatefulWidget {
  const MainRootScreen({super.key});

  @override
  State<MainRootScreen> createState() => _MainRootScreenState();
}

class _MainRootScreenState extends State<MainRootScreen> {
  static const _categoryOccurrence = 'Ocorrencia';

  int _currentIndex = 0;
  String? _lastIncidentFetchDogId;

  @override
  void initState() {
    super.initState();
    // Solicita as permissões essenciais ao entrar no dashboard
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
        // O corpo do app muda conforme a aba selecionada
        body: Stack(
          children: [
            IndexedStack(index: _currentIndex, children: _screens),
            if (activeDogId != null && activeIncident != null)
              Positioned(
                left: 14,
                right: 14,
                bottom: 78,
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

        // BOTÃO CENTRAL: O Gatilho de Operações
        floatingActionButton: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.3),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: FloatingActionButton(
            onPressed: () {
              if (activeDogId != null) {
                _openActionSheet(context, activeDogId);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Inicie um turno para registrar atividades.'),
                  ),
                );
              }
            },
            backgroundColor: AppTheme.primary,
            elevation: 0,
            shape: const CircleBorder(
              side: BorderSide(color: Color(0xFF050D10), width: 4),
            ),
            child: const Icon(Icons.shield, color: Color(0xFF050D10), size: 26),
          ),
        ),

        // POSIÇÃO ANCORADA: Faz o botão "encaixar" na barra
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

        // BARRA DE NAVEGAÇÃO CÔNCAVA
        bottomNavigationBar: BottomAppBar(
          color: AppTheme.background,
          shape: const CircularNotchedRectangle(),
          notchMargin: 8.0,
          child: SizedBox(
            height: 72,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Lado Esquerdo: Turno e Histórico
                Row(
                  children: [
                    _buildNavItem(0, Icons.home_outlined, 'Turno'),
                    _buildNavItem(1, Icons.history, 'Histórico'),
                  ],
                ),
                // Espaço central reservado para o FAB
                const SizedBox(width: 32),
                // Lado Direito: Treino e Cão/Perfil
                Row(
                  children: [
                    _buildNavItem(2, Icons.track_changes_rounded, 'Treino'),
                    _buildNavItem(3, Icons.pets, 'Cão'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
