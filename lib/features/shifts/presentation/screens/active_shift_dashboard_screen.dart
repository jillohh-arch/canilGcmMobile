import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/weather_service.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/data/dog_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

part 'active_shift_dashboard_widgets.dart';
part 'active_shift_metrics_widgets.dart';
part 'active_shift_activity_widgets.dart';
part 'active_shift_readiness.dart';
part 'active_shift_cockpit.dart';
part 'active_shift_dog_switcher.dart';

const _hudBackground = Color(0xFF070B14);
const _hudPanel = Color(0xFF0B1220);
const _hudPanelAlt = Color(0xFF111827);
const _hudCyan = Color(0xFF00E5FF);
const _hudGreen = Color(0xFF00E58A);
const _hudAmber = Color(0xFFFBBF24);
const _hudDanger = Color(0xFFFF3B6B);

class ActiveShiftDashboardScreen extends StatefulWidget {
  const ActiveShiftDashboardScreen({super.key});

  @override
  State<ActiveShiftDashboardScreen> createState() =>
      _ActiveShiftDashboardScreenState();
}

class _ActiveShiftDashboardScreenState
    extends State<ActiveShiftDashboardScreen> {
  final DogService _dogService = DogService();
  String? _lastFetchedDogId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final dogId = shiftVM.activeDogId;

    if (dogId != null && dogId != _lastFetchedDogId) {
      _lastFetchedDogId = dogId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Provider.of<TrainingViewModel>(
          context,
          listen: false,
        ).fetchTrainingsForDog(dogId);
        Provider.of<HealthViewModel>(
          context,
          listen: false,
        ).fetchHealthLogsForDog(dogId);
        Provider.of<IncidentViewModel>(
          context,
          listen: false,
        ).fetchIncidentsForDog(dogId);

        final dogVM = Provider.of<DogViewModel>(context, listen: false);
        final userVM = Provider.of<UserViewModel>(context, listen: false);
        final authVM = Provider.of<AuthViewModel>(context, listen: false);
        final currentRa = HandlerIdentityService.raFromUser(authVM.user) ?? '';

        try {
          final dog = dogVM.dogs.firstWhere((d) => d.id == dogId);
          _checkReadinessStreakTracker(dog, currentRa, userVM, dogVM);
        } catch (_) {}
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer4<
      ShiftViewModel,
      DogViewModel,
      AuthViewModel,
      UserViewModel
    >(
      builder: (context, shiftVM, dogVM, authVM, userVM, _) {
        if (!shiftVM.hasActiveShift) {
          return const Scaffold(
            backgroundColor: _hudBackground,
            body: Center(
              child: Text(
                'Nenhum turno ativo.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
        }

        final fbUser = authVM.user;
        final currentRa = HandlerIdentityService.raFromUser(fbUser);
        final callsign = userVM.displayNameFor(
          ra: currentRa,
          firebaseUser: fbUser,
        );
        final dogId = shiftVM.activeDogId!;

        return StreamBuilder<Dog?>(
          stream: _dogService.watchDog(dogId),
          builder: (context, snapshot) {
            final dog = snapshot.data ?? _localDogFallback(dogVM, dogId);
            if (dog == null) {
              return const Scaffold(
                backgroundColor: _hudBackground,
                body: Center(
                  child: Text(
                    'K9 do turno não encontrado.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              );
            }

            return Scaffold(
              backgroundColor: _hudBackground,
              body: _buildCockpit(context, dog, callsign),
            );
          },
        );
      },
    );
  }
}
