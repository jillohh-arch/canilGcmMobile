import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/services/dog_fitness_service.dart';
import 'package:canil_gcm/core/widgets/app_feedback.dart';
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
  final DogFitnessService _fitnessService = const DogFitnessService();

  @override
  void initState() {
    super.initState();
    PermissionService.requestInitialPermissions();
  }

  Future<void> _startShift(Dog dog) async {
    if (_startingDogId != null) return;

    // Capturar antes do await para evitar uso de BuildContext pós-assíncrono
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    final fbUser = Provider.of<AuthViewModel>(context, listen: false).user;
    final currentRa = HandlerIdentityService.raFromUser(fbUser);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final displayName = userVM.displayNameFor(
      ra: currentRa,
      firebaseUser: fbUser,
    );
    final fitness = _fitnessService.evaluate(dog);

    // Se não apto, pedir confirmação
    if (fitness.status == DogFitnessStatus.unfit) {
      final confirmed = await _showUnfitConfirmation(dog);
      if (confirmed != true) return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _startingDogId = dog.id);

    await shiftVM.startShift(
      dog.id,
      handlerName: displayName,
    );

    if (!mounted) return;
    setState(() => _startingDogId = null);

    if (shiftVM.error != null) {
      AppFeedback.error(
        context,
        shiftVM.error!,
        fallback:
            'Nao foi possivel iniciar o turno. Confira sua conexao e tente novamente.',
      );
    }
  }

  Future<bool?> _showUnfitConfirmation(Dog dog) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfacePanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Assumir ${dog.name} com pendências?',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: Text(
          'Este cão possui pendências críticas. O plantão será registrado com aviso.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(color: AppTheme.textTertiary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Assumir mesmo assim',
              style: GoogleFonts.inter(
                color: AppTheme.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
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

        final selectedFitness = selectedDog != null
            ? _fitnessService.evaluate(selectedDog)
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
                  dogCount: dogVM.dogs.length,
                ),
                const SizedBox(height: 16),

                // ── Lista de cães ──────────────────────────────────
                Expanded(child: _buildBody(dogVM, userVM, currentRa)),

                // ── CTA sticky ─────────────────────────────────────
                if (selectedDog != null && selectedFitness != null)
                  _AssumptionCta(
                    dog: selectedDog,
                    fitness: selectedFitness,
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

  Widget _buildBody(
    DogViewModel dogVM,
    UserViewModel userVM,
    String? currentRa,
  ) {
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
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final dog = dogVM.dogs[index];
        final isSelected = _selectedDogId == dog.id;
        final isTitular = dog.conductorRa == currentRa;
        final fitness = _fitnessService.evaluate(dog);

        // Nome do titular (se não é o condutor logado)
        String? titularName;
        if (!isTitular && dog.conductorRa != null) {
          titularName = userVM.displayNameFor(ra: dog.conductorRa);
        }

        return _DogSelectionCard(
          dog: dog,
          isSelected: isSelected,
          isTitular: isTitular,
          titularName: titularName,
          fitness: fitness,
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _selectedDogId = dog.id;
            });
          },
        );
      },
    );
  }
}
