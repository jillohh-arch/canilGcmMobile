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
import 'package:canil_gcm/features/shifts/domain/shift_authorization.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/widgets/shift_authorization_prompts.dart';
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
  bool _noK9Selected = false;
  bool _startingWithoutK9 = false;
  final DogFitnessService _fitnessService = const DogFitnessService();

  @override
  void initState() {
    super.initState();
    PermissionService.requestInitialPermissions();
  }

  Future<void> _startShift(Dog dog) async {
    if (_startingDogId != null || _startingWithoutK9) return;

    // Capturar antes do await para evitar uso de BuildContext pós-assíncrono
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    final fbUser = Provider.of<AuthViewModel>(context, listen: false).user;
    final currentRa = HandlerIdentityService.raFromUser(fbUser);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final displayName = userVM.displayNameFor(
      ra: currentRa,
      firebaseUser: fbUser,
    );
    // HEALTH-V1-OP-AUTH: a aptidão clínica NÃO é decidida aqui. O antigo
    // diálogo "Assumir mesmo assim" foi removido — ele permitia contornar uma
    // avaliação de inaptidão. A autoridade é o backend, sobre
    // `operational_restrictions`. O fitness legado segue apenas como exibição
    // de pendências nos cards (vacina/antipulgas), sem poder de liberação.
    HapticFeedback.mediumImpact();
    setState(() => _startingDogId = dog.id);

    await shiftVM.startShift(
      dog.id,
      handlerName: displayName,
    );

    if (!mounted) return;
    setState(() => _startingDogId = null);

    await _handleAuthorizationOutcome(shiftVM, dog);
  }

  /// Turno SEM K9: não introduz associação operacional de cão, portanto não há
  /// restrição clínica a validar. Preservado como estava (classificação D).
  Future<void> _startShiftWithoutK9() async {
    if (_startingDogId != null || _startingWithoutK9) return;

    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    final fbUser = Provider.of<AuthViewModel>(context, listen: false).user;
    final currentRa = HandlerIdentityService.raFromUser(fbUser);
    final userVM = Provider.of<UserViewModel>(context, listen: false);
    final displayName = userVM.displayNameFor(
      ra: currentRa,
      firebaseUser: fbUser,
    );

    HapticFeedback.mediumImpact();
    setState(() => _startingWithoutK9 = true);

    await shiftVM.startShift(
      '',
      handlerName: displayName,
    );

    if (!mounted) return;
    setState(() => _startingWithoutK9 = false);

    if (shiftVM.error != null) {
      AppFeedback.error(
        context,
        shiftVM.error!,
        fallback:
            'Nao foi possivel iniciar o turno. Confira sua conexao e tente novamente.',
      );
    }
  }

  /// Apresenta a decisão do backend conforme a natureza real do resultado.
  Future<void> _handleAuthorizationOutcome(
    ShiftViewModel shiftVM,
    Dog dog,
  ) async {
    final failure = shiftVM.authorizationFailure;

    if (failure == null) {
      // Autorizado. Restrição informativa (attention) vira aviso não bloqueante.
      final notices = shiftVM.activeNoticeRestrictions;
      if (notices.isNotEmpty && mounted) {
        AppFeedback.info(
          context,
          'Turno iniciado. ${dog.name} possui '
          '${notices.length == 1 ? 'uma observação' : 'observações'} '
          'de saúde registrada${notices.length == 1 ? '' : 's'}.',
        );
      }
      if (shiftVM.error != null && mounted) {
        AppFeedback.error(
          context,
          shiftVM.error!,
          fallback:
              'Nao foi possivel iniciar o turno. Confira sua conexao e tente novamente.',
        );
      }
      return;
    }

    switch (failure.kind) {
      case ShiftAuthorizationFailureKind.absoluteRestriction:
      case ShiftAuthorizationFailureKind.activityRestricted:
        // Bloqueio clínico definitivo: sem opção de prosseguir.
        await _showRestrictionBlockedDialog(dog, failure);
      case ShiftAuthorizationFailureKind.acknowledgementRequired:
        await _showPartialAcknowledgementDialog(shiftVM, dog, failure);
      case ShiftAuthorizationFailureKind.restrictionsUnavailable:
        // Falha técnica de verificação. NÃO é "sem restrição", e não é queda de
        // conexão — o servidor respondeu dizendo que não pôde verificar.
        if (mounted) {
          AppFeedback.error(
            context,
            'Não foi possível verificar as restrições operacionais de '
            '${dog.name}. Por segurança, o turno não foi iniciado. '
            'Tente novamente.',
          );
        }
      case ShiftAuthorizationFailureKind.network:
        if (mounted) {
          AppFeedback.error(
            context,
            'Sem comunicação com o servidor. Confira sua conexão e '
            'tente novamente.',
          );
        }
      default:
        if (mounted) {
          AppFeedback.error(context, failure.message);
        }
    }

    shiftVM.clearAuthorizationFeedback();
  }


  /// Bloqueio por restrição operacional. Delegado ao prompt compartilhado para
  /// que iniciar turno e trocar K9 apresentem a MESMA decisão igualmente.
  Future<void> _showRestrictionBlockedDialog(
    Dog dog,
    ShiftAuthorizationFailure failure,
  ) async {
    if (!mounted) return;
    await ShiftAuthorizationPrompts.showBlocked(
      context,
      dogName: dog.name,
      failure: failure,
    );
  }

  /// Restrição parcial: coleta ciência e reenvia a MESMA operação ao backend.
  Future<void> _showPartialAcknowledgementDialog(
    ShiftViewModel shiftVM,
    Dog dog,
    ShiftAuthorizationFailure failure,
  ) async {
    if (!mounted) return;
    final acknowledged = await ShiftAuthorizationPrompts.confirmPartial(
      context,
      dogName: dog.name,
      failure: failure,
    );
    if (!acknowledged) {
      shiftVM.clearAuthorizationFeedback();
      return;
    }

    // A ciência é registrada pelo BACKEND ao reexecutar a operação. O aceite
    // não altera a restrição nem o summary — apenas documenta a ciência.
    setState(() => _startingDogId = dog.id);
    final authorized = await shiftVM.acknowledgePartialRestrictions();
    if (!mounted) return;
    setState(() => _startingDogId = null);

    if (!authorized && shiftVM.error != null) {
      AppFeedback.error(context, shiftVM.error!);
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
                if (_noK9Selected)
                  _NoK9Cta(
                    isLoading: _startingWithoutK9,
                    onPressed: _startShiftWithoutK9,
                  )
                else if (selectedDog != null && selectedFitness != null)
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
      itemCount: dogVM.dogs.length + 1, // +1 for "sem K9" option
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        // Última posição: opção "Iniciar sem K9"
        if (index == dogVM.dogs.length) {
          return _NoK9SelectionCard(
            isSelected: _noK9Selected,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _noK9Selected = true;
                _selectedDogId = null;
              });
            },
          );
        }

        final dog = dogVM.dogs[index];
        final isSelected = _selectedDogId == dog.id && !_noK9Selected;
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
              _noK9Selected = false;
            });
          },
        );
      },
    );
  }
}
