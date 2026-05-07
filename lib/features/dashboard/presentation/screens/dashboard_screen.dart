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

// -----------------------------------------------------------------------------
// Tab K9s - Bento Grid
// -----------------------------------------------------------------------------
class _K9sTab extends StatefulWidget {
  const _K9sTab();

  @override
  State<_K9sTab> createState() => _K9sTabState();
}

class _K9sTabState extends State<_K9sTab> {
  String? _lastFetchedDogId;

  @override
  Widget build(BuildContext context) {
    return Consumer4<
      AuthViewModel,
      UserViewModel,
      ShiftViewModel,
      IncidentViewModel
    >(
      builder: (context, authVM, userVM, shiftVM, incidentVM, _) {
        final fbUser = authVM.user;
        final currentRa = HandlerIdentityService.raFromUser(fbUser);
        final userModel = userVM.users.cast<UserModel?>().firstWhere(
          (u) => u?.ra == currentRa,
          orElse: () => null,
        );
        final displayName = userVM.displayNameFor(
          ra: currentRa,
          firebaseUser: fbUser,
        );
        final photoStr = userModel?.photoUrl ?? fbUser?.photoURL;
        final raStr = userModel?.ra ?? currentRa ?? '--';

        final activeDogId = shiftVM.activeDogId;
        if (shiftVM.hasActiveShift &&
            activeDogId != null &&
            activeDogId != _lastFetchedDogId) {
          _lastFetchedDogId = activeDogId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Provider.of<IncidentViewModel>(
              context,
              listen: false,
            ).fetchIncidentsForDog(activeDogId);
          });
        }

        return Consumer<DogViewModel>(
          builder: (context, dogVM, _) {
            final activeDog = shiftVM.hasActiveShift && activeDogId != null
                ? dogVM.dogs.cast<Dog?>().firstWhere(
                    (dog) => dog?.id == activeDogId,
                    orElse: () => null,
                  )
                : null;
            final openIncidents =
                activeDogId == null
                      ? const <Incident>[]
                      : incidentVM.incidents
                            .where(
                              (incident) =>
                                  incident.dogId == activeDogId &&
                                  incident.isInProgress,
                            )
                            .toList()
                  ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

            return CustomScrollView(
              slivers: [
                // AppBar
                SliverAppBar(
                  pinned: true,
                  backgroundColor: _hudBackground,
                  title: Text(
                    'CANIL GCM',
                    style: GoogleFonts.oxanium(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 1.6,
                    ),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _AvatarButton(
                        photoStr: photoStr,
                        displayName: displayName,
                        raStr: raStr,
                        authVM: authVM,
                      ),
                    ),
                  ],
                ),

                // Alert card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: _GreetingCard(
                      displayName: displayName,
                      trainingAlerts: dogVM.dogs
                          .where((d) => dogVM.hasTrainingAlert(d))
                          .length,
                      healthAlerts: dogVM.dogs
                          .where((d) => dogVM.hasHealthAlert(d))
                          .length,
                    ),
                  ),
                ),

                if (shiftVM.hasActiveShift &&
                    activeDog != null &&
                    openIncidents.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _DashboardOpenIncidentCard(
                        incident: openIncidents.first,
                        dogName: activeDog.name,
                        additionalCount: openIncidents.length - 1,
                        onContinue: () => _continueIncident(
                          activeDog.id,
                          activeDog.name,
                          openIncidents.first,
                        ),
                        onQuickClose: () => _showQuickCloseIncidentSheet(
                          openIncidents.first,
                          activeDog.id,
                          activeDog.name,
                        ),
                      ),
                    ),
                  ),

