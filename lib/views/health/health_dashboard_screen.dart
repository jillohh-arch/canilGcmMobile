import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/viewmodels/health_viewmodel.dart';
import 'package:canil_gcm/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/models/dog.dart';
import '../../models/health_log_model.dart';

class HealthDashboardScreen extends StatefulWidget {
  const HealthDashboardScreen({super.key});

  @override
  State<HealthDashboardScreen> createState() => _HealthDashboardScreenState();
}

class _HealthDashboardScreenState extends State<HealthDashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatMilitaryDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final monthNames = [
      '',
      'JAN',
      'FEV',
      'MAR',
      'ABR',
      'MAI',
      'JUN',
      'JUL',
      'AGO',
      'SET',
      'OUT',
      'NOV',
      'DEZ',
    ];
    final month = monthNames[date.month];
    final year = date.year.toString().substring(2);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day$month$year - $hour:${minute}h';
  }

  String _formatShortDate(DateTime? date) {
    if (date == null) return '-- ---';
    final day = date.day.toString().padLeft(2, '0');
    final monthNames = [
      '',
      'JAN',
      'FEV',
      'MAR',
      'ABR',
      'MAI',
      'JUN',
      'JUL',
      'AGO',
      'SET',
      'OUT',
      'NOV',
      'DEZ',
    ];
    return '$day ${monthNames[date.month]}';
  }

  @override
  Widget build(BuildContext context) {
    final shiftVM = Provider.of<ShiftViewModel>(context);
    if (!shiftVM.hasActiveShift) {
      return Scaffold(
        backgroundColor: const Color(0xFF030712),
        body: Center(
          child: Text(
            'Nenhum turno ativo.',
            style: GoogleFonts.inter(color: Colors.white54),
          ),
        ),
      );
    }

    final dogId = shiftVM.activeDogId!;
    final dogVM = Provider.of<DogViewModel>(context);
    final hVM = Provider.of<HealthViewModel>(context);

    final dog = dogVM.dogs.firstWhere(
      (d) => d.id == dogId,
      orElse: () => dogVM.dogs.first,
    );
    final logs = hVM.healthLogs.where((l) => l.dogId == dogId).toList();

    DateTime? lastBath;
    try {
      lastBath = logs.firstWhere((l) => l.logType == 'Banho').date;
    } catch (_) {}

    return Scaffold(
      backgroundColor: const Color(0xFF030712),
      floatingActionButton: null,
      body: CustomScrollView(
        slivers: [
          _buildSliverHeader(),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildBioHudHeader(dog, logs, lastBath),
                _buildSensorRow(dog, lastBath),
                _buildWeightGraphCard(), // O novo gráfico integrado!
                _buildTimelineHeader(),
              ],
            ),
          ),
          _buildTacticalLogs(context, logs),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildSliverHeader() {
    return SliverAppBar(
      expandedHeight: 0,
      pinned: true,
      backgroundColor: const Color(0xFF030712),
      elevation: 0,
      title: Text(
        'BIO-SURVEILLANCE',
        style: GoogleFonts.oxanium(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 3.0,
          color: Colors.cyanAccent.withValues(alpha: 0.7),
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildBioHudHeader(
    Dog dog,
    List<HealthLogModel> logs,
    DateTime? lastBath,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.cyanAccent.withValues(
                      alpha: 0.3 + (_pulseController.value * 0.7),
                    ),
                    width: 2 + (_pulseController.value * 1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withValues(
                        alpha: 0.4 * _pulseController.value,
                      ),
                      blurRadius: 15 + (15 * _pulseController.value),
                      spreadRadius: 2 + (5 * _pulseController.value),
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: CircleAvatar(
              radius: 55, // Aumentado ligeiramente
              backgroundColor: const Color(0xFF111111),
              backgroundImage: dog.profileImageUrl != null
                  ? CachedNetworkImageProvider(dog.profileImageUrl!)
                  : null,
              child: dog.profileImageUrl == null
                  ? const Icon(Icons.pets, size: 40, color: Colors.white24)
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            dog.name.toUpperCase(),
            style: GoogleFonts.oxanium(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          // Barra de Prontidão Tática (Gamificação V1)
          Builder(
            builder: (context) {
              final latestWeight = logs
                  .where((log) => log.weight != null)
                  .map((log) => log.weight!)
                  .cast<double?>()
                  .firstWhere((weight) => weight != null, orElse: () => null);
              final breakdown = dog.calculateReadinessBreakdown(
                lastBathOverride: lastBath,
                weightOverride: latestWeight,
              );
              final score = breakdown.total;
              Color barColor;
              if (score >= 80) {
                barColor = Colors.cyanAccent;
              } else if (score >= 50) {
                barColor = Colors.orangeAccent;
              } else {
                barColor = Colors.redAccent;
              }

              return Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'PRONTIDÃO OPERACIONAL',
                        style: GoogleFonts.oxanium(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white54,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        '$score%',
                        style: GoogleFonts.shareTechMono(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: barColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: barColor.withValues(alpha: 0.3),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: barColor.withValues(alpha: 0.2),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: score / 100,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      ),
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
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: Colors.white60,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // Cards aumentados e com seleção visual
  Widget _buildSensorRow(Dog dog, DateTime? lastBath) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _buildSensorCard(
              'PESO',
              '${dog.weight?.toStringAsFixed(1) ?? "--"} KG',
              Icon(
                Icons.monitor_weight_outlined,
                size: 24,
                color: Colors.cyanAccent,
              ),
              isSelected: true, // Aqui dizemos que este é o ativo!
              onTap: () => _showWeightDialog(dog),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSensorCard(
              'IDADE',
              '${dog.age} ANOS',
              Icon(
                Icons.query_builder,
                size: 24,
                color: Colors.cyanAccent.withValues(alpha: 0.5),
              ),
              isSelected: false,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSensorCard(
              'ÚLT. BANHO',
              _formatShortDate(lastBath).toUpperCase(),
              Icon(
                Icons.water_drop_outlined,
                size: 24,
                color: Colors.cyanAccent.withValues(alpha: 0.5),
              ),
              isSelected: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorCard(
    String label,
    String value,
    Widget icon, {
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        // Padding aumentado para deixar o card maior
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF082F49).withValues(alpha: 0.3)
              : const Color(0xFF111827),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(6),
            topRight: const Radius.circular(6),
            bottomLeft: Radius.circular(isSelected ? 0 : 8),
            bottomRight: Radius.circular(isSelected ? 0 : 8),
          ),
          border: Border.all(
            color: isSelected
                ? Colors.cyanAccent
                : Colors.cyanAccent.withValues(alpha: 0.2),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Stack(
          children: [
            if (onTap != null)
              Positioned(
                top: 0,
                right: 6,
                child: Icon(
                  Icons.edit_rounded,
                  size: 14,
                  color: Colors.cyanAccent.withValues(alpha: 0.85),
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(height: 12),
                Text(
                  value,
                  // Fonte do valor aumentada
                  style: GoogleFonts.shareTechMono(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? Colors.cyanAccent
                        : Colors.cyanAccent.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white : Colors.white54,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (onTap != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'TOQUE PARA ALTERAR',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.robotoMono(
                      fontSize: 7,
                      fontWeight: FontWeight.w900,
                      color: Colors.cyanAccent.withValues(alpha: 0.68),
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showWeightDialog(Dog dog) async {
    final controller = TextEditingController(
      text: dog.weight != null ? dog.weight!.toStringAsFixed(1) : '',
    );

    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF070B14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: Color(0x9900E5FF)),
          ),
          title: Text(
            'ATUALIZAR PESO',
            style: GoogleFonts.oxanium(
              color: Colors.cyanAccent,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Informe o peso atual do cão em quilogramas.',
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
                style: GoogleFonts.shareTechMono(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
                decoration: InputDecoration(
                  suffixText: 'kg',
                  suffixStyle: GoogleFonts.robotoMono(
                    color: Colors.cyanAccent.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w900,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF0B1020),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0x5500E5FF)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                      color: Colors.cyanAccent,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'CANCELAR',
                style: GoogleFonts.robotoMono(
                  color: Colors.white54,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: const Color(0xFF070B14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: () {
                final value = double.tryParse(
                  controller.text.trim().replaceAll(',', '.'),
                );
                if (value == null || value <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Informe um peso válido.'),
                      backgroundColor: Color(0xFFE53935),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: Text(
                'SALVAR',
                style: GoogleFonts.robotoMono(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (result == null || !mounted) return;

    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final healthVM = Provider.of<HealthViewModel>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await dogVM.updateDogWeight(dog.id, result);
      await healthVM.addHealthLog(
        HealthLogModel(
          dogId: dog.id,
          dogName: dog.name,
          date: DateTime.now(),
          logType: 'Rotina',
          healthObservations: 'Pesagem operacional registrada no app.',
          weight: result,
        ),
      );

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Peso atualizado e sincronizado.'),
          backgroundColor: Color(0xFF1B8A4C),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar peso: $e'),
          backgroundColor: const Color(0xFFE53935),
        ),
      );
    }
  }

  // Novo módulo visual: O Gráfico integrado
  Widget _buildWeightGraphCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 120, // Altura do gráfico
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF082F49).withValues(alpha: 0.15),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(6),
            topRight: Radius.circular(6),
          ),
          border: Border.all(color: Colors.cyanAccent, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.cyanAccent.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Título do Gráfico
            Positioned(
              top: 12,
              left: 12,
              child: Row(
                children: [
                  Icon(
                    Icons.show_chart,
                    size: 14,
                    color: Colors.cyanAccent.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ANÁLISE BIOMÉTRICA: EVOLUÇÃO DE PESO',
                    style: GoogleFonts.oxanium(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.cyanAccent.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            // Linhas de Grade de Fundo
            Positioned.fill(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Divider(color: Colors.cyan.withValues(alpha: 0.1), height: 1),
                  Divider(color: Colors.cyan.withValues(alpha: 0.1), height: 1),
                  Divider(color: Colors.cyan.withValues(alpha: 0.1), height: 1),
                ],
              ),
            ),
            // A Pintura do Gráfico Customizado
            Positioned.fill(
              top: 30,
              child: CustomPaint(painter: WeightChartPainter()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      child: Row(
        children: [
          Container(width: 4, height: 14, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          Text(
            'PRONTUÁRIO DE COMBATE / HISTÓRICO',
            style: GoogleFonts.oxanium(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.white54,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTacticalLogs(BuildContext context, List<HealthLogModel> logs) {
    if (logs.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            'NENHUM REGISTRO MÉDICO',
            style: GoogleFonts.shareTechMono(
              color: Colors.white24,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final log = logs[index];
        final bool isExam = log.logType == 'Exame';
        final bool hasAttachments =
            log.mediaAttachments != null && log.mediaAttachments!.isNotEmpty;
        final accentColor = _getLogColor(log.logType);
        final iconData = _getLogIcon(log.logType);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            decoration: ShapeDecoration(
              color: const Color(0xFF0F172A),
              shape: BeveledRectangleBorder(
                borderRadius: BorderRadius.circular(
                  12,
                ), // Corte tático nas bordas
                side: BorderSide(
                  color: accentColor.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              shadows: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cabeçalho do Card (Estilo Badge Militar)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(6),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(iconData, size: 16, color: accentColor),
                      const SizedBox(width: 8),
                      Text(
                        log.logType.toUpperCase(),
                        style: GoogleFonts.shareTechMono(
                          color: accentColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatMilitaryDate(log.date),
                        style: GoogleFonts.shareTechMono(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                // Corpo do Card
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              log.healthObservations.isNotEmpty
                                  ? log.healthObservations
                                  : 'Registro operacional documentado.',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                            if (log.vetName != null &&
                                log.vetName!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black38,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Text(
                                  'VET/RESP: ${log.vetName!.toUpperCase()}',
                                  style: GoogleFonts.shareTechMono(
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                            if (isExam && hasAttachments) ...[
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: accentColor,
                                    width: 1.5,
                                  ),
                                  foregroundColor: accentColor,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                onPressed: () => _openAttachment(
                                  log.mediaAttachments!.first['url'],
                                ),
                                icon: const Icon(
                                  Icons.document_scanner_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  'ACESSAR LAUDO PDF',
                                  style: GoogleFonts.oxanium(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (hasAttachments && !isExam) ...[
                        const SizedBox(width: 16),
                        _buildTacticalThumbnail(
                          log.mediaAttachments!.first['url'],
                          accentColor,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }, childCount: logs.length),
    );
  }

  Widget _buildTacticalThumbnail(String? url, Color accentColor) {
    if (url == null) return const SizedBox.shrink();
    return Container(
      width: 75,
      height: 75,
      padding: const EdgeInsets.all(2), // Espaço para dar efeito de moldura
      decoration: BoxDecoration(
        color: const Color(0xFF030712),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.8),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: Colors.white10),
          errorWidget: (context, url, error) => const Icon(
            Icons.image_not_supported,
            color: Colors.white24,
            size: 24,
          ),
        ),
      ),
    );
  }

  Color _getLogColor(String type) {
    switch (type) {
      case 'Vacina':
        return const Color(0xFFFF00FF); // Magenta Neon
      case 'Exame':
        return Colors.cyanAccent;
      case 'Banho':
        return const Color(0xFF00BFFF); // Deep Sky Blue Neon
      case 'Consulta':
        return Colors.orangeAccent;
      default:
        return Colors.cyan;
    }
  }

  IconData _getLogIcon(String type) {
    switch (type) {
      case 'Vacina':
        return Icons.vaccines;
      case 'Exame':
        return Icons.biotech;
      case 'Banho':
        return Icons.water_drop;
      case 'Consulta':
        return Icons.medical_services;
      default:
        return Icons.fact_check;
    }
  }

  Future<void> _openAttachment(String? url) async {
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// Pintor Tático para simular o gráfico de evolução do peso
class WeightChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final paintGlow = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.4)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    final paintDotOuter = Paint()
      ..color = const Color(0xFF082F49)
      ..style = PaintingStyle.fill;

    final paintDotInner = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.fill;

    // Coordenadas simuladas para o gráfico (pode ser substituído por dados reais no futuro)
    final points = [
      Offset(size.width * 0.05, size.height * 0.8),
      Offset(size.width * 0.25, size.height * 0.6),
      Offset(size.width * 0.50, size.height * 0.75),
      Offset(size.width * 0.75, size.height * 0.3),
      Offset(size.width * 0.95, size.height * 0.2),
    ];

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    // Curva Suave (Cubic Bezier)
    for (int i = 1; i < points.length; i++) {
      final p0 = points[i - 1];
      final p1 = points[i];
      final controlPointX = p0.dx + (p1.dx - p0.dx) / 2;
      path.cubicTo(controlPointX, p0.dy, controlPointX, p1.dy, p1.dx, p1.dy);
    }

    // Desenha o brilho e depois a linha
    canvas.drawPath(path, paintGlow);
    canvas.drawPath(path, paintLine);

    // Desenha os pontos de marcação
    for (var point in points) {
      canvas.drawCircle(point, 5, paintDotOuter);
      canvas.drawCircle(point, 3, paintDotInner);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
