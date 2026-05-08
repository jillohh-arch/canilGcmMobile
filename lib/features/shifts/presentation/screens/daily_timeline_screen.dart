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

part 'daily_timeline_app_shell.dart';
part 'daily_timeline_data_loader.dart';
part 'daily_timeline_date_chip.dart';
part 'daily_timeline_date_controls.dart';
part 'daily_timeline_date_selector.dart';
part 'daily_timeline_detail_helpers.dart';
part 'daily_timeline_detail_icon.dart';
part 'daily_timeline_detail_panel.dart';
part 'daily_timeline_detail_text.dart';
part 'daily_timeline_detail_tile.dart';
part 'daily_timeline_entry_builders.dart';
part 'daily_timeline_entry_data.dart';
part 'daily_timeline_entry_incident_builder.dart';
part 'daily_timeline_entry_routine_health_builders.dart';
part 'daily_timeline_entry_actions.dart';
part 'daily_timeline_entry_expanded_content.dart';
part 'daily_timeline_entry_incident_sections.dart';
part 'daily_timeline_entry_incident_outcomes.dart';
part 'daily_timeline_entry_incident_progress_section.dart';
part 'daily_timeline_entry_documents.dart';
part 'daily_timeline_entry_editor.dart';
part 'daily_timeline_entry_media.dart';
part 'daily_timeline_entry_photo_gallery.dart';
part 'daily_timeline_entry_training_builder.dart';
part 'daily_timeline_entry_tracking_distance.dart';
part 'daily_timeline_entry_tracking_route.dart';
part 'daily_timeline_entry_tracking.dart';
part 'daily_timeline_evolution_attention.dart';
part 'daily_timeline_evolution_attention_alerts.dart';
part 'daily_timeline_evolution_chart.dart';
part 'daily_timeline_evolution_chart_bars.dart';
part 'daily_timeline_evolution_category_visual.dart';
part 'daily_timeline_evolution_chart_data.dart';
part 'daily_timeline_evolution_chart_legend.dart';
part 'daily_timeline_evolution_chart_titles.dart';
part 'daily_timeline_evolution_competency_card.dart';
part 'daily_timeline_evolution_competency_data.dart';
part 'daily_timeline_evolution_competency_icon.dart';
part 'daily_timeline_evolution_competency_share_badge.dart';
part 'daily_timeline_evolution_competencies.dart';
part 'daily_timeline_evolution_filter_chips.dart';
part 'daily_timeline_evolution_formatters.dart';
part 'daily_timeline_evolution_last_training.dart';
part 'daily_timeline_evolution_metrics.dart';
part 'daily_timeline_evolution_recent_session_tile.dart';
part 'daily_timeline_evolution_recent_sessions.dart';
part 'daily_timeline_evolution_recent_sessions_empty.dart';
part 'daily_timeline_evolution_scope.dart';
part 'daily_timeline_evolution_scope_card.dart';
part 'daily_timeline_evolution_sections.dart';
part 'daily_timeline_evolution_stat_rows.dart';
part 'daily_timeline_evolution_stale_category_alerts.dart';
part 'daily_timeline_evolution_summary.dart';
part 'daily_timeline_evolution_titles.dart';
part 'daily_timeline_evolution_training_query.dart';
part 'daily_timeline_evolution_volume_alert.dart';
part 'daily_timeline_evolution_week_comparison_copy.dart';
part 'daily_timeline_evolution_week_comparison_style.dart';
part 'daily_timeline_evolution_week_comparison.dart';
part 'daily_timeline_export.dart';
part 'daily_timeline_filter_chip.dart';
part 'daily_timeline_incident_close_controls.dart';
part 'daily_timeline_incident_close_form.dart';
part 'daily_timeline_incident_close_operational_outcome.dart';
part 'daily_timeline_incident_close_results.dart';
part 'daily_timeline_incident_close_save.dart';
part 'daily_timeline_incident_common_progress_shortcuts.dart';
part 'daily_timeline_incident_close_sheet.dart';
part 'daily_timeline_incident_badge.dart';
part 'daily_timeline_incident_meta_pill.dart';
part 'daily_timeline_incident_default_outcomes.dart';
part 'daily_timeline_incident_outcome_summary.dart';
part 'daily_timeline_incident_outcome_style.dart';
part 'daily_timeline_incident_outcomes.dart';
part 'daily_timeline_incident_progress_shortcuts.dart';
part 'daily_timeline_incident_progress_styles.dart';
part 'daily_timeline_incident_selection_chip.dart';
part 'daily_timeline_incident_shared_widgets.dart';
part 'daily_timeline_incident_status_style.dart';
part 'daily_timeline_incident_time_formatters.dart';
part 'daily_timeline_incident_type_progress_shortcuts.dart';
part 'daily_timeline_incident_update_actions.dart';
part 'daily_timeline_incident_update_form.dart';
part 'daily_timeline_incident_update_header.dart';
part 'daily_timeline_incident_update_note.dart';
part 'daily_timeline_incident_update_outcome_section.dart';
part 'daily_timeline_incident_update_save.dart';
part 'daily_timeline_incident_update_sheet.dart';
part 'daily_timeline_incident_update_shortcut_section.dart';
part 'daily_timeline_item.dart';
part 'daily_timeline_item_card.dart';
part 'daily_timeline_item_header.dart';
part 'daily_timeline_item_indicator.dart';
part 'daily_timeline_item_presentation.dart';
part 'daily_timeline_list.dart';
part 'daily_timeline_map_helpers.dart';
part 'daily_timeline_models.dart';
part 'daily_timeline_occurrences_tab.dart';
part 'daily_timeline_operator_helpers.dart';
part 'daily_timeline_open_incident_card.dart';
part 'daily_timeline_open_incident_card_actions.dart';
part 'daily_timeline_open_incident_card_details.dart';
part 'daily_timeline_open_incident_card_header.dart';
part 'daily_timeline_open_incident_latest_update.dart';
part 'daily_timeline_open_incident_latest_update_icon.dart';
part 'daily_timeline_open_incident_outcome_badges.dart';
part 'daily_timeline_open_incident_stat_tile.dart';
part 'daily_timeline_open_incident_stats.dart';
part 'daily_timeline_open_incidents_data.dart';
part 'daily_timeline_open_incidents_header.dart';
part 'daily_timeline_progress.dart';
part 'daily_timeline_progress_helpers.dart';
part 'daily_timeline_progress_node.dart';
part 'daily_timeline_progress_node_card.dart';
part 'daily_timeline_progress_node_header.dart';
part 'daily_timeline_progress_node_meta.dart';
part 'daily_timeline_progress_node_rail.dart';
part 'daily_timeline_stat_box.dart';
part 'daily_timeline_text_helpers.dart';
part 'daily_timeline_training_categories.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadTimelineDataForActiveShift(),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    if (!shiftVM.hasActiveShift) {
      return _buildNoActiveShiftScaffold();
    }

    final dogId = shiftVM.activeDogId!;
    return _buildTimelineScaffold(dogId);
  }
}
