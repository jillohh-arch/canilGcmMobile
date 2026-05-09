import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';

part 'health_log_timeline.dart';
part 'health_log_timeline_widgets.dart';
part 'health_log_new_form.dart';
part 'health_log_helpers.dart';

class HealthLogScreen extends StatefulWidget {
  final String dogId;
  const HealthLogScreen({super.key, required this.dogId});

  @override
  State<HealthLogScreen> createState() => _HealthLogScreenState();
}

class _HealthLogScreenState extends State<HealthLogScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<HealthViewModel>(
        context,
        listen: false,
      ).fetchHealthLogsForDog(widget.dogId);
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
          'Prontuário Médico',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.amber,
          labelColor: AppTheme.amber,
          unselectedLabelColor: cs.onSurfaceVariant,
          labelStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          unselectedLabelStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          tabs: const [
            Tab(icon: Icon(Icons.timeline_rounded), text: 'Histórico'),
            Tab(
              icon: Icon(Icons.add_circle_outline_rounded),
              text: 'Novo Registro',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _HealthTimeline(dogId: widget.dogId),
          _NewHealthLogForm(
            dogId: widget.dogId,
            onSaved: () => _tabController.animateTo(0),
          ),
        ],
      ),
    );
  }
}

// ── Health Timeline (Apple Health style) ──────────────────────────────────────
