import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/data/dog_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/dynamic_activity_sheet.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/data/training_service.dart';
import 'package:canil_gcm/features/training/domain/training_model.dart';
import 'package:canil_gcm/features/training/presentation/screens/conditioning_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/detection_maintenance_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/guard_protection_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/obedience_training_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/training_log_screen.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/screens/detection_triagem_screen.dart';
import 'package:canil_gcm/features/dogs/data/dog_specialty_service.dart';

part 'training_hub_header.dart';
part 'training_hub_categories.dart';


class TrainingHubScreen extends StatefulWidget {
  const TrainingHubScreen({super.key});

  @override
  State<TrainingHubScreen> createState() => _TrainingHubScreenState();
}

class _TrainingHubScreenState extends State<TrainingHubScreen> {
  final DogService _dogService = DogService();
  final TrainingService _trainingService = TrainingService();

  String? _boundDogId;
  Stream<Dog?>? _dogStream;
  Stream<List<TrainingSpecialtyModel>>? _specialtiesStream;
  Stream<List<TrainingHubSession>>? _sessionsStream;

  void _bindDogStreams(String dogId) {
    if (_boundDogId == dogId) return;
    _boundDogId = dogId;
    _dogStream = _dogService.watchDog(dogId);
    _specialtiesStream = _trainingService.watchSpecialtiesForDog(dogId);
    _sessionsStream = _trainingService.watchSessionsForDog(dogId);
  }

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context);
    final userVM = Provider.of<UserViewModel>(context);
    final authVM = Provider.of<AuthViewModel>(context);

    if (!shiftVM.hasActiveShift || shiftVM.activeDogId == null) {
      return const _TrainingNoShift();
    }

    final dogId = shiftVM.activeDogId!;
    _bindDogStreams(dogId);

    final currentRa =
        shiftVM.handlerId ?? HandlerIdentityService.raFromUser(authVM.user);
    final handler = userVM.findByRa(currentRa);
    final handlerName = userVM.displayNameFor(
      ra: currentRa,
      firebaseUser: authVM.user,
      fallback: 'Condutor',
    );

    return StreamBuilder<Dog?>(
      stream: _dogStream,
      builder: (context, dogSnapshot) {
        final dog = dogSnapshot.data ?? _localDogFallback(dogVM, dogId);
        if (dog == null) {
          return const _TrainingMissingDog();
        }

        return StreamBuilder<List<TrainingSpecialtyModel>>(
          stream: _specialtiesStream,
          builder: (context, specialtiesSnapshot) {
            final specialties =
                specialtiesSnapshot.data ?? const <TrainingSpecialtyModel>[];

            return StreamBuilder<List<TrainingHubSession>>(
              stream: _sessionsStream,
              builder: (context, sessionsSnapshot) {
                final sessions =
                    sessionsSnapshot.data ?? const <TrainingHubSession>[];
                final data = _trainingService.buildHubData(
                  specialties: specialties,
                  sessions: sessions,
                );

                return Scaffold(
                  backgroundColor: _trainingBackground,
                  body: AnnotatedRegion<SystemUiOverlayStyle>(
                    value: SystemUiOverlayStyle.light.copyWith(
                      statusBarColor: Colors.transparent,
                      systemNavigationBarColor: const Color(0xFF07141B),
                      systemNavigationBarIconBrightness: Brightness.light,
                    ),
                    child: _TrainingHubBody(
                      dog: dog,
                      handlerName: handlerName,
                      handlerPhotoUrl: handler?.photoUrl,
                      shiftStartTime: shiftVM.shiftStartTime,
                      data: data,
                      loading:
                          specialtiesSnapshot.connectionState ==
                              ConnectionState.waiting ||
                          sessionsSnapshot.connectionState ==
                              ConnectionState.waiting,
                      onOpenLog: () => _openTrainingLog(context, dog),
                      onNewSession: () => _openTrainingSheet(
                        context,
                        category: 'Treino',
                        dog: dog,
                      ),
                      onTrainingTap: (category) => _openTrainingSheet(
                        context,
                        category: category,
                        dog: dog,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _openTrainingLog(BuildContext context, Dog dog) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrainingLogScreen(dogId: dog.id, dogName: dog.name),
      ),
    );
  }

  void _openTrainingSheet(
    BuildContext context, {
    required String category,
    required Dog dog,
  }) {
    HapticFeedback.mediumImpact();
    final lowerCat = normalizeTrainingKey(category);

    if (lowerCat.contains('detec') || lowerCat.contains('faro')) {
      _navigateToDetectionFlow(context, dog);
      return;
    }


    if (lowerCat.contains('obediencia')) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ObedienceTrainingScreen(dog: dog)),
      );
      return;
    }

    if (lowerCat.contains('condicionamento')) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ConditioningScreen(dog: dog)));
      return;
    }

    if (lowerCat.contains('guarda') || lowerCat.contains('protec')) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GuardProtectionScreen(dog: dog)),
      );
      return;
    }

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

  void _navigateToDetectionFlow(BuildContext context, Dog dog) async {
    final specialtyService = DogSpecialtyService();
    final specialty = await specialtyService.getByType(dog.id, 'deteccao');

    if (!context.mounted) return;

    if (specialty == null || specialty.status == 'not_started') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DetectionTriagemScreen(dog: dog),
          settings: const RouteSettings(name: '/treino/deteccao/triagem'),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DetectionMaintenanceScreen(dog: dog),
        ),
      );
    }
  }
}


