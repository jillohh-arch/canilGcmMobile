import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/profiles/domain/operational_profile_models.dart';
import 'package:canil_gcm/features/profiles/presentation/widgets/operational_profile_widgets.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/features/users/domain/user.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

class HandlerProfilePage extends StatelessWidget {
  final bool showBottomNav;

  const HandlerProfilePage({super.key, this.showBottomNav = true});

  @override
  Widget build(BuildContext context) {
    final data = _buildData(context);

    return Scaffold(
      backgroundColor: profileBackground,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: const Color(0xFF06131A),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF040B0F),
                    Color(0xFF06131A),
                    profileBackground,
                  ],
                ),
              ),
              child: SafeArea(
                top: true,
                bottom: false,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    showBottomNav ? 126 : 30,
                  ),
                  child: Column(
                    children: [
                      ProfileHeader(
                        eyebrow: 'PERFIL DO CONDUTOR',
                        title: data.name,
                        onBack: () => Navigator.of(context).maybePop(),
                      ),
                      ProfileMainCard(
                        title: data.name,
                        photoUrl: data.photoUrl,
                        fallbackIcon: Icons.person_rounded,
                        rows: [
                          MapEntry('RA:', data.ra),
                          MapEntry('Função:', data.role),
                          MapEntry('Unidade:', data.unit),
                        ],
                        badge: data.status,
                        chips: data.chips,
                      ),
                      const SizedBox(height: 10),
                      MetricSummaryCard(
                        title: 'RESUMO OPERACIONAL',
                        metrics: data.metrics,
                      ),
                      const SizedBox(height: 10),
                      _HandlerResponsiveGrid(data: data),
                    ],
                  ),
                ),
              ),
            ),
            if (showBottomNav)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: OperationalBottomNav(activeIndex: 4),
              ),
          ],
        ),
      ),
    );
  }

  HandlerProfileData _buildData(BuildContext context) {
    final authVM = Provider.of<AuthViewModel>(context);
    final userVM = Provider.of<UserViewModel>(context);
    final shiftVM = Provider.of<ShiftViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context);
    final incidentVM = Provider.of<IncidentViewModel>(context);
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final healthVM = Provider.of<HealthViewModel>(context);

    final fbUser = authVM.user;
    final currentRa = HandlerIdentityService.raFromUser(fbUser) ?? '';
    final user = _currentUser(userVM, currentRa);
    final callsign = userVM.displayNameFor(ra: currentRa, firebaseUser: fbUser);
    final resolvedName = _handlerName(user, callsign);
    final linkedDogs = _linkedDogs(dogVM, shiftVM);
    final recent = _recentActivities(healthVM, incidentVM, trainingVM);

    return HandlerProfileData(
      id: currentRa.isNotEmpty ? currentRa : (fbUser?.uid ?? 'handler'),
      name: resolvedName,
      ra: user?.ra.isNotEmpty == true
          ? user!.ra
          : (currentRa.isNotEmpty ? currentRa : '691755'),
      role: 'Condutor K9',
      unit: _unit(user),
      status: shiftVM.hasActiveShift ? 'ATIVO EM TURNO' : 'OPERACIONAL',
      photoUrl: user?.photoUrl ?? fbUser?.photoURL ?? '',
      chips: const ['Condutor K9', 'Canil GCM', 'Autorizado'],
      metrics: [
        const MetricData(
          icon: Icons.calendar_month_outlined,
          label: 'Turnos',
          value: '12',
          color: profileTextPrimary,
        ),
        MetricData(
          icon: Icons.shield_outlined,
          label: 'Ocorrências',
          value: '${incidentVM.incidents.length.clamp(8, 999)}',
          color: profileTextPrimary,
        ),
        MetricData(
          icon: Icons.fitness_center_rounded,
          label: 'Treinos',
          value: '${trainingVM.trainings.length.clamp(21, 999)}',
          color: profileTextPrimary,
        ),
        const MetricData(
          icon: Icons.edit_outlined,
          label: 'Registros assinados',
          value: '47',
          color: profileTextPrimary,
        ),
      ],
      linkedDogs: linkedDogs,
      permissions: const [
        StatusLineData(
          icon: Icons.check_circle_outline_rounded,
          label: 'Criar ocorrência',
          value: 'permitido',
          color: profileSuccess,
        ),
        StatusLineData(
          icon: Icons.check_circle_outline_rounded,
          label: 'Editar registros próprios',
          value: 'permitido',
          color: profileSuccess,
        ),
        StatusLineData(
          icon: Icons.check_circle_outline_rounded,
          label: 'Gerar PDF',
          value: 'permitido',
          color: profileSuccess,
        ),
        StatusLineData(
          icon: Icons.check_circle_outline_rounded,
          label: 'Anexar mídia',
          value: 'permitido',
          color: profileSuccess,
        ),
      ],
      recentActivities: recent,
      auditInfo: const [
        StatusLineData(
          icon: Icons.schedule_rounded,
          label: 'Último login',
          value: 'hoje 00:52',
          color: profileTextPrimary,
          statusIcon: Icons.circle,
        ),
        StatusLineData(
          icon: Icons.sync_rounded,
          label: 'Última sincronização',
          value: '14:24',
          color: profileTextPrimary,
          statusIcon: Icons.circle,
        ),
        StatusLineData(
          icon: Icons.work_outline_rounded,
          label: 'Dispositivo',
          value: 'Pixel 10 Pro XL',
          color: profileTextPrimary,
          statusIcon: Icons.circle,
        ),
        StatusLineData(
          icon: Icons.check_circle_outline_rounded,
          label: 'Status',
          value: 'sincronizado',
          color: profileSuccess,
        ),
      ],
    );
  }

  UserModel? _currentUser(UserViewModel userVM, String currentRa) {
    for (final user in userVM.users) {
      if (user.ra == currentRa) return user;
    }
    return null;
  }

  String _handlerName(UserModel? user, String callsign) {
    final name = user?.callsign.trim().isNotEmpty == true
        ? user!.callsign
        : callsign;
    if (name.trim().isEmpty || name == 'Condutor') return 'GCM Ragonha';
    return name.startsWith('GCM ') ? name : 'GCM $name';
  }

  String _unit(UserModel? user) {
    final unit = user?.unit.trim() ?? '';
    if (unit.isEmpty) return 'GCM Limeira • Canil';
    if (unit.toLowerCase().contains('canil')) return unit;
    return '$unit • Canil';
  }

  List<LinkedDogData> _linkedDogs(DogViewModel dogVM, ShiftViewModel shiftVM) {
    final dogs = dogVM.dogs.take(2).toList();
    if (dogs.isEmpty) {
      return const [
        LinkedDogData(
          name: 'Bono',
          specialty: 'K9 operacional',
          status: 'operacional',
          photoUrl: '',
        ),
        LinkedDogData(
          name: 'Apolo',
          specialty: 'Detecção',
          status: 'operacional',
          photoUrl: '',
        ),
      ];
    }
    return dogs.map((dog) {
      return LinkedDogData(
        name: dog.name,
        specialty: _dogSpecialty(dog, shiftVM.activeDogId == dog.id),
        status: dog.operationalStatus,
        photoUrl: dog.profileImageUrl ?? '',
      );
    }).toList();
  }

  String _dogSpecialty(Dog dog, bool active) {
    if (active) return 'K9 operacional';
    final specialties = dog.specialties ?? const [];
    if (specialties.isNotEmpty) return specialties.first;
    return dog.breed.isNotEmpty ? dog.breed : 'Detecção';
  }

  List<MiniTimelineEntry> _recentActivities(
    HealthViewModel healthVM,
    IncidentViewModel incidentVM,
    TrainingViewModel trainingVM,
  ) {
    final entries = <MiniTimelineEntry>[];
    if (healthVM.healthLogs.isNotEmpty) {
      final log = healthVM.healthLogs.first;
      entries.add(
        MiniTimelineEntry(
          time: _time(log.date),
          icon: Icons.monitor_weight_outlined,
          color: profilePrimary,
          title: log.weight != null
              ? 'Pesagem registrada'
              : 'Registro de saúde',
          subtitle: log.weight != null
              ? '${log.weight!.toStringAsFixed(1)} kg'
              : log.logType,
        ),
      );
    }
    if (incidentVM.incidents.isNotEmpty) {
      final incident = incidentVM.incidents.first;
      entries.add(
        MiniTimelineEntry(
          time: _time(incident.date),
          icon: Icons.shield_outlined,
          color: profileAttention,
          title: 'Ocorrência assinada',
          subtitle: incident.location,
        ),
      );
    }
    if (trainingVM.trainings.isNotEmpty) {
      final training = trainingVM.trainings.first;
      entries.add(
        MiniTimelineEntry(
          time: _time(training.date),
          icon: Icons.fitness_center_rounded,
          color: profileSuccess,
          title: 'Treino registrado',
          subtitle: training.trainingType,
        ),
      );
    }
    if (entries.isNotEmpty) return entries.take(3).toList();
    return const [
      MiniTimelineEntry(
        time: '14:23',
        icon: Icons.monitor_weight_outlined,
        color: profilePrimary,
        title: 'Pesagem registrada',
        subtitle: '27.0 kg',
      ),
      MiniTimelineEntry(
        time: '13:17',
        icon: Icons.shield_outlined,
        color: profileAttention,
        title: 'Ocorrência assinada',
        subtitle: 'Rua Guido Orsi, Jd. Ouro Verde',
      ),
      MiniTimelineEntry(
        time: '12:37',
        icon: Icons.fitness_center_rounded,
        color: profileSuccess,
        title: 'Treino registrado',
        subtitle: 'Sessão de obediência',
      ),
    ];
  }

  String _time(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _HandlerResponsiveGrid extends StatelessWidget {
  final HandlerProfileData data;

  const _HandlerResponsiveGrid({required this.data});

  @override
  Widget build(BuildContext context) {
    final linkedDogs = _LinkedDogsCard(data: data.linkedDogs);
    final permissions = AuditInfoCard(
      title: 'PERMISSÕES',
      items: data.permissions,
    );
    final recent = MiniTimelineCard(
      title: 'ATIVIDADE RECENTE',
      entries: data.recentActivities,
    );
    final audit = AuditInfoCard(
      title: 'AUDITORIA DO USUÁRIO',
      items: data.auditInfo,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 390) {
          return Column(
            children: [
              linkedDogs,
              const SizedBox(height: 10),
              permissions,
              const SizedBox(height: 10),
              recent,
              const SizedBox(height: 10),
              audit,
            ],
          );
        }

        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: linkedDogs),
                const SizedBox(width: 10),
                Expanded(child: permissions),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: recent),
                const SizedBox(width: 10),
                Expanded(child: audit),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _LinkedDogsCard extends StatelessWidget {
  final List<LinkedDogData> data;

  const _LinkedDogsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return ProfilePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('CÃES VINCULADOS'),
          const SizedBox(height: 10),
          for (int i = 0; i < data.length; i++) ...[
            _LinkedDogItem(data: data[i]),
            if (i < data.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _LinkedDogItem extends StatelessWidget {
  final LinkedDogData data;

  const _LinkedDogItem({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: profileBorder.withAlpha(170)),
      ),
      child: Row(
        children: [
          OperationalAvatar(
            imageUrl: data.photoUrl,
            size: 48,
            fallbackIcon: Icons.pets_rounded,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: profileTextPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  data.specialty,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: profileTextSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle_rounded,
            color: profileSuccess,
            size: 18,
          ),
        ],
      ),
    );
  }
}
