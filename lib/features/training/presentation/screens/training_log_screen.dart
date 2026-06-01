import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:printing/printing.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/services/report_service.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/dynamic_activity_sheet.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';

part 'training_log_overview_widgets.dart';
part 'training_log_summary_widgets.dart';
part 'training_log_chart_widgets.dart';
part 'training_log_session_widgets.dart';
part 'training_session_card_parts.dart';
part 'training_session_card_details.dart';
part 'training_session_detail_parts.dart';
part 'training_new_form.dart';
part 'training_new_form_widgets.dart';
part 'training_new_form_actions.dart';
part 'training_new_form_fields.dart';
part 'training_new_form_selectors.dart';

const _hudBackground = AppTheme.background;
const _hudPanel = AppTheme.surfacePanel;
const _hudCyan = AppTheme.primary;

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
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: AppTheme.textPrimary,
            letterSpacing: 1.5,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Exportar PDF',
            icon: const Icon(
              Icons.picture_as_pdf_rounded,
              color: AppTheme.warningAccent,
            ),
            onPressed: () => _exportTrainingPdf(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _TrainingEvolutionTab(dogId: widget.dogId),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: AppTheme.transparent,
            builder: (_) => DynamicActivitySheet(
              category: 'Treino',
              dogId: widget.dogId,
              dogName: widget.dogName,
            ),
          );
        },
        backgroundColor: _hudCyan,
        child: Icon(Icons.add_rounded, color: _hudBackground, size: 28),
      ),
    );
  }

  Future<void> _exportTrainingPdf(BuildContext ctx) async {
    HapticFeedback.mediumImpact();
    final trainingVM = Provider.of<TrainingViewModel>(ctx, listen: false);
    final authVM = Provider.of<AuthViewModel>(ctx, listen: false);
    final userVM = Provider.of<UserViewModel>(ctx, listen: false);
    final dogVM = Provider.of<DogViewModel>(ctx, listen: false);

    final fbUser = authVM.user;
    final currentRa = HandlerIdentityService.raFromUser(fbUser);
    final callsign = userVM.displayNameFor(ra: currentRa, firebaseUser: fbUser);

    final matchingDogs = dogVM.dogs.where((d) => d.id == widget.dogId);
    if (matchingDogs.isEmpty) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('Aguarde o carregamento dos dados do K9.'),
        ),
      );
      return;
    }
    final dog = matchingDogs.first;

    final trainings =
        trainingVM.trainings.where((t) => t.dogId == widget.dogId).toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    if (trainings.isEmpty) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('Nenhuma sessão registrada para ${dog.name}.'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    final entries = trainings
        .map(
          (t) => ReportEntry(
            date: t.date,
            type: t.trainingType,
            location: t.location.isNotEmpty ? t.location : 'Canil GCM',
            observations: t.handlerNotes,
          ),
        )
        .toList();

    try {
      final first = trainings.first.date;
      final last = trainings.last.date;
      String fmt(DateTime d) =>
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

      final pdfBytes = await ReportService.generateActivityReport(
        dog: dog,
        conductorCallsign: callsign,
        entries: entries,
        period: 'Treinos — ${fmt(first)} a ${fmt(last)}',
      );

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'relatorio_treinos_${dog.name.toLowerCase()}.pdf',
      );
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('Erro ao gerar PDF: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }
}
