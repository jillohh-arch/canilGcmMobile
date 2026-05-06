import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:timeline_tile/timeline_tile.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:canil_gcm/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/viewmodels/routine_viewmodel.dart';
import 'package:canil_gcm/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/services/report_service.dart';
import 'package:canil_gcm/services/handler_identity_service.dart';
import 'package:canil_gcm/widgets/hud_tab_bar.dart';
import '../../models/training_session_model.dart';
import 'package:canil_gcm/features/incidents/presentation/screens/occurrence_flow_screen.dart';
import 'dynamic_activity_sheet.dart';

class _IncidentQuickProgressShortcut {
  final String title;
  final String template;

  const _IncidentQuickProgressShortcut({
    required this.title,
    required this.template,
  });
}

class _IncidentProgressStyle {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final Color titleColor;
  final Color backgroundColor;
  final Color borderColor;

  const _IncidentProgressStyle({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.titleColor,
    required this.backgroundColor,
    required this.borderColor,
  });
}

class _IncidentBadgeStyle {
  final IconData icon;
  final Color iconColor;
  final Color textColor;
  final Color backgroundColor;
  final Color borderColor;

  const _IncidentBadgeStyle({
    required this.icon,
    required this.iconColor,
    required this.textColor,
    required this.backgroundColor,
    required this.borderColor,
  });
}

const _hudBackground = Color(0xFF070B14);
const _hudPanel = Color(0xFF0B1220);
const _hudCyan = Color(0xFF00E5FF);
const _hudAmber = Color(0xFFFBBF24);

class DailyTimelineScreen extends StatefulWidget {
  const DailyTimelineScreen({super.key});

  @override
  State<DailyTimelineScreen> createState() => _DailyTimelineScreenState();
}

