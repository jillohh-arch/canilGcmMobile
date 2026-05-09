import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/users/domain/user.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/permission_service.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/core/widgets/hud_panel.dart';

part 'shift_assumption_widgets.dart';
part 'shift_assumption_dog_card_widgets.dart';
part 'shift_assumption_dog_visuals.dart';
part 'shift_assumption_dog_metrics.dart';

const _hudBackground = Color(0xFF070B14);
const _hudPanel = Color(0xFF0B1220);
const _hudPanelDeep = Color(0xFF08111D);
const _hudCyan = Color(0xFF00E5FF);
const _hudAmber = Color(0xFFFFB84D);
const _hudGreen = Color(0xFF00F5A0);
const _hudRed = Color(0xFFFF3B5C);

class ShiftAssumptionScreen extends StatefulWidget {
  const ShiftAssumptionScreen({super.key});

  @override
  State<ShiftAssumptionScreen> createState() => _ShiftAssumptionScreenState();
}

class _ShiftAssumptionScreenState extends State<ShiftAssumptionScreen> {
  late final PageController _pageController;
  int _currentPage = 0;
  String? _startingDogId;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.88);
    PermissionService.requestInitialPermissions();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _startShift({
    required Dog dog,
    required UserModel? userModel,
  }) async {
    if (_startingDogId != null) return;
    HapticFeedback.mediumImpact();
    setState(() => _startingDogId = dog.id);

    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    await shiftVM.startShift(dog.id);

    if (!mounted) return;
    setState(() => _startingDogId = null);

    if (shiftVM.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(shiftVM.error!), backgroundColor: _hudRed),
      );
      return;
    }

    if (userModel != null) {
      await Provider.of<UserViewModel>(
        context,
        listen: false,
      ).grantBadge(userModel.ra, 'pe_na_estrada');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<AuthViewModel, UserViewModel, DogViewModel>(
      builder: (context, authVM, userVM, dogVM, _) {
        final fbUser = authVM.user;
        final currentRa = HandlerIdentityService.raFromUser(fbUser);
        final userModel = userVM.users.cast<UserModel?>().firstWhere(
          (u) => u?.ra == currentRa,
          orElse: () => null,
        );
        final displayName = userVM.displayNameFor(
          ra: currentRa,
          firebaseUser: fbUser,
        );

        return Scaffold(
          backgroundColor: _hudBackground,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 88,
                  left: -130,
                  child: _HudGlow(color: _hudCyan.withAlpha(30), size: 260),
                ),
                Positioned(
                  right: -150,
                  bottom: 80,
                  child: _HudGlow(color: _hudAmber.withAlpha(22), size: 300),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AssumptionHeader(
                      displayName: displayName,
                      dogCount: dogVM.dogs.length,
                    ),
                    const SizedBox(height: 12),
                    Expanded(child: _buildBody(dogVM, userModel)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(DogViewModel dogVM, UserModel? userModel) {
    if (dogVM.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _hudCyan, strokeWidth: 2),
      );
    }

    if (dogVM.dogs.isEmpty) {
      return const _EmptyDogState();
    }

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: dogVM.dogs.length,
            onPageChanged: (index) {
              HapticFeedback.selectionClick();
              setState(() => _currentPage = index);
            },
            itemBuilder: (context, index) {
              final dog = dogVM.dogs[index];
              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  var distance = (_currentPage - index).toDouble();
                  if (_pageController.position.haveDimensions) {
                    final page =
                        _pageController.page ?? _currentPage.toDouble();
                    distance = page - index.toDouble();
                  }
                  final scale = (1 - (distance.abs() * 0.08))
                      .clamp(0.92, 1.0)
                      .toDouble();
                  final opacity = (1 - (distance.abs() * 0.28))
                      .clamp(0.62, 1.0)
                      .toDouble();
                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(scale: scale, child: child),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                  child: _HudDogSelectionCard(
                    dog: dog,
                    isStarting: _startingDogId == dog.id,
                    onSelect: () => _startShift(dog: dog, userModel: userModel),
                  ),
                ),
              );
            },
          ),
        ),
        _PageIndicator(count: dogVM.dogs.length, current: _currentPage),
        const SizedBox(height: 18),
      ],
    );
  }
}
