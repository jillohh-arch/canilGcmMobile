import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/active_shift_dashboard_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/daily_timeline_screen.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_dashboard_screen.dart';
import 'package:canil_gcm/features/users/presentation/screens/profile_screen.dart';
import 'package:canil_gcm/features/gamification/presentation/screens/ranking_screen.dart';
import 'package:canil_gcm/features/incidents/presentation/screens/occurrence_flow_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/dynamic_activity_sheet.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canil_gcm/core/services/permission_service.dart';

part 'main_root_actions.dart';
part 'main_root_action_widgets.dart';
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
    const DailyTimelineScreen(),
    const HealthDashboardScreen(),
    const ProfileScreen(),
    const RankingScreen(),
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

        final rootNavigator = Navigator.of(context, rootNavigator: true);
        if (rootNavigator.canPop()) {
          rootNavigator.pop();
          return;
        }

        final localNavigator = Navigator.of(context);
        if (localNavigator.canPop()) {
          localNavigator.pop();
          return;
        }

        // Se não estiver no dashboard ativo (aba 0), voltar para a aba 0
        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
          return;
        }

        // Se estiver na aba 0, pedir confirmação para fechar o app
        final shouldExit = await showDialog<bool>(
          context: context,
          useRootNavigator: true,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            title: const Text(
              'Encerrar Aplicativo?',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: const Text(
              'Tem certeza que deseja fechar o aplicativo e encerrar sua sessão no dispositivo?',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(
                    color: Color(0xFF00E5FF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                ),
                child: const Text(
                  'Sair',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );

        if (shouldExit == true) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF030712),
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
                color: Colors.cyanAccent.withValues(alpha: 0.3),
                blurRadius: 15,
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
            backgroundColor: const Color(0xFF020617),
            elevation: 0,
            shape: const CircleBorder(),
            child: const Icon(Icons.add, color: Colors.cyanAccent, size: 32),
          ),
        ),

        // POSIÇÃO ANCORADA: Faz o botão "encaixar" na barra
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

        // BARRA DE NAVEGAÇÃO CÔNCAVA
        bottomNavigationBar: BottomAppBar(
          color: const Color(0xFF0F172A),
          shape:
              const CircularNotchedRectangle(), // Cria a curva/berço para o FAB
          notchMargin: 8.0, // Espaço entre o botão e a curva
          child: SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Lado Esquerdo: Turno e Timeline
                Row(
                  children: [
                    _buildNavItem(0, Icons.shield_outlined, 'Turno'),
                    _buildNavItem(1, Icons.history_toggle_off, 'Hist.'),
                  ],
                ),
                // Espaço central reservado para o FAB (Não mexer aqui)
                const SizedBox(width: 32),
                // Lado Direito: Saúde, Ranking e Perfil
                Row(
                  children: [
                    _buildNavItem(4, Icons.leaderboard_outlined, 'Rank'),
                    _buildNavItem(2, Icons.medical_services_outlined, 'Saúde'),
                    _buildNavItem(3, Icons.person_outline, 'Perfil'),
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
