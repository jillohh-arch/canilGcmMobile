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
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/screens/occurrence_flow_screen.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/training/presentation/screens/training_log_screen.dart';

part 'dog_details_widgets.dart';
part 'dog_details_bento.dart';
part 'dog_details_training_bento.dart';
part 'dog_details_health_bento.dart';
part 'dog_details_traits_bento.dart';
part 'dog_weight_dialog.dart';
part 'dog_details_mission_log.dart';

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
    final opStatus = dog.operationalStatus;
    final gradient = AppTheme.statusGradient(opStatus);
    final statusColor = AppTheme.statusColor(opStatus);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Agent Hero Header ───────────────────────────────────────
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            stretch: true,
            backgroundColor: AppTheme.statusBg(opStatus),
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.blurBackground,
              ],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(decoration: BoxDecoration(gradient: gradient)),
                  // Blobs
                  Positioned(
                    right: -60,
                    top: -40,
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha(12),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -30,
                    bottom: -30,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withAlpha(25),
                      ),
                    ),
                  ),
                  // Agent ID layout
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Photo
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(80),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 56,
                              backgroundColor: Colors.white24,
                              backgroundImage: dog.profileImageUrl != null
                                  ? NetworkImage(dog.profileImageUrl!)
                                  : null,
                              child: dog.profileImageUrl == null
                                  ? const FaIcon(
                                      FontAwesomeIcons.dog,
                                      size: 40,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 18),
                          // Info
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _AgentStatusPill(
                                  status: opStatus,
                                  color: statusColor,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  dog.name.toUpperCase(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                    height: 1.0,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      dog.breed,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
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
                                const SizedBox(height: 4),
                                Text(
                                  '${dog.age} anos · ID: ${dog.id.substring(0, 8).toUpperCase()}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: Colors.white38,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Quick Actions ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  _QuickActionButton(
                    icon: Icons.track_changes_rounded,
                    label: 'Faro',
                    color: const Color(0xFFFFB300),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TrainingLogScreen(dogId: dog.id, dogName: dog.name),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _QuickActionButton(
                    icon: Icons.medical_services_rounded,
                    label: 'Saúde',
                    color: const Color(0xFFEF5350),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HealthLogScreen(dogId: dog.id),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _QuickActionButton(
                    icon: Icons.report_rounded,
                    label: 'Ocorrência',
                    color: const Color(0xFF4ECDE4),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OccurrenceFlowScreen(
                          dogId: dog.id,
                          dogName: dog.name,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

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
