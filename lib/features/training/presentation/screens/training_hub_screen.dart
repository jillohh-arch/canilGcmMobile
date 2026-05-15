import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/screens/training_log_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/dynamic_activity_sheet.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';

part 'training_hub_header.dart';
part 'training_hub_stats.dart';
part 'training_hub_categories.dart';

class TrainingHubScreen extends StatelessWidget {
  const TrainingHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context);
    final trainingVM = Provider.of<TrainingViewModel>(context);

    final dogId = shiftVM.activeDogId;
    Dog? dog;
    try {
      dog = dogVM.dogs.firstWhere((d) => d.id == dogId);
    } catch (_) {}

    if (dog == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Text(
            'Nenhum cão ativo no turno.',
            style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: _TrainingHubHeader(dog: dog),
            ),

            // Stats rápidas
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _TrainingHubStats(trainingVM: trainingVM),
              ),
            ),

            // Categorias
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Text(
                  'CATEGORIAS DE TREINO',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textTertiary,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _TrainingHubCategories(
                  dog: dog,
                  onCategoryTap: (category) {
                    HapticFeedback.mediumImpact();
                    _openTrainingSheet(context, category, dog!);
                  },
                ),
              ),
            ),

            // Evolução (link)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: _EvolutionLink(dog: dog),
              ),
            ),

            // Último treino
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: _LastTrainingCard(trainingVM: trainingVM),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticFeedback.mediumImpact();
          _openTrainingSheet(context, 'Treino', dog!);
        },
        backgroundColor: AppTheme.primary,
        child: Icon(Icons.add_rounded, color: AppTheme.background, size: 28),
      ),
    );
  }

  void _openTrainingSheet(BuildContext context, String category, Dog dog) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DynamicActivitySheet(
        category: 'Treino',
        dogId: dog.id,
        dogName: dog.name,
      ),
    );
  }
}

class _EvolutionLink extends StatelessWidget {
  final Dog dog;
  const _EvolutionLink({required this.dog});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TrainingLogScreen(dogId: dog.id, dogName: dog.name),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1A1F),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF1D2C33), width: 0.8),
        ),
        child: Row(
          children: [
            Icon(Icons.show_chart_rounded, color: AppTheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Evolução & Histórico',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Gráficos, sessões anteriores e progresso',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _LastTrainingCard extends StatelessWidget {
  final TrainingViewModel trainingVM;
  const _LastTrainingCard({required this.trainingVM});

  @override
  Widget build(BuildContext context) {
    if (trainingVM.trainings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1A1F),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF1D2C33), width: 0.8),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: AppTheme.textTertiary, size: 18),
            const SizedBox(width: 10),
            Text(
              'Nenhum treino registrado ainda.',
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    final last = trainingVM.trainings.first;
    final timeStr =
        '${last.date.day.toString().padLeft(2, '0')}/${last.date.month.toString().padLeft(2, '0')} às ${last.date.hour.toString().padLeft(2, '0')}:${last.date.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A1F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1D2C33), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ÚLTIMO TREINO',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.textTertiary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.fitness_center_rounded, color: AppTheme.primary, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  last.trainingType,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Text(
                timeStr,
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}