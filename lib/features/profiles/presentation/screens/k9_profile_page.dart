import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/presentation/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/profiles/domain/operational_profile_models.dart';
import 'package:canil_gcm/features/profiles/presentation/widgets/operational_profile_widgets.dart';
import 'package:canil_gcm/features/training/presentation/viewmodels/training_viewmodel.dart';

class K9ProfilePage extends StatelessWidget {
  final Dog dog;
  final bool showBottomNav;

  const K9ProfilePage({
    super.key,
    required this.dog,
    this.showBottomNav = false,
  });

  @override
  Widget build(BuildContext context) {
    final data = _buildData(context, dog);

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
                        eyebrow: 'PERFIL DO CÃO',
                        title: data.name,
                        onBack: () => Navigator.of(context).maybePop(),
                      ),
                      ProfileMainCard(
                        title: data.name,
                        photoUrl: data.photoUrl,
                        fallbackIcon: Icons.pets_rounded,
                        rows: [
                          MapEntry('Raça:', data.breed),
                          MapEntry('Sexo:', data.sex),
                          MapEntry('Idade:', '${data.age} anos'),
                          MapEntry(
                            'Peso:',
                            '${data.weight.toStringAsFixed(1)} kg',
                          ),
                        ],
                        badge: data.operationalStatus,
                        chips: data.specialties,
                      ),
                      const SizedBox(height: 10),
                      MetricSummaryCard(
                        title: 'RESUMO OPERACIONAL',
                        metrics: data.metrics,
                      ),
                      const SizedBox(height: 10),
                      _K9ProfileSections(data: data),
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

  K9ProfileData _buildData(BuildContext context, Dog dog) {
    final healthVM = Provider.of<HealthViewModel>(context);
    final trainingVM = Provider.of<TrainingViewModel>(context);
    final incidentVM = Provider.of<IncidentViewModel>(context);
    final now = DateTime.now();

    final dogHealthLogs =
        healthVM.healthLogs.where((log) => log.dogId == dog.id).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final dogTrainings =
        trainingVM.trainings.where((item) => item.dogId == dog.id).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final dogIncidents =
        incidentVM.incidents.where((item) => item.dogId == dog.id).toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    final latestWeight = dogHealthLogs
        .where((log) => log.weight != null)
        .map((log) => log.weight!)
        .firstOrNull;
    final weight = latestWeight ?? dog.weight ?? 27.0;
    final lastTraining = dogTrainings.isNotEmpty
        ? _ago(dogTrainings.first.date, now)
        : _ago(dog.lastTrainingDate, now, fallback: 'há 3h');
    final lastIncident = dogIncidents.isNotEmpty
        ? _ago(dogIncidents.first.date, now)
        : 'há 11h';
    final specialtyList = (dog.specialties ?? const [])
        .where((item) => item.trim().isNotEmpty)
        .take(3)
        .toList();

    return K9ProfileData(
      id: dog.id,
      name: dog.name.isNotEmpty ? dog.name : 'Bono',
      breed: dog.breed.isNotEmpty ? dog.breed : 'Malinois',
      sex: _sexLabel(dog.sex),
      age: dog.age > 0 ? dog.age : 6,
      weight: weight,
      operationalStatus: _operationalBadge(dog),
      photoUrl: dog.profileImageUrl ?? '',
      specialties: specialtyList.isEmpty
          ? const ['Guarda & Proteção', 'Busca & Captura', 'Detecção']
          : specialtyList,
      metrics: [
        const MetricData(
          icon: Icons.monitor_heart_outlined,
          label: 'Saúde',
          value: 'OK',
          color: profileSuccess,
        ),
        MetricData(
          icon: Icons.fitness_center_rounded,
          label: 'Último treino',
          value: lastTraining,
          color: profileTextPrimary,
        ),
        MetricData(
          icon: Icons.shield_outlined,
          label: 'Última ocorrência',
          value: lastIncident,
          color: profileTextPrimary,
        ),
        const MetricData(
          icon: Icons.calendar_month_outlined,
          label: 'Status',
          value: 'Em serviço',
          color: profileSuccess,
        ),
      ],
      healthItems: _healthItems(dog, now, weight),
      documents: const [
        DocumentData(
          icon: Icons.workspace_premium_outlined,
          name: 'Certificação Detecção',
        ),
        DocumentData(
          icon: Icons.description_outlined,
          name: 'Laudo nutricional',
        ),
        DocumentData(
          icon: Icons.description_outlined,
          name: 'Laudo veterinário',
        ),
        DocumentData(
          icon: Icons.badge_outlined,
          name: 'Cadastro institucional',
        ),
      ],
      recentActivities: _recentEntries(
        dogHealthLogs,
        dogTrainings,
        dogIncidents,
      ),
    );
  }

