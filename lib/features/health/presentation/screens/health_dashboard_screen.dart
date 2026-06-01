import 'package:flutter/material.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';

part 'health_dashboard_helpers.dart';
part 'health_bio_header.dart';
part 'health_bio_avatar.dart';
part 'health_readiness_hud_bar.dart';
part 'health_sensor_cards.dart';
part 'health_sensor_card.dart';
part 'health_weight_update_dialog.dart';
part 'health_weight_section.dart';
part 'health_timeline_section.dart';
part 'health_timeline_log_card.dart';
part 'health_timeline_log_card_header.dart';
part 'health_timeline_log_card_body.dart';
part 'health_timeline_log_attachments.dart';
part 'health_timeline_log_style.dart';
part 'health_weight_chart_painter.dart';

class HealthDashboardScreen extends StatefulWidget {
  const HealthDashboardScreen({super.key});

  @override
  State<HealthDashboardScreen> createState() => _HealthDashboardScreenState();
}

class _HealthDashboardScreenState extends State<HealthDashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    if (!shiftVM.hasActiveShift) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Text(
            'Nenhum turno ativo.',
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary.withAlpha(138),
            ),
          ),
        ),
      );
    }

    final dogId = shiftVM.activeDogId!;
    final dogVM = Provider.of<DogViewModel>(context);
    final hVM = Provider.of<HealthViewModel>(context);

    final dog = dogVM.dogs.firstWhere(
      (d) => d.id == dogId,
      orElse: () => dogVM.dogs.first,
    );
    final logs = hVM.healthLogs.where((l) => l.dogId == dogId).toList();

    DateTime? lastBath;
    try {
      lastBath = logs.firstWhere((l) => l.logType == 'Banho').date;
    } catch (_) {}

    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: null,
      body: CustomScrollView(
        slivers: [
          _buildSliverHeader(),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildBioHudHeader(dog, logs, lastBath),
                _buildSensorRow(dog, lastBath),
                _buildWeightGraphCard(), // O novo gráfico integrado!
                _buildTimelineHeader(),
              ],
            ),
          ),
          _buildTacticalLogs(context, logs),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}