class _TrainingHubBody extends StatelessWidget {
  final Dog dog;
  final String handlerName;
  final String? handlerPhotoUrl;
  final DateTime? shiftStartTime;
  final TrainingHubData data;
  final bool loading;
  final VoidCallback onOpenLog;
  final VoidCallback onNewSession;
  final ValueChanged<String> onTrainingTap;

  const _TrainingHubBody({
    required this.dog,
    required this.handlerName,
    required this.handlerPhotoUrl,
    required this.shiftStartTime,
    required this.data,
    required this.loading,
    required this.onOpenLog,
    required this.onNewSession,
    required this.onTrainingTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF061017), Color(0xFF050D10), Color(0xFF050D10)],
        ),
      ),
      child: SafeArea(
        top: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TrainingHeader(
                dog: dog,
                handlerName: handlerName,
                handlerPhotoUrl: handlerPhotoUrl,
                shiftStartTime: shiftStartTime,
              ),
              const SizedBox(height: 14),
              _TrainingWeekSummary(data: data),
              const SizedBox(height: 14),
              _TrainingSpecialtiesSection(
                specialties: data.specialties,
                loading: loading,
                onTap: onTrainingTap,
              ),
              const SizedBox(height: 14),
              _TrainingGeneralSection(
                trainings: data.generalTrainings,
                onTap: onTrainingTap,
              ),
              const SizedBox(height: 14),
              _TrainingRecentSessionsSection(
                sessions: data.recentSessions,
                onOpenLog: onOpenLog,
              ),
              const SizedBox(height: 16),
              _NewTrainingSessionButton(onTap: onNewSession),
            ],
          ),
        ),
      ),
    );
  }
}

Dog? _localDogFallback(DogViewModel dogVM, String dogId) {
  try {
    return dogVM.dogs.firstWhere((dog) => dog.id == dogId);
  } catch (_) {
    return null;
  }
}

class _TrainingNoShift extends StatelessWidget {
  const _TrainingNoShift();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _trainingBackground,
      body: Center(
        child: Text(
          'Nenhum turno ativo.\nInicie um turno para acessar o hub de treinos.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _trainingTextSecondary),
        ),
      ),
    );
  }
}

class _TrainingMissingDog extends StatelessWidget {
  const _TrainingMissingDog();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _trainingBackground,
      body: Center(
        child: Text(
          'K9 do turno não encontrado.',
          style: TextStyle(color: _trainingTextSecondary),
        ),
      ),
    );
  }
}
