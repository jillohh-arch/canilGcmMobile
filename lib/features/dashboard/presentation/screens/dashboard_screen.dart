import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/users/domain/user.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/dogs/presentation/screens/dog_details_screen.dart';
import 'package:canil_gcm/features/users/presentation/screens/user_management_screen.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/training/presentation/screens/training_log_screen.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/permission_service.dart';
import 'package:canil_gcm/features/incidents/presentation/screens/occurrence_flow_screen.dart';

part 'dashboard_shared_widgets.dart';
part 'dashboard_profile_widgets.dart';
part 'dashboard_open_incident_widgets.dart';
part 'dashboard_open_incident_actions.dart';
part 'dashboard_open_incident_header.dart';
part 'dashboard_open_incident_metrics.dart';
part 'dashboard_open_incident_update.dart';
part 'dashboard_incident_components.dart';
part 'dashboard_dog_cards.dart';
part 'dashboard_featured_dog_card.dart';
part 'dashboard_dog_card_components.dart';
part 'dashboard_dog_card_image.dart';
part 'dashboard_small_dog_card.dart';
part 'dashboard_k9s_tab.dart';
part 'dashboard_k9s_header.dart';
part 'dashboard_k9s_actions.dart';
part 'dashboard_quick_close_sheet.dart';
part 'dashboard_quick_close_actions.dart';
part 'dashboard_quick_close_controls.dart';
part 'dashboard_quick_close_flow.dart';
part 'dashboard_quick_close_frame.dart';
part 'dashboard_quick_close_header.dart';
part 'dashboard_quick_close_note_field.dart';
part 'dashboard_quick_close_rules.dart';
part 'dashboard_training_components.dart';
part 'dashboard_training_tab.dart';

const _hudBackground = Color(0xFF070B14);
const _hudPanel = Color(0xFF0B1220);
const _hudPanelAlt = Color(0xFF111827);
const _hudCyan = Color(0xFF00E5FF);
const _hudAmber = Color(0xFFFBBF24);
const _hudDanger = Color(0xFFFF3B6B);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    PermissionService.requestInitialPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;

        // Se puder dar pop no navigator atual (modais etc), damos o pop.
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
          return;
        }

        // Se não estiver na aba 0, voltar para a aba 0
        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
          return;
        }

        // Se estiver na aba 0, pedir confirmação para fechar app
        final shouldExit = await showDialog<bool>(
          context: context,
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
        backgroundColor: _hudBackground,
        body: IndexedStack(
          index: _selectedIndex,
          children: const [_K9sTab(), _TreinosTab(), _GuardasTab()],
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: _hudPanel,
          indicatorColor: _hudCyan.withAlpha(28),
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) => setState(() => _selectedIndex = i),
          destinations: const [
            NavigationDestination(
              icon: FaIcon(FontAwesomeIcons.dog),
              selectedIcon: FaIcon(FontAwesomeIcons.dog),
              label: 'K9s',
            ),
            NavigationDestination(
              icon: Icon(Icons.fitness_center_outlined),
              selectedIcon: Icon(Icons.fitness_center),
              label: 'Treinos',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Guardas',
            ),
          ],
        ),
      ),
    );
  }
}
