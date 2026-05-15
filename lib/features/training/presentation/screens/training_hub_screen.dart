import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/screens/training_log_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/detection_maintenance_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/obedience_training_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/conditioning_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/guard_protection_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/dynamic_activity_sheet.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';

part 'training_hub_header.dart';
part 'training_hub_categories.dart';

class TrainingHubScreen extends StatelessWidget {
  const TrainingHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context);

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

            // Especialidades + Treinos gerais
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
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
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: _EvolutionLink(dog: dog),
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
    // Route to dedicated screens based on category
    final lowerCat = category.toLowerCase();

    if (lowerCat.contains('detecção') || lowerCat.contains('deteccao')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DetectionMaintenanceScreen(dog: dog),
        ),
      );
      return;
    }

    if (lowerCat.contains('obediência') || lowerCat.contains('obediencia')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ObedienceTrainingScreen(dog: dog),
        ),
      );
      return;
    }

    if (lowerCat.contains('condicionamento')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConditioningScreen(dog: dog),
        ),
      );
      return;
    }

    if (lowerCat.contains('guarda') || lowerCat.contains('proteção') || lowerCat.contains('protecao')) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GuardProtectionScreen(dog: dog),
        ),
      );
      return;
    }

    // Fallback: Faro/Rastro, or generic "Treino"
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