  List<StatusLineData> _healthItems(Dog dog, DateTime now, double weight) {
    final vaccineOk =
        dog.lastVaccineDate == null ||
        now.difference(dog.lastVaccineDate!).inDays <= 365;
    return [
      StatusLineData(
        icon: Icons.vaccines_outlined,
        label: 'Vacina V10',
        value: vaccineOk ? 'em dia' : 'vencida',
        color: vaccineOk ? profileSuccess : profileCritical,
        statusIcon: vaccineOk
            ? Icons.check_circle_outline_rounded
            : Icons.error_outline_rounded,
      ),
      const StatusLineData(
        icon: Icons.calendar_month_outlined,
        label: 'Antirrábica',
        value: 'em dia',
        color: profileSuccess,
      ),
      const StatusLineData(
        icon: Icons.bug_report_outlined,
        label: 'Antipulgas',
        value: 'vence em 8 dias',
        color: profileAttention,
        statusIcon: Icons.warning_amber_rounded,
      ),
      const StatusLineData(
        icon: Icons.health_and_safety_outlined,
        label: 'Vermífugo',
        value: 'próximo em 15 dias',
        color: profileAttention,
        statusIcon: Icons.schedule_rounded,
      ),
      StatusLineData(
        icon: Icons.monitor_weight_outlined,
        label: 'Peso',
        value: weight > 0 ? 'estável' : 'pendente',
        color: weight > 0 ? profileSuccess : profileAttention,
      ),
      const StatusLineData(
        icon: Icons.article_outlined,
        label: 'Exames',
        value: 'vencendo em 30 dias',
        color: profileAttention,
        statusIcon: Icons.warning_amber_rounded,
      ),
    ];
  }

  List<MiniTimelineEntry> _recentEntries(
    List<dynamic> healthLogs,
    List<dynamic> trainings,
    List<dynamic> incidents,
  ) {
    final entries = <MiniTimelineEntry>[];
    if (healthLogs.isNotEmpty && healthLogs.first.weight != null) {
      entries.add(
        MiniTimelineEntry(
          time: _time(healthLogs.first.date),
          icon: Icons.monitor_weight_outlined,
          color: profilePrimary,
          title: 'Pesagem operacional',
          subtitle: '${healthLogs.first.weight!.toStringAsFixed(1)} kg',
        ),
      );
    }
    if (incidents.isNotEmpty) {
      entries.add(
        MiniTimelineEntry(
          time: _time(incidents.first.date),
          icon: Icons.shield_outlined,
          color: profileAttention,
          title: 'Ocorrência • ${incidents.first.type ?? 'Averiguação'}',
          subtitle: incidents.first.location,
        ),
      );
    }
    if (trainings.isNotEmpty) {
      entries.add(
        MiniTimelineEntry(
          time: _time(trainings.first.date),
          icon: Icons.fitness_center_rounded,
          color: profileSuccess,
          title: 'Treino • ${trainings.first.trainingType}',
          subtitle: 'Sessão registrada',
        ),
      );
    }
    if (entries.isNotEmpty) return entries.take(3).toList();
    return const [
      MiniTimelineEntry(
        time: '14:23',
        icon: Icons.monitor_weight_outlined,
        color: profilePrimary,
        title: 'Pesagem operacional',
        subtitle: '27.0 kg',
      ),
      MiniTimelineEntry(
        time: '13:17',
        icon: Icons.shield_outlined,
        color: profileAttention,
        title: 'Ocorrência • Averiguação',
        subtitle: 'Rua Guido Orsi, Jd. Ouro Verde',
      ),
      MiniTimelineEntry(
        time: '12:37',
        icon: Icons.fitness_center_rounded,
        color: profileSuccess,
        title: 'Treino • Obediência',
        subtitle: 'Sessão registrada',
      ),
    ];
  }

  String _sexLabel(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'f' || normalized.startsWith('fem')) return 'Fêmea';
    return 'Macho';
  }

  String _operationalBadge(Dog dog) {
    final status = dog.operationalStatus.toLowerCase();
    if (status.contains('ativo') || status.contains('treino')) {
      return 'OPERACIONAL';
    }
    return dog.operationalStatus.toUpperCase();
  }

  String _ago(DateTime? date, DateTime now, {String fallback = '—'}) {
    if (date == null) return fallback;
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes.clamp(1, 59)}min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    if (diff.inDays == 1) return 'há 1 dia';
    return 'há ${diff.inDays}d';
  }

  String _time(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _K9ProfileSections extends StatelessWidget {
  final K9ProfileData data;

  const _K9ProfileSections({required this.data});

  @override
  Widget build(BuildContext context) {
    final health = ProfilePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('SAÚDE E CONFORMIDADE'),
          const SizedBox(height: 10),
          for (int i = 0; i < data.healthItems.length; i++)
            StatusLineItem(
              data: data.healthItems[i],
              showDivider: i < data.healthItems.length - 1,
            ),
        ],
      ),
    );

    final documents = ProfilePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('DOCUMENTOS E LAUDOS'),
          const SizedBox(height: 9),
          for (int i = 0; i < data.documents.length; i++)
            DocumentCard(
              data: data.documents[i],
              showDivider: i < data.documents.length - 1,
            ),
        ],
      ),
    );

    final timeline = MiniTimelineCard(
      title: 'ÚLTIMOS REGISTROS',
      entries: data.recentActivities,
    );

    return Column(
      children: [
        health,
        const SizedBox(height: 10),
        documents,
        const SizedBox(height: 10),
        timeline,
      ],
    );
  }
}
