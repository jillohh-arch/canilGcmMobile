import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/profiles/presentation/screens/k9_profile_page.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';

class DogProntuarioTabScreen extends StatelessWidget {
  const DogProntuarioTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context);
    final dog = _activeDog(shiftVM.activeDogId, dogVM.dogs);

    if (!shiftVM.hasActiveShift || dog == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Text(
            'Nenhum cão ativo.\nInicie um turno para ver o prontuário.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textPrimary.withAlpha(138),
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return K9ProfilePage(dog: dog);
  }

  Dog? _activeDog(String? dogId, List<Dog> dogs) {
    if (dogId == null) return null;
    for (final dog in dogs) {
      if (dog.id == dogId) return dog;
    }
    return dogs.isNotEmpty ? dogs.first : null;
  }
}
