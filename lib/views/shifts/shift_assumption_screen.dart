import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/dog.dart';
import '../../models/user.dart';
import '../../services/handler_identity_service.dart';
import '../../services/permission_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/dog_viewmodel.dart';
import '../../viewmodels/shift_viewmodel.dart';
import '../../viewmodels/user_viewmodel.dart';
import '../../widgets/hud_panel.dart';

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

class _AssumptionHeader extends StatelessWidget {
  final String displayName;
  final int dogCount;

  const _AssumptionHeader({required this.displayName, required this.dogCount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'K9 DUTY SELECTION',
            style: GoogleFonts.robotoMono(
              color: _hudCyan,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              color: _hudPanel.withAlpha(232),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hudCyan.withAlpha(110)),
              boxShadow: [
                BoxShadow(color: _hudCyan.withAlpha(22), blurRadius: 18),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _hudCyan.withAlpha(18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _hudCyan.withAlpha(130)),
                  ),
                  child: const Icon(
                    Icons.pets_rounded,
                    color: _hudCyan,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SELECIONE SEU CÃO',
                        style: GoogleFonts.oxanium(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Bem-vindo, ${displayName.toUpperCase()}. Escolha o K9 que vai assumir o plantão.',
                        style: GoogleFonts.inter(
                          color: Colors.white60,
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _DogCountBadge(count: dogCount),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DogCountBadge extends StatelessWidget {
  final int count;

  const _DogCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _hudCyan.withAlpha(14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(120)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: GoogleFonts.oxanium(
              color: _hudCyan,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'K9',
            style: GoogleFonts.robotoMono(
              color: Colors.white54,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _HudDogSelectionCard extends StatelessWidget {
  final Dog dog;
  final bool isStarting;
  final VoidCallback onSelect;

  const _HudDogSelectionCard({
    required this.dog,
    required this.isStarting,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final readiness = dog.calculateReadiness();
    final statusColor = _statusColor(dog.operationalStatus);
    final lastTraining = _formatLastTraining(dog.lastTrainingDate);

    return GestureDetector(
      onTap: isStarting ? null : onSelect,
      child: Container(
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(236),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _hudCyan.withAlpha(125), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: _hudCyan.withAlpha(28),
              blurRadius: 24,
              spreadRadius: 1,
            ),
            const BoxShadow(
              color: Colors.black54,
              blurRadius: 18,
              offset: Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(child: _DogBackdrop(dog: dog)),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _hudBackground.withAlpha(20),
                      _hudBackground.withAlpha(90),
                      _hudBackground.withAlpha(245),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(top: 12, left: 12, child: HudCorner(_hudCyan, size: 22)),
            Positioned(
              top: 12,
              right: 12,
              child: HudCorner(_hudCyan, flip: true, size: 22),
            ),
            Positioned(
              top: 18,
              right: 18,
              child: _StatusBadge(
                label: dog.operationalStatus,
                color: statusColor,
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 26, 18, 18),
                child: Column(
                  children: [
                    const Spacer(),
                    _ReadinessBar(value: readiness),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _DogMetric(
                            icon: Icons.monitor_weight_outlined,
                            label: 'PESO',
                            value: dog.weight != null
                                ? '${dog.weight!.toStringAsFixed(1)} KG'
                                : '-- KG',
                            color: _hudCyan,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DogMetric(
                            icon: Icons.schedule_rounded,
                            label: 'IDADE',
                            value: '${dog.age} ANOS',
                            color: _hudAmber,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _WideMetric(
                      icon: Icons.track_changes_rounded,
                      label: 'ÚLTIMO TREINO',
                      value: lastTraining,
                    ),
                    const SizedBox(height: 12),
                    _DogIdentity(dog: dog),
                    const SizedBox(height: 16),
                    _StartShiftButton(isStarting: isStarting),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _statusColor(String status) {
    final normalized = status.toLowerCase();
    if (normalized.contains('ativo') || normalized.contains('treino')) {
      return _hudGreen;
    }
    if (normalized.contains('licen')) {
      return _hudAmber;
    }
    return _hudRed;
  }

  static String _formatLastTraining(DateTime? date) {
    if (date == null) return 'Sem registro';
    final days = DateTime.now().difference(date).inDays;
    if (days <= 0) return 'Hoje';
    if (days == 1) return 'Ontem';
    return 'Há $days dias';
  }
}

class _DogBackdrop extends StatelessWidget {
  final Dog dog;

  const _DogBackdrop({required this.dog});

  @override
  Widget build(BuildContext context) {
    if (dog.profileImageUrl == null || dog.profileImageUrl!.isEmpty) {
      return Container(
        color: _hudPanelDeep,
        child: Center(
          child: FaIcon(
            FontAwesomeIcons.dog,
            size: 86,
            color: _hudCyan.withAlpha(80),
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: dog.profileImageUrl!,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      placeholder: (context, url) => const Center(
        child: CircularProgressIndicator(color: _hudCyan, strokeWidth: 2),
      ),
      errorWidget: (context, url, error) => Container(
        color: _hudPanelDeep,
        child: Center(
          child: FaIcon(
            FontAwesomeIcons.dog,
            size: 72,
            color: _hudCyan.withAlpha(80),
          ),
        ),
      ),
    );
  }
}

class _DogIdentity extends StatelessWidget {
  final Dog dog;

  const _DogIdentity({required this.dog});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hudBackground.withAlpha(185),
            border: Border.all(color: _hudCyan.withAlpha(80)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dog.name.toUpperCase(),
                softWrap: true,
                style: GoogleFonts.oxanium(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                dog.breed.toUpperCase(),
                softWrap: true,
                style: GoogleFonts.robotoMono(
                  color: _hudCyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadinessBar extends StatelessWidget {
  final int value;

  const _ReadinessBar({required this.value});

  @override
  Widget build(BuildContext context) {
    final color = value >= 75
        ? _hudGreen
        : value >= 45
        ? _hudAmber
        : _hudRed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'PRONTIDÃO OPERACIONAL',
              style: GoogleFonts.robotoMono(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
            const Spacer(),
            Text(
              '$value%',
              style: GoogleFonts.oxanium(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: _hudBackground,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white12),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0, 100) / 100,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(color: color.withAlpha(120), blurRadius: 8),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DogMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DogMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(226),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(110)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            softWrap: true,
            style: GoogleFonts.oxanium(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.robotoMono(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _WideMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _WideMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _hudBackground.withAlpha(205),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(70)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _hudCyan, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.robotoMono(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.oxanium(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StartShiftButton extends StatelessWidget {
  final bool isStarting;

  const _StartShiftButton({required this.isStarting});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        color: _hudCyan,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [BoxShadow(color: _hudCyan.withAlpha(70), blurRadius: 16)],
      ),
      child: Center(
        child: isStarting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _hudBackground,
                ),
              )
            : Text(
                'ASSUMIR TURNO',
                style: GoogleFonts.robotoMono(
                  color: _hudBackground,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.6,
                ),
              ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _hudBackground.withAlpha(180),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withAlpha(150)),
          ),
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.robotoMono(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  final int count;
  final int current;

  const _PageIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: List.generate(count, (index) {
        final selected = index == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: selected ? 26 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: selected ? _hudCyan : Colors.white24,
            borderRadius: BorderRadius.circular(4),
            boxShadow: selected
                ? [BoxShadow(color: _hudCyan.withAlpha(80), blurRadius: 10)]
                : null,
          ),
        );
      }),
    );
  }
}

class _EmptyDogState extends StatelessWidget {
  const _EmptyDogState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _hudPanel.withAlpha(230),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _hudCyan.withAlpha(80)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(
                FontAwesomeIcons.dog,
                size: 44,
                color: _hudCyan.withAlpha(160),
              ),
              const SizedBox(height: 16),
              Text(
                'NENHUM CÃO DISPONÍVEL',
                textAlign: TextAlign.center,
                style: GoogleFonts.oxanium(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Cadastre ou libere um K9 para iniciar o plantão.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HudGlow extends StatelessWidget {
  final Color color;
  final double size;

  const _HudGlow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color, blurRadius: size / 2, spreadRadius: 18),
          ],
        ),
      ),
    );
  }
}
