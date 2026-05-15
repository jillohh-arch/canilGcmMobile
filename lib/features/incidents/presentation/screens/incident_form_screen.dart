import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/incidents/domain/occurrence_nature.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import '../widgets/occurrence_nature_search.dart';

part 'incident_feed_widgets.dart';
part 'incident_feed_components.dart';
part 'incident_feed_card.dart';
part 'incident_feed_card_header.dart';
part 'incident_feed_card_sections.dart';
part 'incident_feed_empty_state.dart';
part 'incident_new_form.dart';
part 'incident_new_hero_widgets.dart';
part 'incident_new_context_widgets.dart';
part 'incident_new_info_card.dart';
part 'incident_new_nature_field.dart';
part 'incident_new_start_button.dart';
part 'incident_tactical_grid_painter.dart';

class IncidentFormScreen extends StatefulWidget {
  final String dogId;
  const IncidentFormScreen({super.key, required this.dogId});

  @override
  State<IncidentFormScreen> createState() => _IncidentFormScreenState();
}

class _IncidentFormScreenState extends State<IncidentFormScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<IncidentViewModel>(
        context,
        listen: false,
      ).fetchIncidentsForDog(widget.dogId);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          'Ocorrências',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          labelStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          unselectedLabelStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          tabs: const [
            Tab(icon: Icon(Icons.feed_rounded), text: 'Feed'),
            Tab(icon: Icon(Icons.add_circle_outline_rounded), text: 'Nova'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _IncidentFeed(dogId: widget.dogId),
          _NewIncidentForm(
            dogId: widget.dogId,
            onSaved: () => _tabController.animateTo(0),
          ),
        ],
      ),
    );
  }
}

// Incident Feed (estilo feed/logÃ­stica) --------------------------------------