class _DailyTimelineScreenState extends State<DailyTimelineScreen>
    with SingleTickerProviderStateMixin {
  DateTime _selectedDate = DateTime.now();
  String? _selectedTrainingFilter; // null = Todos
  late TabController _tabController;

  static const _trainingCategories = [
    'Faro',
    'Busca & Captura',
    'Guarda',
    'Obediência',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Ensure incidents are loaded when this screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
      if (shiftVM.hasActiveShift) {
        Provider.of<IncidentViewModel>(
          context,
          listen: false,
        ).fetchIncidentsForDog(shiftVM.activeDogId!);
        Provider.of<TrainingViewModel>(
          context,
          listen: false,
        ).fetchTrainingsForDog(shiftVM.activeDogId!);
        Provider.of<RoutineViewModel>(
          context,
          listen: false,
        ).fetchRoutinesForDog(shiftVM.activeDogId!);
        Provider.of<HealthViewModel>(
          context,
          listen: false,
        ).fetchHealthLogsForDog(shiftVM.activeDogId!);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _currentOperatorId() {
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    return HandlerIdentityService.raFromUser(authVM.user) ?? '';
  }

  String _currentOperatorName(String currentRa) {
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    return userVM.displayNameFor(ra: currentRa, firebaseUser: authVM.user);
  }

  IncidentProgressUpdate _authoredIncidentUpdate({
    required String title,
    required String description,
    required DateTime timestamp,
    String? location,
  }) {
    final currentRa = _currentOperatorId();
    return IncidentProgressUpdate(
      title: title,
      description: description,
      timestamp: timestamp,
      location: location,
      authorId: currentRa,
      authorName: _currentOperatorName(currentRa),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    if (!shiftVM.hasActiveShift) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: Text(
            'Nenhum turno ativo.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
        ),
      );
    }

    final dogId = shiftVM.activeDogId!;
    return Scaffold(
      backgroundColor: _hudBackground,
      appBar: AppBar(
        title: Text(
          'LINHA DO TEMPO',
          style: GoogleFonts.oxanium(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Colors.white,
            letterSpacing: 1.4,
          ),
        ),
        backgroundColor: _hudBackground,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Exportar PDF',
            icon: const Icon(
              Icons.picture_as_pdf_rounded,
              color: Color(0xFFFBBF24),
            ),
            onPressed: () => _exportPdf(context, dogId),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(74),
          child: HudTabBar(
            controller: _tabController,
            tabs: const [
              Tab(
                icon: Icon(Icons.shield_outlined, size: 22),
                text: 'Ocorrências',
              ),
              Tab(
                icon: Icon(Icons.track_changes_rounded, size: 22),
                text: 'Treinos',
              ),
              Tab(
                icon: Icon(Icons.bar_chart_rounded, size: 22),
                text: 'Evolução',
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: ocorrências
          _buildOccurrencesTab(dogId),
          // Tab 2: treinos e rotina
          _buildTrainingsTab(dogId),
          // Tab 3: evolução
          _buildEvolutionTab(dogId),
        ],
      ),
    );
  }

  // Conteúdo da aba de ocorrências
  Widget _buildOccurrencesTab(String dogId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderDate(),
          _buildDateSelector(),
          _buildTimelineList(dogId, filterType: 'Ocorrência'),
        ],
      ),
    );
  }

  // Mantido como fallback para uma possível visão compacta de ocorrências abertas.
  // ignore: unused_element
  Widget _buildOpenIncidentsSection(String dogId) {
    final iVM = Provider.of<IncidentViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final dogName = dogVM.dogs
        .firstWhere(
          (d) => d.id == dogId,
          orElse: () => dogVM.dogs.isNotEmpty
              ? dogVM.dogs.first
              : throw Exception('Cão não encontrado'),
        )
        .name;

    final openIncidents =
        iVM.incidents
            .where(
              (incident) => incident.dogId == dogId && incident.isInProgress,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (openIncidents.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBBF24).withAlpha(28),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFFBBF24).withAlpha(90),
                  ),
                ),
                child: const Icon(
                  Icons.pending_actions_rounded,
                  color: Color(0xFFFBBF24),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OCORRÊNCIAS EM ANDAMENTO',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${openIncidents.length} caso(s) aberto(s) para continuidade',
                      style: GoogleFonts.inter(
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
          const SizedBox(height: 12),
          ...openIncidents.map(
            (incident) => _buildOpenIncidentCard(
              dogId: dogId,
              dogName: dogName,
              incident: incident,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpenIncidentCard({
    required String dogId,
    required String dogName,
    required Incident incident,
  }) {
    final accent = const Color(0xFFFBBF24);
    final latestUpdate = incident.progressUpdates.isNotEmpty
        ? incident.progressUpdates.last
        : null;
    final statusStyle = _resolveIncidentStatusBadgeStyle(incident.status);
    final resultLabel = incident.displayResult.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(18),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (incident.type ?? 'Ocorrência').toUpperCase(),
                      style: GoogleFonts.inter(
                        color: accent,
                        fontSize: 10,
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
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildIncidentBadge(
                          label: incident.status.toUpperCase(),
                          style: statusStyle,
                        ),
                        if (resultLabel.isNotEmpty &&
                            resultLabel.toLowerCase() !=
                                incident.status.toLowerCase())
                          _buildIncidentBadge(
                            label: resultLabel,
                            style: _resolveIncidentOutcomeBadgeStyle(
                              resultLabel,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accent.withAlpha(70)),
                ),
                child: Icon(Icons.radar_rounded, color: accent, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildOpenIncidentStat(
                icon: Icons.schedule_rounded,
                label: 'Aberta',
                value: _formatIncidentRelative(incident.startedAt),
              ),
              _buildOpenIncidentStat(
                icon: Icons.update_rounded,
                label: 'Atualizada',
                value: _formatIncidentTimestamp(incident.updatedAt),
              ),
              if (incident.outcomes.isNotEmpty)
                _buildOpenIncidentStat(
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
                    (outcome) => _buildIncidentBadge(
                      label: outcome,
                      style: _resolveIncidentOutcomeBadgeStyle(outcome),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (latestUpdate != null) ...[
            const SizedBox(height: 12),
            _buildIncidentLatestUpdateCard(
              incident: incident,
              latestUpdate: latestUpdate,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showUnifiedUpdateSheet(
                    incident: incident,
                    dogId: dogId,
                    dogName: dogName,
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: Text(
                    'Atualizar',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
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
                  onPressed: () => _showQuickCloseIncidentSheet(
                    dogId: dogId,
                    dogName: dogName,
                    incident: incident,
                  ),
                  icon: const Icon(Icons.task_alt_rounded, size: 16),
                  label: Text(
                    'Encerrar',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
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

  Widget _buildOpenIncidentStat({
    required IconData icon,
    required String label,
    required String value,
  }) {
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
              mainAxisSize: MainAxisSize.min,
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

  Widget _buildIncidentLatestUpdateCard({
    required Incident incident,
    required IncidentProgressUpdate latestUpdate,
  }) {
    final progressStyle = _resolveIncidentProgressStyle(
      latestUpdate.title,
      latestUpdate.description,
    );
    final location = (latestUpdate.location ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: progressStyle.backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: progressStyle.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: progressStyle.iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(
              progressStyle.icon,
              size: 16,
              color: progressStyle.iconColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  latestUpdate.title.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: progressStyle.titleColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
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
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildIncidentMetaPill(
                      icon: Icons.schedule_rounded,
                      label: _formatIncidentTimestamp(latestUpdate.timestamp),
                    ),
                    if (location.isNotEmpty)
                      _buildIncidentMetaPill(
                        icon: Icons.place_rounded,
                        label: location,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentBadge({
    required String label,
    required _IncidentBadgeStyle style,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: style.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 13, color: style.iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: style.textColor,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentMetaPill({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white54),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white60,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentQuickSheetHeader({
    required String title,
    required Incident incident,
    required _IncidentBadgeStyle badgeStyle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: badgeStyle.backgroundColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: badgeStyle.borderColor),
              ),
              child: Icon(
                badgeStyle.icon,
                color: badgeStyle.iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
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
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildIncidentBadge(
              label: incident.status.toUpperCase(),
              style: _resolveIncidentStatusBadgeStyle(incident.status),
            ),
            _buildIncidentMetaPill(
              icon: Icons.schedule_rounded,
              label: _formatIncidentTimestamp(incident.updatedAt),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIncidentSelectionChip({
    required String label,
    required bool selected,
    required _IncidentBadgeStyle style,
    required VoidCallback onTap,
  }) {
    final effectiveStyle = selected
        ? style
        : _IncidentBadgeStyle(
            icon: style.icon,
            iconColor: Colors.white54,
            textColor: Colors.white70,
            backgroundColor: Colors.white.withAlpha(6),
            borderColor: Colors.white12,
          );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: effectiveStyle.backgroundColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: effectiveStyle.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              effectiveStyle.icon,
              size: 13,
              color: effectiveStyle.iconColor,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                color: effectiveStyle.textColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUnifiedUpdateSheet({
    required Incident incident,
    required String dogId,
    required String dogName,
  }) async {
    final incidentVM = Provider.of<IncidentViewModel>(context, listen: false);
    final noteController = TextEditingController();
    final selectedOutcomes = <String>{...incident.outcomes};
    final shortcuts = _quickProgressShortcutsForSubtype(incident.type);
    String? selectedShortcut;

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
                    color: const Color(0xFF0F1923),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF4ECDE4).withAlpha(60),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4ECDE4).withAlpha(15),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4ECDE4).withAlpha(25),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFF4ECDE4).withAlpha(80),
                                ),
                              ),
                              child: const Icon(
                                Icons.edit_rounded,
                                color: Color(0xFF4ECDE4),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ATUALIZAR OCORRÊNCIA',
                                    style: GoogleFonts.oxanium(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  Text(
                                    incident.location,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: Colors.white38,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        if (shortcuts.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text(
                            'ETAPAS RÁPIDAS',
                            style: GoogleFonts.inter(
                              color: Colors.white38,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: shortcuts.map((s) {
                              final isSelected = selectedShortcut == s.title;
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  setModalState(() {
                                    if (isSelected) {
                                      selectedShortcut = null;
                                      noteController.clear();
                                    } else {
                                      selectedShortcut = s.title;
                                      noteController.text = s.template;
                                    }
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF4ECDE4).withAlpha(25)
                                        : Colors.white.withAlpha(6),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(
                                              0xFF4ECDE4,
                                            ).withAlpha(100)
                                          : Colors.white10,
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Text(
                                    s.title,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? const Color(0xFF4ECDE4)
                                          : Colors.white54,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],

                        const SizedBox(height: 18),
                        Text(
                          'DESFECHOS PARCIAIS',
                          style: GoogleFonts.inter(
                            color: Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
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
                                return _buildIncidentSelectionChip(
                                  label: outcome,
                                  selected: isSelected,
                                  style: _resolveIncidentOutcomeBadgeStyle(
                                    outcome,
                                  ),
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
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Descreva o andamento da ocorrência...',
                            hintStyle: GoogleFonts.inter(
                              color: Colors.white24,
                              fontSize: 12,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF141C20),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                color: Color(0xFF1D2C33),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                color: Color(0xFF4ECDE4),
                                width: 1.5,
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
                                  foregroundColor: Colors.white54,
                                  side: const BorderSide(color: Colors.white10),
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
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  final note = noteController.text.trim();
                                  if (selectedShortcut == null &&
                                      note.isEmpty &&
                                      selectedOutcomes.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Selecione uma etapa, desfecho ou descreva o andamento.',
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    return;
                                  }

                                  final now = DateTime.now();
                                  final title =
                                      selectedShortcut ??
                                      (selectedOutcomes.isNotEmpty
                                          ? selectedOutcomes.first
                                          : 'Atualização operacional');
                                  final description = note.isNotEmpty
                                      ? note
                                      : selectedOutcomes.isNotEmpty
                                      ? 'Desfechos: ${selectedOutcomes.join(', ')}.'
                                      : 'Andamento registrado.';

                                  final updates =
                                      List<IncidentProgressUpdate>.from(
                                        incident.progressUpdates,
                                      )..add(
                                        _authoredIncidentUpdate(
                                          title: title,
                                          description: description,
                                          timestamp: now,
                                          location: incident.location,
                                        ),
                                      );

                                  final updated = incident.copyWith(
                                    status: 'Em andamento',
                                    outcomes: selectedOutcomes.toList(),
                                    updatedAt: now,
                                    result: selectedOutcomes.isNotEmpty
                                        ? selectedOutcomes.first
                                        : incident.result,
                                    progressUpdates: updates,
                                  );

                                  await incidentVM.updateIncident(updated);
                                  if (!mounted) return;
                                  Navigator.of(this.context).pop();
                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text('Ocorrência atualizada.'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF004E5B),
                                  foregroundColor: const Color(0xFF4ECDE4),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    side: const BorderSide(
                                      color: Color(0xFF4ECDE4),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Salvar atualização',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
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

  Future<void> _showQuickCloseIncidentSheet({
    required String dogId,
    required String dogName,
    required Incident incident,
  }) async {
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
                        _buildIncidentQuickSheetHeader(
                          title: 'ENCERRAR OCORRÊNCIA',
                          incident: incident,
                          badgeStyle: const _IncidentBadgeStyle(
                            icon: Icons.task_alt_rounded,
                            iconColor: Color(0xFF4ADE80),
                            textColor: Color(0xFF86EFAC),
                            backgroundColor: Color(0x144ADE80),
                            borderColor: Color(0x334ADE80),
                          ),
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
                          children: ['Com êxito', 'Sem êxito'].map((option) {
                            final isSelected =
                                operationalSuccess == (option == 'Com êxito');
                            return _buildIncidentSelectionChip(
                              label: option,
                              selected: isSelected,
                              style: option == 'Com êxito'
                                  ? const _IncidentBadgeStyle(
                                      icon: Icons.task_alt_rounded,
                                      iconColor: Color(0xFF4ADE80),
                                      textColor: Color(0xFF86EFAC),
                                      backgroundColor: Color(0x144ADE80),
                                      borderColor: Color(0x334ADE80),
                                    )
                                  : const _IncidentBadgeStyle(
                                      icon: Icons.cancel_rounded,
                                      iconColor: Color(0xFFF87171),
                                      textColor: Color(0xFFFCA5A5),
                                      backgroundColor: Color(0x14F87171),
                                      borderColor: Color(0x33F87171),
                                    ),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setModalState(() {
                                  operationalSuccess = option == 'Com êxito';
                                });
                              },
                            );
                          }).toList(),
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
                                return _buildIncidentSelectionChip(
                                  label: outcome,
                                  selected: isSelected,
                                  style: _resolveIncidentOutcomeBadgeStyle(
                                    outcome,
                                  ),
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

                                  updates.add(
                                    _authoredIncidentUpdate(
                                      title: 'Encerramento da ocorrência',
                                      description: note.isNotEmpty
                                          ? note
                                          : 'Ocorrência encerrada pela equipe.',
                                      timestamp: now,
                                      location: incident.location,
                                    ),
                                  );

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
                                  if (!mounted) {
                                    return;
                                  }
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
                                  'Encerrar',
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

  List<_IncidentQuickProgressShortcut> _quickProgressShortcutsForSubtype(
    String? subtype,
  ) {
    const common = [
      _IncidentQuickProgressShortcut(
        title: 'Conduzido a Santa Casa',
        template: 'Conduzido à Santa Casa para avaliação/perícia médica.',
      ),
      _IncidentQuickProgressShortcut(
        title: 'Apresentado no DP',
        template:
            'Ocorrência apresentada no Distrito Policial para as providências cabíveis.',
      ),
      _IncidentQuickProgressShortcut(
        title: 'Aguardando perícia',
        template: 'Equipe aguardando perícia para continuidade da ocorrência.',
      ),
      _IncidentQuickProgressShortcut(
        title: 'Aguardando vaga',
        template:
            'Equipe aguardando vaga/recepção para prosseguimento da apresentação.',
      ),
      _IncidentQuickProgressShortcut(
        title: 'Encerrada apresentação',
        template:
            'Apresentação encerrada, aguardando consolidação do desfecho final.',
      ),
    ];

    switch (subtype) {
      case 'detection':
      case 'narcoticsSearch':
        return const [
          _IncidentQuickProgressShortcut(
            title: 'Material localizado',
            template:
                'K9 indicou positivamente e o material foi localizado no ponto de busca.',
          ),
          _IncidentQuickProgressShortcut(
            title: 'Aguardando pesagem',
            template:
                'Material apreendido, aguardando pesagem/quantificação oficial.',
          ),
          ...common,
        ];
      case 'missingPerson':
        return const [
          _IncidentQuickProgressShortcut(
            title: 'Varredura em andamento',
            template:
                'Varredura em andamento na área informada com apoio do K9.',
          ),
          _IncidentQuickProgressShortcut(
            title: 'Pessoa localizada',
            template:
                'Pessoa localizada e equipe seguindo para os procedimentos posteriores.',
          ),
          ...common,
        ];
      case 'supportVehicle':
        return const [
          _IncidentQuickProgressShortcut(
            title: 'Apoio no local',
            template:
                'Equipe no local prestando apoio operacional à guarnição solicitante.',
          ),
          _IncidentQuickProgressShortcut(
            title: 'Guarnição apoiada',
            template:
                'Apoio prestado à guarnição no local, ocorrência seguindo em atendimento.',
          ),
          ...common,
        ];
      case 'serviceOrder':
        return const [
          _IncidentQuickProgressShortcut(
            title: 'Fiscalização em andamento',
            template:
                'Fiscalização em andamento conforme Ordem de Serviço, sem desfecho final até o momento.',
          ),
          ...common,
        ];
      case 'event':
        return const [
          _IncidentQuickProgressShortcut(
            title: 'Ação educativa em andamento',
            template:
                'Ação educativa/palestra em andamento com acompanhamento da equipe.',
          ),
          ...common,
        ];
      case 'other':
        return const [
          _IncidentQuickProgressShortcut(
            title: 'Local preservado',
            template:
                'Local preservado pela equipe até a chegada/atuação do órgão competente.',
          ),
          _IncidentQuickProgressShortcut(
            title: 'Trânsito sinalizado',
            template:
                'Trânsito sinalizado e fluxo organizado para segurança no local.',
          ),
          ...common,
        ];
      default:
        return common;
    }
  }

  List<String> _quickCloseOutcomeOptionsForSubtype(String? subtype) {
    switch (subtype) {
      case 'detection':
      case 'narcoticsSearch':
        return const [
          'Droga apreendida',
          'Indivíduo detido',
          'Apoio prestado',
          'BO elaborado',
          'Encaminhamento médico',
          'Sem constatação',
        ];
      case 'supportVehicle':
        return const [
          'Apoio prestado',
          'Indivíduo detido',
          'Encaminhamento médico',
          'BO elaborado',
          'Local preservado',
          'Sem constatação',
        ];
      case 'missingPerson':
        return const [
          'Pessoa localizada',
          'Objeto localizado',
          'Apoio prestado',
          'Encaminhamento médico',
          'BO elaborado',
          'Sem constatação',
        ];
      case 'serviceOrder':
        return const [
          'Apoio prestado',
          'BO elaborado',
          'Local preservado',
          'Encaminhamento médico',
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
          'Vítima socorrida',
          'Encaminhamento médico',
          'Trânsito sinalizado',
          'Local preservado',
          'Indivíduo detido',
          'BO elaborado',
          'Sem constatação',
        ];
      default:
        return const [
          'Apoio prestado',
          'Indivíduo detido',
          'BO elaborado',
          'Sem constatação',
        ];
    }
  }

  String? _prioritizedQuickCloseOutcomeSummary(
    Set<String> outcomes,
    String? subtype,
  ) {
    if (outcomes.contains('Droga apreendida')) {
      return 'Apreensão Positiva';
    }
    if (subtype == 'missingPerson' && outcomes.contains('Pessoa localizada')) {
      return 'Sucesso';
    }
    if (outcomes.contains('Indivíduo detido')) {
      return 'Indivíduo detido';
    }
    if (outcomes.contains('Vítima socorrida')) {
      return 'Vítima socorrida';
    }
    if (outcomes.contains('Encaminhamento médico')) {
      return 'Encaminhamento médico';
    }
    if (outcomes.contains('Trânsito sinalizado')) {
      return 'Trânsito sinalizado';
    }
    if (outcomes.contains('Local preservado')) {
      return 'Local preservado';
    }
    if (outcomes.contains('Ação educativa concluída')) {
      return 'Ação educativa concluída';
    }
    if (outcomes.contains('Apoio prestado')) {
      return 'Apoio prestado';
    }
    if (outcomes.contains('BO elaborado')) {
      return 'BO elaborado';
    }
    if (outcomes.contains('Sem constatação')) {
      return 'Sem constatação';
    }

    return null;
  }

  String _buildQuickCloseResultSummary({
    required Incident incident,
    required Set<String> selectedOutcomes,
    required bool operationalSuccess,
  }) {
    final summary = _prioritizedQuickCloseOutcomeSummary(
      selectedOutcomes,
      incident.type,
    );
    if (summary != null) {
      return summary;
    }
    return operationalSuccess ? 'Êxito' : 'Sem êxito';
  }

  _IncidentProgressStyle _resolveIncidentProgressStyle(
    String? title,
    String? description,
  ) {
    final normalizedTitle = (title ?? '').toLowerCase();
    final normalizedDescription = (description ?? '').toLowerCase();

    if (normalizedTitle.contains('encerramento')) {
      return const _IncidentProgressStyle(
        icon: Icons.task_alt_rounded,
        iconColor: Color(0xFF4ADE80),
        iconBackground: Color(0x1F4ADE80),
        titleColor: Color(0xFF86EFAC),
        backgroundColor: Color(0x1418241C),
        borderColor: Color(0x334ADE80),
      );
    }

    if (normalizedTitle.contains('apreens') ||
        normalizedTitle.contains('resultado') ||
        normalizedTitle.contains('detido') ||
        normalizedTitle.contains('localizada') ||
        normalizedDescription.contains('resultados parciais')) {
      return const _IncidentProgressStyle(
        icon: Icons.fact_check_rounded,
        iconColor: Color(0xFFFBBF24),
        iconBackground: Color(0x1FFBBF24),
        titleColor: Color(0xFFFCD34D),
        backgroundColor: Color(0x14FBBF24),
        borderColor: Color(0x33FBBF24),
      );
    }

    return const _IncidentProgressStyle(
      icon: Icons.timeline_rounded,
      iconColor: Color(0xFF38BDF8),
      iconBackground: Color(0x1F38BDF8),
      titleColor: Color(0xFF7DD3FC),
      backgroundColor: Color(0x1438BDF8),
      borderColor: Color(0x3338BDF8),
    );
  }

  _IncidentBadgeStyle _resolveIncidentStatusBadgeStyle(String status) {
    final normalized = status.toLowerCase();

    if (normalized.contains('concl')) {
      return const _IncidentBadgeStyle(
        icon: Icons.task_alt_rounded,
        iconColor: Color(0xFF4ADE80),
        textColor: Color(0xFF86EFAC),
        backgroundColor: Color(0x144ADE80),
        borderColor: Color(0x334ADE80),
      );
    }

    if (normalized.contains('cancel')) {
      return const _IncidentBadgeStyle(
        icon: Icons.cancel_rounded,
        iconColor: Color(0xFFF87171),
        textColor: Color(0xFFFCA5A5),
        backgroundColor: Color(0x14F87171),
        borderColor: Color(0x33F87171),
      );
    }

    return const _IncidentBadgeStyle(
      icon: Icons.radar_rounded,
      iconColor: Color(0xFFFBBF24),
      textColor: Color(0xFFFCD34D),
      backgroundColor: Color(0x14FBBF24),
      borderColor: Color(0x33FBBF24),
    );
  }

  _IncidentBadgeStyle _resolveIncidentOutcomeBadgeStyle(String outcome) {
    final normalized = outcome.toLowerCase();

    if (normalized.contains('droga') || normalized.contains('apreens')) {
      return const _IncidentBadgeStyle(
        icon: Icons.inventory_2_rounded,
        iconColor: Color(0xFFFBBF24),
        textColor: Color(0xFFFCD34D),
        backgroundColor: Color(0x14FBBF24),
        borderColor: Color(0x33FBBF24),
      );
    }

    if (normalized.contains('detido') || normalized.contains('preso')) {
      return const _IncidentBadgeStyle(
        icon: Icons.gpp_good_rounded,
        iconColor: Color(0xFFFB7185),
        textColor: Color(0xFFFDA4AF),
        backgroundColor: Color(0x14FB7185),
        borderColor: Color(0x33FB7185),
      );
    }

    if (normalized.contains('localiz')) {
      return const _IncidentBadgeStyle(
        icon: Icons.location_searching_rounded,
        iconColor: Color(0xFF38BDF8),
        textColor: Color(0xFF7DD3FC),
        backgroundColor: Color(0x1438BDF8),
        borderColor: Color(0x3338BDF8),
      );
    }

    if (normalized.contains('apoio') ||
        normalized.contains('encaminhamento') ||
        normalized.contains('socorrida') ||
        normalized.contains('transito') ||
        normalized.contains('preservado')) {
      return const _IncidentBadgeStyle(
        icon: Icons.volunteer_activism_rounded,
        iconColor: Color(0xFF2DD4BF),
        textColor: Color(0xFF99F6E4),
        backgroundColor: Color(0x142DD4BF),
        borderColor: Color(0x332DD4BF),
      );
    }

    if (normalized.contains('sem constat')) {
      return const _IncidentBadgeStyle(
        icon: Icons.search_off_rounded,
        iconColor: Color(0xFF94A3B8),
        textColor: Color(0xFFCBD5E1),
        backgroundColor: Color(0x1494A3B8),
        borderColor: Color(0x3394A3B8),
      );
    }

    return const _IncidentBadgeStyle(
      icon: Icons.fact_check_rounded,
      iconColor: Color(0xFFA78BFA),
      textColor: Color(0xFFC4B5FD),
      backgroundColor: Color(0x14A78BFA),
      borderColor: Color(0x33A78BFA),
    );
  }

  String _formatIncidentRelative(DateTime startedAt) {
    final diff = DateTime.now().difference(startedAt);
    if (diff.inDays > 0) {
      return '${diff.inDays}d';
    }
    if (diff.inHours > 0) {
      return '${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    }
    return '${diff.inMinutes.clamp(0, 59)}m';
  }

  String _formatIncidentTimestamp(DateTime timestamp) {
    return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')} '
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  // Conteúdo da aba de treinos e rotina
  Widget _buildTrainingsTab(String dogId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderDate(),
          _buildDateSelector(),
          _buildTimelineList(dogId, filterType: 'Training'),
        ],
      ),
    );
  }

  // Conteúdo da aba de evolução
  Widget _buildEvolutionTab(String dogId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEvolutionSummarySection(dogId),
          _buildTrainingFilterChips(),
          const SizedBox(height: 14),
          _buildEvolutionSectionTitle(
            _buildEvolutionVolumeTitle(),
            icon: Icons.bar_chart_rounded,
          ),
          const SizedBox(height: 8),
          _buildEvolutionBarChart(dogId),
          const SizedBox(height: 16),
          _buildCompetencyEvolutionSection(dogId),
          const SizedBox(height: 16),
          _buildEvolutionAttentionSection(dogId),
          const SizedBox(height: 16),
          _buildEvolutionSectionTitle(
            _buildEvolutionRecentSessionsTitle(),
            icon: Icons.history_rounded,
          ),
          _buildRecentPerformanceSessions(dogId),
        ],
      ),
    );
  }

  Widget _buildEvolutionSectionTitle(String title, {required IconData icon}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hudCyan.withAlpha(18),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hudCyan.withAlpha(90)),
            ),
            child: Icon(icon, color: _hudCyan, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.robotoMono(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildEvolutionVolumeTitle() {
    if (_selectedTrainingFilter == null) {
      return 'CARGA DE TREINO NOS ÚLTIMOS 7 DIAS';
    }
    return 'CARGA DE ${_selectedTrainingFilter!.toUpperCase()} NOS ÚLTIMOS 7 DIAS';
  }

  String _buildEvolutionRecentSessionsTitle() {
    if (_selectedTrainingFilter == null) {
      return 'ÚLTIMAS SESSÕES';
    }
    return 'ÚLTIMAS SESSÕES DE ${_selectedTrainingFilter!.toUpperCase()}';
  }

  String _buildEvolutionScopeHeadline() {
    if (_selectedTrainingFilter == null) {
      return 'Panorama geral de performance';
    }
    return 'Esta semana de ${_selectedTrainingFilter!}';
  }

  String _buildEvolutionScopeDescription() {
    if (_selectedTrainingFilter == null) {
      return 'Leitura consolidada dos treinos de performance registrados nesta semana.';
    }
    return 'Resumo do recorte atual para ${_selectedTrainingFilter!}, usando apenas registros reais deste período.';
  }

  // Apenas estes subtipos são aceitos na evolução
  static const _performanceAllowlist = [
    'Faro',
    'Busca & Captura',
    'Busca de Pessoa',
    'Guarda e Proteção',
    'Guarda',
    'Obediência',
  ];

  bool _isPerformanceType(String trainingType) {
    // Allowlist-based: only types explicitly in the list are included
    for (final allowed in _performanceAllowlist) {
      if (trainingType.toLowerCase().contains(allowed.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  bool _matchesTrainingFilter(String trainingType) {
    if (_selectedTrainingFilter == null) return true;
    return trainingType.toLowerCase().contains(
          _selectedTrainingFilter!.toLowerCase(),
        ) ||
        (_selectedTrainingFilter == 'Busca & Captura' &&
            (trainingType.contains('Busca') ||
                trainingType.contains('Captura')));
  }

  String _normalizePerformanceCategory(String trainingType) {
    final normalized = trainingType.toLowerCase();
    if (normalized.contains('faro')) return 'Faro';
    if (normalized.contains('busca') || normalized.contains('captura')) {
      return 'Busca & Captura';
    }
    if (normalized.contains('guarda') || normalized.contains('prote')) {
      return 'Guarda';
    }
    if (normalized.contains('obedi')) return 'Obediência';
    return trainingType;
  }

  List<TrainingSessionModel> _getPerformanceTrainings(
    String dogId, {
    int? lastDays,
    bool applyFilter = true,
  }) {
    final tVM = Provider.of<TrainingViewModel>(context, listen: false);
    final now = DateTime.now();
    final startDate = lastDays == null
        ? null
        : DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: lastDays - 1));

    final trainings = tVM.trainings.where((training) {
      if (training.dogId != dogId) return false;
      if (!_isPerformanceType(training.trainingType)) return false;
      if (applyFilter && !_matchesTrainingFilter(training.trainingType)) {
        return false;
      }
      if (startDate != null && training.date.isBefore(startDate)) return false;
      return true;
    }).toList()..sort((a, b) => b.date.compareTo(a.date));

    return trainings;
  }

  Widget _buildEvolutionSummarySection(String dogId) {
    final trainings = _getPerformanceTrainings(dogId, lastDays: 7);
    final previousTrainings = _getPerformanceTrainings(dogId, lastDays: 14)
        .where((training) {
          final cutoff = DateTime.now().subtract(const Duration(days: 7));
          return training.date.isBefore(cutoff);
        })
        .toList();
    final totalSessions = trainings.length;
    final totalMinutes = trainings.fold<double>(
      0,
      (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
    );
    final previousTotalSessions = previousTrainings.length;
    final previousTotalMinutes = previousTrainings.fold<double>(
      0,
      (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
    );
    final averageMinutes = totalSessions == 0
        ? 0
        : totalMinutes / totalSessions;
    final mostFrequentCategory = _resolveMostFrequentCategory(trainings);
    final lastTraining = trainings.isNotEmpty ? trainings.first : null;
    final focusVisual = _resolveEvolutionCategoryVisual(mostFrequentCategory);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _hudPanel.withAlpha(235),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hudCyan.withAlpha(70)),
              boxShadow: [
                BoxShadow(color: _hudCyan.withAlpha(18), blurRadius: 18),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RECORTE ATUAL',
                  style: GoogleFonts.robotoMono(
                    color: _hudCyan.withAlpha(210),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _buildEvolutionScopeHeadline(),
                  style: GoogleFonts.oxanium(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _buildEvolutionScopeDescription(),
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatBox(
                label: 'SESSÕES',
                value: '$totalSessions',
                icon: Icons.format_list_numbered_rounded,
                color: const Color(0xFF00E5FF),
              ),
              const SizedBox(width: 10),
              _StatBox(
                label: 'TEMPO',
                value: totalMinutes > 0
                    ? '${totalMinutes.toStringAsFixed(0)} min'
                    : '--',
                icon: Icons.timer_rounded,
                color: const Color(0xFF00E5FF),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatBox(
                label: 'MÉDIA',
                value: averageMinutes > 0
                    ? '${averageMinutes.toStringAsFixed(1)} min'
                    : '--',
                icon: Icons.bar_chart_rounded,
                color: const Color(0xFF00E5FF),
              ),
              const SizedBox(width: 10),
              _StatBox(
                label: 'FOCO',
                value: mostFrequentCategory,
                icon: focusVisual.icon,
                color: focusVisual.color,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildEvolutionWeekComparisonCard(
            currentMinutes: totalMinutes,
            previousMinutes: previousTotalMinutes,
            currentSessions: totalSessions,
            previousSessions: previousTotalSessions,
            scopeLabel: _selectedTrainingFilter,
          ),
          if (lastTraining != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(8),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: focusVisual.color.withAlpha(24),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      focusVisual.icon,
                      color: focusVisual.color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedTrainingFilter == null
                              ? 'ÚLTIMO TREINO'
                              : 'ÚLTIMO REGISTRO DE ${_selectedTrainingFilter!.toUpperCase()}',
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_formatEvolutionDate(lastTraining.date)} • ${lastTraining.location.isNotEmpty ? lastTraining.location : 'Local não informado'}',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEvolutionWeekComparisonCard({
    required double currentMinutes,
    required double previousMinutes,
    required int currentSessions,
    required int previousSessions,
    String? scopeLabel,
  }) {
    final deltaMinutes = currentMinutes - previousMinutes;
    final deltaSessions = currentSessions - previousSessions;
    final isUp = deltaMinutes > 0;
    final isDown = deltaMinutes < 0;
    final accent = isUp
        ? const Color(0xFF4ADE80)
        : isDown
        ? const Color(0xFFF87171)
        : const Color(0xFF94A3B8);
    final icon = isUp
        ? Icons.trending_up_rounded
        : isDown
        ? Icons.trending_down_rounded
        : Icons.remove_rounded;
    final scopeText = scopeLabel ?? 'performance';

    final headline = previousMinutes <= 0
        ? 'Primeira base comparável de $scopeText'
        : isUp
        ? '$scopeText acima da semana anterior'
        : isDown
        ? '$scopeText abaixo da semana anterior'
        : 'Mesmo volume de $scopeText na semana anterior';

    final detail = previousMinutes <= 0
        ? 'Esta semana soma ${_formatEvolutionMinutes(currentMinutes)} em $currentSessions sessão(ões).'
        : '${deltaMinutes.abs().toStringAsFixed(0)} min e ${deltaSessions.abs()} sessão(ões) de diferença • ${((deltaMinutes.abs() / previousMinutes) * 100).toStringAsFixed(0)}% em relação à semana passada.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(95)),
        boxShadow: [BoxShadow(color: accent.withAlpha(18), blurRadius: 14)],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withAlpha(24),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scopeLabel == null
                      ? 'COMPARATIVO SEMANAL'
                      : 'COMPARATIVO DE ${scopeLabel.toUpperCase()}',
                  style: GoogleFonts.robotoMono(
                    color: accent.withAlpha(220),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  headline,
                  style: GoogleFonts.oxanium(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: GoogleFonts.inter(
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

  // Filtro por categoria de treino
  Widget _buildTrainingFilterChips() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _FilterChip(
            label: 'Todos',
            selected: _selectedTrainingFilter == null,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedTrainingFilter = null);
            },
          ),
          ..._trainingCategories.map(
            (cat) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _FilterChip(
                label: cat,
                selected: _selectedTrainingFilter == cat,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(
                    () => _selectedTrainingFilter =
                        _selectedTrainingFilter == cat ? null : cat,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _resolveMostFrequentCategory(List<TrainingSessionModel> trainings) {
    if (trainings.isEmpty) return '--';

    final counts = <String, int>{};
    for (final training in trainings) {
      final category = _normalizePerformanceCategory(training.trainingType);
      counts[category] = (counts[category] ?? 0) + 1;
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  String _formatEvolutionDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final difference = today.difference(target).inDays;

    if (difference == 0) return 'Hoje';
    if (difference == 1) return 'Ontem';
    return DateFormat('dd/MM').format(date);
  }

  ({IconData icon, Color color}) _resolveEvolutionCategoryVisual(
    String category,
  ) {
    switch (category) {
      case 'Faro':
        return (icon: Icons.sensors_rounded, color: const Color(0xFF38BDF8));
      case 'Busca & Captura':
        return (
          icon: Icons.crisis_alert_rounded,
          color: const Color(0xFFF97316),
        );
      case 'Guarda':
        return (icon: Icons.shield_rounded, color: const Color(0xFF4ADE80));
      case 'Obediência':
        return (icon: Icons.rule_rounded, color: const Color(0xFFA78BFA));
      default:
        return (icon: Icons.pets_rounded, color: const Color(0xFFFBBF24));
    }
  }

  String _formatEvolutionMinutes(double minutes) {
    if (minutes <= 0) return '0 min';
    return '${minutes.toStringAsFixed(0)} min';
  }

  List<({double minutes, String? primaryCategory, Set<String> categories})>
  _buildDailyTrainingSummaries(String dogId) {
    final trainings = _getPerformanceTrainings(dogId, lastDays: 7);
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 6));
    final totals = List.generate(7, (_) => <String, double>{}, growable: false);

    for (final training in trainings) {
      final trainingDay = DateTime(
        training.date.year,
        training.date.month,
        training.date.day,
      );
      final index = trainingDay.difference(start).inDays;
      if (index >= 0 && index < 7) {
        final category = _normalizePerformanceCategory(training.trainingType);
        totals[index][category] =
            (totals[index][category] ?? 0) +
            ((training.searchDuration ?? 0) / 60);
      }
    }

    return totals
        .map((dailyTotals) {
          if (dailyTotals.isEmpty) {
            return (
              minutes: 0.0,
              primaryCategory: null,
              categories: <String>{},
            );
          }

          final entries = dailyTotals.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          final totalMinutes = dailyTotals.values.fold<double>(
            0,
            (sum, value) => sum + value,
          );

          return (
            minutes: totalMinutes,
            primaryCategory: entries.first.key,
            categories: dailyTotals.keys.toSet(),
          );
        })
        .toList(growable: false);
  }

  Widget _buildEvolutionBarChart(String dogId) {
    final dailySummaries = _buildDailyTrainingSummaries(dogId);
    final maxY = dailySummaries.fold<double>(
      0,
      (max, summary) => summary.minutes > max ? summary.minutes : max,
    );
    final chartMaxY = maxY <= 0
        ? 30.0
        : (maxY * 1.25).clamp(30, 240).toDouble();

    return Container(
      height: 320,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(60)),
        boxShadow: [BoxShadow(color: _hudCyan.withAlpha(14), blurRadius: 16)],
      ),
      child: Column(
        children: [
          Expanded(
            child: BarChart(
              BarChartData(
                maxY: chartMaxY,
                alignment: BarChartAlignment.spaceAround,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: chartMaxY / 4,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.white.withAlpha(18),
                      strokeWidth: 1,
                    );
                  },
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: chartMaxY / 4,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: GoogleFonts.inter(
                            color: Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final now = DateTime.now();
                        final date = DateTime(
                          now.year,
                          now.month,
                          now.day,
                        ).subtract(Duration(days: 6 - value.toInt()));
                        final labels = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];
                        if (value.toInt() < 0 ||
                            value.toInt() >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            labels[date.weekday - 1],
                            style: GoogleFonts.inter(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1E1E1E),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final summary = dailySummaries[group.x.toInt()];
                      final categoryLabel = summary.categories.isEmpty
                          ? 'Sem treino'
                          : summary.categories.join(' • ');
                      return BarTooltipItem(
                        '${rod.toY.toStringAsFixed(0)} min\n$categoryLabel',
                        GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
                  ),
                ),
                barGroups: dailySummaries.asMap().entries.map((entry) {
                  final summary = entry.value;
                  final visual = summary.primaryCategory == null
                      ? null
                      : _resolveEvolutionCategoryVisual(
                          summary.primaryCategory!,
                        );
                  final isEmpty = summary.minutes == 0;
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: summary.minutes,
                        width: 18,
                        borderRadius: BorderRadius.circular(6),
                        color: isEmpty
                            ? Colors.white.withAlpha(18)
                            : visual!.color,
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _trainingCategories.map((category) {
              final visual = _resolveEvolutionCategoryVisual(category);
              return _buildEvolutionLegendChip(
                label: category,
                color: visual.color,
                icon: visual.icon,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEvolutionLegendChip({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.robotoMono(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompetencyEvolutionSection(String dogId) {
    final trainings = _getPerformanceTrainings(dogId, lastDays: 7);
    final grouped = <String, List<TrainingSessionModel>>{};
    final totalMinutes = trainings.fold<double>(
      0,
      (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
    );

    for (final training in trainings) {
      final category = _normalizePerformanceCategory(training.trainingType);
      grouped.putIfAbsent(category, () => []).add(training);
    }

    final cards = grouped.entries.toList()
      ..sort((a, b) {
        final aMinutes = a.value.fold<double>(
          0,
          (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
        );
        final bMinutes = b.value.fold<double>(
          0,
          (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
        );
        return bMinutes.compareTo(aMinutes);
      });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Text(
              'COMPETÊNCIAS TRABALHADAS',
              style: GoogleFonts.robotoMono(
                color: _hudCyan.withAlpha(210),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
          if (cards.isEmpty)
            _buildEvolutionMessageCard(
              icon: Icons.track_changes_rounded,
              title: 'Nenhuma competência registrada',
              description:
                  'Ainda não há treinos de performance suficientes nesta janela para comparar a evolução.',
            )
          else
            ...cards.map((entry) {
              final sessions = entry.value.length;
              final minutes = entry.value.fold<double>(
                0,
                (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
              );
              final latest = entry.value.first;
              final share = totalMinutes <= 0
                  ? 0
                  : (minutes / totalMinutes) * 100;
              final visual = _resolveEvolutionCategoryVisual(entry.key);

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _hudPanel.withAlpha(230),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: visual.color.withAlpha(70)),
                  boxShadow: [
                    BoxShadow(
                      color: visual.color.withAlpha(14),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: visual.color.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(visual.icon, color: visual.color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: GoogleFonts.oxanium(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: visual.color.withAlpha(20),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${share.toStringAsFixed(0)}%',
                                  style: GoogleFonts.robotoMono(
                                    color: visual.color,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$sessions sessão(ões) • ${minutes.toStringAsFixed(0)} min • Último registro ${_formatEvolutionDate(latest.date)}',
                            style: GoogleFonts.inter(
                              color: Colors.white60,
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
            }),
        ],
      ),
    );
  }

  Widget _buildEvolutionAttentionSection(String dogId) {
    final currentWindow = _getPerformanceTrainings(dogId, lastDays: 7);
    final previousWindow = _getPerformanceTrainings(dogId, lastDays: 14).where((
      training,
    ) {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      return training.date.isBefore(cutoff);
    }).toList();

    final currentMinutes = currentWindow.fold<double>(
      0,
      (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
    );
    final previousMinutes = previousWindow.fold<double>(
      0,
      (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
    );

    final alerts = <Widget>[];
    final scopeLabel = _selectedTrainingFilter ?? 'performance';

    if (currentWindow.isEmpty) {
      alerts.add(
        _buildEvolutionMessageCard(
          icon: Icons.warning_amber_rounded,
          title: 'Sem registros recentes de $scopeLabel',
          description:
              'Nenhum treino desse recorte foi registrado nos últimos 7 dias.',
        ),
      );
    } else if (previousMinutes > 0 && currentMinutes < previousMinutes) {
      final variation =
          ((previousMinutes - currentMinutes) / previousMinutes) * 100;
      alerts.add(
        _buildEvolutionMessageCard(
          icon: Icons.trending_down_rounded,
          title: '$scopeLabel abaixo da semana anterior',
          description:
              'O volume caiu ${variation.toStringAsFixed(0)}% em comparação com a semana passada.',
        ),
      );
    } else if (previousMinutes > 0 && currentMinutes > previousMinutes) {
      final variation =
          ((currentMinutes - previousMinutes) / previousMinutes) * 100;
      alerts.add(
        _buildEvolutionMessageCard(
          icon: Icons.trending_up_rounded,
          title: '$scopeLabel acima da semana anterior',
          description:
              'O volume subiu ${variation.toStringAsFixed(0)}% em relação à semana passada.',
        ),
      );
    }

    for (final category in const [
      'Faro',
      'Busca & Captura',
      'Guarda',
      'Obediência',
    ]) {
      if (_selectedTrainingFilter != null &&
          category != _selectedTrainingFilter) {
        continue;
      }

      final categoryTrainings =
          _getPerformanceTrainings(dogId, applyFilter: false)
              .where(
                (training) =>
                    _normalizePerformanceCategory(training.trainingType) ==
                    category,
              )
              .toList();

      if (categoryTrainings.isEmpty) continue;

      final latest = categoryTrainings.first.date;
      final daysWithout = DateTime.now()
          .difference(DateTime(latest.year, latest.month, latest.day))
          .inDays;

      if (daysWithout >= 7) {
        alerts.add(
          _buildEvolutionMessageCard(
            icon: Icons.schedule_rounded,
            title: '$category sem registro recente',
            description:
                'A última sessão dessa competência foi há $daysWithout dias.',
          ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Text(
              _selectedTrainingFilter == null
                  ? 'ATENÇÃO DO PERÍODO'
                  : 'ATENÇÃO EM ${_selectedTrainingFilter!.toUpperCase()}',
              style: GoogleFonts.robotoMono(
                color: _hudCyan.withAlpha(210),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
          if (alerts.isEmpty)
            _buildEvolutionMessageCard(
              icon: Icons.verified_rounded,
              title: _selectedTrainingFilter == null
                  ? 'Rotina consistente'
                  : 'Recorte consistente',
              description: _selectedTrainingFilter == null
                  ? 'Os registros recentes mostram continuidade de treino sem alertas importantes.'
                  : 'Os registros recentes de ${_selectedTrainingFilter!} estão consistentes neste período.',
            )
          else
            ...alerts.map(
              (alert) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: alert,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEvolutionMessageCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudAmber.withAlpha(65)),
        boxShadow: [BoxShadow(color: _hudAmber.withAlpha(12), blurRadius: 12)],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hudAmber.withAlpha(80)),
            ),
            child: Icon(icon, color: _hudAmber, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.oxanium(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    color: Colors.white60,
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

  Widget _buildRecentPerformanceSessions(String dogId) {
    final trainings = _getPerformanceTrainings(dogId, lastDays: 14);

    if (trainings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.track_changes_rounded,
                size: 60,
                color: Colors.white.withAlpha(30),
              ),
              const SizedBox(height: 12),
              Text(
                'Nenhuma sessão de performance registrada',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: trainings.length.clamp(0, 8),
      itemBuilder: (context, index) {
        final training = trainings[index];
        final minutes = ((training.searchDuration ?? 0) / 60).round();
        final location = training.location.trim();
        final subtitle = location.isEmpty
            ? _formatEvolutionDate(training.date)
            : '${_formatEvolutionDate(training.date)} • $location';
        final visual = _resolveEvolutionCategoryVisual(
          _normalizePerformanceCategory(training.trainingType),
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hudPanel.withAlpha(230),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: visual.color.withAlpha(70)),
            boxShadow: [
              BoxShadow(color: visual.color.withAlpha(12), blurRadius: 12),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: visual.color.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: visual.color.withAlpha(70)),
                ),
                child: Icon(
                  Icons.timeline_rounded,
                  color: visual.color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      training.trainingType,
                      style: GoogleFonts.oxanium(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                minutes > 0 ? '$minutes min' : '--',
                style: GoogleFonts.robotoMono(
                  color: visual.color,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Exportação em PDF
  Future<void> _exportPdf(BuildContext ctx, String dogId) async {
    final tVM = Provider.of<TrainingViewModel>(ctx, listen: false);
    final iVM = Provider.of<IncidentViewModel>(ctx, listen: false);
    final hVM = Provider.of<HealthViewModel>(ctx, listen: false);
    final rVM = Provider.of<RoutineViewModel>(ctx, listen: false);
    final authVM = Provider.of<AuthViewModel>(ctx, listen: false);
    final userVM = Provider.of<UserViewModel>(ctx, listen: false);
    final dogVM = Provider.of<DogViewModel>(ctx, listen: false);

    final dog = dogVM.dogs.firstWhere(
      (d) => d.id == dogId,
      orElse: () => dogVM.dogs.first,
    );
    final fbUser = authVM.user;
    final currentRa = HandlerIdentityService.raFromUser(fbUser);
    final userModel = userVM.users.cast<dynamic>().firstWhere(
      (u) => u?.ra == currentRa,
      orElse: () => null,
    );
    final callsign = userModel?.callsign ?? fbUser?.displayName ?? 'GCM';

    final entries = <ReportEntry>[];

    for (final t in tVM.trainings.where((t) => t.dogId == dogId)) {
      entries.add(
        ReportEntry(
          date: t.date,
          type: t.trainingType,
          location: t.location,
          observations: t.handlerNotes,
        ),
      );
    }
    for (final r in rVM.routines.where((r) => r.dogId == dogId)) {
      entries.add(
        ReportEntry(
          date: r.timestamp,
          type: r.activityType,
          location: r.dogName,
          observations: r.notes ?? '',
        ),
      );
    }
    for (final h in hVM.healthLogs.where((h) => h.dogId == dogId)) {
      entries.add(
        ReportEntry(
          date: h.date,
          type: h.logType,
          location: h.dogName,
          observations: h.healthObservations,
        ),
      );
    }
    for (final i in iVM.incidents.where((i) => i.dogId == dogId)) {
      entries.add(
        ReportEntry(
          date: i.date,
          type: i.type ?? 'Ocorrência',
          location: i.location,
          observations: i.description,
        ),
      );
    }

    final pdfBytes = await ReportService.generateActivityReport(
      dog: dog,
      conductorCallsign: callsign,
      entries: entries,
    );

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'relatorio_k9_${dog.name.toLowerCase()}.pdf',
    );
  }

  Widget _buildHeaderDate() {
    final monthName = DateFormat('MMMM, y').format(_selectedDate);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            monthName.toUpperCase(),
            style: GoogleFonts.inter(
              color: Colors.white38,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          IconButton(
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                builder: (context, child) => Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.dark(
                      primary: Color(0xFFFBBF24),
                      surface: Color(0xFF1C1C1E),
                    ),
                  ),
                  child: child!,
                ),
              );
              if (date != null) setState(() => _selectedDate = date);
            },
            icon: const Icon(
              Icons.calendar_today_rounded,
              size: 16,
              color: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return Container(
      height: 96,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        reverse: true,
        itemCount: 31, // Últimos 31 dias
        itemBuilder: (context, index) {
          final date = DateTime.now().subtract(Duration(days: index));
          final isSelected =
              date.year == _selectedDate.year &&
              date.month == _selectedDate.month &&
              date.day == _selectedDate.day;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedDate = date);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 55,
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF00E5FF).withAlpha(34)
                    : const Color(0xFF0B1020),
                borderRadius: BorderRadius.circular(6),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withAlpha(80),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF00E5FF)
                      : const Color(0x3300E5FF),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _getWeekday(date.weekday),
                    style: GoogleFonts.robotoMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? const Color(0xFF00E5FF)
                          : Colors.white38,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${date.day}',
                    style: GoogleFonts.oxanium(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: isSelected ? Colors.white : Colors.white70,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: 18,
                    height: 2,
                    color: isSelected
                        ? const Color(0xFF00E5FF)
                        : Colors.white12,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _getWeekday(int weekday) {
    const days = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SAB', 'DOM'];
    return days[weekday - 1];
  }

  // Estilo Dark nativo do Google Maps
  final String _darkMapStyle = '''
  [
    {"elementType": "geometry", "stylers": [{"color": "#212121"}]},
    {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
    {"elementType": "labels.text.fill", "stylers": [{"color": "#757575"}]},
    {"elementType": "labels.text.stroke", "stylers": [{"color": "#212121"}]},
    {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#000000"}]},
    {"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#2c2c2c"}]}
  ]
  ''';

  LatLngBounds _getBounds(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  String _resolveHealthTimelineTitle(dynamic healthLog) {
    final logType = (healthLog.logType ?? '').toString().trim();
    if (logType.isNotEmpty && logType.toLowerCase() != 'rotina') {
      return logType;
    }

    final vaccines = healthLog.vaccines is List
        ? List<String>.from(healthLog.vaccines as List)
        : const <String>[];
    if (vaccines.isNotEmpty) {
      return vaccines.first;
    }

    final observations = (healthLog.healthObservations ?? '').toString().trim();
    if (observations.isNotEmpty) {
      final firstSentence = observations.split(RegExp(r'[.!?\n]')).first.trim();
      if (firstSentence.isNotEmpty) {
        return firstSentence;
      }
    }

    return 'Registro de saúde';
  }

  String _resolveIncidentTimelineTitle(Incident incident) {
    final type = (incident.type ?? '').trim();
    if (type.isNotEmpty) {
      return type;
    }

    if (incident.outcomes.isNotEmpty) {
      return incident.outcomes.first;
    }

    final latestUpdate = incident.progressUpdates.isNotEmpty
        ? incident.progressUpdates.last.title.trim()
        : '';
    if (latestUpdate.isNotEmpty) {
      return latestUpdate;
    }

    return 'Registro operacional';
  }

  String _cleanTimelineTitle(_TimelineEntry entry) {
    final rawTitle = entry.title.trim();
    final normalized = rawTitle
        .replaceAll('TREINO: ', '')
        .replaceAll('ROTINA: ', '')
        .replaceAll('OCORRÊNCIA: ', '')
        .replaceAll('SAÚDE: ', '')
        .trim();

    if (normalized.isNotEmpty) {
      return normalized;
    }

    switch (entry.type) {
      case 'Treino':
        return 'Treino';
      case 'Rotina':
        return 'Rotina';
      case 'Ocorrência':
        return 'Ocorrência';
      case 'Saude':
        return 'Saúde';
      default:
        return 'Registro';
    }
  }

  String _buildTimelineSubtitle(_TimelineEntry entry, String timeStr) {
    final location = entry.location.trim();
    if (location.isEmpty) {
      return timeStr;
    }
    return '$timeStr \u2022 $location';
  }

  Widget _buildTimelineDetailPanel(_TimelineEntry entry, Color accent) {
    final details = _visibleTimelineDetails(entry);
    if (details.isEmpty) {
      return const SizedBox.shrink();
    }

    final title = switch (entry.type) {
      'Treino' => 'TELEMETRIA DO TREINO',
      'Rotina' => 'ROTINA OPERACIONAL',
      'Saude' => 'PRONTUÁRIO DE SAÚDE',
      'Ocorrência' => 'DADOS DA OCORRÊNCIA',
      _ => 'DETALHES DO REGISTRO',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF070B14).withAlpha(225),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 3, height: 16, color: accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.oxanium(
                  color: accent.withAlpha(230),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: details.map((entryDetail) {
              final key = entryDetail.key;
              final value = entryDetail.value.toString().trim();
              final isLong = _isLongTimelineDetail(key, value);
              final child = _buildTimelineDetailTile(
                label: key,
                value: value,
                icon: _timelineDetailIcon(key),
                accent: accent,
                expanded: isLong,
              );

              if (isLong) {
                return child;
              }

              return FractionallySizedBox(widthFactor: 0.47, child: child);
            }).toList(),
          ),
        ],
      ),
    );
  }

  List<MapEntry<String, dynamic>> _visibleTimelineDetails(
    _TimelineEntry entry,
  ) {
    return entry.details.entries.where((detail) {
      final key = detail.key;
      final value = detail.value;
      final normalizedKey = key.toLowerCase();

      if (value == null || value.toString().trim().isEmpty) return false;
      if (key.startsWith('_')) return false;
      if (key == 'Resultado') return false;
      if (normalizedKey.contains('tracking')) return false;
      if (normalizedKey.contains('_mediaattachments')) return false;

      return true;
    }).toList();
  }

  bool _isLongTimelineDetail(String key, String value) {
    final normalizedKey = key.toLowerCase();
    return normalizedKey == 'notas' ||
        normalizedKey == 'observações' ||
        normalizedKey == 'descrição' ||
        value.length > 46;
  }

  IconData _timelineDetailIcon(String key) {
    final normalizedKey = key.toLowerCase();
    if (normalizedKey.contains('clima')) return Icons.cloud_outlined;
    if (normalizedKey.contains('duração')) return Icons.timer_outlined;
    if (normalizedKey.contains('distância')) return Icons.straighten_rounded;
    if (normalizedKey.contains('status')) return Icons.verified_rounded;
    if (normalizedKey.contains('peso')) return Icons.monitor_weight_outlined;
    if (normalizedKey.contains('vacina')) return Icons.vaccines_rounded;
    if (normalizedKey.contains('veterin')) return Icons.medical_services;
    if (normalizedKey.contains('nota') ||
        normalizedKey.contains('observ') ||
        normalizedKey.contains('descr')) {
      return Icons.notes_rounded;
    }
    if (normalizedKey.contains('umidade')) return Icons.water_drop_outlined;
    if (normalizedKey.contains('vento')) return Icons.air_rounded;
    return Icons.data_object_rounded;
  }

  Widget _buildTimelineDetailTile({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
    required bool expanded,
  }) {
    return Container(
      width: expanded ? double.infinity : null,
      constraints: BoxConstraints(minHeight: expanded ? 0 : 74),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1020).withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(70)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withAlpha(20),
            const Color(0xFF0F1726),
            const Color(0xFF070B14),
          ],
        ),
      ),
      child: expanded
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTimelineDetailIcon(icon, accent),
                const SizedBox(width: 9),
                Expanded(child: _buildTimelineDetailText(label, value, true)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTimelineDetailIcon(icon, accent),
                const SizedBox(height: 8),
                _buildTimelineDetailText(label, value, false),
              ],
            ),
    );
  }

  Widget _buildTimelineDetailIcon(IconData icon, Color accent) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withAlpha(22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(110)),
      ),
      child: Icon(icon, size: 14, color: accent.withAlpha(230)),
    );
  }

  Widget _buildTimelineDetailText(String label, String value, bool expanded) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.robotoMono(
            color: Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: expanded ? 12 : 13,
            fontWeight: expanded ? FontWeight.w500 : FontWeight.w800,
            height: 1.35,
          ),
          overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          maxLines: expanded ? null : 2,
        ),
      ],
    );
  }

  Widget _buildIncidentProgressTimeline({
    required List updates,
    required Color accent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF070B14).withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(95)),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var index = 0; index < updates.length; index++)
            _buildIncidentProgressNode(
              step: updates[index],
              index: index,
              isLast: index == updates.length - 1,
              accent: accent,
            ),
        ],
      ),
    );
  }

  Widget _buildIncidentProgressNode({
    required dynamic step,
    required int index,
    required bool isLast,
    required Color accent,
  }) {
    final stepMap = step is Map ? step : <String, dynamic>{};
    final title = (stepMap['title']?.toString().trim().isNotEmpty ?? false)
        ? stepMap['title'].toString().trim()
        : 'Atualização operacional';
    final description = stepMap['description']?.toString().trim() ?? '';
    final progressStyle = _resolveIncidentProgressStyle(title, description);
    final rawTimestamp = stepMap['timestamp'];
    final ts = _coerceTimelineDate(rawTimestamp);
    final tsLabel = ts == null
        ? ''
        : '${ts.day.toString().padLeft(2, '0')}/${ts.month.toString().padLeft(2, '0')} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    final location = stepMap['location']?.toString().trim() ?? '';
    final authorName = stepMap['authorName']?.toString().trim() ?? '';
    final authorId = stepMap['authorId']?.toString().trim() ?? '';
    final authorLabel = authorName.isNotEmpty
        ? authorName
        : authorId.isNotEmpty
        ? 'RA $authorId'
        : '';

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 8 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: progressStyle.iconBackground,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: progressStyle.iconColor.withAlpha(170),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: progressStyle.iconColor.withAlpha(70),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: Icon(
                    progressStyle.icon,
                    size: 15,
                    color: progressStyle.iconColor,
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 58,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: progressStyle.borderColor.withAlpha(120),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: progressStyle.backgroundColor.withAlpha(225),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: progressStyle.borderColor.withAlpha(185),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    progressStyle.borderColor.withAlpha(32),
                    const Color(0xFF0B1020),
                    const Color(0xFF070B14),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ETAPA ${(index + 1).toString().padLeft(2, '0')}',
                        style: GoogleFonts.robotoMono(
                          color: accent.withAlpha(210),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title.toUpperCase(),
                          style: GoogleFonts.oxanium(
                            color: progressStyle.titleColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (authorLabel.isNotEmpty ||
                      tsLabel.isNotEmpty ||
                      location.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (authorLabel.isNotEmpty)
                          _buildProgressMetaChip(
                            icon: Icons.badge_outlined,
                            label: authorLabel,
                            color: progressStyle.iconColor,
                          ),
                        if (tsLabel.isNotEmpty)
                          _buildProgressMetaChip(
                            icon: Icons.schedule_rounded,
                            label: tsLabel,
                            color: progressStyle.iconColor,
                          ),
                        if (location.isNotEmpty)
                          _buildProgressMetaChip(
                            icon: Icons.place_outlined,
                            label: location,
                            color: progressStyle.iconColor,
                          ),
                      ],
                    ),
                  ],
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      description,
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressMetaChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(85)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color.withAlpha(210), size: 12),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              style: GoogleFonts.robotoMono(
                color: Colors.white60,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _coerceTimelineDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);

    try {
      final dynamic maybeTimestamp = value;
      final converted = maybeTimestamp.toDate();
      if (converted is DateTime) {
        return converted;
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Widget _buildTimelineList(String dogId, {String? filterType}) {
    final tVM = Provider.of<TrainingViewModel>(context);
    final iVM = Provider.of<IncidentViewModel>(context);
    final hVM = Provider.of<HealthViewModel>(context);
    final rVM = Provider.of<RoutineViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final dogName = dogVM.dogs
        .firstWhere(
          (d) => d.id == dogId,
          orElse: () => dogVM.dogs.isNotEmpty
              ? dogVM.dogs.first
              : throw Exception('Cão não encontrado'),
        )
        .name;

    // Filter by selected date (Inclusive start, exclusive end)
    final startOfDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final trainings = tVM.trainings
        .where(
          (t) =>
              t.dogId == dogId &&
              !t.date.isBefore(startOfDay) &&
              t.date.isBefore(endOfDay),
        )
        .toList();

    final incidents = iVM.incidents
        .where(
          (i) =>
              i.dogId == dogId &&
              !i.isInProgress &&
              !i.date.isBefore(startOfDay) &&
              i.date.isBefore(endOfDay),
        )
        .toList();

    final healthLogs = hVM.healthLogs
        .where(
          (h) =>
              h.dogId == dogId &&
              !h.date.isBefore(startOfDay) &&
              h.date.isBefore(endOfDay),
        )
        .toList();

    final routines = rVM.routines
        .where(
          (r) =>
              r.dogId == dogId &&
              !r.timestamp.isBefore(startOfDay) &&
              r.timestamp.isBefore(endOfDay),
        )
        .toList();

    List<_TimelineEntry> entries = [];

    // Include trainings/health only if not in Ocorrência-only tab
    if (filterType != 'Ocorrência') {
      for (var r in routines) {
        entries.add(
          _TimelineEntry(
            id: r.id,
            category: 'Rotina',
            originalModel: r,
            time: r.timestamp,
            title: 'ROTINA: ${r.activityType}',
            location: r.dogName.isNotEmpty ? r.dogName : dogName,
            type: 'Rotina',
            details: {
              'Status': r.status,
              'Notas': r.notes,
              if (r.mediaAttachments != null && r.mediaAttachments!.isNotEmpty)
                '_mediaAttachments': r.mediaAttachments,
              ...?r.metadata,
            },
          ),
        );
      }

      for (var h in healthLogs) {
        final healthTitle = _resolveHealthTimelineTitle(h);
        entries.add(
          _TimelineEntry(
            id: h.id,
            category: 'Saude',
            originalModel: h,
            time: h.date,
            title: 'SAÚDE: $healthTitle',
            location: h.dogName.isNotEmpty ? h.dogName : dogName,
            type: 'Saude',
            details: {
              if (h.weight != null) 'Peso': '${h.weight} kg',
              if (h.vaccines.isNotEmpty) 'Vacinas': h.vaccines.join(', '),
              'Observações': h.healthObservations,
              if (h.vetName != null && h.vetName!.isNotEmpty)
                'Veterinário': h.vetName,
              if (h.mediaAttachments != null && h.mediaAttachments!.isNotEmpty)
                '_mediaAttachments': h.mediaAttachments,
            },
          ),
        );
      }

      for (var t in trainings) {
        // Apply category filter if set
        if (_selectedTrainingFilter != null) {
          final matchesFilter =
              t.trainingType.toLowerCase().contains(
                _selectedTrainingFilter!.toLowerCase(),
              ) ||
              (_selectedTrainingFilter == 'Busca & Captura' &&
                  (t.trainingType.contains('Busca') ||
                      t.trainingType.contains('Captura')));
          if (!matchesFilter) continue;
        }
        final isRoutine = [
          'Passeio',
          'Lazer/Brincadeira',
          'Condicionamento Físico',
          'Outros',
          'Brincadeira',
          'Alimentação',
          'Limpeza',
          'Descanso',
          'Escovação',
        ].contains(t.trainingType);
        entries.add(
          _TimelineEntry(
            id: t.id,
            category: isRoutine ? 'Rotina' : 'Treino',
            originalModel: t,
            time: t.date,
            title: isRoutine
                ? 'ROTINA: ${t.trainingType}'
                : 'TREINO: ${t.trainingType}',
            location: t.location,
            type: isRoutine ? 'Rotina' : 'Treino',
            details: {
              'Clima': t.weather,
              'Duração': t.searchDuration != null
                  ? '${(t.searchDuration! / 60).round()} min'
                  : null,
              'Notas': t.handlerNotes,
              if (t.mediaAttachments != null && t.mediaAttachments!.isNotEmpty)
                '_mediaAttachments': t.mediaAttachments,
              ...?t.metadata,
            },
          ),
        );
      }
    }

    // Include incidents only if not in Training-only tab
    if (filterType != 'Training') {
      for (var i in incidents) {
        final incidentTitle = _resolveIncidentTimelineTitle(i);
        entries.add(
          _TimelineEntry(
            id: i.id,
            category: 'Ocorrência',
            originalModel: i,
            time: i.date,
            title: 'OCORRÊNCIA: $incidentTitle',
            location: i.location,
            type: 'Ocorrência',
            details: {
              'Resultado': i.displayResult,
              'Status': i.status,
              'Descrição': i.description,
              if (i.outcomes.isNotEmpty) '_outcomes': i.outcomes,
              if (i.progressUpdates.isNotEmpty)
                '_progressUpdates': i.progressUpdates
                    .map(
                      (update) => {
                        'title': update.title,
                        'description': update.description,
                        'location': update.location,
                        'timestamp': update.timestamp,
                        'authorId': update.authorId,
                        'authorName': update.authorName,
                      },
                    )
                    .toList(),
              if (i.mediaAttachments != null && i.mediaAttachments!.isNotEmpty)
                '_mediaAttachments': i.mediaAttachments,
            },
          ),
        );
      }
    }

    entries.sort((a, b) => b.time.compareTo(a.time));

    if (entries.isEmpty) {
      final bool isIncidentsTab = filterType == 'Ocorrência';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isIncidentsTab
                    ? Icons.shield_outlined
                    : Icons.assignment_turned_in_outlined,
                size: 80,
                color: Colors.white.withAlpha(50),
              ),
              const SizedBox(height: 16),
              Text(
                isIncidentsTab
                    ? 'Nenhuma ocorrência encontrada'
                    : 'Plantão Tranquilo',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              if (!isIncidentsTab)
                Text(
                  'Puxe o card abaixo para registrar a primeira atividade do K9.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white38,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 16, 10, 32),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final current = entries[index];
        final incident = current.originalModel is Incident
            ? current.originalModel as Incident
            : null;
        final isActiveIncident = incident?.isInProgress ?? false;
        final timeStr =
            "${current.time.hour.toString().padLeft(2, '0')}:${current.time.minute.toString().padLeft(2, '0')}";

        IconData icon;
        Color color;
        switch (current.type) {
          case 'Treino':
            icon = Icons.track_changes_rounded;
            color = const Color(0xFFFFB300);
            break;
          case 'Rotina':
            icon = Icons.pets_rounded;
            color = const Color(0xFF43A047);
            break;
          case 'Ocorrência':
            icon = isActiveIncident
                ? Icons.pending_actions_rounded
                : Icons.shield_outlined;
            color = isActiveIncident ? _hudAmber : const Color(0xFFE53935);
            break;
          case 'Saude':
            icon = Icons.vaccines_rounded;
            color = const Color(0xFF8E24AA);
            break;
          default:
            icon = Icons.info_outline;
            color = Colors.blueGrey;
        }

        final cleanTitle = _cleanTimelineTitle(current);
        final subtitle = _buildTimelineSubtitle(current, timeStr);

        String mainMetric = '';
        if (current.type == 'Treino' && current.details['Duração'] != null) {
          mainMetric = current.details['Duração'];
        }
        if (isActiveIncident) {
          mainMetric = 'EM ANDAMENTO';
        } else if (current.type == 'Ocorrência' &&
            current.details['Resultado'] != null) {
          mainMetric = current.details['Resultado'].toString().toUpperCase();
        }

        return TimelineTile(
          alignment: TimelineAlign.manual,
          lineXY: 0.12,
          isFirst: index == 0,
          isLast: index == entries.length - 1,
          beforeLineStyle: LineStyle(
            color: color.withAlpha(90),
            thickness: 2.5,
          ),
          afterLineStyle: LineStyle(color: color.withAlpha(70), thickness: 2.5),
          indicatorStyle: IndicatorStyle(
            width: 40,
            height: 40,
            drawGap: true,
            indicator: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF070B14),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: color.withAlpha(140),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(child: Icon(icon, color: color, size: 19)),
            ),
          ),
          endChild: Padding(
            padding: const EdgeInsets.only(
              left: 14,
              right: 4,
              bottom: 16,
              top: 4,
            ),
            child: Card(
              elevation: 0,
              color: const Color(0xFF0B1020),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(color: color.withAlpha(150), width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: color, width: 4)),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color.withAlpha(32),
                        const Color(0xFF0F1726),
                        const Color(0xFF070B14),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withAlpha(45),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      onExpansionChanged: (expanded) {
                        if (expanded) HapticFeedback.lightImpact();
                      },
                      iconColor: color,
                      collapsedIconColor: color.withAlpha(180),
                      tilePadding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                      title: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF070B14),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: color.withAlpha(170)),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withAlpha(60),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            child: Icon(icon, color: color, size: 17),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cleanTitle.toUpperCase(),
                                  style: GoogleFonts.oxanium(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    letterSpacing: 1.1,
                                  ),
                                  softWrap: true,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  subtitle,
                                  style: GoogleFonts.robotoMono(
                                    color: Colors.white60,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  softWrap: true,
                                ),
                                if (mainMetric.isNotEmpty) ...[
                                  const SizedBox(height: 9),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withAlpha(20),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: color.withAlpha(120),
                                        ),
                                      ),
                                      child: Text(
                                        mainMetric,
                                        style: GoogleFonts.oxanium(
                                          color: color,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 11,
                                          letterSpacing: 0.7,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildTimelineDetailPanel(current, color),

                              if (current.type == 'Ocorrência' &&
                                  current.details['_outcomes'] is List &&
                                  (current.details['_outcomes'] as List)
                                      .isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'RESULTADOS FINAIS',
                                  style: GoogleFonts.oxanium(
                                    color: color.withAlpha(230),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children:
                                      (current.details['_outcomes'] as List).map<
                                        Widget
                                      >((outcome) {
                                        final badgeStyle =
                                            _resolveIncidentOutcomeBadgeStyle(
                                              outcome.toString(),
                                            );
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: badgeStyle.backgroundColor,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: badgeStyle.borderColor,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                badgeStyle.icon,
                                                size: 13,
                                                color: badgeStyle.iconColor,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                outcome.toString(),
                                                style: GoogleFonts.inter(
                                                  color: badgeStyle.textColor,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                ),
                              ],

                              if (current.type == 'Ocorrência' &&
                                  current.details['_progressUpdates'] is List &&
                                  (current.details['_progressUpdates'] as List)
                                      .isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Text(
                                  'LINHA DO TEMPO',
                                  style: GoogleFonts.oxanium(
                                    color: color.withAlpha(230),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildIncidentProgressTimeline(
                                  updates:
                                      current.details['_progressUpdates']
                                          as List,
                                  accent: color,
                                ),
                              ],

                              if (current.details.containsKey(
                                    '_trackingDistance',
                                  ) ||
                                  current.details.containsKey(
                                    '_trackingdistance',
                                  )) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF070B14,
                                    ).withAlpha(220),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: color.withAlpha(140),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.straighten_rounded,
                                        color: color,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'DISTÂNCIA TOTAL PERCORRIDA: ',
                                        style: GoogleFonts.robotoMono(
                                          color: color.withAlpha(210),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        () {
                                          final dist =
                                              ((current.details['_trackingDistance'] ??
                                                          current
                                                              .details['_trackingdistance'])
                                                      as num)
                                                  .toDouble();
                                          return dist > 999
                                              ? '${(dist / 1000).toStringAsFixed(1)} km'
                                              : '${dist.toStringAsFixed(1)} m';
                                        }(),
                                        style: GoogleFonts.oxanium(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              // Renderiza o mini-mapa em estilo Strava
                              if (current.details.containsKey(
                                    '_trackingRoute',
                                  ) ||
                                  current.details.containsKey(
                                    '_trackingroute',
                                  )) ...[
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    height: 200,
                                    width: double.infinity,
                                    child: () {
                                      final rawRoute =
                                          (current.details['_trackingRoute'] ??
                                                  current
                                                      .details['_trackingroute'])
                                              as List;
                                      final route = rawRoute
                                          .map<LatLng>(
                                            (p) => LatLng(
                                              (p['lat'] as num).toDouble(),
                                              (p['lng'] as num).toDouble(),
                                            ),
                                          )
                                          .toList();

                                      if (route.isEmpty) {
                                        return const SizedBox();
                                      }

                                      return GoogleMap(
                                        style: _darkMapStyle,
                                        initialCameraPosition: CameraPosition(
                                          target: route.first,
                                          zoom: 15,
                                        ),
                                        onMapCreated: (controller) {
                                          // Pequeno atraso para o mapa carregar antes de ajustar os limites.
                                          Future.delayed(
                                            const Duration(milliseconds: 500),
                                            () {
                                              controller.animateCamera(
                                                CameraUpdate.newLatLngBounds(
                                                  _getBounds(route),
                                                  32,
                                                ),
                                              );
                                            },
                                          );
                                        },
                                        polylines: {
                                          Polyline(
                                            polylineId: PolylineId(
                                              'route_${current.time.millisecondsSinceEpoch}',
                                            ),
                                            points: route,
                                            color: const Color(0xFFFBBF24),
                                            width: 4,
                                          ),
                                        },
                                        scrollGesturesEnabled: false,
                                        zoomGesturesEnabled: false,
                                        tiltGesturesEnabled: false,
                                        rotateGesturesEnabled: false,
                                        myLocationButtonEnabled: false,
                                        zoomControlsEnabled: false,
                                        mapToolbarEnabled: false,
                                      );
                                    }(),
                                  ),
                                ),
                              ],

                              // Renderiza a galeria de fotos
                              if (current.details.containsKey(
                                    '_mediaAttachments',
                                  ) &&
                                  (current.details['_mediaAttachments'] as List)
                                      .isNotEmpty) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 100,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount:
                                        (current.details['_mediaAttachments']
                                                as List)
                                            .length,
                                    itemBuilder: (context, idx) {
                                      final media =
                                          (current.details['_mediaAttachments']
                                              as List)[idx];
                                      if (media['type'] == 'pdf') {
                                        return const SizedBox.shrink();
                                      }
                                      return Container(
                                        width: 140,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          color: const Color(0xFF070B14),
                                          border: Border.all(
                                            color: color.withAlpha(120),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: color.withAlpha(35),
                                              blurRadius: 12,
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: Stack(
                                            children: [
                                              Positioned.fill(
                                                child: CachedNetworkImage(
                                                  imageUrl: media['url'] ?? '',
                                                  fit: BoxFit.cover,
                                                  placeholder: (context, url) =>
                                                      const Center(
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color: Colors
                                                                  .white38,
                                                            ),
                                                      ),
                                                  errorWidget:
                                                      (
                                                        context,
                                                        url,
                                                        err,
                                                      ) => const Center(
                                                        child: Icon(
                                                          Icons.broken_image,
                                                          color: Colors.white24,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                              if (media['caption'] != null &&
                                                  media['caption']
                                                      .toString()
                                                      .isNotEmpty)
                                                Positioned(
                                                  bottom: 0,
                                                  left: 0,
                                                  right: 0,
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                    color: Colors.black87,
                                                    child: Text(
                                                      media['caption'],
                                                      style: GoogleFonts.inter(
                                                        color: Colors.white,
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],

                              // Botão para abrir PDF (exames).
                              if (current.type == 'Saude' &&
                                  (current.details['_mediaAttachments']
                                              as List? ??
                                          [])
                                      .any((m) => m['type'] == 'pdf')) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      final pdfMedia =
                                          (current.details['_mediaAttachments']
                                                  as List)
                                              .firstWhere(
                                                (m) => m['type'] == 'pdf',
                                              );
                                      final url = Uri.parse(pdfMedia['url']);
                                      if (await canLaunchUrl(url)) {
                                        await launchUrl(
                                          url,
                                          mode: LaunchMode.externalApplication,
                                        );
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.picture_as_pdf_rounded,
                                      color: Colors.black,
                                    ),
                                    label: Text(
                                      'VISUALIZAR DOCUMENTO (PDF)',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w900,
                                        color: Colors.black,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFBBF24),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 16),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Wrap(
                                  spacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        Map<String, dynamic> data;
                                        String handlerIdStr = '';
                                        if (current.category == 'Ocorrência') {
                                          data = current.originalModel.toJson();
                                          handlerIdStr =
                                              current.originalModel.handlerId;
                                        } else {
                                          data = current.originalModel.toJson();
                                        }
                                        data['_rawDate'] = current.time;
                                        if (handlerIdStr.isNotEmpty) {
                                          data['_rawHandlerId'] = handlerIdStr;
                                        }

                                        if (current.category == 'Ocorrência' &&
                                            current.originalModel is Incident) {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  OccurrenceFlowScreen(
                                                    dogId: dogId,
                                                    dogName: dogName,
                                                    incident:
                                                        current.originalModel
                                                            as Incident,
                                                  ),
                                            ),
                                          );
                                          return;
                                        }

                                        showModalBottomSheet(
                                          context: context,
                                          isScrollControlled: true,
                                          backgroundColor: Colors.transparent,
                                          builder: (context) =>
                                              DynamicActivitySheet(
                                                category: current.category,
                                                dogId: dogId,
                                                dogName: dogName,
                                                initialData: data,
                                                documentId: current.id,
                                              ),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.edit_rounded,
                                        size: 14,
                                      ),
                                      label: Text(
                                        'EDITAR REGISTRO',
                                        style: GoogleFonts.oxanium(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: color,
                                        side: BorderSide(
                                          color: color.withAlpha(180),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                          horizontal: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
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
            ),
          ),
        );
      },
    );
  }
}

class _TimelineEntry {
  final String? id;
  final String category;
  final dynamic originalModel;
  final DateTime time;
  final String title;
  final String location;
  final String type;
  final Map<String, dynamic> details;

  _TimelineEntry({
    this.id,
    required this.category,
    this.originalModel,
    required this.time,
    required this.title,
    required this.location,
    required this.type,
    required this.details,
  });
}

// Widget auxiliar de estatística.
class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(230),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withAlpha(80)),
          boxShadow: [BoxShadow(color: color.withAlpha(12), blurRadius: 12)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.robotoMono(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.robotoMono(
                color: Colors.white54,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Widget auxiliar de filtro
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF00E5FF).withAlpha(30)
              : _hudPanel.withAlpha(180),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? const Color(0xFF00E5FF) : const Color(0xFF2A2A2A),
            width: 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withAlpha(28),
                    blurRadius: 12,
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: GoogleFonts.robotoMono(
            color: selected ? const Color(0xFF00E5FF) : Colors.white70,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
