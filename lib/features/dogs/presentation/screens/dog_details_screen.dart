import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_log_screen.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/screens/occurrence_flow_screen.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/training/presentation/screens/training_log_screen.dart';

part 'dog_details_widgets.dart';
part 'dog_details_header.dart';
part 'dog_details_hero_widgets.dart';
part 'dog_details_bento.dart';
part 'dog_details_training_bento.dart';
part 'dog_details_health_bento.dart';
part 'dog_details_traits_bento.dart';
part 'dog_weight_dialog.dart';
part 'dog_details_mission_log.dart';
part 'dog_details_mission_log_widgets.dart';
part 'dog_details_mission_log_parts.dart';

class DogDetailsScreen extends StatefulWidget {
  final Dog dog;
  const DogDetailsScreen({super.key, required this.dog});

  @override
  State<DogDetailsScreen> createState() => _DogDetailsScreenState();
}

class _DogDetailsScreenState extends State<DogDetailsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TrainingViewModel>(
        context,
        listen: false,
      ).fetchTrainingsForDog(widget.dog.id);
      Provider.of<HealthViewModel>(
        context,
        listen: false,
      ).fetchHealthLogsForDog(widget.dog.id);
      Provider.of<IncidentViewModel>(
        context,
        listen: false,
      ).fetchIncidentsForDog(widget.dog.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dogList = Provider.of<DogViewModel>(context).dogs;
    final dog = dogList.firstWhere(
      (d) => d.id == widget.dog.id,
      orElse: () => widget.dog,
    );
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Agent Hero Header ───────────────────────────────────────
          _buildHeroHeader(dog),

          // ── Quick Actions ──────────────────────────────────────────
          _buildQuickActions(dog),

          // ── COCKPIT BENTO GRID ────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _CockpitBento(dog: dog),
            ),
          ),

          // ── Mission Log ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
              child: _MissionLog(dog: dog),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Cockpit Bento Grid ────────────────────────────────────────────────────────
