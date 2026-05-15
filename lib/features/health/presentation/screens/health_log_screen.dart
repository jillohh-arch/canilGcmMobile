import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';

part 'health_log_timeline.dart';
part 'health_log_filter_bar.dart';
part 'health_log_timeline_list.dart';
part 'health_log_timeline_item.dart';
part 'health_log_timeline_item_body.dart';
part 'health_log_expanded_details.dart';
part 'health_log_empty_state.dart';
part 'health_log_new_form.dart';
part 'health_log_type_selector.dart';
part 'health_log_form_fields.dart';
part 'health_log_save_button.dart';
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
          'ProntuÃ¡rio MÃ©dico',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.amber,
          labelColor: AppTheme.amber,
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
            Tab(icon: Icon(Icons.timeline_rounded), text: 'HistÃ³rico'),
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

// â”€â”€ Health Timeline (Apple Health style) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
