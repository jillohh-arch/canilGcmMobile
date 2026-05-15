import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';

part 'global_incidents_body.dart';
part 'global_incidents_components.dart';
part 'global_incidents_empty_state.dart';
part 'global_incidents_feed_card.dart';
part 'global_incidents_feed_card_header.dart';
part 'global_incidents_feed_card_sections.dart';

class GlobalIncidentsScreen extends StatefulWidget {
  const GlobalIncidentsScreen({super.key});

  @override
  State<GlobalIncidentsScreen> createState() => _GlobalIncidentsScreenState();
}

class _GlobalIncidentsScreenState extends State<GlobalIncidentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<IncidentViewModel>(
        context,
        listen: false,
      ).fetchAllIncidents();
    });
  }

  @override
  Widget build(BuildContext context) {
    final iVM = Provider.of<IncidentViewModel>(context);
    final incidents = [...iVM.incidents]
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Feed de OcorrÃªncias',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: _GlobalIncidentsBody(
        isLoading: iVM.isLoading,
        incidents: incidents,
      ),
    );
  }
}
