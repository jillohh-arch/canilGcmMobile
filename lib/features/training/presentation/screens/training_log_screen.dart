import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/dynamic_activity_sheet.dart';

part 'training_log_overview_widgets.dart';
part 'training_log_chart_widgets.dart';
part 'training_log_session_widgets.dart';
part 'training_session_card_parts.dart';
part 'training_session_detail_parts.dart';
part 'training_new_form.dart';

const _hudBackground = Color(0xFF070B14);
const _hudPanel = Color(0xFF0B1220);
const _hudCyan = Color(0xFF00E5FF);

class TrainingLogScreen extends StatefulWidget {
  final String dogId;
  final String dogName;
  const TrainingLogScreen({super.key, required this.dogId, this.dogName = ''});

  @override
  State<TrainingLogScreen> createState() => _TrainingLogScreenState();
}

class _TrainingLogScreenState extends State<TrainingLogScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TrainingViewModel>(
        context,
        listen: false,
      ).fetchTrainingsForDog(widget.dogId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _hudBackground,
      appBar: AppBar(
        backgroundColor: _hudBackground,
        elevation: 0,
        title: Text(
          'EVOLUÇÃO',
          style: GoogleFonts.oxanium(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Colors.white,
            letterSpacing: 1.5,
          ),
        ),
        centerTitle: true,
      ),
      body: _TrainingEvolutionTab(dogId: widget.dogId),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) => DynamicActivitySheet(
              category: 'Treino',
              dogId: widget.dogId,
              dogName: widget.dogName,
            ),
          );
        },
        backgroundColor: _hudCyan,
        child: const Icon(Icons.add_rounded, color: _hudBackground, size: 28),
      ),
    );
  }
}
