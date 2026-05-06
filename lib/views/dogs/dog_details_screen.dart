import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:canil_gcm/models/dog.dart';
import 'package:canil_gcm/theme/app_theme.dart';
import '../health/health_log_screen.dart';
import '../../models/health_log_model.dart';
import 'package:canil_gcm/viewmodels/training_viewmodel.dart';
import 'package:canil_gcm/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/viewmodels/incident_viewmodel.dart';
import 'package:canil_gcm/features/incidents/presentation/screens/occurrence_flow_screen.dart';
import '../trainings/training_log_screen.dart';

class DogDetailsScreen extends StatefulWidget {
  final Dog dog;
  const DogDetailsScreen({super.key, required this.dog});

  @override
  State<DogDetailsScreen> createState() => _DogDetailsScreenState();
}

class _DogDetailsScreenState extends State<DogDetailsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TrainingViewModel>(
        context,
        listen: false,
      ).fetchTrainingsForDog(widget.dog.id);
      Provider.of<HealthViewModel>(
        context,
        listen: false,
      ).fetchHealthLogsForDog(widget.dog.id);
      Provider.of<IncidentViewModel>(
        context,
        listen: false,
      ).fetchIncidentsForDog(widget.dog.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final dogList = Provider.of<DogViewModel>(context).dogs;
    final dog = dogList.firstWhere(
      (d) => d.id == widget.dog.id,
      orElse: () => widget.dog,
    );
    final opStatus = dog.operationalStatus;
    final gradient = AppTheme.statusGradient(opStatus);
    final statusColor = AppTheme.statusColor(opStatus);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Agent Hero Header ───────────────────────────────────────
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            stretch: true,
            backgroundColor: AppTheme.statusBg(opStatus),
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.blurBackground,
              ],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(decoration: BoxDecoration(gradient: gradient)),
                  // Blobs
                  Positioned(
                    right: -60,
                    top: -40,
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha(12),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -30,
                    bottom: -30,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withAlpha(25),
                      ),
                    ),
                  ),
                  // Agent ID layout
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Photo
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(80),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 56,
                              backgroundColor: Colors.white24,
                              backgroundImage: dog.profileImageUrl != null
                                  ? NetworkImage(dog.profileImageUrl!)
                                  : null,
                              child: dog.profileImageUrl == null
                                  ? const FaIcon(
                                      FontAwesomeIcons.dog,
                                      size: 40,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 18),
                          // Info
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _AgentStatusPill(
                                  status: opStatus,
                                  color: statusColor,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  dog.name.toUpperCase(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                    height: 1.0,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      dog.breed,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      dog.sex == 'F'
                                          ? Icons.female_rounded
                                          : Icons.male_rounded,
                                      size: 16,
                                      color: dog.sex == 'F'
                                          ? const Color(0xFFFF80AB)
                                          : const Color(0xFF82B1FF),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${dog.age} anos · ID: ${dog.id.substring(0, 8).toUpperCase()}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: Colors.white38,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Quick Actions ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  _QuickActionButton(
                    icon: Icons.track_changes_rounded,
                    label: 'Faro',
                    color: const Color(0xFFFFB300),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TrainingLogScreen(dogId: dog.id, dogName: dog.name),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _QuickActionButton(
                    icon: Icons.medical_services_rounded,
                    label: 'Saúde',
                    color: const Color(0xFFEF5350),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HealthLogScreen(dogId: dog.id),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _QuickActionButton(
                    icon: Icons.report_rounded,
                    label: 'Ocorrência',
                    color: const Color(0xFF4ECDE4),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OccurrenceFlowScreen(
                          dogId: dog.id,
                          dogName: dog.name,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── COCKPIT BENTO GRID ────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _CockpitBento(dog: dog),
            ),
          ),

          // ── Mission Log ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
              child: _MissionLog(dog: dog),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Cockpit Bento Grid ────────────────────────────────────────────────────────
class _CockpitBento extends StatelessWidget {
  final Dog dog;
  const _CockpitBento({required this.dog});

  @override
  Widget build(BuildContext context) {
    final tVM = Provider.of<TrainingViewModel>(context);
    final hVM = Provider.of<HealthViewModel>(context);

    // Last training info
    final trainings = tVM.trainings..sort((a, b) => b.date.compareTo(a.date));
    final lastTraining = trainings.isNotEmpty ? trainings.first : null;
    final scentCount = trainings.where((t) => t.trainingType == 'Faro').length;

    // Last health info
    final healthLogs = hVM.healthLogs..sort((a, b) => b.date.compareTo(a.date));
    final lastHealth = healthLogs.isNotEmpty ? healthLogs.first : null;
    final lastHealthWeight = healthLogs
        .where((h) => h.weight != null)
        .firstOrNull
        ?.weight;
    final lastWeight = dog.weight ?? lastHealthWeight;

    return Column(
      children: [
        // ── Bloco 1: Treino/Faro (largura total) ─────────────────────
        _BentoBlock(
          height: 110,
          accent: const Color(0xFFFFB300),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFB300).withAlpha(30),
                  border: Border.all(
                    color: const Color(0xFFFFB300).withAlpha(100),
                  ),
                ),
                child: const Icon(
                  Icons.track_changes_rounded,
                  color: Color(0xFFFFB300),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      lastTraining != null
                          ? 'ÚLTIMO TREINO DE ${lastTraining.trainingType.toUpperCase()}'
                          : 'ÚLTIMO TREINO DE FARO',
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFFFB300),
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (lastTraining != null) ...[
                      Text(
                        '${lastTraining.trainingType}${lastTraining.substanceUsed != null ? " · ${lastTraining.substanceUsed}" : ""}',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        lastTraining.location,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.white54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ] else
                      Text(
                        'Nenhum treino registrado',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: Colors.white38,
                        ),
                      ),
                  ],
                ),
              ),
              // Right: count
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$scentCount',
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFFFB300),
                    ),
                  ),
                  Text(
                    'SESSÕES',
                    style: GoogleFonts.poppins(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: Colors.white38,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── Bloco 2 + Bloco 3: Saúde + Peso (row) ────────────────────
        Row(
          children: [
            // Bloco 2: Saúde (2/3 width)
            Expanded(
              flex: 2,
              child: _BentoBlock(
                height: 120,
                accent: const Color(0xFFEF5350),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.medical_services_rounded,
                          color: const Color(0xFFEF5350),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'SAÚDE',
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFEF5350),
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                    if (lastHealth != null) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lastHealth.logType,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            _formatDate(lastHealth.date),
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    ] else
                      Text(
                        'Sem registros',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.white38,
                        ),
                      ),
                    // Vaccine indicator
                    if (dog.lastVaccineDate != null) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.vaccines_rounded,
                            size: 12,
                            color: Colors.white38,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Vacina: ${_formatDate(dog.lastVaccineDate!)}',
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              color: Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Bloco 3: Peso (1/3 width)
            Expanded(
              flex: 1,
              child: GestureDetector(
                onTap: () => _showWeightDialog(context, dog, lastWeight),
                child: _BentoBlock(
                  height: 120,
                  accent: const Color(0xFF66BB6A),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(
                            Icons.monitor_weight_outlined,
                            color: const Color(0xFF66BB6A),
                            size: 18,
                          ),
                          Icon(
                            Icons.edit_rounded,
                            color: const Color(0xFF66BB6A).withAlpha(150),
                            size: 14,
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lastWeight != null
                                ? lastWeight.toStringAsFixed(1)
                                : '--',
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'KG',
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white38,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'PESO',
                        style: GoogleFonts.poppins(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF66BB6A),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Bloco 4: Sexo + Idade (row de 2 menores) ─────────────────
        Row(
          children: [
            // Sexo
            Expanded(
              child: _BentoBlock(
                height: 80,
                accent: dog.sex == 'F'
                    ? const Color(0xFFFF80AB)
                    : const Color(0xFF82B1FF),
                child: Row(
                  children: [
                    Icon(
                      dog.sex == 'F'
                          ? Icons.female_rounded
                          : Icons.male_rounded,
                      size: 28,
                      color: dog.sex == 'F'
                          ? const Color(0xFFFF80AB)
                          : const Color(0xFF82B1FF),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          dog.sex == 'F' ? 'Fêmea' : 'Macho',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'SEXO',
                          style: GoogleFonts.poppins(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Idade
            Expanded(
              child: _BentoBlock(
                height: 80,
                accent: const Color(0xFF4ECDE4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cake_outlined,
                      size: 26,
                      color: Color(0xFF4ECDE4),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${dog.age} anos',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'IDADE',
                          style: GoogleFonts.poppins(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Condutor
            if (dog.conductorRa != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _BentoBlock(
                  height: 80,
                  accent: const Color(0xFFFFB300),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.badge_outlined,
                        size: 18,
                        color: Color(0xFFFFB300),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'RA ${dog.conductorRa}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'CONDUTOR',
                        style: GoogleFonts.poppins(
                          fontSize: 7,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _showWeightDialog(BuildContext context, Dog dog, double? currentWeight) {
    final TextEditingController controller = TextEditingController(
      text: currentWeight != null ? currentWeight.toStringAsFixed(1) : '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141A21),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        title: Text(
          'ATUALIZAR PESO',
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 1.0,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Insira o novo peso do cão em quilogramas (kg).',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: GoogleFonts.robotoMono(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              decoration: InputDecoration(
                suffixText: 'kg',
                suffixStyle: GoogleFonts.poppins(color: Colors.white38),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF2A2A2A)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF66BB6A), width: 1.5),
                ),
                filled: true,
                fillColor: Colors.black12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'CANCELAR',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: Colors.white38,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF66BB6A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () async {
              final val = double.tryParse(controller.text.replaceAll(',', '.'));
              if (val == null || val <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Informe um peso válido.'),
                    backgroundColor: Color(0xFFE53935),
                  ),
                );
                return;
              }

              final messenger = ScaffoldMessenger.of(context);
              final dogVM = Provider.of<DogViewModel>(context, listen: false);
              final healthVM = Provider.of<HealthViewModel>(
                context,
                listen: false,
              );

              Navigator.pop(ctx);

              try {
                await dogVM.updateDogWeight(dog.id, val);

                final hLog = HealthLogModel(
                  dogId: dog.id,
                  dogName: dog.name,
                  date: DateTime.now(),
                  logType: 'Rotina',
                  healthObservations: 'Pesagem de rotina registrada no dossiê.',
                  weight: val,
                );
                await healthVM.addHealthLog(hLog);

                if (!context.mounted) return;
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Peso atualizado em tempo real.'),
                    backgroundColor: Color(0xFF66BB6A),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Erro ao atualizar peso: $e'),
                    backgroundColor: const Color(0xFFE53935),
                  ),
                );
              }
            },
            child: Text(
              'SALVAR',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bento Block container ─────────────────────────────────────────────────────
class _BentoBlock extends StatelessWidget {
  final Widget child;
  final Color accent;
  final double height;
  const _BentoBlock({
    required this.child,
    required this.accent,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(60), width: 0.8),
      ),
      child: child,
    );
  }
}

// ── Agent Status Pill ─────────────────────────────────────────────────────────
class _AgentStatusPill extends StatelessWidget {
  final String status;
  final Color color;
  const _AgentStatusPill({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(60),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(150), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            AppTheme.statusLabel(status),
            style: GoogleFonts.poppins(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick Action Button ───────────────────────────────────────────────────────
class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withAlpha(70), width: 0.8),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 5),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mission Log ───────────────────────────────────────────────────────────────
class _MissionLog extends StatelessWidget {
  final Dog dog;
  const _MissionLog({required this.dog});

  @override
  Widget build(BuildContext context) {
    final tVM = Provider.of<TrainingViewModel>(context);
    final hVM = Provider.of<HealthViewModel>(context);
    final iVM = Provider.of<IncidentViewModel>(context);

    final List<_TimelineItem> items = [];

    for (var t in tVM.trainings) {
      final isScent = t.trainingType == 'Faro';
      items.add(
        _TimelineItem(
          date: t.date,
          title:
              '${t.trainingType}${t.substanceUsed != null ? " · ${t.substanceUsed}" : ""}',
          subtitle: t.location,
          icon: isScent
              ? Icons.track_changes_rounded
              : (t.trainingType == 'Proteção'
                    ? Icons.shield_rounded
                    : Icons.school_rounded),
          color: const Color(0xFFFFB300),
          tag: 'TREINO',
        ),
      );
    }
    for (var h in hVM.healthLogs) {
      final (icon, color) = _healthIconAndColor(h.logType);
      items.add(
        _TimelineItem(
          date: h.date,
          title: h.logType,
          subtitle: h.vaccines.isNotEmpty
              ? h.vaccines.join(', ')
              : h.healthObservations,
          icon: icon,
          color: color,
          tag: 'SAÚDE',
        ),
      );
    }
    for (var i in iVM.incidents) {
      items.add(
        _TimelineItem(
          date: i.date,
          title: i.type ?? 'Ocorrência',
          subtitle: '${i.result} · ${i.location}',
          icon: Icons.report_rounded,
          color: const Color(0xFF4ECDE4),
          tag: 'OCORRÊNCIA',
        ),
      );
    }

    items.sort((a, b) => b.date.compareTo(a.date));
    final visible = items.take(12).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'LOG DE MISSÕES',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: Colors.white38,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: Colors.white10)),
          ],
        ),
        const SizedBox(height: 16),
        if (visible.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Icon(Icons.timeline_rounded, size: 40, color: Colors.white12),
                  const SizedBox(height: 8),
                  Text(
                    'Nenhuma atividade registrada',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.white24,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...List.generate(visible.length, (i) {
            final item = visible[i];
            final isLast = i == visible.length - 1;
            return _TimelineRow(item: item, isLast: isLast);
          }),
      ],
    );
  }

  (IconData, Color) _healthIconAndColor(String logType) {
    switch (logType) {
      case 'Vacina':
        return (Icons.vaccines_rounded, const Color(0xFFEF5350));
      case 'Consulta':
        return (Icons.local_hospital_rounded, const Color(0xFF66BB6A));
      case 'Exame':
        return (Icons.biotech_rounded, const Color(0xFF7E57C2));
      case 'Medicação':
        return (Icons.medication_rounded, const Color(0xFFFF7043));
      case 'Banho':
        return (Icons.water_drop_rounded, const Color(0xFF29B6F6));
      default:
        return (Icons.medical_services_rounded, const Color(0xFFEF5350));
    }
  }
}

class _TimelineItem {
  final DateTime date;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String tag;
  _TimelineItem({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.tag,
  });
}

class _TimelineRow extends StatelessWidget {
  final _TimelineItem item;
  final bool isLast;
  const _TimelineRow({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateStr =
        '${item.date.day.toString().padLeft(2, '0')}/${item.date.month.toString().padLeft(2, '0')}/${item.date.year.toString().substring(2)}';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.color.withAlpha(30),
                    border: Border.all(
                      color: item.color.withAlpha(120),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(item.icon, color: item.color, size: 16),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: Colors.white10,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.outlineVariant, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: item.color.withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.tag,
                            style: GoogleFonts.poppins(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: item.color,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Text(
                          dateStr,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white30,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.white38,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