                // Section label
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _hudPanel.withAlpha(210),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _hudCyan.withAlpha(65)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _hudCyan.withAlpha(18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _hudCyan.withAlpha(120),
                              ),
                            ),
                            child: const Icon(
                              Icons.pets_rounded,
                              color: _hudCyan,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SELECIONE SEU CÃO',
                                  style: GoogleFonts.oxanium(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Cães operacionais disponíveis',
                                  style: GoogleFonts.robotoMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _hudCyan.withAlpha(16),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _hudCyan.withAlpha(120),
                              ),
                            ),
                            child: Text(
                              '${dogVM.dogs.length}',
                              style: GoogleFonts.robotoMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: _hudCyan,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Bento Grid body
                if (dogVM.isLoading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (dogVM.dogs.isEmpty)
                  SliverFillRemaining(
                    child: _EmptyState(
                      icon: FontAwesomeIcons.dog,
                      message: 'Nenhum cão cadastrado',
                      hint: 'Toque em + para adicionar',
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      child: _BentoDogGrid(dogs: dogVM.dogs, dogVM: dogVM),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _continueIncident(
    String dogId,
    String dogName,
    Incident incident,
  ) async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OccurrenceFlowScreen(
          dogId: dogId,
          dogName: dogName,
          incident: incident,
        ),
      ),
    );
  }

  Future<void> _showQuickCloseIncidentSheet(
    Incident incident,
    String dogId,
    String dogName,
  ) async {
    final incidentVM = Provider.of<IncidentViewModel>(context, listen: false);
    final noteController = TextEditingController();
    final selectedOutcomes = incident.outcomes.isNotEmpty
        ? <String>{...incident.outcomes}
        : _quickCloseDefaultOutcomesForSubtype(incident.type);
    var operationalSuccess = incident.operationalSuccess ?? true;

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              return Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  top: 16,
                ),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161618),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0x144ADE80),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0x334ADE80),
                                ),
                              ),
                              child: const Icon(
                                Icons.task_alt_rounded,
                                color: Color(0xFF4ADE80),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ENCERRAR OCORRÊNCIA',
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${incident.type ?? 'Ocorrência'} - ${incident.location}',
                                    style: GoogleFonts.inter(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'DESFECHO OPERACIONAL',
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _QuickIncidentChip(
                              label: 'Com êxito',
                              selected: operationalSuccess,
                              icon: Icons.task_alt_rounded,
                              selectedTextColor: const Color(0xFF86EFAC),
                              selectedIconColor: const Color(0xFF4ADE80),
                              selectedBorderColor: const Color(0x334ADE80),
                              selectedBackgroundColor: const Color(0x144ADE80),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setModalState(() {
                                  operationalSuccess = true;
                                });
                              },
                            ),
                            _QuickIncidentChip(
                              label: 'Sem êxito',
                              selected: !operationalSuccess,
                              icon: Icons.cancel_rounded,
                              selectedTextColor: const Color(0xFFFCA5A5),
                              selectedIconColor: const Color(0xFFF87171),
                              selectedBorderColor: const Color(0x33F87171),
                              selectedBackgroundColor: const Color(0x14F87171),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setModalState(() {
                                  operationalSuccess = false;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'RESULTADOS FINAIS',
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              _quickCloseOutcomeOptionsForSubtype(
                                incident.type,
                              ).map((outcome) {
                                final isSelected = selectedOutcomes.contains(
                                  outcome,
                                );
                                return _QuickIncidentChip(
                                  label: outcome,
                                  selected: isSelected,
                                  icon: _iconForOutcome(outcome),
                                  selectedTextColor: _textColorForOutcome(
                                    outcome,
                                  ),
                                  selectedIconColor: _iconColorForOutcome(
                                    outcome,
                                  ),
                                  selectedBorderColor: _borderColorForOutcome(
                                    outcome,
                                  ),
                                  selectedBackgroundColor:
                                      _backgroundColorForOutcome(outcome),
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setModalState(() {
                                      if (isSelected) {
                                        selectedOutcomes.remove(outcome);
                                      } else {
                                        selectedOutcomes.add(outcome);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: noteController,
                          maxLines: 3,
                          minLines: 2,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Atualização final',
                            labelStyle: GoogleFonts.inter(
                              color: Colors.white54,
                            ),
                            filled: true,
                            fillColor: Colors.white.withAlpha(6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                color: Color(0xFFFBBF24),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: const BorderSide(color: Colors.white12),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  'Cancelar',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  final now = DateTime.now();
                                  final updates =
                                      List<IncidentProgressUpdate>.from(
                                        incident.progressUpdates,
                                      );
                                  final note = noteController.text.trim();

                                  if (note.isNotEmpty) {
                                    updates.add(
                                      IncidentProgressUpdate(
                                        title: 'Encerramento da ocorrência',
                                        description: note,
                                        timestamp: now,
                                        location: incident.location,
                                      ),
                                    );
                                  }

                                  final closedIncident = incident.copyWith(
                                    status: 'Concluída',
                                    operationalSuccess: operationalSuccess,
                                    outcomes: selectedOutcomes.toList(),
                                    endedAt: now,
                                    updatedAt: now,
                                    result: _buildQuickCloseResultSummary(
                                      incident: incident,
                                      selectedOutcomes: selectedOutcomes,
                                      operationalSuccess: operationalSuccess,
                                    ),
                                    progressUpdates: updates,
                                  );

                                  await incidentVM.updateIncident(
                                    closedIncident,
                                  );
                                  if (!mounted) return;
                                  Navigator.of(this.context).pop();
                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Ocorrência encerrada com sucesso.',
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFFBBF24),
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  'Encerrar agora',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      noteController.dispose();
    }
  }

  Set<String> _quickCloseDefaultOutcomesForSubtype(String? subtype) {
    switch (subtype) {
      case 'supportVehicle':
      case 'serviceOrder':
      case 'event':
      case 'other':
        return {'Apoio prestado'};
      default:
        return <String>{};
    }
  }

  List<String> _quickCloseOutcomeOptionsForSubtype(String? subtype) {
    switch (subtype) {
      case 'detection':
      case 'narcoticsSearch':
        return const [
          'Droga apreendida',
          'Individuo detido',
          'Apoio prestado',
          'BO elaborado',
          'Encaminhamento medico',
          'Sem constatação',
        ];
      case 'supportVehicle':
        return const [
          'Apoio prestado',
          'Individuo detido',
          'Encaminhamento medico',
          'BO elaborado',
          'Local preservado',
          'Sem constatação',
        ];
      case 'missingPerson':
        return const [
          'Pessoa localizada',
          'Objeto localizado',
          'Apoio prestado',
          'Encaminhamento medico',
          'BO elaborado',
          'Sem constatação',
        ];
      case 'serviceOrder':
        return const [
          'Apoio prestado',
          'BO elaborado',
          'Local preservado',
          'Encaminhamento medico',
          'Sem constatação',
        ];
      case 'event':
        return const [
          'Apoio prestado',
          'Ação educativa concluída',
          'BO elaborado',
          'Sem constatação',
        ];
      case 'other':
        return const [
          'Apoio prestado',
          'Vitima socorrida',
          'Encaminhamento medico',
          'Trânsito sinalizado',
          'Local preservado',
          'BO elaborado',
          'Sem constatação',
        ];
      default:
        return const ['Apoio prestado', 'BO elaborado', 'Sem constatação'];
    }
  }

  String _buildQuickCloseResultSummary({
    required Incident incident,
    required Set<String> selectedOutcomes,
    required bool operationalSuccess,
  }) {
    if (selectedOutcomes.contains('Droga apreendida')) {
      return 'Apreensao positiva';
    }
    if (selectedOutcomes.contains('Pessoa localizada')) {
      return 'Sucesso';
    }
    if (selectedOutcomes.contains('Individuo detido')) {
      return 'Individuo detido';
    }
    if (selectedOutcomes.contains('Vitima socorrida')) {
      return 'Vitima socorrida';
    }
    if (selectedOutcomes.contains('Encaminhamento medico')) {
      return 'Encaminhamento medico';
    }
    if (selectedOutcomes.contains('Trânsito sinalizado')) {
      return 'Trânsito sinalizado';
    }
    if (selectedOutcomes.contains('Local preservado')) {
      return 'Local preservado';
    }
    if (selectedOutcomes.contains('Ação educativa concluída')) {
      return 'Ação educativa concluída';
    }
    if (selectedOutcomes.contains('Apoio prestado')) {
      return 'Apoio prestado';
    }
    if (selectedOutcomes.contains('BO elaborado')) {
      return 'BO elaborado';
    }
    if (selectedOutcomes.contains('Sem constatação')) {
      return 'Sem constatação';
    }
    return operationalSuccess ? 'Êxito' : 'Sem êxito';
  }

  IconData _iconForOutcome(String outcome) {
    final normalized = outcome.toLowerCase();
    if (normalized.contains('droga') || normalized.contains('apreens')) {
      return Icons.inventory_2_rounded;
    }
    if (normalized.contains('detido') || normalized.contains('preso')) {
      return Icons.gpp_good_rounded;
    }
    if (normalized.contains('localiz')) {
      return Icons.location_searching_rounded;
    }
    if (normalized.contains('apoio') ||
        normalized.contains('encaminhamento') ||
        normalized.contains('socorrida') ||
        normalized.contains('transito') ||
        normalized.contains('preservado')) {
      return Icons.volunteer_activism_rounded;
    }
    if (normalized.contains('sem constat')) {
      return Icons.search_off_rounded;
    }
    return Icons.fact_check_rounded;
  }

  Color _iconColorForOutcome(String outcome) {
    final normalized = outcome.toLowerCase();
    if (normalized.contains('droga') || normalized.contains('apreens')) {
      return const Color(0xFFFBBF24);
    }
    if (normalized.contains('detido') || normalized.contains('preso')) {
      return const Color(0xFFFB7185);
    }
    if (normalized.contains('localiz')) {
      return const Color(0xFF38BDF8);
    }
    if (normalized.contains('apoio') ||
        normalized.contains('encaminhamento') ||
        normalized.contains('socorrida') ||
        normalized.contains('transito') ||
        normalized.contains('preservado')) {
      return const Color(0xFF2DD4BF);
    }
    if (normalized.contains('sem constat')) {
      return const Color(0xFF94A3B8);
    }
    return const Color(0xFFA78BFA);
  }

  Color _textColorForOutcome(String outcome) {
    final normalized = outcome.toLowerCase();
    if (normalized.contains('droga') || normalized.contains('apreens')) {
      return const Color(0xFFFCD34D);
    }
    if (normalized.contains('detido') || normalized.contains('preso')) {
      return const Color(0xFFFDA4AF);
    }
    if (normalized.contains('localiz')) {
      return const Color(0xFF7DD3FC);
    }
    if (normalized.contains('apoio') ||
        normalized.contains('encaminhamento') ||
        normalized.contains('socorrida') ||
        normalized.contains('transito') ||
        normalized.contains('preservado')) {
      return const Color(0xFF99F6E4);
    }
    if (normalized.contains('sem constat')) {
      return const Color(0xFFCBD5E1);
    }
    return const Color(0xFFC4B5FD);
  }

  Color _borderColorForOutcome(String outcome) {
    final normalized = outcome.toLowerCase();
    if (normalized.contains('droga') || normalized.contains('apreens')) {
      return const Color(0x33FBBF24);
    }
    if (normalized.contains('detido') || normalized.contains('preso')) {
      return const Color(0x33FB7185);
    }
    if (normalized.contains('localiz')) {
      return const Color(0x3338BDF8);
    }
    if (normalized.contains('apoio') ||
        normalized.contains('encaminhamento') ||
        normalized.contains('socorrida') ||
        normalized.contains('transito') ||
        normalized.contains('preservado')) {
      return const Color(0x332DD4BF);
    }
    if (normalized.contains('sem constat')) {
      return const Color(0x3394A3B8);
    }
    return const Color(0x33A78BFA);
  }

  Color _backgroundColorForOutcome(String outcome) {
    final normalized = outcome.toLowerCase();
    if (normalized.contains('droga') || normalized.contains('apreens')) {
      return const Color(0x14FBBF24);
    }
    if (normalized.contains('detido') || normalized.contains('preso')) {
      return const Color(0x14FB7185);
    }
    if (normalized.contains('localiz')) {
      return const Color(0x1438BDF8);
    }
    if (normalized.contains('apoio') ||
        normalized.contains('encaminhamento') ||
        normalized.contains('socorrida') ||
        normalized.contains('transito') ||
        normalized.contains('preservado')) {
      return const Color(0x142DD4BF);
    }
    if (normalized.contains('sem constat')) {
      return const Color(0x1494A3B8);
    }
    return const Color(0x14A78BFA);
  }
}

// Bento Dog Grid --------------------------------------------------------------
class _BentoDogGrid extends StatelessWidget {
  final List<Dog> dogs;
  final DogViewModel dogVM;
  const _BentoDogGrid({required this.dogs, required this.dogVM});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Featured card (first dog - full width)
        _FeaturedDogCard(dog: dogs.first, dogVM: dogVM),
        const SizedBox(height: 10),

        // Remaining dogs in 2-column grid
        if (dogs.length > 1) _buildGrid(context, dogs.sublist(1)),
      ],
    );
  }

  Widget _buildGrid(BuildContext context, List<Dog> remaining) {
    final rows = <Widget>[];
    for (int i = 0; i < remaining.length; i += 2) {
      final left = remaining[i];
      final right = i + 1 < remaining.length ? remaining[i + 1] : null;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SmallDogCard(dog: left, dogVM: dogVM),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: right != null
                  ? _SmallDogCard(dog: right, dogVM: dogVM)
                  : const SizedBox(),
            ),
          ],
        ),
      );
      if (i + 2 < remaining.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }
}

// Featured Dog Card (full width) ----------------------------------------------
class _FeaturedDogCard extends StatelessWidget {
  final Dog dog;
  final DogViewModel dogVM;
  const _FeaturedDogCard({required this.dog, required this.dogVM});

  @override
  Widget build(BuildContext context) {
    final opStatus = dog.operationalStatus;
    final sColor = AppTheme.statusColor(opStatus);
    final sLabel = AppTheme.statusLabel(opStatus);
    final sIcon = AppTheme.statusIcon(opStatus);
    final hasTraining = dogVM.hasTrainingAlert(dog);
    final hasHealth = dogVM.hasHealthAlert(dog);

    String lastTrainingStr = '--';
    if (dog.lastTrainingDate != null) {
      final diff = DateTime.now().difference(dog.lastTrainingDate!).inDays;
      lastTrainingStr = diff == 0 ? 'Hoje' : '${diff}d';
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DogDetailsScreen(dog: dog)),
      ),
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(235),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _hudCyan.withAlpha(90), width: 1),
          boxShadow: [BoxShadow(color: _hudCyan.withAlpha(24), blurRadius: 18)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Photo (square left side)
            SizedBox(
              width: 130,
              child: dog.profileImageUrl != null
                  ? Image.network(dog.profileImageUrl!, fit: BoxFit.cover)
                  : Container(
                      color: _hudPanelAlt,
                      child: Center(
                        child: FaIcon(
                          FontAwesomeIcons.dog,
                          size: 40,
                          color: _hudCyan.withAlpha(160),
                        ),
                      ),
                    ),
            ),

            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top: status pill
                    Row(
                      children: [
                        _InlineStatusPill(
                          label: sLabel,
                          color: sColor,
                          icon: sIcon,
                        ),
                        const Spacer(),
                        if (hasHealth)
                          _TinyAlert(
                            icon: Icons.vaccines_rounded,
                            color: Colors.redAccent,
                          ),
                        if (hasTraining) ...[
                          const SizedBox(width: 4),
                          _TinyAlert(
                            icon: Icons.fitness_center_rounded,
                            color: Colors.orangeAccent,
                          ),
                        ],
                      ],
                    ),
                    // Name + breed
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dog.name.toUpperCase(),
                          style: GoogleFonts.oxanium(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 1.0,
                          ),
                        ),
                        Text(
                          dog.breed,
                          style: GoogleFonts.robotoMono(
                            fontSize: 11,
                            color: Colors.white54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    // Stats row
                    Row(
                      children: [
                        _MicroStat(label: 'Idade', value: '${dog.age}a'),
                        const SizedBox(width: 14),
                        _MicroStat(
                          label: 'Treino',
                          value: lastTrainingStr,
                          highlight: hasTraining,
                        ),
                        const SizedBox(width: 14),
                        Icon(
                          dog.sex == 'F'
                              ? Icons.female_rounded
                              : Icons.male_rounded,
                          size: 16,
                          color: dog.sex == 'F'
                              ? const Color(0xFFFF80AB)
                              : const Color(0xFF82B1FF),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Small Dog Card (2-column grid) ----------------------------------------------
class _SmallDogCard extends StatelessWidget {
  final Dog dog;
  final DogViewModel dogVM;
  const _SmallDogCard({required this.dog, required this.dogVM});

  @override
  Widget build(BuildContext context) {
    final opStatus = dog.operationalStatus;
    final sColor = AppTheme.statusColor(opStatus);
    final sLabel = AppTheme.statusLabel(opStatus);
    final sIcon = AppTheme.statusIcon(opStatus);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DogDetailsScreen(dog: dog)),
      ),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(230),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _hudCyan.withAlpha(65), width: 1),
          boxShadow: [BoxShadow(color: _hudCyan.withAlpha(16), blurRadius: 14)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info (top as title)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dog.name.toUpperCase(),
                    style: GoogleFonts.oxanium(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.7,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          dog.breed,
                          style: GoogleFonts.robotoMono(
                            fontSize: 10,
                            color: Colors.white54,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _InlineStatusPill(
                        label: sLabel,
                        color: sColor,
                        icon: sIcon,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Photo (bottom)
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: dog.profileImageUrl != null
                    ? Image.network(
                        dog.profileImageUrl!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      )
                    : Container(
                        color: _hudPanelAlt,
                        child: Center(
                          child: FaIcon(
                            FontAwesomeIcons.dog,
                            size: 32,
                            color: _hudCyan.withAlpha(145),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Inline status pill ----------------------------------------------------------
class _InlineStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _InlineStatusPill({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.robotoMono(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyAlert extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _TinyAlert({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Icon(icon, size: 14, color: color);
}

class _MicroStat extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _MicroStat({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.oxanium(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: highlight ? _hudAmber : Colors.white,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.robotoMono(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            color: Colors.white54,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// Avatar button ---------------------------------------------------------------
class _AvatarButton extends StatelessWidget {
  final String? photoStr;
  final String displayName;
  final String raStr;
  final AuthViewModel authVM;
  const _AvatarButton({
    required this.photoStr,
    required this.displayName,
    required this.raStr,
    required this.authVM,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _ProfileSheet(
          displayName: displayName,
          raStr: raStr,
          authVM: authVM,
          photoStr: photoStr,
        ),
      ),
      child: CircleAvatar(
        radius: 18,
        backgroundColor: cs.secondaryContainer,
        backgroundImage: photoStr != null ? NetworkImage(photoStr!) : null,
        child: photoStr == null
            ? Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'O',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.onSecondaryContainer,
                ),
              )
            : null,
      ),
    );
  }
}

class _ProfileSheet extends StatelessWidget {
  final String displayName;
  final String raStr;
  final String? photoStr;
  final AuthViewModel authVM;
  const _ProfileSheet({
    required this.displayName,
    required this.raStr,
    required this.photoStr,
    required this.authVM,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: cs.secondaryContainer,
            backgroundImage: photoStr != null ? NetworkImage(photoStr!) : null,
            child: photoStr == null
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'O',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: cs.onSecondaryContainer,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          Text(displayName, style: Theme.of(context).textTheme.titleLarge),
          if (raStr != '--')
            Text(
              'RA: $raStr',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              authVM.signOut();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sair do sistema'),
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
          ),
        ],
      ),
    );
  }
}

// Greeting card ---------------------------------------------------------------
class _GreetingCard extends StatelessWidget {
  final String displayName;
  final int trainingAlerts;
  final int healthAlerts;
  const _GreetingCard({
    required this.displayName,
    required this.trainingAlerts,
    required this.healthAlerts,
  });

  @override
  Widget build(BuildContext context) {
    final total = trainingAlerts + healthAlerts;
    final now = DateTime.now();
    final months = [
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez',
    ];
    final dateStr = '${now.day} de ${months[now.month - 1]}';

    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(225),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _hudCyan.withAlpha(65)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: _hudCyan, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tudo em dia',
                    style: GoogleFonts.oxanium(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$dateStr · Sem alertas operacionais',
                    style: GoogleFonts.robotoMono(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudDanger.withAlpha(105), width: 0.8),
        boxShadow: [BoxShadow(color: _hudDanger.withAlpha(24), blurRadius: 16)],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _hudDanger, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total alerta${total > 1 ? 's' : ''} operacional${total > 1 ? 'is' : ''}',
                  style: GoogleFonts.oxanium(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
                if (trainingAlerts > 0)
                  Text(
                    '• $trainingAlerts cão sem treino há +3 dias',
                    style: GoogleFonts.robotoMono(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (healthAlerts > 0)
                  Text(
                    '• $healthAlerts vacina${healthAlerts > 1 ? 's' : ''} vencida${healthAlerts > 1 ? 's' : ''}',
                    style: GoogleFonts.robotoMono(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardOpenIncidentCard extends StatelessWidget {
  final Incident incident;
  final String dogName;
  final int additionalCount;
  final VoidCallback onContinue;
  final VoidCallback onQuickClose;

  const _DashboardOpenIncidentCard({
    required this.incident,
    required this.dogName,
    required this.additionalCount,
    required this.onContinue,
    required this.onQuickClose,
  });

  @override
  Widget build(BuildContext context) {
    final latestUpdate = incident.progressUpdates.isNotEmpty
        ? incident.progressUpdates.last
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x33FBBF24)),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 18, spreadRadius: 1),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0x14FBBF24),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0x33FBBF24)),
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: Color(0xFFFBBF24),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OCORRÊNCIA EM ANDAMENTO',
                      style: GoogleFonts.inter(
                        color: const Color(0xFFFCD34D),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      incident.location,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${incident.type ?? 'Ocorrência'} • $dogName',
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (additionalCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    '+$additionalCount aberta(s)',
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _IncidentDashboardPill(
                icon: Icons.schedule_rounded,
                label: 'Aberta',
                value: _formatDashboardIncidentRelative(incident.startedAt),
              ),
              _IncidentDashboardPill(
                icon: Icons.update_rounded,
                label: 'Atualizada',
                value: _formatDashboardIncidentTimestamp(incident.updatedAt),
              ),
              if (incident.outcomes.isNotEmpty)
                _IncidentDashboardPill(
                  icon: Icons.fact_check_rounded,
                  label: 'Resultados',
                  value: '${incident.outcomes.length} marcados',
                ),
            ],
          ),
          if (incident.outcomes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: incident.outcomes
                  .map(
                    (outcome) => _QuickIncidentChip(
                      label: outcome,
                      selected: true,
                      icon: Icons.fact_check_rounded,
                      selectedTextColor: const Color(0xFFFCD34D),
                      selectedIconColor: const Color(0xFFFBBF24),
                      selectedBorderColor: const Color(0x33FBBF24),
                      selectedBackgroundColor: const Color(0x14FBBF24),
                      onTap: () {},
                    ),
                  )
                  .toList(),
            ),
          ],
          if (latestUpdate != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    latestUpdate.title.toUpperCase(),
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    latestUpdate.description.isNotEmpty
                        ? latestUpdate.description
                        : incident.description,
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onContinue,
                  icon: const Icon(Icons.playlist_add_check_rounded, size: 16),
                  label: Text(
                    'Continuar ocorrência',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white12),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onQuickClose,
                  icon: const Icon(Icons.task_alt_rounded, size: 16),
                  label: Text(
                    'Encerrar agora',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFBBF24),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDashboardIncidentRelative(DateTime startedAt) {
    final diff = DateTime.now().difference(startedAt);
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) {
      return '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    }
    return '${diff.inMinutes.clamp(0, 59)}m';
  }

  String _formatDashboardIncidentTimestamp(DateTime timestamp) {
    return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')} '
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}

class _IncidentDashboardPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _IncidentDashboardPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFFBBF24)),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickIncidentChip extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData icon;
  final Color selectedTextColor;
  final Color selectedIconColor;
  final Color selectedBorderColor;
  final Color selectedBackgroundColor;
  final VoidCallback onTap;

  const _QuickIncidentChip({
    required this.label,
    required this.selected,
    required this.icon,
    required this.selectedTextColor,
    required this.selectedIconColor,
    required this.selectedBorderColor,
    required this.selectedBackgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? selectedBackgroundColor : Colors.white.withAlpha(6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? selectedBorderColor : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? selectedIconColor : Colors.white54,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                color: selected ? selectedTextColor : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Tab Treinos
// -----------------------------------------------------------------------------
class _TreinosTab extends StatelessWidget {
  const _TreinosTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<DogViewModel>(
      builder: (context, dogVM, _) {
        return CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: _hudBackground,
              title: Text(
                'TREINOS',
                style: GoogleFonts.oxanium(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 1.6,
                ),
              ),
            ),
            if (dogVM.isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: _hudCyan),
                ),
              )
            else if (dogVM.dogs.isEmpty)
              SliverFillRemaining(
                child: _EmptyState(
                  icon: FontAwesomeIcons.dog,
                  message: 'Nenhum cão cadastrado',
                  hint: 'Cadastre um cão para registrar treinos',
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _hudPanel.withAlpha(210),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _hudCyan.withAlpha(65)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _hudAmber.withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: _hudAmber.withAlpha(130)),
                          ),
                          child: const Icon(
                            Icons.fitness_center_rounded,
                            color: _hudAmber,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SELECIONE O CÃO PARA TREINO',
                                style: GoogleFonts.oxanium(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Acesse o diário operacional e registre uma sessão.',
                                style: GoogleFonts.robotoMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList.separated(
                  itemCount: dogVM.dogs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final d = dogVM.dogs[i];
                    return _TrainingDogLaunchCard(
                      dog: d,
                      dogVM: dogVM,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TrainingLogScreen(dogId: d.id),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TrainingDogLaunchCard extends StatelessWidget {
  final Dog dog;
  final DogViewModel dogVM;
  final VoidCallback onTap;

  const _TrainingDogLaunchCard({
    required this.dog,
    required this.dogVM,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasTrainingAlert = dogVM.hasTrainingAlert(dog);
    final lastTraining = dog.lastTrainingDate == null
        ? 'Sem registro recente'
        : _formatTrainingAge(dog.lastTrainingDate!);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(230),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: hasTrainingAlert
                ? _hudAmber.withAlpha(140)
                : _hudCyan.withAlpha(65),
          ),
          boxShadow: [
            BoxShadow(
              color: (hasTrainingAlert ? _hudAmber : _hudCyan).withAlpha(18),
              blurRadius: 16,
            ),
          ],
        ),
        child: Row(
          children: [
            _DogAvatar(dog: dog, radius: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dog.name.toUpperCase(),
                    style: GoogleFonts.oxanium(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.9,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dog.breed,
                    style: GoogleFonts.robotoMono(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _TrainingInfoChip(
                        icon: Icons.schedule_rounded,
                        label: lastTraining,
                        color: hasTrainingAlert ? _hudAmber : _hudCyan,
                      ),
                      _TrainingInfoChip(
                        icon: Icons.monitor_weight_outlined,
                        label: dog.weight != null
                            ? '${dog.weight!.toStringAsFixed(1)} kg'
                            : 'Peso pendente',
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _hudCyan.withAlpha(18),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _hudCyan.withAlpha(100)),
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                color: _hudCyan,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTrainingAge(DateTime date) {
    final diff = DateTime.now().difference(date).inDays;
    if (diff <= 0) return 'Treino hoje';
    if (diff == 1) return 'Treino há 1 dia';
    return 'Treino há $diff dias';
  }
}

class _TrainingInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _TrainingInfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.robotoMono(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Tab Guardas
// -----------------------------------------------------------------------------
class _GuardasTab extends StatelessWidget {
  const _GuardasTab();

  @override
  Widget build(BuildContext context) => const UserManagementScreen();
}

// Dog Avatar ------------------------------------------------------------------
class _DogAvatar extends StatelessWidget {
  final Dog dog;
  final double radius;
  const _DogAvatar({required this.dog, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _hudCyan.withAlpha(125), width: 1.5),
        boxShadow: [BoxShadow(color: _hudCyan.withAlpha(28), blurRadius: 12)],
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: _hudPanelAlt,
        backgroundImage: dog.profileImageUrl != null
            ? NetworkImage(dog.profileImageUrl!)
            : null,
        child: dog.profileImageUrl == null
            ? FaIcon(
                FontAwesomeIcons.dog,
                size: radius * 0.8,
                color: _hudCyan.withAlpha(180),
              )
            : null,
      ),
    );
  }
}

// Empty state -----------------------------------------------------------------
class _EmptyState extends StatelessWidget {
  final dynamic icon;
  final String message;
  final String hint;
  const _EmptyState({
    required this.icon,
    required this.message,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon is IconData
              ? Icon(icon as IconData, size: 64, color: cs.outlineVariant)
              : FaIcon(icon as dynamic, size: 64, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Kept for backward compat if any screen still uses DogCard
class DogCard extends StatelessWidget {
  final Dog dog;
  final DogViewModel dogVM;
  const DogCard({super.key, required this.dog, required this.dogVM});

  @override
  Widget build(BuildContext context) =>
      _FeaturedDogCard(dog: dog, dogVM: dogVM);
}
