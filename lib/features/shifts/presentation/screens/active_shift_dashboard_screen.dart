import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:canil_gcm/services/weather_service.dart';

import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/viewmodels/user_viewmodel.dart';
import 'package:canil_gcm/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/services/handler_identity_service.dart';
import 'dart:ui';

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

  void _checkReadinessStreakTracker(
    Dog dog,
    String currentRa,
    UserViewModel userVM,
    DogViewModel dogVM,
  ) async {
    final score = _calculateOperationalReadiness(dog);
    final today = DateTime.now().toIso8601String().substring(0, 10);

    Map<String, dynamic> streak = dog.readinessStreak != null
        ? Map.from(dog.readinessStreak!)
        : {'lastCheck': '', 'days90': 0, 'days95': 0};
    if (streak['lastCheck'] == today) return; // Snapshot já contabilizado hoje

    final currentDays90 =
        (streak['days90'] as int?) ?? (streak['days'] as int? ?? 0);
    final currentDays95 = (streak['days95'] as int?) ?? 0;

    if (score >= 90) {
      if (streak['lastCheck'] != '') {
        final last = DateTime.parse(streak['lastCheck'] as String);
        final diff = DateTime.now().difference(last).inDays;
        if (diff == 1) {
          streak['days90'] = currentDays90 + 1;
          streak['days95'] = score >= 95 ? currentDays95 + 1 : 0;
        } else if (diff > 1) {
          streak['days90'] = 1;
          streak['days95'] = score >= 95 ? 1 : 0;
        }
      } else {
        streak['days90'] = 1;
        streak['days95'] = score >= 95 ? 1 : 0;
      }
    } else {
      streak['days90'] = 0;
      streak['days95'] = 0;
    }

    streak['days'] = streak['days90'];
    streak['lastCheck'] = today;

    final updatedDog = Dog(
      id: dog.id,
      name: dog.name,
      breed: dog.breed,
      sex: dog.sex,
      dateOfBirth: dog.dateOfBirth,
      status: dog.status,
      profileImageUrl: dog.profileImageUrl,
      conductorRa: dog.conductorRa,
      lastTrainingDate: dog.lastTrainingDate,
      lastVaccineDate: dog.lastVaccineDate,
      weight: dog.weight,
      registrationNumber: dog.registrationNumber,
      idealWeightMin: dog.idealWeightMin,
      idealWeightMax: dog.idealWeightMax,
      lastBathDate: dog.lastBathDate,
      readinessStreak: streak,
    );
    await dogVM.saveDog(updatedDog);

    if (((streak['days90'] as int?) ?? 0) >= 30 &&
        dog.conductorRa == currentRa) {
      await userVM.grantBadge(currentRa, 'guardiao');
    }
    if (((streak['days95'] as int?) ?? 0) >= 90 &&
        dog.conductorRa == currentRa) {
      await userVM.grantBadge(currentRa, 'sentinela_da_saude');
    }
  }

  int _calculateOperationalReadiness(Dog dog) {
    final healthVM = Provider.of<HealthViewModel>(context, listen: false);
    final dogLogs =
        healthVM.healthLogs.where((log) => log.dogId == dog.id).toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    DateTime? lastBathOverride;
    double? weightOverride;

    for (final log in dogLogs) {
      if (lastBathOverride == null && log.logType == 'Banho') {
        lastBathOverride = log.date;
      }
      if (weightOverride == null && log.weight != null) {
        weightOverride = log.weight;
      }
      if (lastBathOverride != null && weightOverride != null) {
        break;
      }
    }

    return dog.calculateReadiness(
      lastBathOverride: lastBathOverride,
      weightOverride: weightOverride,
    );
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

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('dogs')
              .doc(dogId)
              .snapshots(),
          builder: (context, snapshot) {
            Dog dog;
            if (snapshot.hasData && snapshot.data!.exists) {
              try {
                final data = snapshot.data!.data() as Map<String, dynamic>;
                data['id'] = snapshot.data!.id;
                dog = Dog.fromJson(data);
              } catch (e) {
                dog = dogVM.dogs.firstWhere(
                  (d) => d.id == dogId,
                  orElse: () => dogVM.dogs.first,
                );
              }
            } else {
              dog = dogVM.dogs.firstWhere(
                (d) => d.id == dogId,
                orElse: () => dogVM.dogs.first,
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

  Widget _buildCockpit(BuildContext context, Dog dog, String callsign) {
    return CustomScrollView(
      slivers: [
        _buildHeroHeader(context, dog, callsign),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Row(
              children: [
                Text(
                  'PAINEL DE COMANDO',
                  style: GoogleFonts.robotoMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: _hudCyan.withAlpha(220),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(height: 1, color: _hudCyan.withAlpha(70)),
                ),
              ],
            ),
          ),
        ),

        // Health alert banner (only shown when there are upcoming appointments)
        _HealthAlertBanner(dogId: dog.id),

        // New layout: cockpit tático
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                _DogInfoCockpitCard(dog: dog),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _WeatherCockpitCard()),
                    const SizedBox(width: 16),
                    Expanded(child: _ShiftMetricsCockpitCard(dog: dog)),
                  ],
                ),
                const SizedBox(height: 16),
                _TodayActivitiesCard(dogId: dog.id),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroHeader(BuildContext context, Dog dog, String callsign) {
    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      backgroundColor: _hudBackground,
      iconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (dog.profileImageUrl != null)
              Hero(
                tag: 'dog_profile_${dog.id}',
                child: CachedNetworkImage(
                  imageUrl: dog.profileImageUrl!,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              )
            else
              Container(
                color: _hudPanel,
                child: const Center(
                  child: FaIcon(
                    FontAwesomeIcons.dog,
                    size: 64,
                    color: Colors.white24,
                  ),
                ),
              ),

            // Gradient Overlay (Scrim)
            ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black54,
                        Colors.black.withAlpha(50), // Slight tint for glass
                        _hudBackground.withAlpha(170),
                        _hudBackground,
                      ],
                      stops: const [0.0, 0.3, 0.6, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // Crisp K9 CircleAvatar centered over the blurred banner
            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  // Centered crisp photo
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _hudCyan, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: _hudCyan.withAlpha(110),
                          blurRadius: 34,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 48,
                      backgroundColor: _hudPanelAlt,
                      backgroundImage: dog.profileImageUrl != null
                          ? CachedNetworkImageProvider(dog.profileImageUrl!)
                          : null,
                      child: dog.profileImageUrl == null
                          ? const FaIcon(
                              FontAwesomeIcons.dog,
                              size: 36,
                              color: Colors.white54,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Callsign + K9 name (INTERACTIVE)
                  GestureDetector(
                    onTap: () => _showDogSwitcher(context, dog),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$callsign & ${dog.name}'.toUpperCase(),
                          style: GoogleFonts.oxanium(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.6,
                            height: 1.1,
                            shadows: [
                              Shadow(color: Colors.black87, blurRadius: 8),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.swap_horiz_rounded,
                          color: _hudCyan,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Status pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _hudPanel.withAlpha(220),
                      borderRadius: BorderRadius.circular(6),
                      border: const Border(
                        left: BorderSide(color: _hudGreen, width: 3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _hudGreen,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'TURNO ATIVO',
                          style: GoogleFonts.robotoMono(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _hudGreen,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDogSwitcher(BuildContext context, Dog currentDog) {
    HapticFeedback.heavyImpact();
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TROCA RÁPIDA DE K9',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF00E5FF),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: dogVM.dogs.length,
                  itemBuilder: (context, index) {
                    final dog = dogVM.dogs[index];
                    final isSelected = dog.id == currentDog.id;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: isSelected
                            ? const Color(0xFF00E5FF)
                            : Colors.white12,
                        backgroundImage: dog.profileImageUrl != null
                            ? CachedNetworkImageProvider(dog.profileImageUrl!)
                            : null,
                        child: dog.profileImageUrl == null
                            ? Icon(
                                Icons.pets,
                                color: isSelected
                                    ? Colors.black
                                    : Colors.white38,
                              )
                            : null,
                      ),
                      title: Text(
                        dog.name.toUpperCase(),
                        style: GoogleFonts.inter(
                          color: isSelected
                              ? const Color(0xFF00E5FF)
                              : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        dog.breed,
                        style: GoogleFonts.inter(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_circle,
                              color: Color(0xFF00E5FF),
                            )
                          : null,
                      onTap: () async {
                        if (!isSelected) {
                          await shiftVM.switchDog(dog.id);
                        }
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DogInfoCockpitCard extends StatelessWidget {
  final Dog dog;
  const _DogInfoCockpitCard({required this.dog});

  @override
  Widget build(BuildContext context) {
    final String ageStr = '${dog.age} anos';
    final String sexStr = dog.sex == 'M' ? 'Macho' : 'Fêmea';
    final String weightStr = dog.weight != null
        ? '${dog.weight!.toStringAsFixed(1)} kg'
        : '-- kg';
    final raStr = dog.conductorRa != null && dog.conductorRa!.isNotEmpty
        ? dog.conductorRa!
        : 'S/N';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(110), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _hudCyan.withAlpha(28),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.info_outline_rounded, color: _hudCyan, size: 16),
              _PulsingIndicator(),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            dog.name.toUpperCase(),
            style: GoogleFonts.oxanium(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: _hudCyan,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'RA: $raStr',
            style: GoogleFonts.robotoMono(
              fontSize: 14,
              color: Colors.white54,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _buildReadinessBar(
            _calculateOperationalReadiness(dog),
            _calculateReadinessBreakdown(dog),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _CockpitMiniStat(
                  icon: Icons.cake_outlined,
                  label: 'Idade',
                  value: ageStr,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CockpitMiniStat(
                  icon: Icons.pets_outlined,
                  label: 'Sexo',
                  value: sexStr,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CockpitMiniStat(
                  icon: Icons.monitor_weight_outlined,
                  label: 'Peso',
                  value: weightStr,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _calculateOperationalReadiness(Dog dog) {
    return _calculateReadinessBreakdown(dog).total;
  }

  ({int total, int vacinacao, int peso, int higiene, int treino})
  _calculateReadinessBreakdown(Dog dog) {
    return dog.calculateReadinessBreakdown();
  }

  Widget _buildReadinessBar(
    int score,
    ({int total, int vacinacao, int peso, int higiene, int treino}) breakdown,
  ) {
    Color barColor;
    if (score >= 80) {
      barColor = _hudGreen;
    } else if (score >= 50) {
      barColor = _hudAmber;
    } else {
      barColor = _hudDanger;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'PRONTIDÃO OPERACIONAL',
              style: GoogleFonts.robotoMono(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.white60,
                letterSpacing: 1.0,
              ),
            ),
            Text(
              '$score%',
              style: GoogleFonts.oxanium(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: barColor,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: score / 100,
            backgroundColor: Colors.white.withAlpha(18),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Vacinação, peso, higiene e treino recente.',
          style: GoogleFonts.inter(
            fontSize: 10,
            color: Colors.white38,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Vacinação ${breakdown.vacinacao}/30 • Peso ${breakdown.peso}/25 • Higiene ${breakdown.higiene}/15 • Treino ${breakdown.treino}/30',
          style: GoogleFonts.robotoMono(
            fontSize: 10,
            color: Colors.white54,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CockpitMiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _CockpitMiniStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: _hudPanelAlt.withAlpha(210),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(75)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: _hudCyan.withAlpha(190), size: 22),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value.toUpperCase(),
              style: GoogleFonts.oxanium(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.robotoMono(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Colors.white54,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherCockpitCard extends StatefulWidget {
  @override
  State<_WeatherCockpitCard> createState() => _WeatherCockpitCardState();
}

class _WeatherCockpitCardState extends State<_WeatherCockpitCard> {
  String _temp = '--°C';
  String _humidity = 'Umidade --%';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final weatherService = WeatherService();
      final weather = await weatherService.getCurrentWeather(
        position.latitude,
        position.longitude,
      );

      if (weather != null && mounted) {
        setState(() {
          _temp = '${weather['temperature']}°C';
          _humidity = 'Umidade ${weather['humidity']}%';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'CONDIÇÕES / CLIMA',
            style: GoogleFonts.robotoMono(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white60,
              letterSpacing: 0.9,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Icon(Icons.thermostat_rounded, color: _hudAmber, size: 36),
              const SizedBox(width: 8),
              if (_loading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  _temp,
                  style: GoogleFonts.oxanium(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: _hudCyan,
                    letterSpacing: 0.8,
                  ),
                ),
            ],
          ),
          Text(
            _humidity,
            style: GoogleFonts.robotoMono(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftMetricsCockpitCard extends StatefulWidget {
  final Dog dog;
  const _ShiftMetricsCockpitCard({required this.dog});

  @override
  State<_ShiftMetricsCockpitCard> createState() =>
      _ShiftMetricsCockpitCardState();
}

class _ShiftMetricsCockpitCardState extends State<_ShiftMetricsCockpitCard> {
  Timer? _timer;
  String _activeTimeText = '--h --m';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    if (!mounted) return;
    final shiftVM = Provider.of<ShiftViewModel>(context, listen: false);
    final startTime = shiftVM.shiftStartTime;
    if (startTime != null) {
      final diff = DateTime.now().difference(startTime);
      final hours = diff.inHours.toString().padLeft(2, '0');
      final minutes = (diff.inMinutes % 60).toString().padLeft(2, '0');
      final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
      setState(() {
        _activeTimeText = '${hours}h ${minutes}m ${seconds}s';
      });
    } else {
      setState(() {
        _activeTimeText = '--h --m';
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get total registries
    final int hLogs = Provider.of<HealthViewModel>(context).healthLogs.length;
    final int tLogs = Provider.of<TrainingViewModel>(context).trainings.length;
    final int todayLogs = hLogs + tLogs; // Just a mock combination of logs

    return Container(
      height: 130,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'TEMPO ATIVO',
            style: GoogleFonts.robotoMono(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white60,
              letterSpacing: 0.9,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.timer_outlined, color: _hudCyan, size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _activeTimeText,
                    style: GoogleFonts.oxanium(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _hudCyan,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Text(
            '$todayLogs Registros hoje',
            style: GoogleFonts.robotoMono(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}

// Health Alert Banner ---------------------------------------------------------
class _HealthAlertBanner extends StatelessWidget {
  final String dogId;
  const _HealthAlertBanner({required this.dogId});

  @override
  Widget build(BuildContext context) {
    final hVM = Provider.of<HealthViewModel>(context);
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 7));

    // Find health logs that have a return date within the next 7 days
    final alerts = hVM.healthLogs.where((h) {
      if (h.dogId != dogId) return false;
      // Return date is stored as "Retorno agendado: DD/MM/YYYY"
      if (!h.healthObservations.contains('Retorno agendado:')) return false;
      try {
        final raw = h.healthObservations.split('Retorno agendado:').last.trim();
        final parts = raw.split('/');
        if (parts.length != 3) return false;
        final date = DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
        return date.isAfter(now.subtract(const Duration(days: 1))) &&
            date.isBefore(horizon);
      } catch (_) {
        return false;
      }
    }).toList();

    if (alerts.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final nextLog = alerts.first;
    final rawDate = nextLog.healthObservations
        .split('Retorno agendado:')
        .last
        .trim()
        .split('\n')
        .first
        .trim();

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _hudPanel.withAlpha(235),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _hudAmber, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _hudAmber.withAlpha(40),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: _hudAmber,
                size: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ALERTA DE SAÚDE',
                      style: GoogleFonts.robotoMono(
                        color: _hudAmber,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${nextLog.logType} — Retorno agendado: $rawDate',
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Today Activities Card -------------------------------------------------------
class _TodayActivitiesCard extends StatelessWidget {
  final String dogId;
  const _TodayActivitiesCard({required this.dogId});

  @override
  Widget build(BuildContext context) {
    final tVM = Provider.of<TrainingViewModel>(context);
    final iVM = Provider.of<IncidentViewModel>(context);
    final hVM = Provider.of<HealthViewModel>(context);

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // Gather today's entries
    final List<_ActivityEntry> entries = [];

    for (final t in tVM.trainings) {
      if (t.dogId != dogId) continue;
      if (t.date.isBefore(startOfDay) || t.date.isAfter(endOfDay)) continue;
      final isRoutine = [
        'Passeio',
        'Lazer/Brincadeira',
        'Brincadeira',
        'Condicionamento Físico',
        'Alimentação',
        'Limpeza',
        'Descanso',
        'Escovação',
        'Outros',
      ].contains(t.trainingType);
      entries.add(
        _ActivityEntry(
          time: t.date,
          label: t.trainingType,
          icon: isRoutine ? Icons.pets_rounded : Icons.track_changes_rounded,
          color: isRoutine ? const Color(0xFF43A047) : const Color(0xFFFFB300),
        ),
      );
    }

    for (final i in iVM.incidents) {
      if (i.dogId != dogId) continue;
      if (i.date.isBefore(startOfDay) || i.date.isAfter(endOfDay)) continue;
      entries.add(
        _ActivityEntry(
          time: i.date,
          label: i.type ?? 'Ocorrência',
          icon: Icons.shield_outlined,
          color: const Color(0xFFE53935),
        ),
      );
    }

    for (final h in hVM.healthLogs) {
      if (h.dogId != dogId) continue;
      if (h.date.isBefore(startOfDay) || h.date.isAfter(endOfDay)) continue;
      entries.add(
        _ActivityEntry(
          time: h.date,
          label: h.logType,
          icon: Icons.vaccines_rounded,
          color: const Color(0xFF8E24AA),
        ),
      );
    }

    entries.sort((a, b) => b.time.compareTo(a.time)); // most recent first

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(85)),
        boxShadow: [BoxShadow(color: _hudCyan.withAlpha(20), blurRadius: 18)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.history_edu_rounded,
                    color: _hudCyan,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ÚLTIMAS ATIVIDADES',
                    style: GoogleFonts.robotoMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white60,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              Text(
                'HOJE',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: _hudAmber,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  'Nenhuma atividade registrada hoje',
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
                ),
              ),
            )
          else
            ...entries.take(5).map((e) => _ActivityRow(entry: e)),
          if (entries.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '+ ${entries.length - 5} mais — ver Linha do Tempo',
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityEntry {
  final DateTime time;
  final String label;
  final IconData icon;
  final Color color;
  _ActivityEntry({
    required this.time,
    required this.label,
    required this.icon,
    required this.color,
  });
}

class _ActivityRow extends StatelessWidget {
  final _ActivityEntry entry;
  const _ActivityRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final timeStr =
        '${entry.time.hour.toString().padLeft(2, '0')}:${entry.time.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: entry.color.withAlpha(40),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: entry.color.withAlpha(110)),
              boxShadow: [
                BoxShadow(color: entry.color.withAlpha(30), blurRadius: 12),
              ],
            ),
            child: Icon(entry.icon, color: entry.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.label,
              style: GoogleFonts.oxanium(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                letterSpacing: 0.6,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            timeStr,
            style: GoogleFonts.robotoMono(
              color: _hudCyan.withAlpha(170),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingIndicator extends StatefulWidget {
  @override
  __PulsingIndicatorState createState() => __PulsingIndicatorState();
}

class __PulsingIndicatorState extends State<_PulsingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _animation = Tween(begin: 2.0, end: 10.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _hudGreen,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _hudGreen.withAlpha(150),
                    blurRadius: _animation.value,
                    spreadRadius: _animation.value / 2,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        Text(
          'EM PATRULHA',
          style: GoogleFonts.robotoMono(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: _hudGreen,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}
