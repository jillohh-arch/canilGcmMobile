import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/active_shift_dashboard_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/daily_timeline_screen.dart';
import 'health/health_dashboard_screen.dart';
import 'profile/profile_screen.dart';
import 'gamification/ranking_screen.dart';
import 'package:canil_gcm/features/incidents/presentation/screens/occurrence_flow_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/dynamic_activity_sheet.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canil_gcm/services/permission_service.dart';

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

  // Helper para construir os itens da barra de navegação
  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return MaterialButton(
      minWidth: 40,
      onPressed: () => _onTabTapped(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isSelected ? Colors.cyanAccent : Colors.white54,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.cyanAccent : Colors.white54,
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Incident? _activeIncidentForDog(List<Incident> incidents, String dogId) {
    final openIncidents =
        incidents
            .where(
              (incident) => incident.dogId == dogId && incident.isInProgress,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (openIncidents.isEmpty) return null;
    return openIncidents.first;
  }

  String _dogNameFor(BuildContext context, String dogId) {
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    for (final dog in dogVM.dogs) {
      if (dog.id == dogId) return dog.name;
    }
    return dogVM.dogs.isNotEmpty ? dogVM.dogs.first.name : 'K9';
  }

  void _continueActiveIncident(
    BuildContext context, {
    required String dogId,
    required Incident incident,
  }) {
    HapticFeedback.lightImpact();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => OccurrenceFlowScreen(
          dogId: dogId,
          dogName: _dogNameFor(context, dogId),
          incident: incident,
        ),
      ),
    );
  }

  void _openActionSheet(BuildContext context, String dogId) {
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final dogName = dogVM.dogs
        .firstWhere(
          (d) => d.id == dogId,
          orElse: () => dogVM.dogs.isNotEmpty
              ? dogVM.dogs.first
              : throw Exception('Cão não encontrado'),
        )
        .name;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      builder: (BuildContext bc) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 24.0,
              horizontal: 16.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Título do Menu
                Text(
                  'CENTRAL DE REGISTRO',
                  style: GoogleFonts.oxanium(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.cyanAccent.withValues(alpha: 0.8),
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 24),
                // Grid de Opções
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildMenuOption(
                      context,
                      bc,
                      'OCORRÊNCIA',
                      Icons.local_police_outlined,
                      Colors.redAccent,
                      dogId,
                      dogName,
                      _categoryOccurrence,
                    ),
                    _buildMenuOption(
                      context,
                      bc,
                      'TREINO',
                      Icons.track_changes,
                      Colors.orangeAccent,
                      dogId,
                      dogName,
                      'Treino',
                    ),
                    _buildMenuOption(
                      context,
                      bc,
                      'SAÚDE',
                      Icons.medical_services_outlined,
                      const Color(0xFFFF00FF),
                      dogId,
                      dogName,
                      'Saude',
                    ),
                    _buildMenuOption(
                      context,
                      bc,
                      'ROTINA',
                      Icons.assignment_outlined,
                      Colors.cyanAccent,
                      dogId,
                      dogName,
                      'Rotina',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  // Design Tático dos Botões do Menu
  Widget _buildMenuOption(
    BuildContext rootContext,
    BuildContext menuContext,
    String title,
    IconData icon,
    Color color,
    String dogId,
    String dogName,
    String category,
  ) {
    return InkWell(
      onTap: () async {
        final rootNavigator = Navigator.of(rootContext, rootNavigator: true);
        if (category == _categoryOccurrence) {
          final incidentVM = Provider.of<IncidentViewModel>(
            rootContext,
            listen: false,
          );
          final openIncident = await incidentVM.findOpenIncident(dogId: dogId);
          if (!rootContext.mounted) return;
          if (Navigator.of(menuContext).canPop()) {
            Navigator.of(menuContext).pop();
          }
          if (openIncident != null) {
            final shouldContinue = await _showOpenIncidentDialog(rootContext);
            if (!rootContext.mounted || shouldContinue != true) return;
            rootNavigator.push(
              MaterialPageRoute(
                builder: (_) => OccurrenceFlowScreen(
                  dogId: dogId,
                  dogName: dogName,
                  incident: openIncident,
                ),
              ),
            );
            return;
          }
          rootNavigator.push(
            MaterialPageRoute(
              builder: (_) =>
                  OccurrenceFlowScreen(dogId: dogId, dogName: dogName),
            ),
          );
          return;
        }

        if (Navigator.of(menuContext).canPop()) {
          Navigator.of(menuContext).pop();
        }
        // Abre o formulário correto
        Future.microtask(() {
          if (!mounted) return;
          if (category == _categoryOccurrence) {
            rootNavigator.push(
              MaterialPageRoute(
                builder: (_) =>
                    OccurrenceFlowScreen(dogId: dogId, dogName: dogName),
              ),
            );
            return;
          }

          showModalBottomSheet(
            context: rootNavigator.context,
            useRootNavigator: true,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) => DynamicActivitySheet(
              category: category,
              dogId: dogId,
              dogName: dogName,
            ),
          );
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 150, // Largura para caber 2 botões por linha
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.shareTechMono(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showOpenIncidentDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: const Text(
          'Ocorrência em andamento',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Já existe uma ocorrência aberta para este K9. Continue o registro ou encerre antes de iniciar outra.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }
}

class _ActiveIncidentBanner extends StatelessWidget {
  final Incident incident;
  final String dogName;
  final VoidCallback onTap;

  const _ActiveIncidentBanner({
    required this.incident,
    required this.dogName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = (incident.type ?? 'Ocorrência').trim();
    final location = incident.location.trim().isEmpty
        ? 'Local não informado'
        : incident.location.trim();

    return SafeArea(
      top: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1220).withAlpha(244),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFFFFB84D).withAlpha(190),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFB84D).withAlpha(46),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
                const BoxShadow(
                  color: Colors.black54,
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB84D).withAlpha(24),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFFFB84D).withAlpha(150),
                    ),
                  ),
                  child: const Icon(
                    Icons.pending_actions_rounded,
                    color: Color(0xFFFFB84D),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'OCORRÊNCIA EM ANDAMENTO',
                        style: GoogleFonts.robotoMono(
                          color: const Color(0xFFFFB84D),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.oxanium(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$dogName • $location',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: Colors.white60,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB84D),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'CONTINUAR',
                    style: GoogleFonts.robotoMono(
                      color: const Color(0xFF070B14),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
