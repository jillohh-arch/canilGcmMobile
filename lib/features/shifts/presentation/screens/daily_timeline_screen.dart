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

import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/routine/presentation/viewmodels/routine_viewmodel.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/routine/domain/routine_model.dart';
import 'package:canil_gcm/core/services/report_service.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/widgets/hud_tab_bar.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/incidents/presentation/screens/occurrence_flow_screen.dart';
import 'dynamic_activity_sheet.dart';

part 'daily_timeline_date_controls.dart';
part 'daily_timeline_detail_helpers.dart';
part 'daily_timeline_detail_panel.dart';
part 'daily_timeline_detail_tile.dart';
part 'daily_timeline_entry_builders.dart';
part 'daily_timeline_entry_data.dart';
part 'daily_timeline_entry_actions.dart';
part 'daily_timeline_entry_expanded_content.dart';
part 'daily_timeline_entry_incident_sections.dart';
part 'daily_timeline_entry_media.dart';
part 'daily_timeline_entry_tracking.dart';
part 'daily_timeline_evolution_attention.dart';
part 'daily_timeline_evolution_chart.dart';
part 'daily_timeline_evolution_chart_data.dart';
part 'daily_timeline_evolution_chart_legend.dart';
part 'daily_timeline_evolution_competencies.dart';
part 'daily_timeline_evolution_filter_chips.dart';
part 'daily_timeline_evolution_last_training.dart';
part 'daily_timeline_evolution_metrics.dart';
part 'daily_timeline_evolution_recent_sessions.dart';
part 'daily_timeline_evolution_scope.dart';
part 'daily_timeline_evolution_sections.dart';
part 'daily_timeline_evolution_summary.dart';
part 'daily_timeline_evolution_titles.dart';
part 'daily_timeline_evolution_training_query.dart';
part 'daily_timeline_evolution_week_comparison.dart';
part 'daily_timeline_export.dart';
part 'daily_timeline_incident_close_controls.dart';
part 'daily_timeline_incident_close_form.dart';
part 'daily_timeline_incident_close_options.dart';
part 'daily_timeline_incident_close_sheet.dart';
part 'daily_timeline_incident_chips.dart';
part 'daily_timeline_incident_outcomes.dart';
part 'daily_timeline_incident_progress_styles.dart';
part 'daily_timeline_incident_shortcuts.dart';
part 'daily_timeline_incident_shared_widgets.dart';
part 'daily_timeline_incident_styles.dart';
part 'daily_timeline_incident_time_formatters.dart';
part 'daily_timeline_incident_update_controls.dart';
part 'daily_timeline_incident_update_form.dart';
part 'daily_timeline_incident_update_options.dart';
part 'daily_timeline_incident_update_sheet.dart';
part 'daily_timeline_item.dart';
part 'daily_timeline_item_header.dart';
part 'daily_timeline_item_presentation.dart';
part 'daily_timeline_list.dart';
part 'daily_timeline_map_helpers.dart';
part 'daily_timeline_models.dart';
part 'daily_timeline_occurrences_tab.dart';
part 'daily_timeline_open_incident_card.dart';
part 'daily_timeline_open_incident_card_actions.dart';
part 'daily_timeline_open_incident_card_details.dart';
part 'daily_timeline_open_incident_card_header.dart';
part 'daily_timeline_open_incident_latest_update.dart';
part 'daily_timeline_open_incident_stats.dart';
part 'daily_timeline_progress.dart';
part 'daily_timeline_progress_helpers.dart';
part 'daily_timeline_progress_node.dart';
part 'daily_timeline_text_helpers.dart';
part 'daily_timeline_widgets.dart';

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
}
