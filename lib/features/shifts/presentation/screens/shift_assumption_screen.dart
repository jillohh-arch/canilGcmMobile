import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/permission_service.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

part 'shift_assumption_header.dart';
part 'shift_assumption_dog_card_widgets.dart';
part 'shift_assumption_empty_state.dart';

class ShiftAssumptionScreen extends StatefulWidget {
  const ShiftAssumptionScreen({super.key});

  @override
  State<ShiftAssumptionScreen> createState() => _ShiftAssumptionScreenState();
}

class _ShiftAssumptionScreenState extends State<ShiftAssumptionScreen> {
  String? _selectedDogId;
  String? _startingDogId;

  @override
  void initState() {
    super.initState();
    PermissionService.requestInitialPermissions();
  }

  Future<void> _startShift(Dog dog) async {
    if (_startingDogId != null) return;
    HapticFeedback.mediumImpact();
    setState(() => _startingDogId = dog.id);

    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    await shiftVM.startShift(dog.id);

    if (!mounted) return;
    setState(() => _startingDogId = null);

    if (shiftVM.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(shiftVM.error!),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<AuthViewModel, UserViewModel, DogViewModel>(
      builder: (context, authVM, userVM, dogVM, _) {
        final fbUser = authVM.user;
        final currentRa = HandlerIdentityService.raFromUser(fbUser);
        final displayName = userVM.displayNameFor(
          ra: currentRa,
          firebaseUser: fbUser,
        );

        final selectedDog = _selectedDogId != null
            ? dogVM.dogs.cast<Dog?>().firstWhere(
                (d) => d?.id == _selectedDogId,
                orElse: () => null,
              )
            : null;

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ─────────────────────────────────────────
                _AssumptionHeader(
                  displayName: displayName,
                  ra: currentRa ?? '',
                ),
                const SizedBox(height: 16),

                // ── Lista de cães ──────────────────────────────────
                Expanded(child: _buildBody(dogVM, currentRa)),

                // ── CTA sticky ─────────────────────────────────────
                if (selectedDog != null)
                  _AssumptionCta(
                    dog: selectedDog,
                    isLoading: _startingDogId == selectedDog.id,
                    onPressed: () => _startShift(selectedDog),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(DogViewModel dogVM, String? currentRa) {
    if (dogVM.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (dogVM.dogs.isEmpty) {
      return const _EmptyDogState();
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: dogVM.dogs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final dog = dogVM.dogs[index];
        final isSelected = _selectedDogId == dog.id;
        final isTitular = dog.conductorRa == currentRa;

        return _DogSelectionCard(
          dog: dog,
          isSelected: isSelected,
          isTitular: isTitular,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _selectedDogId = dog.id);
          },
        );
      },
    );
  }
}